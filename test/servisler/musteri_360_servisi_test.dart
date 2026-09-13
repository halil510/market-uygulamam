// test/servisler/musteri_360_servisi_test.dart
//
// FAZ 7 — Müşteri 360/CRM: segment sınıflandırma kuralının saf-fonksiyon
// seviyesinde doğrulanması (bkz. lib/servisler/musteri_360_servisi.dart).
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/servisler/musteri_360_servisi.dart';
import '../helper/test_initializer.dart';

void main() {
  // Musteri360Servisi.istatistikGetir Veritabani() singleton'ı üzerinden
  // çalıştığı için (diğer depo/servis testlerinde olduğu gibi, bkz.
  // veri_sagligi_satis_kasa_test.dart) burada servisin AYNI SQL'i gerçek
  // şema üzerinde doğrudan doğrulanıyor — sütun/tablo adı hatalarını
  // (ör. yanlış JOIN) yakalamak için.
  group('istatistikGetir SQL (şema doğrulaması)', () {
    late Database db;
    setUp(() async => db = await TestVeritabani.olustur());
    tearDown(() => db.close());

    test('iptal edilmemiş satışlar toplanır, iptaller hariç tutulur', () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db);
      final cariId = await TestVeritabani.ornekCariEkle(db);
      await db.insert('satislar', {
        'fis_no': 'F1', 'cari_id': cariId, 'genel_toplam': 100,
        'tarih': '2026-09-01 10:00:00', 'iptal': 0, 'is_deleted': 0,
      });
      await db.insert('satislar', {
        'fis_no': 'F2', 'cari_id': cariId, 'genel_toplam': 9999,
        'tarih': '2026-09-05 10:00:00', 'iptal': 1, 'is_deleted': 0,
      });

      final rows = await db.rawQuery('''
        SELECT tarih, genel_toplam FROM satislar
        WHERE cari_id = ? AND iptal = 0 AND is_deleted = 0
        ORDER BY tarih ASC
      ''', [cariId]);

      expect(rows.length, 1);
      expect(rows.first['genel_toplam'], 100);
      // urunId sadece tablo FK bütünlüğü için ekleniyor, sorguda kullanılmıyor.
      expect(urunId, isPositive);
    });

    test('ürün bazlı en çok alınanlar JOIN ile doğru toplanır', () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db, urunAdi: 'Süt');
      final cariId = await TestVeritabani.ornekCariEkle(db);
      final satisId = await db.insert('satislar', {
        'fis_no': 'F1', 'cari_id': cariId, 'genel_toplam': 50,
        'tarih': '2026-09-01 10:00:00', 'iptal': 0, 'is_deleted': 0,
      });
      await db.insert('satis_kalem', {
        'satis_id': satisId, 'urun_id': urunId, 'urun_adi': 'Süt',
        'miktar': 2, 'birim_fiyat': 25, 'toplam_tutar': 50,
      });

      final rows = await db.rawQuery('''
        SELECT sk.urun_adi AS urun_adi, SUM(sk.miktar) AS miktar, SUM(sk.toplam_tutar) AS tutar
        FROM satis_kalem sk
        JOIN satislar s ON s.id = sk.satis_id
        WHERE s.cari_id = ? AND s.iptal = 0 AND s.is_deleted = 0
        GROUP BY sk.urun_adi
        ORDER BY tutar DESC
        LIMIT 5
      ''', [cariId]);

      expect(rows.length, 1);
      expect(rows.first['urun_adi'], 'Süt');
      expect(rows.first['tutar'], 50);
    });
  });
  group('musteriSegmentiHesapla', () {
    test('hiç satışı olmayan cari → Yeni', () {
      final s = musteriSegmentiHesapla(
        islemSayisi: 0,
        sonSatistanGecenGun: null,
        riskKullanimOrani: 0,
        son180GunIslemSayisi: 0,
      );
      expect(s, MusteriSegmenti.yeni);
    });

    test('risk kullanımı %90 ve üzeri → Riskli (diğer her şeyden önce)', () {
      final s = musteriSegmentiHesapla(
        islemSayisi: 20,
        sonSatistanGecenGun: 1,
        riskKullanimOrani: 0.95,
        son180GunIslemSayisi: 10,
      );
      expect(s, MusteriSegmenti.riskli);
    });

    test('en az 3 satışı olup 90 günden fazla süredir alışveriş yapmayan → Kaybedilmek Üzere', () {
      final s = musteriSegmentiHesapla(
        islemSayisi: 5,
        sonSatistanGecenGun: 120,
        riskKullanimOrani: 0,
        son180GunIslemSayisi: 0,
      );
      expect(s, MusteriSegmenti.kaybedilmekUzere);
    });

    test('2 satışı olup uzun süredir gelmeyen "Kaybedilmek Üzere" SAYILMAZ (eşik: en az 3 işlem)', () {
      final s = musteriSegmentiHesapla(
        islemSayisi: 2,
        sonSatistanGecenGun: 200,
        riskKullanimOrani: 0,
        son180GunIslemSayisi: 0,
      );
      expect(s, isNot(MusteriSegmenti.kaybedilmekUzere));
    });

    test('son 180 günde 6+ işlem → VIP', () {
      final s = musteriSegmentiHesapla(
        islemSayisi: 10,
        sonSatistanGecenGun: 2,
        riskKullanimOrani: 0,
        son180GunIslemSayisi: 6,
      );
      expect(s, MusteriSegmenti.vip);
    });

    test('son 180 günde 2-5 işlem → Sadık', () {
      final s = musteriSegmentiHesapla(
        islemSayisi: 4,
        sonSatistanGecenGun: 10,
        riskKullanimOrani: 0,
        son180GunIslemSayisi: 3,
      );
      expect(s, MusteriSegmenti.sadik);
    });

    test('düşük frekans, riskte değil, kaybedilmiyor → Standart', () {
      final s = musteriSegmentiHesapla(
        islemSayisi: 1,
        sonSatistanGecenGun: 5,
        riskKullanimOrani: 0,
        son180GunIslemSayisi: 1,
      );
      expect(s, MusteriSegmenti.standart);
    });
  });

  group('MusteriIstatistik.sonSatistanGecenGun', () {
    test('satış yoksa null döner', () {
      expect(MusteriIstatistik.bos.sonSatistanGecenGun(DateTime.now()), isNull);
    });

    test('son satış tarihinden bugüne geçen gün doğru hesaplanır', () {
      final simdi = DateTime(2026, 9, 13);
      final istat = MusteriIstatistik(
        islemSayisi: 1,
        toplamCiro: 100,
        ortalamaSepet: 100,
        sonSatisTarihi: DateTime(2026, 9, 1),
        ilkSatisTarihi: DateTime(2026, 9, 1),
        ortalamaGunAraligi: null,
        enCokAlinanUrunler: const [],
      );
      expect(istat.sonSatistanGecenGun(simdi), 12);
    });
  });
}
