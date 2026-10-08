// lib/servisler/bulut/supabase_oturum.dart
//
// İŞLETME HESABIYLA BULUT GİRİŞİ (kullanıcı kararı 2026-09-28).
//
// ÖNCEDEN: her cihazda tam yetkili `sb_secret_` (service_role) anahtarı
// duruyordu — Supabase'in satır güvenliğini (RLS) tamamen atlar; cihazı ele
// geçiren buluttaki TÜM veriye erişebilirdi.
//
// ŞİMDİ: cihaz, Supabase Auth'ta açılmış işletme hesabının e-posta/şifresiyle
// BİR KEZ giriş yapar. İsteklerde:
//   apikey        = herkese açık (publishable) anahtar
//   Authorization = Bearer <kısa ömürlü erişim anahtarı (JWT, ~1 saat)>
// Erişim anahtarı süresi dolmadan yenileme anahtarıyla (refresh token —
// güvenli depoda) kendiliğinden yenilenir. Kasiyerler yine uygulama içi PIN
// ile girer; internet yokken yerel çalışma etkilenmez.
//
// GEÇİŞ: giriş yapılmamış cihazlarda kayıtlı anahtar eskisi gibi hem apikey
// hem Bearer olarak gider ([bearer] anahtarın kendisini döner) — tüm cihazlar
// giriş yaptıktan sonra gizli anahtar Supabase panelinden iptal edilmeli.
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../log_servisi.dart';
import 'supabase_ayarlari.dart';

/// Giriş/yenileme hatası — mesaj kullanıcıya gösterilebilir.
class OturumHatasi implements Exception {
  final String mesaj;
  OturumHatasi(this.mesaj);
  @override
  String toString() => mesaj;
}

class SupabaseOturum {
  static final SupabaseOturum _instance = SupabaseOturum._();
  factory SupabaseOturum() => _instance;
  SupabaseOturum._();

  static const _secure = FlutterSecureStorage();
  static const _kYenileme = 'mp_supabase_yenileme_secure';
  static const _kEposta = 'mp_supabase_eposta_secure';

  /// Testlerde sahte HTTP istemcisi takmak için.
  @visibleForTesting
  static http.Client? testIstemci;
  Future<http.Response> _post(Uri u, {Map<String, String>? headers, Object? body}) =>
      testIstemci != null
          ? testIstemci!.post(u, headers: headers, body: body)
          : http.post(u, headers: headers, body: body);

  String? _erisim;
  DateTime? _bitis;
  String? _eposta;
  Future<void>? _yenilemeDevam;

  /// Oturum düştü (yenileme anahtarı geçersiz — ör. şifre değişti, hesap
  /// silindi): kullanıcı Ayarlar'dan yeniden giriş yapmalı.
  final oturumDustu = ValueNotifier<bool>(false);

  String? get eposta => _eposta;
  bool get girisli => _eposta != null;

  /// Anahtar tam yetkili (RLS'i atlayan) gizli anahtar mı?
  static bool gizliAnahtarMi(String? key) {
    if (key == null) return false;
    if (key.startsWith('sb_secret_')) return true;
    // Eski JWT biçimli service_role anahtarı.
    final parcalar = key.split('.');
    if (parcalar.length == 3) {
      try {
        final yuk = utf8.decode(base64Url.decode(base64Url.normalize(parcalar[1])));
        return (jsonDecode(yuk) as Map)['role'] == 'service_role';
      } catch (_) {}
    }
    return false;
  }

  /// Authorization: Bearer değeri. Geçerli oturum varsa erişim anahtarı,
  /// yoksa (geçiş dönemi / giriş yapılmamış) kayıtlı anahtarın kendisi.
  static String bearer(String key) {
    final o = _instance;
    if (o._erisim != null && o._bitis != null && DateTime.now().isBefore(o._bitis!)) {
      return o._erisim!;
    }
    return key;
  }

  /// Oturumun erişim anahtarının bitiş zamanı (oturum yoksa null).
  DateTime? get erisimBitis => _erisim == null ? null : _bitis;

  /// Geçerli (süresi dolmamış) erişim anahtarı var mı?
  bool get erisimGecerli =>
      _erisim != null && _bitis != null && DateTime.now().isBefore(_bitis!);

  /// Bu anahtarla buluta yazılabilir mi? Gizli anahtar (geçiş dönemi) ya da
  /// geçerli oturum gerekir. Değilse gönderim BEKLETİLİR — herkese açık
  /// anahtarla gönderim 401 alıp kuyruk satırlarını kalıcı hataya düşürürdü.
  static bool gonderimeHazir(String key) =>
      gizliAnahtarMi(key) || _instance.erisimGecerli;

  /// Uygulama açılışında: kayıtlı oturum varsa yükle ve erişim anahtarı al.
  Future<void> yukle() async {
    _eposta = await _secure.read(key: _kEposta);
    if (_eposta != null) await tazele();
  }

  /// İstek atmadan ÖNCE çağrılır: oturum varsa ve erişim anahtarının süresi
  /// 5 dakikadan az kaldıysa yeniler. Eşzamanlı çağrılar tek yenilemeyi
  /// paylaşır. Ağ hatasında sessiz kalır (bir sonraki çağrıda tekrar denenir).
  Future<void> tazele() {
    if (_eposta == null) return Future.value();
    if (_erisim != null && _bitis != null &&
        _bitis!.difference(DateTime.now()) > const Duration(minutes: 5)) {
      return Future.value();
    }
    return _yenilemeDevam ??= _yenile().whenComplete(() => _yenilemeDevam = null);
  }

  Future<void> _yenile() async {
    final yenileme = await _secure.read(key: _kYenileme);
    final url = await SupabaseAyarlari.urlOku();
    final key = await SupabaseAyarlari.hamKeyOku();
    if (yenileme == null || url == null || key == null) return;
    try {
      final r = await _post(Uri.parse('$url/auth/v1/token?grant_type=refresh_token'),
              headers: {'apikey': key, 'Content-Type': 'application/json'},
              body: jsonEncode({'refresh_token': yenileme}))
          .timeout(const Duration(seconds: 15));
      if (r.statusCode == 200) {
        await _yanitiIsle(r.body);
        oturumDustu.value = false;
      } else if (r.statusCode == 400 || r.statusCode == 401) {
        // Yenileme anahtarı geçersiz — yeniden giriş gerekli.
        _erisim = null;
        _bitis = null;
        oturumDustu.value = true;
        LogServisi().uyari('SupabaseOturum: oturum yenilenemedi, yeniden giriş gerekli',
            ek: 'HTTP ${r.statusCode}');
      }
    } catch (e) {
      // Ağ yok vb. — mevcut (belki süresi dolmuş) anahtarla devam; sonra tekrar.
      if (kDebugMode) debugPrint('SupabaseOturum yenileme: $e');
    }
  }

  Future<void> _yanitiIsle(String govde) async {
    final j = jsonDecode(govde) as Map<String, dynamic>;
    _erisim = j['access_token'] as String?;
    final sure = (j['expires_in'] as num?)?.toInt() ?? 3600;
    _bitis = DateTime.now().add(Duration(seconds: sure));
    final yeniYenileme = j['refresh_token'] as String?;
    if (yeniYenileme != null) await _secure.write(key: _kYenileme, value: yeniYenileme);
    final e = (j['user'] as Map?)?['email'] as String?;
    if (e != null) {
      _eposta = e;
      await _secure.write(key: _kEposta, value: e);
    }
  }

  /// İşletme hesabıyla giriş. [url] ve [key] (herkese açık anahtar) önceden
  /// SupabaseAyarlari'na kaydedilmiş olmalı.
  Future<void> girisYap(String eposta, String sifre) async {
    final url = await SupabaseAyarlari.urlOku();
    final key = await SupabaseAyarlari.hamKeyOku();
    if (url == null || key == null || url.isEmpty || key.isEmpty) {
      throw OturumHatasi('Önce Supabase adresini ve anahtarını kaydedin.');
    }
    if (gizliAnahtarMi(key)) {
      throw OturumHatasi('Giriş için "herkese açık" (sb_publishable_…) anahtarı girin — '
          'gizli anahtar cihazda tutulmamalı.');
    }
    final http.Response r;
    try {
      r = await _post(Uri.parse('$url/auth/v1/token?grant_type=password'),
              headers: {'apikey': key, 'Content-Type': 'application/json'},
              body: jsonEncode({'email': eposta.trim(), 'password': sifre}))
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw OturumHatasi('Sunucuya ulaşılamadı. İnternet bağlantınızı kontrol edin.');
    }
    if (r.statusCode != 200) {
      throw OturumHatasi(r.statusCode == 400
          ? 'E-posta veya şifre hatalı.'
          : 'Giriş yapılamadı (hata kodu ${r.statusCode}).');
    }
    await _yanitiIsle(r.body);
    oturumDustu.value = false;
  }

  /// Oturumu kapatır (cihaz bir daha giriş yapana kadar buluta erişemez).
  Future<void> cikis() async {
    final url = await SupabaseAyarlari.urlOku();
    final key = await SupabaseAyarlari.hamKeyOku();
    final erisim = _erisim;
    if (url != null && key != null && erisim != null) {
      try {
        await _post(Uri.parse('$url/auth/v1/logout'),
            headers: {'apikey': key, 'Authorization': 'Bearer $erisim'})
            .timeout(const Duration(seconds: 10));
      } catch (_) {}
    }
    _erisim = null;
    _bitis = null;
    _eposta = null;
    await _secure.delete(key: _kYenileme);
    await _secure.delete(key: _kEposta);
  }

  @visibleForTesting
  void testSifirla() {
    _erisim = null;
    _bitis = null;
    _eposta = null;
    _yenilemeDevam = null;
    oturumDustu.value = false;
  }
}
