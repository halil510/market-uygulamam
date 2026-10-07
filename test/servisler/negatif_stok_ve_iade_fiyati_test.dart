// test/servisler/negatif_stok_ve_iade_fiyati_test.dart
//
// Kullanıcı kararları (2026-10-07):
//  B2 — stok eksiye düşebilir; iade hayalet stok üretmez.
//  B4 — hızlı iade, bugünkü fiyattan değil satışta ödenen fiyattan yapılır.
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/depolar/cari_deposu.dart';
import 'package:market_plus/depolar/stok_deposu.dart';
import 'package:market_plus/depolar/urun_deposu.dart';
import 'package:market_plus/servisler/iade_islem_servisi.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import 'package:sqflite/sqflite.dart';
import '../helper/test_initializer.dart';

void main() {
  late Database db;

  setUp(() async {
    db = await TestVeritabani.olustur();
    Veritabani.testVeritabani = db;
  });
  tearDown(() => db.close());

  Future<double> stok(int urunId) async =>
      ((await db.query('urunler', columns: ['stok'], where: 'id = ?', whereArgs: [urunId]))
              .first['stok'] as num)
          .toDouble();

  group('B2 — negatif stok', () {
    test('stok 2 iken 5 satılırsa −3 olur; 5 iade gelince gerçek stok (2) kalır', () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db, barkod: 'NEG', stok: 0);
      final depo = StokDeposu();
      await depo.stokGir(urunId: urunId, miktar: 2); // ilk stok 0 → 2 (hareketli)
      await db.transaction((txn) => depo.stokDusTxn(txn, 'g-satis', urunId: urunId, miktar: 5));
      expect(await stok(urunId), -3);

      final hareket = (await db.query('stok_hareket', where: "global_id = 'g-satis'")).first;
      expect((hareket['sonraki_stok'] as num) - (hareket['onceki_stok'] as num), -5,
          reason: 'hareket farkı satılan miktarın tamamı olmalı');

      await depo.stokGir(urunId: urunId, miktar: 5); // iade girişi
      expect(await stok(urunId), 2, reason: 'hayalet stok (+3) oluşmamalı');
    });

    test('negatif stoklu ürün mutabakatta "uyumsuz" sayılıp 0\'a çekilmez', () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db, barkod: 'NEG2', stok: 0);
      await db.transaction((txn) => StokDeposu().stokDusTxn(txn, 'g1', urunId: urunId, miktar: 4));
      expect(await StokDeposu().mutabakatUyumsuzlukSayisi(), 0);
      expect(await StokDeposu().stokMutabakatYap(), 0);
      expect(await stok(urunId), -4);
    });
  });

  group('B4 — hızlı iade satışta ödenen fiyattan', () {
    late int urunId;

    Future<void> satisEkle({required double netFiyat, int? cariId, String tarih = '2026-10-01T10:00:00'}) async {
      final satisId = await db.insert('satislar', {
        'fis_no': 'S-$netFiyat-$cariId', 'tarih': tarih, 'is_deleted': 0, 'cari_id': ?cariId,
      });
      await db.insert('satis_kalem', {
        'satis_id': satisId, 'urun_id': urunId, 'urun_adi': 'Çay', 'miktar': 1,
        'birim_fiyat': netFiyat + 2, 'net_fiyat': netFiyat, 'toplam_tutar': netFiyat,
      });
    }

    Future<(int, String, Map<int, double>)> iadeEt({int? cariId}) async {
      final urun = (await UrunDeposu().idileGetir(urunId))!;
      return IadeIslemServisi().topluIadeKaydet(
        kalemler: [IadeKalemGirdi(urun: urun, adet: 2)],
        odemeYontemi: 'Kart/Banka',
        kullaniciId: null,
        kullaniciAdi: 'test',
        cari: cariId == null ? null : await CariDeposu().idileGetir(cariId),
      );
    }

    setUp(() async {
      urunId = await TestVeritabani.ornekUrunEkle(db, barkod: 'CAY', stok: 10);
    });

    test('zamdan sonra iade, bugünkü fiyattan değil ödenen net fiyattan yapılır', () async {
      await satisEkle(netFiyat: 10);
      await db.update('urunler', {'satis_fiyati': 15}, where: 'id = ?', whereArgs: [urunId]);

      final (iadeId, _, fiyatlar) = await iadeEt();
      expect(fiyatlar[urunId], 10);
      final iade = (await db.query('iade', where: 'id = ?', whereArgs: [iadeId])).first;
      expect(iade['toplam_tutar'], 20);
      final kalem = (await db.query('iade_kalem', where: 'iade_id = ?', whereArgs: [iadeId])).first;
      expect(kalem['birim_fiyat'], 10);
    });

    test('en son geçerli satış esas alınır; iptal edilmiş satış sayılmaz', () async {
      await satisEkle(netFiyat: 8, tarih: '2026-09-01T10:00:00');
      await satisEkle(netFiyat: 9, tarih: '2026-09-20T10:00:00');
      final iptalId = await db.insert('satislar', {
        'fis_no': 'IPT', 'tarih': '2026-10-05T10:00:00', 'is_deleted': 0, 'iptal': 1,
      });
      await db.insert('satis_kalem', {
        'satis_id': iptalId, 'urun_id': urunId, 'urun_adi': 'Çay', 'miktar': 1,
        'birim_fiyat': 50, 'net_fiyat': 50, 'toplam_tutar': 50,
      });
      final (_, _, fiyatlar) = await iadeEt();
      expect(fiyatlar[urunId], 9);
    });

    test('müşteri seçiliyse o müşterinin satış fiyatı kullanılır', () async {
      final cariId = await db.insert('cari', {'unvan': 'Ahmet', 'cari_tipi': 'Müşteri', 'bakiye': 0});
      await satisEkle(netFiyat: 7, cariId: cariId, tarih: '2026-09-01T10:00:00');
      await satisEkle(netFiyat: 12, tarih: '2026-10-01T10:00:00'); // başkasına, daha yeni
      final (_, _, fiyatlar) = await iadeEt(cariId: cariId);
      expect(fiyatlar[urunId], 7);
    });

    test('satış kaydı yoksa iade bugünkü fiyatla YAPILMAZ, reddedilir', () async {
      await expectLater(iadeEt(), throwsA(isA<IadeSatisFiyatiBulunamadiHatasi>()));
      expect(await db.query('iade'), isEmpty);
      expect(await stok(urunId), 10);
    });
  });
}
