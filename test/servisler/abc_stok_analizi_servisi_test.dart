// test/servisler/abc_stok_analizi_servisi_test.dart
//
// FAZ 8 — ABC Stok Analizi: Pareto sınıflandırma kuralının saf-fonksiyon
// seviyesinde doğrulanması (bkz. lib/servisler/abc_stok_analizi_servisi.dart).
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/servisler/abc_stok_analizi_servisi.dart';
import '../helper/test_initializer.dart';

void main() {
  group('abcSinifiHesapla', () {
    test('hiç girdi yoksa boş liste döner', () {
      expect(abcSinifiHesapla([]), isEmpty);
    });

    test('tek ürün varsa kümülatif %100 olur ve eşik-sonrası (endpoint) kurala göre C sınıfına düşer', () {
      // Klasik Pareto sınıflandırması kümülatif yüzdeyi ÜRÜN DAHİL EDİLDİKTEN
      // SONRAKİ (endpoint) değerle karşılaştırır — tek SKU'lu (veya baskın
      // tek üründen oluşan) uç durumlarda sezgiye aykırı ama standart/
      // dokümante edilmiş davranış budur.
      final sonuc = abcSinifiHesapla([
        const AbcUrunGirdi(urunId: 1, urunAdi: 'Tek Ürün', tutar: 1000, miktar: 10),
      ]);
      expect(sonuc.single.kumulatifYuzde, 100.0);
      expect(sonuc.single.sinif, AbcSinifi.c);
    });

    test('büyükten küçüğe sıralanır ve kümülatif yüzdeye göre A/B/C atanır', () {
      // Toplam 1000: 800 (%80) + 150 (%95) + 50 (%100)
      final sonuc = abcSinifiHesapla([
        const AbcUrunGirdi(urunId: 3, urunAdi: 'Düşük', tutar: 50, miktar: 1),
        const AbcUrunGirdi(urunId: 1, urunAdi: 'Yüksek', tutar: 800, miktar: 1),
        const AbcUrunGirdi(urunId: 2, urunAdi: 'Orta', tutar: 150, miktar: 1),
      ]);

      expect(sonuc.map((s) => s.urunAdi).toList(), ['Yüksek', 'Orta', 'Düşük']);
      expect(sonuc[0].sinif, AbcSinifi.a); // kümülatif %80
      expect(sonuc[1].sinif, AbcSinifi.b); // kümülatif %95
      expect(sonuc[2].sinif, AbcSinifi.c); // kümülatif %100
    });

    test('eşik sınırında (%80 tam) A sınıfında kalır', () {
      final sonuc = abcSinifiHesapla([
        const AbcUrunGirdi(urunId: 1, urunAdi: 'X', tutar: 80, miktar: 1),
        const AbcUrunGirdi(urunId: 2, urunAdi: 'Y', tutar: 20, miktar: 1),
      ]);
      expect(sonuc[0].kumulatifYuzde, 80.0);
      expect(sonuc[0].sinif, AbcSinifi.a);
    });

    test('toplam ciro 0 ise boş liste döner (sıfıra bölme yok)', () {
      final sonuc = abcSinifiHesapla([
        const AbcUrunGirdi(urunId: 1, urunAdi: 'X', tutar: 0, miktar: 0),
      ]);
      expect(sonuc, isEmpty);
    });
  });

  // AbcStokAnaliziServisi.analizGetir Veritabani() singleton'ı üzerinden
  // çalıştığı için (diğer servis testlerinde olduğu gibi) burada AYNI SQL
  // gerçek şema üzerinde doğrulanıyor.
  group('analizGetir SQL (şema doğrulaması)', () {
    late Database db;
    setUp(() async => db = await TestVeritabani.olustur());
    tearDown(() => db.close());

    test('ürün bazlı ciro grup toplamı JOIN ile doğru hesaplanır, iptaller hariç', () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db, urunAdi: 'Ekmek');
      final satisId = await db.insert('satislar', {
        'fis_no': 'F1', 'genel_toplam': 40, 'tarih': '2026-09-01 10:00:00',
        'iptal': 0, 'is_deleted': 0,
      });
      await db.insert('satis_kalem', {
        'satis_id': satisId, 'urun_id': urunId, 'urun_adi': 'Ekmek',
        'miktar': 4, 'birim_fiyat': 10, 'toplam_tutar': 40,
      });
      final iptalSatisId = await db.insert('satislar', {
        'fis_no': 'F2', 'genel_toplam': 999, 'tarih': '2026-09-02 10:00:00',
        'iptal': 1, 'is_deleted': 0,
      });
      await db.insert('satis_kalem', {
        'satis_id': iptalSatisId, 'urun_id': urunId, 'urun_adi': 'Ekmek',
        'miktar': 99, 'birim_fiyat': 10, 'toplam_tutar': 999,
      });

      final rows = await db.rawQuery('''
        SELECT sk.urun_id AS urun_id, sk.urun_adi AS urun_adi,
               SUM(sk.toplam_tutar) AS tutar, SUM(sk.miktar) AS miktar
        FROM satis_kalem sk
        JOIN satislar s ON s.id = sk.satis_id
        WHERE s.iptal = 0 AND s.is_deleted = 0
          AND DATE(s.tarih) >= DATE('now', 'localtime', ?)
        GROUP BY sk.urun_id
      ''', ['-365 days']);

      expect(rows.length, 1);
      expect(rows.first['tutar'], 40);
    });
  });
}
