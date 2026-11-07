// test/servisler/auth_servisi_giris_test.dart
//
// Kademe 2 (2026-11-06): AuthServisi.girisYap() uçtan uca — önceden yalnız
// hashle() test ediliyordu; giriş akışı kırılırsa uygulama açılamaz.
// GERÇEK AuthServisi + KullaniciDeposu + GirisDenemeSayaci çağrılır
// (bellek-içi gerçek şema, SharedPreferences mock).
//
// Not: kilit eşiği UygSabitler.maxHataliGiris (5), süre kilitSureSaniye
// (30 sn). Kilit süresince girisYap false DEĞİL AuthKilitliException fırlatır
// (ekran bu istisnadan kalan süreyi gösterir).
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/cekirdek/sabitler/uygulama_sabitleri.dart';
import 'package:market_plus/cekirdek/utils/sifre_hash.dart';
import 'package:market_plus/servisler/auth_servisi.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  final auth = AuthServisi();

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (_) async => null);
    SharedPreferences.setMockInitialValues({});
    db = await TestVeritabani.olustur();
    Veritabani.testVeritabani = db;
  });
  tearDown(() async {
    await auth.cikisYap();
    Veritabani.testVeritabani = null;
    await db.close();
  });

  /// Tuzlu (yeni şema) kullanıcı.
  Future<int> tuzluKullanici(String ad, String sifre, {int aktif = 1}) {
    final tuz = SifreHash.tuzUret();
    return db.insert('kullanicilar', {
      'kullanici_adi': ad,
      'sifre_hash': SifreHash.hashleTuzlu(sifre, tuz),
      'tuz': tuz,
      'ad_soyad': 'Test $ad',
      'rol': 'kasiyer',
      'aktif': aktif,
      'is_deleted': 0,
    });
  }

  Future<int?> denemeSayisi(String ad) async =>
      (await SharedPreferences.getInstance()).getInt('giris_deneme_$ad');

  test('doğru kullanıcı + doğru şifre → giriş yapılır, aktif kullanıcı dolar', () async {
    await tuzluKullanici('ayse', 'Sifre123');
    expect(await auth.girisYap('ayse', 'Sifre123'), isTrue);
    expect(auth.aktifKullanici, isNotNull);
    expect(auth.aktifKullanici!.kullaniciAdi, 'ayse');
  });

  test('yanlış şifre → false, deneme sayacı artar', () async {
    await tuzluKullanici('ali', 'Dogru1');
    expect(await auth.girisYap('ali', 'yanlis'), isFalse);
    expect(auth.aktifKullanici, isNull);
    expect(await denemeSayisi('ali'), 1);
  });

  test('olmayan kullanıcı → false ve sayaç yine artar (kullanıcı var/yok bilgisi sızmaz)', () async {
    expect(await auth.girisYap('hayalet', 'x'), isFalse);
    expect(await denemeSayisi('hayalet'), 1);
  });

  test('veritabanı hatası "hatalı şifre" gibi false DÖNMEZ: hata iletilir, '
      'deneme sayacı artmaz', () async {
    // Regresyon: catch içinde `return false` vardı — DB açılamazsa kasiyer
    // "Hatalı şifre" görüyor, birkaç denemede de hesabı kilitleniyordu.
    await db.execute('DROP TABLE kullanicilar');
    await expectLater(auth.girisYap('ayse', 'Sifre123'), throwsA(isA<Exception>()));
    expect(await denemeSayisi('ayse'), isNull);
    expect(auth.aktifKullanici, isNull);
  });

  test('aktif = 0 kullanıcı doğru şifreyle bile giremez', () async {
    await tuzluKullanici('pasif', 'Sifre1', aktif: 0);
    expect(await auth.girisYap('pasif', 'Sifre1'), isFalse);
    expect(auth.aktifKullanici, isNull);
  });

  test('eşik kadar yanlış denemeden sonra kilit: doğru şifre bile reddedilir', () async {
    await tuzluKullanici('veli', 'Dogru1');
    for (var i = 0; i < UygSabitler.maxHataliGiris; i++) {
      expect(await auth.girisYap('veli', 'yanlis$i'), isFalse);
    }
    await expectLater(auth.girisYap('veli', 'Dogru1'),
        throwsA(isA<AuthKilitliException>()));
    expect(auth.aktifKullanici, isNull);
  });

  test('kilit süresi dolunca doğru şifreyle girilir', () async {
    await tuzluKullanici('zeynep', 'Dogru1');
    // Süresi geçmiş bir kilit kaydı (uygulama yeniden açılmış gibi).
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('giris_kilit_zeynep',
        DateTime.now().subtract(const Duration(seconds: 1)).millisecondsSinceEpoch);
    expect(await auth.girisYap('zeynep', 'Dogru1'), isTrue);
  });

  test('başarılı giriş sonrası deneme sayacı temizlenir', () async {
    await tuzluKullanici('mehmet', 'Dogru1');
    await auth.girisYap('mehmet', 'yanlis');
    await auth.girisYap('mehmet', 'yanlis');
    expect(await denemeSayisi('mehmet'), 2);

    expect(await auth.girisYap('mehmet', 'Dogru1'), isTrue);
    expect(await denemeSayisi('mehmet'), isNull);
  });

  test('tuzsuz eski hash\'li kullanıcı girebilir ve şifresi tuzlu şemaya yükseltilir', () async {
    final id = await db.insert('kullanicilar', {
      'kullanici_adi': 'eski',
      'sifre_hash': SifreHash.eskiHashle('Eski123'),
      'ad_soyad': 'Eski Kullanıcı',
      'rol': 'kasiyer',
      'aktif': 1,
      'is_deleted': 0,
    });

    expect(await auth.girisYap('eski', 'Eski123'), isTrue);

    final satir = (await db.query('kullanicilar', where: 'id = ?', whereArgs: [id])).first;
    expect((satir['tuz'] as String?)?.isNotEmpty, isTrue, reason: 'sessizce tuzlu şemaya geçmeli');
    expect(satir['sifre_hash'], SifreHash.hashleTuzlu('Eski123', satir['tuz'] as String));

    // Yükseltme sonrası da aynı şifreyle girilebilir.
    await auth.cikisYap();
    expect(await auth.girisYap('eski', 'Eski123'), isTrue);
  });

  test('tuzlu kullanıcı: doğru şifre kabul, yanlış şifre ret', () async {
    await tuzluKullanici('tuzlu', 'Gizli9');
    expect(await auth.girisYap('tuzlu', 'gizli9'), isFalse, reason: 'büyük/küçük harf duyarlı');
    expect(await auth.girisYap('tuzlu', 'Gizli9'), isTrue);
  });
}
