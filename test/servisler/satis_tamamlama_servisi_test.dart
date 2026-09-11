// test/servisler/satis_tamamlama_servisi_test.dart
//
// SatisTamamlamaServisi, hizli_satis_ekrani.dart'tan (protokol §6/§35 —
// mimari borç) birebir taşınan satış tamamlama mantığını içerir: satış +
// kalemler + stok düşümü + kasa/cari hareketi TEK transaction'da.
// Servis Veritabani() singleton'ı üzerinden çalıştığı için burada aynı
// sırada gerçek depo Txn metotlarını (servisin kullandığı BİREBİR aynı
// kod) TestVeritabani üzerinde çağırarak doğruluyoruz.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:market_plus/depolar/cari_deposu.dart';
import 'package:market_plus/depolar/kasa_deposu.dart';
import 'package:market_plus/depolar/satis_deposu.dart';
import 'package:market_plus/depolar/stok_deposu.dart';
import 'package:market_plus/modeller/cari_hareket_model.dart';
import 'package:market_plus/modeller/kasa_hareket_model.dart';
import 'package:market_plus/modeller/satis_kalem_model.dart';
import 'package:market_plus/modeller/satis_model.dart';
import '../helper/test_initializer.dart';

/// SatisTamamlamaServisi.tamamla()'nın nakit/veresiye dallarıyla BİREBİR
/// aynı sırada depo Txn metotlarını çağıran yardımcı.
Future<int> _satisiSimuleEt(
  Database db, {
  required int urunId,
  required double miktar,
  required double birimFiyat,
  required String odemeYontemi,
  int? cariId,
  double odenenTutar = 0,
  bool stokAdimindaPatlat = false,
}) async {
  final satisDepo = SatisDeposu();
  final stokDepo = StokDeposu();
  final kasaDepo = KasaDeposu();
  final cariDepo = CariDeposu();

  final toplam = miktar * birimFiyat;
  late int satisId;

  await db.transaction((txn) async {
    satisId = await satisDepo.satisEkleTxn(
      txn,
      SatisModel(
        tarih: DateTime.now(), cariId: cariId,
        toplamTutar: toplam, genelToplam: toplam,
        odenenTutar: odenenTutar, odemeYontemi: odemeYontemi, fisTipi: 'Satış',
      ),
      [SatisKalemModel(
        satisId: 0, urunId: urunId, urunAdi: 'Test Ürün',
        miktar: miktar, birimFiyat: birimFiyat, toplamTutar: toplam,
      )],
    );

    if (stokAdimindaPatlat) {
      throw Exception('Simüle edilmiş hata — stok düşümünde');
    }

    await stokDepo.stokDusTxn(txn, const Uuid().v4(),
        urunId: urunId, miktar: miktar, referansId: satisId, referansTuru: 'satis');

    if (odemeYontemi == 'Cari' && cariId != null) {
      await cariDepo.hareketEkleTxn(txn, CariHareketModel(
        cariId: cariId, tarih: DateTime.now(), fisTipi: 'Satış',
        fisId: satisId, aciklama: 'Veresiye satış',
        borc: toplam, alacak: 0, odemeTuru: 'Cari',
      ));
    } else if (odenenTutar > 0) {
      await kasaDepo.hareketEkleTxn(txn, KasaHareketModel(
        hareketTipi: 'Satış', tutar: odenenTutar,
        referansId: satisId, referansTuru: 'satis', tarih: DateTime.now(),
      ));
    }
  });

  return satisId;
}

void main() {
  late Database db;

  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  group('SatisTamamlamaServisi mantığı — nakit satış', () {
    test('satış, kalem, stok düşümü ve kasa hareketi tek işlemde oluşur', () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db, stok: 50, satisFiyati: 20);

      final satisId = await _satisiSimuleEt(db,
          urunId: urunId, miktar: 3, birimFiyat: 20,
          odemeYontemi: 'Nakit', odenenTutar: 60);

      final satis = (await db.query('satislar', where: 'id = ?', whereArgs: [satisId])).first;
      expect((satis['genel_toplam'] as num).toDouble(), equals(60.0));

      final kalemler = await db.query('satis_kalem', where: 'satis_id = ?', whereArgs: [satisId]);
      expect(kalemler, hasLength(1));

      final urun = (await db.query('urunler', where: 'id = ?', whereArgs: [urunId])).first;
      expect((urun['stok'] as num).toDouble(), equals(47.0), reason: '50 - 3 = 47');

      final kasa = await db.query('kasa_hareketleri',
          where: 'referans_id = ? AND referans_turu = ?', whereArgs: [satisId, 'satis']);
      expect(kasa, hasLength(1));
      expect((kasa.first['tutar'] as num).toDouble(), equals(60.0));

      final cariHareket = await db.query('cari_hareket', where: 'fis_id = ?', whereArgs: [satisId]);
      expect(cariHareket, isEmpty, reason: 'nakit satışta cari hareketi oluşmamalı');
    });
  });

  group('SatisTamamlamaServisi mantığı — veresiye (Cari) satış', () {
    test('kasa hareketi OLUŞMAZ, cari hareketi borç olarak oluşur', () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db, stok: 20, satisFiyati: 100);
      final cariId = await TestVeritabani.ornekCariEkle(db);

      final satisId = await _satisiSimuleEt(db,
          urunId: urunId, miktar: 2, birimFiyat: 100,
          odemeYontemi: 'Cari', cariId: cariId, odenenTutar: 0);

      final kasa = await db.query('kasa_hareketleri',
          where: 'referans_id = ? AND referans_turu = ?', whereArgs: [satisId, 'satis']);
      expect(kasa, isEmpty, reason: 'veresiye satışta kasa hareketi OLUŞMAMALI');

      final cariHareket = await db.query('cari_hareket', where: 'fis_id = ?', whereArgs: [satisId]);
      expect(cariHareket, hasLength(1));
      expect((cariHareket.first['borc'] as num).toDouble(), equals(200.0));
      expect((cariHareket.first['alacak'] as num).toDouble(), equals(0.0));

      final cari = (await db.query('cari', where: 'id = ?', whereArgs: [cariId])).first;
      expect((cari['bakiye'] as num).toDouble(), equals(200.0),
          reason: 'Cari bakiye borç hareketiyle artmalı (protokol §8)');
    });
  });

  group('SatisTamamlamaServisi mantığı — atomiklik', () {
    test('stok adımı başarısız olursa satış TAMAMEN geri alınır', () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db, stok: 10, satisFiyati: 50);

      await expectLater(
        _satisiSimuleEt(db, urunId: urunId, miktar: 1, birimFiyat: 50,
            odemeYontemi: 'Nakit', odenenTutar: 50, stokAdimindaPatlat: true),
        throwsException,
      );

      expect(await db.query('satislar'), isEmpty,
          reason: 'Rollback sonrası satış kaydı KALMAMALI');
      final urun = (await db.query('urunler', where: 'id = ?', whereArgs: [urunId])).first;
      expect((urun['stok'] as num).toDouble(), equals(10.0),
          reason: 'Stok değişmemiş olmalı');
    });
  });

  group('SatisTamamlamaServisi.fisiGuncelle mantığı', () {
    test('miktar artışı: stok ekstra düşer, kasaya ek tutar yazılır (nakit fiş)', () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db, stok: 100, satisFiyati: 10);
      // Önce 2 adetlik bir satış oluştur (stok 100 -> 98).
      final satisId = await _satisiSimuleEt(db,
          urunId: urunId, miktar: 2, birimFiyat: 10, odemeYontemi: 'Nakit', odenenTutar: 20);

      // Fişi 5 adede çıkar (miktar farkı: +3) — fisiGuncelle mantığını simüle et.
      final satisDepo = SatisDeposu();
      final stokDepo = StokDeposu();
      final kasaDepo = KasaDeposu();
      late Map<int, double> stokFarklari;
      await db.transaction((txn) async {
        stokFarklari = await satisDepo.fisiGuncelleTxn(txn,
            satisId: satisId,
            yeniKalemler: [SatisKalemModel(
              satisId: satisId, urunId: urunId, urunAdi: 'Test Ürün',
              miktar: 5, birimFiyat: 10, toplamTutar: 50,
            )],
            yeniGenelToplam: 50, yeniOdenenTutar: 50);

        for (final girdi in stokFarklari.entries) {
          final gid = const Uuid().v4();
          if (girdi.value > 0) {
            await stokDepo.stokDusTxn(txn, gid, urunId: girdi.key, miktar: girdi.value,
                referansId: satisId, referansTuru: 'fis_guncelleme');
          } else {
            await stokDepo.stokGirTxn(txn, gid, urunId: girdi.key, miktar: -girdi.value,
                referansId: satisId, referansTuru: 'fis_guncelleme');
          }
        }
        await kasaDepo.hareketEkleTxn(txn, KasaHareketModel(
          hareketTipi: 'Satış', tutar: 30, tarih: DateTime.now(),
          aciklama: 'Fiş güncelleme',
        ));
      });

      expect(stokFarklari[urunId], equals(3.0), reason: '5 - 2 = 3 adet fazladan düşülmeli');

      final urun = (await db.query('urunler', where: 'id = ?', whereArgs: [urunId])).first;
      expect((urun['stok'] as num).toDouble(), equals(95.0), reason: '100 - 2 - 3 = 95');

      final satis = (await db.query('satislar', where: 'id = ?', whereArgs: [satisId])).first;
      expect((satis['genel_toplam'] as num).toDouble(), equals(50.0));

      final kalemler = await db.query('satis_kalem', where: 'satis_id = ?', whereArgs: [satisId]);
      expect(kalemler, hasLength(1));
      expect((kalemler.first['miktar'] as num).toDouble(), equals(5.0));
    });

    test('adımlardan biri hata fırlatırsa fiş güncellemesi TAMAMEN geri alınır', () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db, stok: 100, satisFiyati: 10);
      final satisId = await _satisiSimuleEt(db,
          urunId: urunId, miktar: 2, birimFiyat: 10, odemeYontemi: 'Nakit', odenenTutar: 20);

      final satisDepo = SatisDeposu();
      await expectLater(
        db.transaction((txn) async {
          await satisDepo.fisiGuncelleTxn(txn,
              satisId: satisId,
              yeniKalemler: [SatisKalemModel(
                satisId: satisId, urunId: urunId, urunAdi: 'Test Ürün',
                miktar: 9, birimFiyat: 10, toplamTutar: 90,
              )],
              yeniGenelToplam: 90, yeniOdenenTutar: 90);
          throw Exception('Simüle edilmiş hata — kasa adımında');
        }),
        throwsException,
      );

      // Rollback sonrası hem satış başlığı hem kalemler ESKİ haliyle kalmalı.
      final satis = (await db.query('satislar', where: 'id = ?', whereArgs: [satisId])).first;
      expect((satis['genel_toplam'] as num).toDouble(), equals(20.0),
          reason: 'Rollback sonrası eski toplam (20) korunmalı, 90 olmamalı');
      final kalemler = await db.query('satis_kalem', where: 'satis_id = ?', whereArgs: [satisId]);
      expect((kalemler.first['miktar'] as num).toDouble(), equals(2.0));
    });
  });
}
