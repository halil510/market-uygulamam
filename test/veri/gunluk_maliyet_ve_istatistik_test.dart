// test/veri/gunluk_maliyet_ve_istatistik_test.dart
//
// Madde 31 (Dashboard) denetimi, 2026-09-20 — SatisDeposu.gunlukMaliyet()
// (yeni) ve gunlukIstatistik()'in yeni 'cari' anahtarı. SatisDeposu
// Veritabani() singleton'ına bağımlı olduğundan (projenin yerleşik test
// deseni), BİREBİR aynı SQL gerçek şema üzerinde doğrulanıyor. Sorgular
// DATE('now','localtime') kullandığından, test satırları BUGÜNÜN
// tarihiyle ekleniyor.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import '../helper/test_initializer.dart';

Future<double> _gunlukMaliyet(Database db) async {
  final rows = await db.rawQuery('''
    SELECT COALESCE(SUM(
      CASE WHEN sk.alis_fiyat > 0 THEN sk.miktar * sk.alis_fiyat
           ELSE sk.miktar * COALESCE(u.alis_fiyat, 0) END
    ), 0) as maliyet
    FROM satis_kalem sk
    JOIN satislar s ON sk.satis_id = s.id
    LEFT JOIN urunler u ON sk.urun_id = u.id
    WHERE DATE(s.tarih) = DATE('now','localtime')
      AND s.iptal = 0 AND s.is_deleted = 0
  ''');
  return (rows.first['maliyet'] as num?)?.toDouble() ?? 0;
}

Future<Map<String, double>> _gunlukIstatistik(Database db) async {
  final res = await db.rawQuery(
    "SELECT COUNT(*) as satis_sayisi, SUM(genel_toplam) as ciro, "
    "SUM(iskonto_tutar) as iskonto, "
    "SUM(CASE WHEN odeme_yontemi = 'Nakit' THEN odenen_tutar ELSE 0 END) as nakit, "
    "SUM(CASE WHEN odeme_yontemi = 'Kredi Kartı' THEN odenen_tutar ELSE 0 END) as kart, "
    "SUM(CASE WHEN odeme_yontemi = 'Cari' THEN genel_toplam ELSE 0 END) as cari "
    "FROM satislar "
    "WHERE DATE(tarih) = DATE('now','localtime') AND iptal = 0 AND is_deleted = 0",
  );
  if (res.isEmpty) return {};
  final r = res.first;
  return {
    'satis_sayisi': (r['satis_sayisi'] as num?)?.toDouble() ?? 0,
    'ciro':         (r['ciro']         as num?)?.toDouble() ?? 0,
    'nakit':        (r['nakit']        as num?)?.toDouble() ?? 0,
    'kart':         (r['kart']         as num?)?.toDouble() ?? 0,
    'cari':         (r['cari']         as num?)?.toDouble() ?? 0,
  };
}

void main() {
  late Database db;
  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  final simdi = DateTime.now();

  Future<int> satisEkle({String odemeYontemi = 'Nakit', double genelToplam = 100, double odenenTutar = 100}) {
    return db.insert('satislar', {
      'tarih': simdi.toIso8601String(), 'odeme_yontemi': odemeYontemi,
      'genel_toplam': genelToplam, 'odenen_tutar': odenenTutar, 'iptal': 0, 'is_deleted': 0,
    });
  }

  group('gunlukMaliyet', () {
    test('bugünkü satışların tarihsel maliyeti (sk.alis_fiyat) toplanır', () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db, alisFiyat: 999); // güncel fiyat KULLANILMAMALI
      final satisId = await satisEkle();
      await db.insert('satis_kalem', {
        'satis_id': satisId, 'urun_id': urunId, 'urun_adi': 'Test',
        'miktar': 2, 'birim_fiyat': 100, 'alis_fiyat': 60, 'toplam_tutar': 200,
      });

      expect(await _gunlukMaliyet(db), 120.0, reason: '2 × 60 (tarihsel) = 120, 999 (güncel) DEĞİL');
    });

    test('dünkü satış bugünkü maliyete dahil edilmez', () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db, alisFiyat: 50);
      final dun = simdi.subtract(const Duration(days: 1));
      final satisId = await db.insert('satislar', {
        'tarih': dun.toIso8601String(), 'genel_toplam': 100, 'iptal': 0, 'is_deleted': 0,
      });
      await db.insert('satis_kalem', {
        'satis_id': satisId, 'urun_id': urunId, 'urun_adi': 'Test',
        'miktar': 1, 'birim_fiyat': 100, 'alis_fiyat': 50, 'toplam_tutar': 100,
      });

      expect(await _gunlukMaliyet(db), 0.0);
    });
  });

  group('gunlukIstatistik — cari anahtarı', () {
    test('Cari satışlar genel_toplam ile sayılır (odenen_tutar 0 olsa bile)', () async {
      await satisEkle(odemeYontemi: 'Cari', genelToplam: 250, odenenTutar: 0);

      final ist = await _gunlukIstatistik(db);

      expect(ist['cari'], 250.0);
      expect(ist['nakit'], 0.0);
    });

    test('Nakit/Kart/Cari karışık günde her biri doğru toplanır', () async {
      await satisEkle(odemeYontemi: 'Nakit', genelToplam: 100, odenenTutar: 100);
      await satisEkle(odemeYontemi: 'Kredi Kartı', genelToplam: 50, odenenTutar: 50);
      await satisEkle(odemeYontemi: 'Cari', genelToplam: 75, odenenTutar: 0);

      final ist = await _gunlukIstatistik(db);

      expect(ist['nakit'], 100.0);
      expect(ist['kart'], 50.0);
      expect(ist['cari'], 75.0);
      expect(ist['ciro'], 225.0);
    });
  });
}
