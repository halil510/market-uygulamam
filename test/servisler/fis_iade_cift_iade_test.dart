// test/servisler/fis_iade_cift_iade_test.dart
//
// Derin analiz 2026-10-07 (B3): fiş iadesinde "iade edilebilir miktar"
// artık transaction içinde veritabanından yeniden hesaplanıyor. Ekranın
// bellekteki (bayat) değeri ne derse desin aynı kalem iki kez iade edilemez.
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/depolar/iade_deposu.dart';
import 'package:market_plus/servisler/iade_islem_servisi.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import 'package:sqflite/sqflite.dart';
import '../helper/test_initializer.dart';

void main() {
  late Database db;
  late int urunId;
  late int satisId;

  setUp(() async {
    db = await TestVeritabani.olustur();
    Veritabani.testVeritabani = db;
    urunId = await TestVeritabani.ornekUrunEkle(db, barkod: 'IADE1', stok: 10);
    satisId = await db.insert('satislar', {
      'fis_no': 'S-1', 'tarih': DateTime.now().toIso8601String(), 'is_deleted': 0,
    });
    // Ürün fişte iki ayrı satırda: toplam 2 adet satıldı.
    for (var i = 0; i < 2; i++) {
      await db.insert('satis_kalem', {
        'satis_id': satisId, 'urun_id': urunId, 'urun_adi': 'Test', 'miktar': 1,
        'birim_fiyat': 10, 'toplam_tutar': 10,
      });
    }
  });
  tearDown(() => db.close());

  Future<void> iadeEt(double miktar, {double ekranOnceki = 0}) =>
      IadeIslemServisi().fisKalemIadeKaydet(
        satisId: satisId,
        cariId: null,
        urunId: urunId,
        urunAdi: 'Test',
        birimFiyat: 10,
        kalanMiktar: miktar,
        oncekiIadeMiktar: ekranOnceki,
        odemeYontemi: 'Kart/Banka',
        kullaniciId: null,
        kullaniciAdi: 'test',
      );

  Future<double> stok() async =>
      ((await db.query('urunler', columns: ['stok'], where: 'id = ?', whereArgs: [urunId]))
              .first['stok'] as num)
          .toDouble();

  test('iki satırdaki toplam miktar (2) iade edilebilir; üçüncü adet reddedilir', () async {
    await iadeEt(2);
    expect(await stok(), 12);

    // Ekran bayat değerle (önceki iade = 0) tekrar denese bile reddedilir.
    await expectLater(iadeEt(1), throwsA(isA<IadeMiktariAsildiHatasi>()));
    expect(await stok(), 12, reason: 'reddedilen iade stoğa yazılmamalı');
    expect(await IadeDeposu().fisIadeliMiktarlariGetir(satisId), {urunId: 2.0});
  });

  test('kısmi iadeden sonra yalnız kalan miktar iade edilebilir', () async {
    await iadeEt(1);
    await expectLater(
      iadeEt(2),
      throwsA(isA<IadeMiktariAsildiHatasi>()
          .having((e) => e.iadeEdilebilir, 'iadeEdilebilir', 1)),
    );
    await iadeEt(1);
    expect(await stok(), 12);
  });

  test('silinmiş iade "iade edilmiş" sayılmaz', () async {
    await iadeEt(2);
    await db.update('iade', {'deleted_at': DateTime.now().toIso8601String()},
        where: 'satis_id = ?', whereArgs: [satisId]);
    expect(await IadeDeposu().fisIadeliMiktarlariGetir(satisId), isEmpty);
    await iadeEt(2); // tekrar iade edilebilir
  });
}
