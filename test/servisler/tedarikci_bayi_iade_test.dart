// test/servisler/tedarikci_bayi_iade_test.dart
//
// Kullanıcı kuralları (2026-10-07):
//  Tedarikçi iade — fiyat: son alış maliyeti (raf fiyatı DEĞİL), stok AZALIR
//                   (eksiye düşebilir), tedarikçiye olan borcumuz DÜŞER.
//  Bayi iade      — fiyat: bayiye özel toptan fiyatı (raf fiyatı DEĞİL), stok
//                   ARTAR, bayinin borç bakiyesi DÜŞER.
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/depolar/cari_deposu.dart';
import 'package:market_plus/ekranlar/cari/cari_detay_ekrani.dart' show cariHareketleriniGrupla;
import 'package:market_plus/modeller/cari_model.dart';
import 'package:market_plus/servisler/iade_islem_servisi.dart';
import 'package:market_plus/servisler/veri_sagligi_servisi.dart';
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

  Future<double> bakiye(int cariId) async =>
      ((await db.query('cari', columns: ['bakiye'], where: 'id = ?', whereArgs: [cariId]))
              .first['bakiye'] as num)
          .toDouble();

  Future<CariModel> cari(int id) async => (await CariDeposu().idileGetir(id))!;

  /// Cari hareket ekleyip bakiyeyi kanonik kuralla (borç − alacak) kurar.
  Future<void> acilisHareketi(int cariId, {double borc = 0, double alacak = 0}) async {
    await db.insert('cari_hareket', {
      'cari_id': cariId, 'tarih': '2026-10-01T10:00:00', 'fis_tipi': 'Açılış',
      'aciklama': 'test', 'borc': borc, 'alacak': alacak, 'is_deleted': 0,
    });
    await db.rawUpdate(
        'UPDATE cari SET bakiye = (SELECT SUM(borc) - SUM(alacak) FROM cari_hareket '
        'WHERE cari_id = ? AND is_deleted = 0) WHERE id = ?', [cariId, cariId]);
  }

  Future<void> saglikliOlmali() async {
    final sonuclar = await VeriSagligiServisi().tumKontrolleriCalistir();
    for (final id in ['cari_mutabakat', 'stok_mutabakat', 'iade_kalem_stok', 'fk']) {
      final s = sonuclar.firstWhere((x) => x.id == id);
      expect(s.durum, SaglikDurum.yesil, reason: '$id: ${s.mesaj}');
    }
  }

  group('tedarikciyeIadeEt', () {
    late int urunId;
    late int tedarikciId;

    setUp(() async {
      urunId = await TestVeritabani.ornekUrunEkle(db,
          barkod: 'TED1', satisFiyati: 150, alisFiyat: 100, stok: 0);
      await db.update('urunler', {'alis_kdv_oran': 20, 'alis_fiyat_kdv_dahil': 0},
          where: 'id = ?', whereArgs: [urunId]);
      // Stoğun hareket geçmişi olsun (mutabakat tutarlı kalsın): 10 adet giriş.
      await db.insert('stok_hareket', {
        'urun_id': urunId, 'hareket_turu': 'Alim Giris', 'miktar': 10,
        'onceki_stok': 0, 'sonraki_stok': 10, 'tarih': '2026-10-01T09:00:00',
      });
      await db.update('urunler', {'stok': 10}, where: 'id = ?', whereArgs: [urunId]);
      tedarikciId = await TestVeritabani.ornekCariEkle(db, unvan: 'Toptancı A', cariTipi: 'Tedarikçi');
      await acilisHareketi(tedarikciId, alacak: 1200); // 10 × 120 borcumuz
    });

    Future<CariIadeSonucu> iadeEt(double miktar, {int? digerUrun}) async =>
        IadeIslemServisi().tedarikciyeIadeEt(
          tedarikci: await cari(tedarikciId),
          kalemler: [IadeMiktari(urunId: digerUrun ?? urunId, miktar: miktar)],
          kullaniciId: null,
          kullaniciAdi: 'test',
        );

    test('son alış maliyeti (KDV dahil) ile — raf fiyatı değil; stok azalır, borç düşer', () async {
      final sonuc = await iadeEt(3);

      expect(sonuc.toplamTutar, 360, reason: '3 × (100 + %20 KDV), raf fiyatı 150 KULLANILMAZ');
      expect(sonuc.birimFiyatlar[urunId], 120);
      expect(await stok(urunId), 7);
      expect(await bakiye(tedarikciId), -840, reason: 'borcumuz 1200 → 840');

      final baslik = (await db.query('tedarikci_iadeler')).single;
      expect(baslik['cari_id'], tedarikciId);
      expect(baslik['toplam_tutar'], 360);
      expect(baslik['iade_no'], sonuc.fisNo);
      final kalem = (await db.query('tedarikci_iade_kalem')).single;
      expect(kalem['birim_fiyat'], 100, reason: 'KDV hariç alış saklanır');
      expect(kalem['kdv_oran'], 20);
      expect(kalem['toplam_tutar'], 360);

      final hareket = (await db.query('stok_hareket',
              where: 'referans_turu = ? AND referans_id = ?',
              whereArgs: ['tedarikci_iade', sonuc.iadeId]))
          .single;
      expect(hareket['hareket_turu'], 'Tedarikçi İadesi');
      expect((hareket['sonraki_stok'] as num) - (hareket['onceki_stok'] as num), -3);

      final cariHareket = (await db.query('cari_hareket',
              where: 'fis_tipi = ? AND fis_id = ?', whereArgs: ['Tedarikçi İadesi', sonuc.iadeId]))
          .single;
      expect(cariHareket['borc'], 360);
      expect(cariHareket['alacak'], 0);

      // İade 'iade' (müşteri iadesi) tablosuna YAZILMAZ.
      expect(await db.query('iade'), isEmpty);
      await saglikliOlmali();
    });

    test('alımın yazdığı KDV dahil maliyet varsa o kullanılır', () async {
      await db.update('urunler', {'alis_fiyat_kdv_dahil': 125},
          where: 'id = ?', whereArgs: [urunId]);
      expect((await iadeEt(2)).toplamTutar, 250);
    });

    test('stok eksiye düşebilir (B2)', () async {
      await iadeEt(12);
      expect(await stok(urunId), -2);
      await saglikliOlmali();
    });

    test('aynı ürün iki satırda gelirse tek kalemde birleşir', () async {
      final sonuc = await IadeIslemServisi().tedarikciyeIadeEt(
        tedarikci: await cari(tedarikciId),
        kalemler: [IadeMiktari(urunId: urunId, miktar: 1), IadeMiktari(urunId: urunId, miktar: 2)],
        kullaniciId: null,
        kullaniciAdi: 'test',
      );
      expect((await db.query('tedarikci_iade_kalem')).single['miktar'], 3);
      expect(sonuc.toplamTutar, 360);
    });

    test('maliyeti tanımsız ürün reddedilir; hiçbir şey yazılmaz', () async {
      final maliyetsiz = await TestVeritabani.ornekUrunEkle(db, barkod: 'TED0', alisFiyat: 0, stok: 5);
      await expectLater(iadeEt(1, digerUrun: maliyetsiz), throwsA(isA<IadeGecersizHatasi>()));
      expect(await db.query('tedarikci_iadeler'), isEmpty);
      expect(await stok(maliyetsiz), 5);
      expect(await bakiye(tedarikciId), -1200);
    });

    test('tedarikçi olmayan cariye tedarikçi iadesi yapılamaz', () async {
      final musteri = await TestVeritabani.ornekCariEkle(db, unvan: 'Müşteri', cariTipi: 'Müşteri');
      await expectLater(
        IadeIslemServisi().tedarikciyeIadeEt(
            tedarikci: await cari(musteri),
            kalemler: [IadeMiktari(urunId: urunId, miktar: 1)],
            kullaniciId: null,
            kullaniciAdi: 'test'),
        throwsA(isA<IadeGecersizHatasi>()),
      );
    });

    group('tedarikciIadesiniIptalEt (Cari Hareketler\'den silme)', () {
      test('stok ve borç tamamen eski hâline döner, belge iptal olur, ekstrede iz kalmaz',
          () async {
        final sonuc = await iadeEt(3);
        expect(await stok(urunId), 7);

        await IadeIslemServisi().tedarikciIadesiniIptalEt(sonuc.iadeId);

        expect(await stok(urunId), 10, reason: 'iade edilen mal stoğa geri girer');
        expect(await bakiye(tedarikciId), -1200, reason: 'borcumuz eski hâline döner');
        final baslik = (await db.query('tedarikci_iadeler')).single;
        expect(baslik['is_deleted'], 1);
        final iptalHareketi = (await db.query('stok_hareket',
                where: 'referans_turu = ?', whereArgs: ['tedarikci_iade_iptal']))
            .single;
        expect(iptalHareketi['hareket_turu'], 'Tedarikçi İadesi İptali');

        final ekstre = cariHareketleriniGrupla(
            await CariDeposu().hareketleriniGetir(tedarikciId, limit: 100));
        expect(ekstre.where((h) => h.fisTipi.startsWith('Tedarikçi İadesi')), isEmpty,
            reason: 'iptal edilen iade çifti ekstrede gizlenir (alım iptali gibi)');
        await saglikliOlmali();
      });

      test('iki kez iptal edilemez', () async {
        final sonuc = await iadeEt(1);
        await IadeIslemServisi().tedarikciIadesiniIptalEt(sonuc.iadeId);
        await expectLater(IadeIslemServisi().tedarikciIadesiniIptalEt(sonuc.iadeId),
            throwsA(isA<IadeGecersizHatasi>()));
        expect(await stok(urunId), 10, reason: 'ikinci iptal stoğu tekrar artırmamalı');
      });

      test('lot takipli üründe FEFO\'nun düştüğü lot miktarı geri gelir', () async {
        await db.update('urunler', {'lot_takibi': 1}, where: 'id = ?', whereArgs: [urunId]);
        final lotId = await db.insert('lot_seri', {
          'urun_id': urunId, 'lot_no': 'L1', 'miktar': 10, 'aktif': 1,
          'kayit_tarihi': '2026-10-01T09:00:00',
        });
        final sonuc = await iadeEt(4);
        Future<double> lotMiktar() async =>
            ((await db.query('lot_seri', where: 'id = ?', whereArgs: [lotId])).first['miktar'] as num)
                .toDouble();
        expect(await lotMiktar(), 6);

        await IadeIslemServisi().tedarikciIadesiniIptalEt(sonuc.iadeId);
        expect(await lotMiktar(), 10);
        expect(await stok(urunId), 10);
      });

      test('genel cari iptali tedarikçi iadesi satırını reddeder (yarım iş yapmaz)', () async {
        final sonuc = await iadeEt(2);
        final satir = (await CariDeposu().hareketleriniGetir(tedarikciId, limit: 100))
            .firstWhere((h) => h.fisTipi == 'Tedarikçi İadesi' && h.fisId == sonuc.iadeId);
        await expectLater(CariDeposu().hareketIptalEt(satir), throwsA(isA<Exception>()));
        expect(await stok(urunId), 8);
        expect(await bakiye(tedarikciId), -960);
      });
    });

    test('sıfır miktar ve boş liste reddedilir', () async {
      await expectLater(iadeEt(0), throwsA(isA<IadeGecersizHatasi>()));
      await expectLater(
        IadeIslemServisi().tedarikciyeIadeEt(
            tedarikci: await cari(tedarikciId), kalemler: const [], kullaniciId: null, kullaniciAdi: 't'),
        throwsA(isA<IadeGecersizHatasi>()),
      );
    });
  });

  group('bayidenIadeAl', () {
    late int urunId;
    late int bayiId;

    setUp(() async {
      urunId = await TestVeritabani.ornekUrunEkle(db, barkod: 'BAY1', satisFiyati: 100, stok: 0);
      await db.update('urunler', {'toptan_fiyat': 70}, where: 'id = ?', whereArgs: [urunId]);
      bayiId = await TestVeritabani.ornekCariEkle(db, unvan: 'Bayi B', cariTipi: 'Müşteri');
      await db.update('cari', {'musteri_tipi': 'Bayi'}, where: 'id = ?', whereArgs: [bayiId]);
      await acilisHareketi(bayiId, borc: 700); // bayinin bize borcu
    });

    Future<CariIadeSonucu> iadeAl(double miktar) async => IadeIslemServisi().bayidenIadeAl(
          bayi: await cari(bayiId),
          kalemler: [IadeMiktari(urunId: urunId, miktar: miktar)],
          kullaniciId: null,
          kullaniciAdi: 'test',
        );

    test('bayi (toptan) fiyatıyla — raf fiyatı değil; stok artar, bayi borcu düşer', () async {
      final sonuc = await iadeAl(2);

      expect(sonuc.birimFiyatlar[urunId], 70, reason: 'raf fiyatı 100 KULLANILMAZ');
      expect(sonuc.toplamTutar, 140);
      expect(await stok(urunId), 2);
      expect(await bakiye(bayiId), 560, reason: 'bayi borcu 700 → 560');

      final iade = (await db.query('iade')).single;
      expect(iade['cari_id'], bayiId);
      expect(iade['iade_nedeni'], 'Bayi iadesi');
      expect(iade['toplam_tutar'], 140);
      final kalem = (await db.query('iade_kalem')).single;
      expect(kalem['birim_fiyat'], 70);
      final cariHareket = (await db.query('cari_hareket',
              where: 'fis_tipi = ? AND fis_id = ?', whereArgs: ['İade', sonuc.iadeId]))
          .single;
      expect(cariHareket['alacak'], 140);
      expect(cariHareket['borc'], 0);
      expect(await db.query('kasa_hareketleri'), isEmpty, reason: 'kasaya dokunulmaz');
      await saglikliOlmali();
    });

    test('bayinin fiyat grubuna özel ürün fiyatı önceliklidir', () async {
      final grupId = await db.insert('fiyat_gruplari', {'ad': 'Altın Bayi', 'aktif': 1});
      await db.insert('urun_fiyat_gruplari', {'urun_id': urunId, 'fiyat_grubu_id': grupId, 'fiyat': 65});
      await db.update('cari', {'fiyat_grubu_id': grupId}, where: 'id = ?', whereArgs: [bayiId]);

      final sonuc = await iadeAl(2);
      expect(sonuc.birimFiyatlar[urunId], 65);
      expect(await bakiye(bayiId), 570);
    });

    test('bayi olmayan (perakende) cariden bayi iadesi alınamaz', () async {
      final perakende = await TestVeritabani.ornekCariEkle(db, unvan: 'Perakende', cariTipi: 'Müşteri');
      await expectLater(
        IadeIslemServisi().bayidenIadeAl(
            bayi: await cari(perakende),
            kalemler: [IadeMiktari(urunId: urunId, miktar: 1)],
            kullaniciId: null,
            kullaniciAdi: 'test'),
        throwsA(isA<IadeGecersizHatasi>()),
      );
      expect(await db.query('iade'), isEmpty);
    });
  });
}
