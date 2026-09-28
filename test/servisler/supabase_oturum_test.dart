// test/servisler/supabase_oturum_test.dart
//
// İşletme hesabıyla bulut girişi (2026-09-28): tam yetkili gizli anahtar
// cihazdan kalkar; istekler herkese açık anahtar + kısa ömürlü erişim
// anahtarıyla gider. Supabase Auth sahte HTTP istemcisiyle taklit edilir.
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:market_plus/servisler/bulut/supabase_ayarlari.dart';
import 'package:market_plus/servisler/bulut/supabase_oturum.dart';

const _url = 'https://ornek.supabase.co';
const _acik = 'sb_publishable_ACIK';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final depo = <String, String>{};
  final istekler = <http.Request>[];
  late int yenilemeYaniti; // yenileme uç noktasının döneceği HTTP kodu
  late int erisimSuresi;   // expires_in (sn)
  var sayac = 0;

  http.Response tokenYaniti() => http.Response(
      jsonEncode({
        'access_token': 'ERISIM_${++sayac}',
        'refresh_token': 'YENILEME_$sayac',
        'expires_in': erisimSuresi,
        'user': {'email': 'kasa@isletme.com'},
      }),
      200);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    depo.clear();
    istekler.clear();
    sayac = 0;
    yenilemeYaniti = 200;
    erisimSuresi = 3600;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (c) async {
      final a = (c.arguments as Map?) ?? {};
      final k = a['key'] as String?;
      switch (c.method) {
        case 'write': depo[k!] = a['value'] as String; return null;
        case 'read': return depo[k];
        case 'delete': depo.remove(k); return null;
        case 'containsKey': return depo.containsKey(k);
        case 'readAll': return Map<String, String>.from(depo);
      }
      return null;
    });
    SupabaseOturum.testIstemci = MockClient((r) async {
      istekler.add(r);
      final govde = r.body.isEmpty ? <String, dynamic>{} : jsonDecode(r.body) as Map;
      if (r.url.path == '/auth/v1/token' && r.url.queryParameters['grant_type'] == 'password') {
        return govde['password'] == 'dogru'
            ? tokenYaniti()
            : http.Response('{"error":"invalid_grant"}', 400);
      }
      if (r.url.path == '/auth/v1/token' && r.url.queryParameters['grant_type'] == 'refresh_token') {
        return yenilemeYaniti == 200 ? tokenYaniti() : http.Response('{}', yenilemeYaniti);
      }
      if (r.url.path == '/auth/v1/logout') return http.Response('', 204);
      return http.Response('bilinmeyen', 404);
    });
    SupabaseOturum().testSifirla();
    await SupabaseAyarlari.kaydet(url: _url, key: _acik);
  });

  tearDown(() => SupabaseOturum.testIstemci = null);

  test('Giriş yapılmamışken (geçiş dönemi) kayıtlı anahtar Bearer olarak kullanılır', () {
    expect(SupabaseOturum.bearer(_acik), _acik);
  });

  test('Başarılı giriş: erişim anahtarı Bearer olur, e-posta hatırlanır, istek herkese açık anahtarla gider', () async {
    await SupabaseOturum().girisYap('kasa@isletme.com', 'dogru');
    expect(SupabaseOturum().girisli, isTrue);
    expect(SupabaseOturum().eposta, 'kasa@isletme.com');
    expect(SupabaseOturum.bearer(_acik), 'ERISIM_1');
    expect(istekler.single.headers['apikey'], _acik);
    expect(depo.values, contains('YENILEME_1'), reason: 'yenileme anahtarı güvenli depoda');
  });

  test('Hatalı şifre: anlaşılır hata, oturum açılmaz', () async {
    await expectLater(SupabaseOturum().girisYap('kasa@isletme.com', 'yanlis'),
        throwsA(isA<OturumHatasi>().having((e) => e.mesaj, 'mesaj', contains('hatalı'))));
    expect(SupabaseOturum().girisli, isFalse);
  });

  test('Gizli anahtar kayıtlıyken giriş reddedilir (gizli anahtar cihazda kalmasın)', () async {
    await SupabaseAyarlari.kaydet(url: _url, key: 'sb_secret_GIZLI');
    await expectLater(SupabaseOturum().girisYap('kasa@isletme.com', 'dogru'),
        throwsA(isA<OturumHatasi>()));
    expect(istekler, isEmpty, reason: 'ağa hiç çıkılmamalı');
  });

  test('Süresi dolmak üzere olan oturum, anahtar okunurken kendiliğinden yenilenir', () async {
    erisimSuresi = 60; // 5 dk'dan az kaldı → yenilenmeli
    await SupabaseOturum().girisYap('kasa@isletme.com', 'dogru');
    erisimSuresi = 3600;
    await SupabaseAyarlari.keyOku();
    expect(SupabaseOturum.bearer(_acik), 'ERISIM_2');
    final yenileme = istekler.last;
    expect(yenileme.url.queryParameters['grant_type'], 'refresh_token');
    expect(jsonDecode(yenileme.body)['refresh_token'], 'YENILEME_1');
  });

  test('Süresi uzun olan oturumda gereksiz yenileme yapılmaz', () async {
    await SupabaseOturum().girisYap('kasa@isletme.com', 'dogru');
    await SupabaseAyarlari.keyOku();
    await SupabaseAyarlari.keyOku();
    expect(istekler.length, 1, reason: 'yalnız giriş isteği');
  });

  test('Aynı anda gelen yenilemeler tek istekte birleşir', () async {
    erisimSuresi = 60;
    await SupabaseOturum().girisYap('kasa@isletme.com', 'dogru');
    await Future.wait([SupabaseOturum().tazele(), SupabaseOturum().tazele(), SupabaseOturum().tazele()]);
    expect(istekler.where((r) => r.url.queryParameters['grant_type'] == 'refresh_token').length, 1);
  });

  test('Yenileme reddedilirse (şifre değişti vb.) "oturum düştü" işaretlenir', () async {
    erisimSuresi = 60;
    await SupabaseOturum().girisYap('kasa@isletme.com', 'dogru');
    yenilemeYaniti = 400;
    await SupabaseOturum().tazele();
    expect(SupabaseOturum().oturumDustu.value, isTrue);
  });

  test('Oturumu kapatınca erişim ve yenileme anahtarı silinir', () async {
    await SupabaseOturum().girisYap('kasa@isletme.com', 'dogru');
    await SupabaseOturum().cikis();
    expect(SupabaseOturum().girisli, isFalse);
    expect(SupabaseOturum.bearer(_acik), _acik);
    expect(depo.values, isNot(contains('YENILEME_1')));
  });

  test('Açılışta kayıtlı oturum yüklenir ve erişim anahtarı alınır', () async {
    await SupabaseOturum().girisYap('kasa@isletme.com', 'dogru');
    SupabaseOturum().testSifirla(); // uygulama kapandı
    await SupabaseOturum().yukle();
    expect(SupabaseOturum().girisli, isTrue);
    expect(SupabaseOturum.bearer(_acik), 'ERISIM_2');
  });

  group('Gönderime hazır mı (kuyruk 401 alıp kalıcı hataya düşmesin)', () {
    test('Herkese açık anahtar + giriş yok → gönderim bekler', () {
      expect(SupabaseOturum.gonderimeHazir(_acik), isFalse);
    });
    test('Gizli anahtar (geçiş dönemi) → gönderilir', () {
      expect(SupabaseOturum.gonderimeHazir('sb_secret_x'), isTrue);
    });
    test('Geçerli oturum → gönderilir; oturum kapanınca bekler', () async {
      await SupabaseOturum().girisYap('kasa@isletme.com', 'dogru');
      expect(SupabaseOturum.gonderimeHazir(_acik), isTrue);
      await SupabaseOturum().cikis();
      expect(SupabaseOturum.gonderimeHazir(_acik), isFalse);
    });
  });

  group('Gizli anahtar tespiti', () {
    test('sb_secret_ gizli', () => expect(SupabaseOturum.gizliAnahtarMi('sb_secret_x'), isTrue));
    test('sb_publishable_ açık', () => expect(SupabaseOturum.gizliAnahtarMi(_acik), isFalse));
    String jwt(String rol) =>
        'x.${base64Url.encode(utf8.encode(jsonEncode({'role': rol}))).replaceAll('=', '')}.y';
    test('Eski JWT service_role gizli', () => expect(SupabaseOturum.gizliAnahtarMi(jwt('service_role')), isTrue));
    test('Eski JWT anon açık', () => expect(SupabaseOturum.gizliAnahtarMi(jwt('anon')), isFalse));
  });
}
