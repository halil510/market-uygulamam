// test/urun_fiyat_maliyet_tarih_test.dart
//
// Ürün listesi: "Fiyat Güncelleme Tarihi" yalnızca SATIŞ fiyatı değişince,
// "Maliyet Güncelleme Tarihi" yalnızca ALIŞ fiyatı değişince damgalanır —
// tüm yazma yollarında (tekli/toplu/döviz/alım/excel). Ayrıca kayıtlı kolon
// tercihinde sonradan eklenen kolonlar kaybolmaz.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/depolar/urun_deposu.dart';
import 'package:market_plus/ekranlar/urun/masaustu/urun_masaustu_gorunum.dart';
import 'package:market_plus/modeller/urun_model.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import 'helper/test_initializer.dart';

void main() {
  late Database db;
  late int id;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await TestVeritabani.olustur();
    Veritabani.testVeritabani = db;
    id = await TestVeritabani.ornekUrunEkle(db, satisFiyati: 100, alisFiyat: 80);
    await db.update('urunler', {'alis_kdv_oran': 20, 'alis_fiyat_kdv_dahil': 96},
        where: 'id = ?', whereArgs: [id]);
  });
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    Veritabani.testVeritabani = null;
    await db.close();
  });

  Future<Map<String, Object?>> satir() async =>
      (await db.query('urunler', where: 'id = ?', whereArgs: [id])).first;

  group('fiyatMaliyetDamgala', () {
    test('satış fiyatı değişti → yalnız fiyat tarihi', () {
      final yeni = <String, dynamic>{'satis_fiyati': 120.0, 'alis_fiyat': 80.0};
      UrunDeposu.fiyatMaliyetDamgala(
          yeni, {'satis_fiyati': 100.0, 'alis_fiyat': 80.0}, 'T1');
      expect(yeni['fiyat_guncelleme_tarih'], 'T1');
      expect(yeni.containsKey('maliyet_guncelleme_tarih'), isFalse);
    });
    test('alış fiyatı değişti → yalnız maliyet tarihi', () {
      final yeni = <String, dynamic>{'satis_fiyati': 100.0, 'alis_fiyat': 90.0};
      UrunDeposu.fiyatMaliyetDamgala(
          yeni, {'satis_fiyati': 100.0, 'alis_fiyat': 80.0}, 'T1');
      expect(yeni['maliyet_guncelleme_tarih'], 'T1');
      expect(yeni.containsKey('fiyat_guncelleme_tarih'), isFalse);
    });
    test('değişmedi (int/double farkı dahil) → hiçbiri', () {
      final yeni = <String, dynamic>{'satis_fiyati': 100, 'alis_fiyat': 80.0};
      UrunDeposu.fiyatMaliyetDamgala(
          yeni, {'satis_fiyati': 100.0, 'alis_fiyat': 80}, 'T1');
      expect(yeni.containsKey('fiyat_guncelleme_tarih'), isFalse);
      expect(yeni.containsKey('maliyet_guncelleme_tarih'), isFalse);
    });
  });

  group('yazma yolları', () {
    test('alanGuncelle: satış fiyatı → fiyat tarihi, maliyet tarihi boş', () async {
      await UrunDeposu().alanGuncelle(id, {'satis_fiyati': 130.0});
      final s = await satir();
      expect(s['fiyat_guncelleme_tarih'], isNotNull);
      expect(s['maliyet_guncelleme_tarih'], isNull);
    });

    test('alanGuncelle: alış fiyatı → maliyet tarihi, fiyat tarihi boş', () async {
      await UrunDeposu().alanGuncelle(id, {'alis_fiyat': 85.0});
      final s = await satir();
      expect(s['maliyet_guncelleme_tarih'], isNotNull);
      expect(s['fiyat_guncelleme_tarih'], isNull);
    });

    test('alanGuncelle: aynı değer yazılırsa tarih DEĞİŞMEZ', () async {
      await UrunDeposu().alanGuncelle(id, {'satis_fiyati': 100.0, 'alis_fiyat': 80.0});
      final s = await satir();
      expect(s['fiyat_guncelleme_tarih'], isNull);
      expect(s['maliyet_guncelleme_tarih'], isNull);
    });

    test('topluAlanGuncelle (döviz ekranı): alış + KDV dahil → maliyet tarihi', () async {
      await UrunDeposu().topluAlanGuncelle({
        id: {'alis_fiyat': 90.0, 'alis_fiyat_kdv_dahil': 108.0}
      });
      final s = await satir();
      expect(s['maliyet_guncelleme_tarih'], isNotNull);
      expect(s['fiyat_guncelleme_tarih'], isNull);
    });

    test('alisFiyatiGuncelle → maliyet tarihi (fiyat tarihi DEĞİL), KDV dahil yenilenir', () async {
      await UrunDeposu().alisFiyatiGuncelle(id, 100);
      final s = await satir();
      expect(s['maliyet_guncelleme_tarih'], isNotNull);
      expect(s['fiyat_guncelleme_tarih'], isNull);
      expect((s['alis_fiyat_kdv_dahil'] as num).toDouble(), 120.0);
    });

    test('topluFiyatGuncelle satış → fiyat tarihi; alış → maliyet tarihi + KDV dahil', () async {
      await UrunDeposu().topluFiyatGuncelle([id], 10, tip: 'satis');
      var s = await satir();
      expect(s['fiyat_guncelleme_tarih'], isNotNull);
      expect(s['maliyet_guncelleme_tarih'], isNull);
      expect((s['satis_fiyati'] as num).toDouble(), closeTo(110, 1e-9));

      await UrunDeposu().topluFiyatGuncelle([id], 25, tip: 'alis');
      s = await satir();
      expect(s['maliyet_guncelleme_tarih'], isNotNull);
      expect((s['alis_fiyat'] as num).toDouble(), closeTo(100, 1e-9));
      expect((s['alis_fiyat_kdv_dahil'] as num).toDouble(), closeTo(120, 1e-9),
          reason: 'toplu alış güncellemesi KDV dahil maliyeti bayat bırakmamalı');
    });

    test('topluFiyatUygula (satış) → fiyat tarihi', () async {
      await UrunDeposu().topluFiyatUygula({id: 150.0});
      final s = await satir();
      expect(s['fiyat_guncelleme_tarih'], isNotNull);
      expect(s['maliyet_guncelleme_tarih'], isNull);
    });

    test('yeni ürün: ilk fiyat ve maliyet tarihi dolu gelir', () async {
      final yeniId = await UrunDeposu().ekle(const UrunModel(
          urunAdi: 'Yeni', barkod: 'YENI-1', satisFiyati: 10, alisFiyat: 6));
      final s = (await db.query('urunler', where: 'id = ?', whereArgs: [yeniId])).first;
      expect(s['fiyat_guncelleme_tarih'], isNotNull);
      expect(s['maliyet_guncelleme_tarih'], isNotNull);
    });
  });

  group('kolon tercihi birleştirme', () {
    final gecerli = UrunMasaustuGorunum.katalog.map((k) => k.anahtar).toSet();

    test('katalogda fiyat/maliyet güncelleme kolonları VAR', () {
      for (final a in [
        'fiyatGuncTarih', 'fiyatGuncKullanici',
        'maliyetGuncTarih', 'maliyetGuncKullanici',
      ]) {
        expect(gecerli, contains(a));
      }
    });

    test('eski kayıt (bilinen yok): yalnız fiyat/maliyet kolonları eklenir, kapatılanlar geri gelmez', () {
      final kayitli = ['urunAdi', 'barkod', 'stok'];
      final s = UrunMasaustuGorunum.kolonTercihiBirlestir(
          kayitli: kayitli, bilinen: null, gecerli: gecerli);
      expect(s, containsAll(['urunAdi', 'barkod', 'stok']));
      expect(s, containsAll(['fiyatGuncTarih', 'maliyetGuncTarih']));
      expect(s.contains('renk'), isFalse, reason: 'kullanıcı bilerek açmamış');
    });

    test('bilinen listesi varsa yalnız YENİ eklenen kolonlar açılır', () {
      final bilinen = gecerli.difference({'fiyatGuncTarih'}).toList();
      final kayitli = ['urunAdi', 'barkod'];
      final s = UrunMasaustuGorunum.kolonTercihiBirlestir(
          kayitli: kayitli, bilinen: bilinen, gecerli: gecerli);
      expect(s, contains('fiyatGuncTarih'));
      expect(s.contains('renk'), isFalse);
    });

    test('kullanıcı kapattığı bilinen kolon tekrar açılmaz; silinmiş kolon atılır', () {
      final s = UrunMasaustuGorunum.kolonTercihiBirlestir(
          kayitli: ['urunAdi', 'artikSilinmisKolon'],
          bilinen: gecerli.toList(),
          gecerli: gecerli);
      expect(s, {'urunAdi'});
    });
  });
}
