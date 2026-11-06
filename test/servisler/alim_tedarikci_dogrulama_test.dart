// test/servisler/alim_tedarikci_dogrulama_test.dart
//
// Regresyon (2026-11-06): AlimIslemServisi.alimKaydet() tedarikçinin
// var/aktif olduğunu hiç kontrol etmiyordu. Form açıkken tedarikçi başka
// bir cihazda silinirse alım + veresiye borç SİLİNMİŞ cariye yazılıyordu;
// hiç olmayan bir id ise SQLite FK hatası (787) ile anlaşılmaz bir mesaj
// çıkıyordu. Artık işlem başlamadan net bir hatayla reddedilir ve hiçbir
// stok/kasa/cari kaydı oluşmaz.
//
// GERÇEK AlimIslemServisi çağrılır.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/servisler/alim_islem_servisi.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late int urunId;

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (_) async => null);
    SharedPreferences.setMockInitialValues({});
    db = await TestVeritabani.olustur();
    Veritabani.testVeritabani = db;
    urunId = await TestVeritabani.ornekUrunEkle(db, stok: 10);
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    Veritabani.testVeritabani = null;
    await db.close();
  });

  Future<void> alim(int? tedarikciId) => AlimIslemServisi().alimKaydet(
        mevcutSiparisId: null,
        kalemler: [AlimKalemGirdi(urunId: urunId, miktar: 5, alisFiyat: 20)],
        tedarikciId: tedarikciId,
        tedarikciAdi: 'T',
        genelToplam: 100,
        odemeYontemi: 'Cari',
        kullaniciId: null,
        kullaniciAdi: null,
      );

  Future<int> sayi(String tablo) async =>
      (await db.rawQuery('SELECT COUNT(*) AS c FROM $tablo')).first['c'] as int;

  Future<double> stok() async => ((await db.query('urunler',
              columns: ['stok'], where: 'id = ?', whereArgs: [urunId]))
          .first['stok'] as num)
      .toDouble();

  test('silinmiş tedarikçiye alım reddedilir, hiçbir kayıt oluşmaz', () async {
    final cariId = await TestVeritabani.ornekCariEkle(db, cariTipi: 'Tedarikçi');
    await db.update('cari', {'is_deleted': 1}, where: 'id = ?', whereArgs: [cariId]);

    await expectLater(alim(cariId), throwsA(isA<Exception>()
        .having((e) => e.toString(), 'mesaj', contains('tedarikçi'))));

    expect(await sayi('tedarikci_siparisler'), 0);
    expect(await sayi('cari_hareket'), 0);
    expect(await stok(), 10);
  });

  test('var olmayan tedarikçi id → FK hatası yerine anlaşılır hata', () async {
    await expectLater(alim(99999), throwsA(isA<Exception>()
        .having((e) => e.toString(), 'mesaj', contains('tedarikçi'))));
    expect(await sayi('tedarikci_siparisler'), 0);
    expect(await stok(), 10);
  });

  test('aktif tedarikçiyle alım normal çalışır (davranış korunur)', () async {
    final cariId = await TestVeritabani.ornekCariEkle(db, cariTipi: 'Tedarikçi');
    await alim(cariId);
    expect(await sayi('tedarikci_siparisler'), 1);
    expect(await stok(), 15);
    final bakiye = (await db.query('cari',
            columns: ['bakiye'], where: 'id = ?', whereArgs: [cariId]))
        .first['bakiye'] as num;
    expect(bakiye.toDouble(), -100);
  });
}
