// test/hesap_kdv_iskonto_cari_test.dart
//
// KDV / iskonto / kuruş yuvarlama / cari bakiye tutarlılığı (2026-10-03).
// Rastgele (sabit tohumlu) binlerce sepet ve cari hareket dizisiyle
// DEĞİŞMEZLERİ doğrular:
//   • Her para tutarı en fazla 2 ondalıktır (kuruş-altı kalıntı yok).
//   • Satır toplamlarının toplamı = fiş toplamı (kuruşu kuruşuna).
//   • matrah + KDV = KDV dahil tutar (satır bazında, ±1 kuruş).
//   • Kaydedilen satış = ekranda gösterilen sepet.
//   • Cari bakiye = Σ(borç − alacak); borç kadar tahsilat bakiyeyi TAM 0 yapar.
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/cekirdek/utils/para_utils.dart';
import 'package:market_plus/depolar/bekleyen_siparis_deposu.dart';
import 'package:market_plus/depolar/cari_deposu.dart';
import 'package:market_plus/depolar/satis_deposu.dart';
import 'package:market_plus/modeller/cari_hareket_model.dart';
import 'package:market_plus/modeller/satis_kalem_model.dart';
import 'package:market_plus/modeller/satis_model.dart';
import 'package:market_plus/modeller/sepet_model.dart';
import 'package:market_plus/modeller/urun_model.dart';
import 'package:market_plus/saglayicilar/riverpod/sepet_provider.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import 'helper/test_initializer.dart';

bool _kurusMu(double v) => (v * 100 - (v * 100).roundToDouble()).abs() < 1e-6;

UrunModel _urun(double fiyat, String kdv) => UrunModel(
    urunAdi: 'x', satisFiyati: fiyat, kdvOran: kdv, birimAdi: 'Adet', stok: 100);

void main() {
  group('ParaUtils.yuvarla', () {
    test('ticari yuvarlama (yarım kuruş yukarı), ikilik tabandaki tuzaklar dahil', () {
      expect(ParaUtils.yuvarla(1.005), 1.01);
      expect(ParaUtils.yuvarla(2.675), 2.68);
      expect(ParaUtils.yuvarla(26.973), 26.97);
      expect(ParaUtils.yuvarla(26.975), 26.98);
      expect(ParaUtils.yuvarla(0.004), 0);
      expect(ParaUtils.yuvarla(0.005), 0.01);
      expect(ParaUtils.yuvarla(-1.005), -1.01);
      expect(ParaUtils.yuvarla(-0.001), 0);
      expect(ParaUtils.yuvarla(1234567.891), 1234567.89);
      expect(ParaUtils.yuvarla(double.nan), 0);
      expect(ParaUtils.yuvarla(100), 100);
    });
    test('idempotent: yuvarla(yuvarla(x)) == yuvarla(x)', () {
      final r = Random(1);
      for (var i = 0; i < 5000; i++) {
        final v = (r.nextDouble() - 0.3) * 10000;
        expect(ParaUtils.yuvarla(ParaUtils.yuvarla(v)), ParaUtils.yuvarla(v));
      }
    });
  });

  group('SepetKalem / SepetDurum — rastgele sepetler', () {
    final oranlar = ['0', '1', '10', '20'];
    final miktarlar = [1.0, 2.0, 3.0, 7.0, 0.5, 0.25, 1.375, 12.0, 0.333];
    final iskontolar = [0.0, 5.0, 10.0, 12.5, 33.33, 50.0, 7.0];

    test('3000 sepet: kuruş, toplam ve KDV değişmezleri', () {
      final r = Random(42);
      for (var n = 0; n < 3000; n++) {
        final kalemSayisi = 1 + r.nextInt(8);
        final kalemler = <SepetKalem>[];
        for (var i = 0; i < kalemSayisi; i++) {
          final fiyat = (1 + r.nextInt(99999)) / 100; // 0.01 .. 999.99
          kalemler.add(SepetKalem(
            urun: _urun(fiyat, oranlar[r.nextInt(4)]),
            miktar: miktarlar[r.nextInt(miktarlar.length)],
            iskontoOran: iskontolar[r.nextInt(iskontolar.length)],
          ));
        }
        final sepet = SepetDurum(kalemler: kalemler);

        var satirToplami = 0.0;
        for (final k in kalemler) {
          expect(_kurusMu(k.toplamTutar), isTrue, reason: 'satır toplamı kuruş: ${k.toplamTutar}');
          expect(_kurusMu(k.kdvTutar), isTrue, reason: 'satır KDV kuruş: ${k.kdvTutar}');
          expect(_kurusMu(k.iskontoTutar), isTrue);
          expect(k.kdvTutar, lessThanOrEqualTo(k.toplamTutar + 1e-9));
          // matrah + KDV = KDV dahil tutar: matrah'ı bağımsız hesapla.
          final matrah = k.toplamTutar / (1 + k.kdvOran / 100);
          expect((matrah + k.kdvTutar - k.toplamTutar).abs(), lessThanOrEqualTo(0.0051),
              reason: 'matrah+KDV != toplam');
          satirToplami += k.toplamTutar;
        }
        expect(_kurusMu(sepet.araToplam), isTrue);
        expect(sepet.araToplam, closeTo(satirToplami, 0.0051));
        expect(sepet.genelToplam, sepet.araToplam, reason: 'genel iskonto yokken eşit');
        expect(_kurusMu(sepet.kdvToplam), isTrue);
        expect(sepet.kdvToplam, lessThanOrEqualTo(sepet.genelToplam + 1e-9));
      }
    });

    test('iskonto sonrası fiyat ASLA negatif/artan olmaz; %100 iskonto 0 yapar', () {
      final k = SepetKalem(urun: _urun(100, '20'), miktar: 3, iskontoOran: 100);
      expect(k.toplamTutar, 0);
      expect(k.kdvTutar, 0);
      final k2 = SepetKalem(urun: _urun(100, '20'), miktar: 3, iskontoOran: 0);
      expect(k2.toplamTutar, 300);
      expect(k2.kdvTutar, 50, reason: '300 KDV dahil, %20 → 50 (300/1.2=250)');
    });

    test('bilinen örnekler (elle doğrulanmış)', () {
      // 9,99 × 3, %10 iskonto: 8,991 × 3 = 26,973 → 26,97; KDV %10: 26,97/1,1=24,518… → KDV 2,45
      final k = SepetKalem(urun: _urun(9.99, '10'), miktar: 3, iskontoOran: 10);
      expect(k.toplamTutar, 26.97);
      expect(k.kdvTutar, 2.45);
      expect(k.iskontoTutar, 2.997 > 0 ? 3.0 : 0, reason: '29,97 × %10 = 2,997 → 3,00');
      // 100 TL %20 KDV dahil: KDV = 100 − 100/1,2 = 16,67
      expect(SepetKalem(urun: _urun(100, '20')).kdvTutar, 16.67);
      // %1 KDV: 101 TL → 1,00
      expect(SepetKalem(urun: _urun(101, '1')).kdvTutar, 1.0);
      // KDV %0: kdv 0
      expect(SepetKalem(urun: _urun(55.55, '0')).kdvTutar, 0);
    });

    test('genel iskonto: toplam kuruş, KDV matrahla birlikte küçülür', () {
      final kalemler = [SepetKalem(urun: _urun(100, '20'), miktar: 3)];
      final s = SepetDurum(kalemler: kalemler, genelIskontoYuzde: 10);
      expect(s.araToplam, 300);
      expect(s.iskontoTutar, 30);
      expect(s.genelToplam, 270);
      expect(s.kdvToplam, 45, reason: 'KDV 50 × 0,9 = 45 (270 / 1,2 = 225 → KDV 45)');
    });

    test('SatisKalemModel.copyWith yeniden hesapta kuruş ve KDV tutarlı', () {
      final r = Random(7);
      for (var n = 0; n < 2000; n++) {
        final fiyat = (1 + r.nextInt(99999)) / 100;
        final m = SatisKalemModel(
            satisId: 1, urunId: 1, urunAdi: 'x', miktar: 1, birimFiyat: fiyat,
            kdvOran: [1.0, 10.0, 20.0][r.nextInt(3)]);
        final c = m.copyWith(
            miktar: miktarlar[r.nextInt(miktarlar.length)],
            iskontoOran: iskontolar[r.nextInt(iskontolar.length)]);
        expect(_kurusMu(c.toplamTutar), isTrue);
        expect(_kurusMu(c.kdvTutar), isTrue);
        expect(_kurusMu(c.iskontoTutar), isTrue);
        final matrah = c.toplamTutar / (1 + c.kdvOran / 100);
        expect((matrah + c.kdvTutar - c.toplamTutar).abs(), lessThanOrEqualTo(0.0051));
      }
    });
  });

  group('Kaydedilen satış = sepet; cari bakiye kuruşu kuruşuna', () {
    late Database db;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = await TestVeritabani.olustur();
      Veritabani.testVeritabani = db;
    });
    tearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      Veritabani.testVeritabani = null;
      await db.close();
    });

    test('kayıttan sonra satis_kalem toplamları = fiş toplamı = sepet toplamı', () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db, stok: 1000);
      final r = Random(11);
      for (var n = 0; n < 60; n++) {
        final kalemler = <SepetKalem>[];
        for (var i = 0; i < 1 + r.nextInt(6); i++) {
          kalemler.add(SepetKalem(
            urun: _urun((1 + r.nextInt(50000)) / 100, ['1', '10', '20'][r.nextInt(3)]),
            miktar: [1.0, 2.0, 3.0, 0.5, 1.375][r.nextInt(5)],
            iskontoOran: [0.0, 10.0, 12.5][r.nextInt(3)],
          ));
        }
        final sepet = SepetDurum(kalemler: kalemler);
        final satisKalemleri = [
          for (final k in kalemler)
            SatisKalemModel(
              satisId: 0, urunId: urunId, urunAdi: 'x', miktar: k.miktar,
              birimFiyat: k.birimFiyat, toplamTutar: k.toplamTutar,
              iskontoOran: k.iskontoOran, iskontoTutar: k.iskontoTutar,
              kdvOran: k.kdvOran, kdvTutar: k.kdvTutar, netFiyat: k.netFiyat,
            )
        ];
        late int satisId;
        await db.transaction((txn) async {
          satisId = await SatisDeposu().satisEkleTxn(
              txn,
              SatisModel(
                  tarih: DateTime.now(), toplamTutar: sepet.genelToplam,
                  genelToplam: sepet.genelToplam, kdvTutar: sepet.kdvToplam,
                  odenenTutar: sepet.genelToplam, odemeYontemi: 'Nakit'),
              satisKalemleri);
        });
        final satis = (await db.query('satislar', where: 'id = ?', whereArgs: [satisId])).first;
        final toplam = (await db.rawQuery(
                'SELECT SUM(toplam_tutar) t, SUM(kdv_tutar) k FROM satis_kalem WHERE satis_id = ?',
                [satisId]))
            .first;
        final gt = (satis['genel_toplam'] as num).toDouble();
        expect(gt, sepet.genelToplam);
        expect((toplam['t'] as num).toDouble(), closeTo(gt, 0.0051), reason: 'satır toplamları ≠ fiş');
        expect((toplam['k'] as num).toDouble(), closeTo(sepet.kdvToplam, 0.0051));
        expect(_kurusMu((satis['genel_toplam'] as num).toDouble()), isTrue);
      }
    });

    Future<double> bakiye(int id) async => ((await db.query('cari',
            columns: ['bakiye'], where: 'id = ?', whereArgs: [id])).first['bakiye'] as num)
        .toDouble();

    Future<void> hareket(int cariId, {double borc = 0, double alacak = 0, DateTime? tarih}) =>
        db.transaction((txn) => CariDeposu().hareketEkleTxn(
            txn,
            CariHareketModel(
              cariId: cariId, tarih: tarih ?? DateTime.now(),
              fisTipi: borc > 0 ? 'Satış' : 'Tahsilat', aciklama: 't',
              borc: borc, alacak: alacak,
            ))).then((_) {});

    test('kuruş-altı borç hayalet bakiye bırakmaz: 26,973 borç + 26,97 tahsilat = TAM 0', () async {
      final cari = await TestVeritabani.ornekCariEkle(db);
      await hareket(cari, borc: 26.973); // ekrandan kuruş-altı gelse bile
      expect(await bakiye(cari), 26.97);
      await hareket(cari, alacak: 26.97);
      expect(await bakiye(cari), 0.0);
      expect(await CariDeposu().bakiyeUyumsuzlukSayisi(), 0);
    });

    test('rastgele 300 hareket: bakiye = Σ(borç−alacak) kuruşu kuruşuna', () async {
      final cari = await TestVeritabani.ornekCariEkle(db);
      final r = Random(5);
      var beklenenKurus = 0;
      for (var i = 0; i < 300; i++) {
        final kurus = 1 + r.nextInt(500000);
        final tutar = kurus / 100;
        if (r.nextBool()) {
          await hareket(cari, borc: tutar);
          beklenenKurus += kurus;
        } else {
          await hareket(cari, alacak: tutar);
          beklenenKurus -= kurus;
        }
        if (i % 50 == 0) {
          expect(await bakiye(cari), beklenenKurus / 100, reason: 'adım $i');
        }
      }
      expect(await bakiye(cari), beklenenKurus / 100);
      // Mutabakat: elle bozulan bakiye geri düzelir.
      await db.update('cari', {'bakiye': 12345.67}, where: 'id = ?', whereArgs: [cari]);
      await CariDeposu().bakiyeMutabakatYap();
      expect(await bakiye(cari), beklenenKurus / 100);
    });

    test('devreden bakiye + dönem hareketi = güncel bakiye', () async {
      final cari = await TestVeritabani.ornekCariEkle(db);
      final t0 = DateTime(2026, 1, 10);
      final t1 = DateTime(2026, 2, 10);
      await hareket(cari, borc: 100.10, tarih: t0);
      await hareket(cari, alacak: 40.05, tarih: t0.add(const Duration(days: 1)));
      await hareket(cari, borc: 59.99, tarih: t1);
      await hareket(cari, alacak: 10.01, tarih: t1.add(const Duration(days: 1)));
      final devreden = await CariDeposu().devredenBakiye(cari, t1);
      expect(devreden, closeTo(60.05, 1e-9));
      expect(ParaUtils.yuvarla(devreden + 59.99 - 10.01), await bakiye(cari));
    });

    test('hareket iptali bakiyeyi öncekine TAM döndürür', () async {
      final cari = await TestVeritabani.ornekCariEkle(db);
      await hareket(cari, borc: 250.50);
      await hareket(cari, borc: 33.33);
      final onceki = await bakiye(cari);
      await hareket(cari, alacak: 100.01);
      final h = (await CariDeposu().hareketleriniGetir(cari))
          .firstWhere((h) => h.alacak == 100.01);
      await CariDeposu().hareketIptalEt(h);
      expect(await bakiye(cari), onceki);
    });
  });

  group('Satış başlığı KDV/iskonto (Kâr-Zarar KDV\'si, AI raporları)', () {
    late Database db;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = await TestVeritabani.olustur();
      Veritabani.testVeritabani = db;
    });
    tearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      Veritabani.testVeritabani = null;
      await db.close();
    });

    SatisKalemModel kalem(int urunId, double fiyat, double miktar, double kdv, {double isk = 0}) {
      final k = SepetKalem(urun: _urun(fiyat, '${kdv.toInt()}'), miktar: miktar, iskontoOran: isk);
      return SatisKalemModel(
        satisId: 0, urunId: urunId, urunAdi: 'x', miktar: k.miktar,
        birimFiyat: k.birimFiyat, toplamTutar: k.toplamTutar,
        iskontoOran: k.iskontoOran, iskontoTutar: k.iskontoTutar,
        kdvOran: kdv, kdvTutar: k.kdvTutar, netFiyat: k.netFiyat,
      );
    }

    test('POS satışı başlığa kalemlerden kdv_tutar/iskonto_tutar yazar (önceden hep 0)', () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db, stok: 100);
      final kalemler = [
        kalem(urunId, 100, 3, 20),            // KDV 50
        kalem(urunId, 9.99, 3, 10, isk: 10),  // 26,97 → KDV 2,45; iskonto 3,00
      ];
      late int id;
      await db.transaction((txn) async {
        id = await SatisDeposu().satisEkleTxn(
            txn,
            SatisModel(tarih: DateTime.now(), genelToplam: 326.97, toplamTutar: 326.97),
            kalemler);
      });
      final s = (await db.query('satislar', where: 'id = ?', whereArgs: [id])).first;
      expect((s['kdv_tutar'] as num).toDouble(), 52.45);
      expect((s['iskonto_tutar'] as num).toDouble(), 3.0);
    });

    test('fiş güncellenince başlık KDV/iskonto yeni kalemlerle yenilenir', () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db, stok: 100);
      late int id;
      await db.transaction((txn) async {
        id = await SatisDeposu().satisEkleTxn(
            txn,
            SatisModel(tarih: DateTime.now(), genelToplam: 300, toplamTutar: 300),
            [kalem(urunId, 100, 3, 20)]);
        await SatisDeposu().fisiGuncelleTxn(txn,
            satisId: id,
            yeniKalemler: [kalem(urunId, 100, 1, 20)],
            yeniGenelToplam: 100.004,
            yeniOdenenTutar: 100.004);
      });
      final s = (await db.query('satislar', where: 'id = ?', whereArgs: [id])).first;
      expect((s['genel_toplam'] as num).toDouble(), 100.0);
      expect((s['kdv_tutar'] as num).toDouble(), 16.67);
    });
  });

  group('Bekleyen (toptan) sipariş kalemi — kuruş ve KDV', () {
    test('rastgele 2000 kalem: tutarlar kuruş, KDV toplamın içinden', () {
      final r = Random(3);
      for (var n = 0; n < 2000; n++) {
        final k = BekleyenSiparisKalemGirdi(
          urunId: 1, urunAdi: 'x', birimAdi: 'Koli',
          birimCarpani: [1.0, 6.0, 12.0, 24.0][r.nextInt(4)],
          miktar: [1.0, 2.0, 3.0, 0.5][r.nextInt(4)],
          birimFiyat: (1 + r.nextInt(50000)) / 100, alisFiyat: 1,
          iskontoOran: [0.0, 5.0, 12.5, 33.33][r.nextInt(4)],
          kdvOran: [0.0, 1.0, 10.0, 20.0][r.nextInt(4)],
        );
        expect(_kurusMu(k.toplamTutar), isTrue);
        expect(_kurusMu(k.iskontoTutar), isTrue);
        expect(_kurusMu(k.kdvTutar), isTrue);
        expect(k.kdvTutar, lessThanOrEqualTo(k.toplamTutar + 1e-9));
      }
    });
  });
}
