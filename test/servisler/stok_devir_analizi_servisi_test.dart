// test/servisler/stok_devir_analizi_servisi_test.dart
//
// FAZ 8 — Stok Devir Analizi: sınıflandırma ve sıralama kuralının saf-
// fonksiyon seviyesinde doğrulanması (bkz.
// lib/servisler/stok_devir_analizi_servisi.dart).
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/servisler/stok_devir_analizi_servisi.dart';
import '../helper/test_initializer.dart';

void main() {
  group('stokDevirSatiriHesapla', () {
    test('satış yok, stok var → Hareketsiz', () {
      final s = stokDevirSatiriHesapla(
        const DevirGirdi(urunId: 1, urunAdi: 'X', satilanMiktar: 0, mevcutStok: 20),
      );
      expect(s.sinif, DevirSinifi.hareketsiz);
      expect(s.devirHizi, 0);
    });

    test('stok tükenmiş (0) ama satış var → Hızlı, devir hızı null (sonsuz)', () {
      final s = stokDevirSatiriHesapla(
        const DevirGirdi(urunId: 1, urunAdi: 'X', satilanMiktar: 15, mevcutStok: 0),
      );
      expect(s.sinif, DevirSinifi.hizli);
      expect(s.devirHizi, isNull);
    });

    test('devir hızı >= 3 → Hızlı', () {
      final s = stokDevirSatiriHesapla(
        const DevirGirdi(urunId: 1, urunAdi: 'X', satilanMiktar: 30, mevcutStok: 10),
      );
      expect(s.devirHizi, 3.0);
      expect(s.sinif, DevirSinifi.hizli);
    });

    test('devir hızı 0.5-3 arası → Normal', () {
      final s = stokDevirSatiriHesapla(
        const DevirGirdi(urunId: 1, urunAdi: 'X', satilanMiktar: 10, mevcutStok: 10),
      );
      expect(s.devirHizi, 1.0);
      expect(s.sinif, DevirSinifi.normal);
    });

    test('devir hızı 0.5 altı → Yavaş', () {
      final s = stokDevirSatiriHesapla(
        const DevirGirdi(urunId: 1, urunAdi: 'X', satilanMiktar: 2, mevcutStok: 10),
      );
      expect(s.devirHizi, 0.2);
      expect(s.sinif, DevirSinifi.yavas);
    });

    test('satış yok, stok da yok → mevcutStok<=0 dalına düşer (Hızlı/null), Hareketsiz DEĞİL', () {
      final s = stokDevirSatiriHesapla(
        const DevirGirdi(urunId: 1, urunAdi: 'X', satilanMiktar: 0, mevcutStok: 0),
      );
      expect(s.sinif, DevirSinifi.hizli);
    });
  });

  group('stokDevirAnaliziHesapla sıralama', () {
    test('Hareketsizler her zaman en üstte, aksi halde devir hızı artan sırada', () {
      final sonuc = stokDevirAnaliziHesapla([
        const DevirGirdi(urunId: 1, urunAdi: 'Hızlı', satilanMiktar: 30, mevcutStok: 10),
        const DevirGirdi(urunId: 2, urunAdi: 'Hareketsiz', satilanMiktar: 0, mevcutStok: 5),
        const DevirGirdi(urunId: 3, urunAdi: 'Yavaş', satilanMiktar: 1, mevcutStok: 10),
      ]);
      expect(sonuc.map((s) => s.urunAdi).toList(), ['Hareketsiz', 'Yavaş', 'Hızlı']);
    });
  });

  // StokDevirAnaliziServisi.analizGetir Veritabani() singleton'ı üzerinden
  // çalıştığı için burada AYNI SQL gerçek şema üzerinde doğrulanıyor.
  group('analizGetir SQL (şema doğrulaması)', () {
    late Database db;
    setUp(() async => db = await TestVeritabani.olustur());
    tearDown(() => db.close());

    Future<List<Map<String, Object?>>> _analiz(Database db, int gunSayisi) {
      return db.rawQuery('''
        SELECT u.id AS urun_id, u.urun_adi AS urun_adi, u.stok AS stok,
               COALESCE(sub.satilan, 0) AS satilan
        FROM urunler u
        LEFT JOIN (
          SELECT sk.urun_id AS urun_id, SUM(sk.miktar) AS satilan
          FROM satis_kalem sk
          JOIN satislar s ON s.id = sk.satis_id
          WHERE s.iptal = 0 AND s.is_deleted = 0
            AND DATE(s.tarih) >= DATE('now', 'localtime', ?)
          GROUP BY sk.urun_id
        ) sub ON sub.urun_id = u.id
        WHERE u.is_deleted = 0 AND u.aktif = 1 AND u.stok > 0
      ''', ['-$gunSayisi days']);
    }

    test('stoğu olan ama hiç satılmayan ürün 0 satış olarak görünür', () async {
      await TestVeritabani.ornekUrunEkle(db, urunAdi: 'Tozlanan Ürün', stok: 12);

      final rows = await _analiz(db, 90);

      expect(rows.length, 1);
      expect(rows.first['urun_adi'], 'Tozlanan Ürün');
      expect(rows.first['satilan'], 0);
      expect(rows.first['stok'], 12);
    });

    test('DÜZELTME REGRESYONU: pencere DIŞINDAKİ eski satış "satilan"a dahil EDİLMEZ', () async {
      // Kök neden: eski sorgu tarih filtresini LEFT JOIN'in ON koşuluna
      // koyuyordu — bu, sk.miktar'ı SUM'dan dışlamıyor, sadece s.*
      // alanlarını NULL'a çeviriyordu. 200 gün önceki bir satış, "son 90
      // gün" analizine sızıyordu.
      final urunId =
          await TestVeritabani.ornekUrunEkle(db, urunAdi: 'Eskiden Popüler', stok: 12);
      final eskiSatisId = await db.insert('satislar', {
        'fis_no': 'ESKI-1', 'genel_toplam': 500,
        'tarih': DateTime.now().subtract(const Duration(days: 200)).toIso8601String(),
        'iptal': 0, 'is_deleted': 0,
      });
      await db.insert('satis_kalem', {
        'satis_id': eskiSatisId, 'urun_id': urunId, 'urun_adi': 'Eskiden Popüler',
        'miktar': 500, 'birim_fiyat': 1, 'toplam_tutar': 500,
      });

      final rows = await _analiz(db, 90);

      expect(rows.length, 1);
      expect(rows.first['satilan'], 0,
          reason: '200 gün önceki satış "son 90 gün" penceresine sızmamalı');
    });

    test('stoğu 0 olan pasif ürün rapora hiç girmez', () async {
      await TestVeritabani.ornekUrunEkle(db, urunAdi: 'Tükenmiş', stok: 0);

      final rows = await db.rawQuery('''
        SELECT u.id FROM urunler u
        WHERE u.is_deleted = 0 AND u.aktif = 1 AND u.stok > 0
      ''');

      expect(rows, isEmpty);
    });
  });
}
