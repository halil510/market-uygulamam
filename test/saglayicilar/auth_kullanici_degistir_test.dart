// test/saglayicilar/auth_kullanici_degistir_test.dart
//
// DERİN DENETİM (2026-11-09, #77): "Kullanıcı Değiştir"de tek hatalı PIN
// mevcut oturumu kapatıp giriş ekranına atıyordu (Auth.girisYap hatada
// durumu 'cikisYapildi' yapıyordu).
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/cekirdek/utils/sifre_hash.dart';
import 'package:market_plus/saglayicilar/riverpod/auth_provider.dart';
import 'package:market_plus/servisler/auth_servisi.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late ProviderContainer c;

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (_) async => null);
    SharedPreferences.setMockInitialValues({});
    db = await TestVeritabani.olustur();
    Veritabani.testVeritabani = db;
    for (final ad in ['ayse', 'mehmet']) {
      final tuz = SifreHash.tuzUret();
      await db.insert('kullanicilar', {
        'kullanici_adi': ad,
        'sifre_hash': SifreHash.hashleTuzlu('Sifre123', tuz),
        'tuz': tuz,
        'ad_soyad': 'Test $ad',
        'rol': 'kasiyer',
        'aktif': 1,
        'is_deleted': 0,
      });
    }
    c = ProviderContainer();
    // autoDispose: dinleyici tutulmazsa notifier testin ortasında atılır.
    c.listen(authProvider, (_, _) {}); // build + açılış oturum kontrolü
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });

  tearDown(() async {
    await AuthServisi().cikisYap();
    c.dispose();
    Veritabani.testVeritabani = null;
    await db.close();
  });

  test('açık oturumda hatalı PIN oturumu kapatmaz', () async {
    final n = c.read(authProvider.notifier);
    expect(await n.girisYap('ayse', 'Sifre123'), GirisSonucu.basarili);
    expect(c.read(authProvider).girisYapildi, isTrue);

    expect(await n.girisYap('mehmet', 'yanlis'), GirisSonucu.hataliSifre);
    expect(c.read(authProvider).girisYapildi, isTrue,
        reason: 'tek hatalı PIN açık oturumu kapatmamalı');
    expect(c.read(authProvider).kullanici?.kullaniciAdi, 'ayse');
  });

  test('oturum yokken hatalı şifre çıkış durumunda kalır', () async {
    final n = c.read(authProvider.notifier);
    expect(await n.girisYap('ayse', 'yanlis'), GirisSonucu.hataliSifre);
    expect(c.read(authProvider).girisYapildi, isFalse);
  });
}
