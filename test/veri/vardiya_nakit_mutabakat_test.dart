// test/veri/vardiya_nakit_mutabakat_test.dart
//
// Derin analiz turunda bulunan hata: vardiya_ekrani.dart'taki "Beklenen
// Kasa" hesabı SADECE nakit SATIŞLARI (satislar tablosu) sayıyordu —
// vardiya sırasındaki nakit tahsilat/gider/ödeme/virman hiç dahil
// değildi, kasiyer hiçbir hata yapmadığı halde "fazla/eksik" çıkabiliyordu.
// Düzeltme: KasaDeposu.nakitDegisimi(baslangic) — guncelBakiyeNakit()
// ile AYNI filtre, ama [baslangic]'tan bu yana.
//
// KasaDeposu Veritabani() singleton'ı üzerinden çalıştığı için (diğer
// depo testlerinde olduğu gibi) burada AYNI SQL gerçek şema üzerinde
// doğrulanıyor.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import '../helper/test_initializer.dart';

// 🔴 DÜZELTME (Madde 12 denetimi, 2026-09-16): bu kopya 'Gider İptali'yi
// EKSİK bırakıyordu — KasaHareketModel.girisTipleri (gerçek kaynak,
// lib/modeller/kasa_hareket_model.dart) ile karşılaştırılınca ortaya
// çıktı (yeni bir test bunu beklenenden farklı bir sonuçla yakaladı).
// Artık gerçek kaynakla BİREBİR aynı.
const _girisTipleri = {
  'Satış', 'Tahsilat', 'AçılışKasa', 'Giriş', 'Virman Giriş',
  'Iade Iptali', 'İade İptali', 'Ödeme Girişi', 'Gider İptali',
};

Future<double> _nakitDegisimi(Database db, DateTime baslangic) async {
  final icYer = List.filled(_girisTipleri.length, '?').join(',');
  final rows = await db.rawQuery('''
    SELECT COALESCE(SUM(
      CASE WHEN hareket_tipi IN ($icYer) THEN tutar ELSE -tutar END
    ), 0) as bakiye
    FROM kasa_hareketleri
    WHERE deleted_at IS NULL AND (odeme_yontemi IS NULL OR odeme_yontemi = 'Nakit')
      AND datetime(tarih) >= datetime(?)
  ''', [..._girisTipleri, baslangic.toIso8601String()]);
  return (rows.first['bakiye'] as num?)?.toDouble() ?? 0;
}

/// KasaDeposu.nakitDegisimiKirilim() ile BİREBİR aynı SQL — Madde 12
/// denetimi (2026-09-16): "Diğer Nakit Hareketler" lump-sum satırının
/// Tahsilat/Gider/Ödeme/Virman/Diğer olarak kalem kalem ayrılması.
Future<Map<String, double>> _nakitDegisimiKirilim(Database db, DateTime baslangic) async {
  final icYer = List.filled(_girisTipleri.length, '?').join(',');
  final rows = await db.rawQuery('''
    SELECT
      CASE
        WHEN hareket_tipi = 'Tahsilat' THEN 'Tahsilat'
        WHEN hareket_tipi IN ('Gider','Gider İptali') THEN 'Gider'
        WHEN hareket_tipi IN ('Ödeme','Ödeme Girişi') THEN 'Ödeme'
        WHEN hareket_tipi IN ('Virman Giriş','Virman Çıkış') THEN 'Virman'
        ELSE 'Diğer'
      END AS kategori,
      COALESCE(SUM(
        CASE WHEN hareket_tipi IN ($icYer) THEN tutar ELSE -tutar END
      ), 0) AS net
    FROM kasa_hareketleri
    WHERE deleted_at IS NULL AND (odeme_yontemi IS NULL OR odeme_yontemi = 'Nakit')
      AND datetime(tarih) >= datetime(?)
      AND hareket_tipi NOT IN ('Satış', 'AçılışKasa')
    GROUP BY kategori
  ''', [..._girisTipleri, baslangic.toIso8601String()]);
  return {
    for (final r in rows) (r['kategori'] as String): (r['net'] as num?)?.toDouble() ?? 0,
  };
}

void main() {
  late Database db;
  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  group('KasaDeposu.nakitDegisimi (vardiya kapanış mutabakatı)', () {
    test('sadece satış değil, tahsilat/gider de dahil edilir', () async {
      final acilis = DateTime(2026, 9, 13, 9, 0);
      await db.insert('kasa_hareketleri', {
        'hareket_tipi': 'Satış', 'tutar': 200, 'tarih': acilis.add(const Duration(hours: 1)).toIso8601String(),
      });
      await db.insert('kasa_hareketleri', {
        'hareket_tipi': 'Tahsilat', 'tutar': 300, 'tarih': acilis.add(const Duration(hours: 2)).toIso8601String(),
      });
      await db.insert('kasa_hareketleri', {
        'hareket_tipi': 'Gider', 'tutar': 50, 'tarih': acilis.add(const Duration(hours: 3)).toIso8601String(),
      });

      final sonuc = await _nakitDegisimi(db, acilis);

      expect(sonuc, 450.0, reason: '200 (satış) + 300 (tahsilat) - 50 (gider) = 450');
    });

    test('vardiya açılışından ÖNCEKİ hareketler dahil edilmez', () async {
      final acilis = DateTime(2026, 9, 13, 9, 0);
      await db.insert('kasa_hareketleri', {
        'hareket_tipi': 'Satış', 'tutar': 999,
        'tarih': acilis.subtract(const Duration(hours: 1)).toIso8601String(),
      });

      final sonuc = await _nakitDegisimi(db, acilis);

      expect(sonuc, 0.0);
    });

    test('Kart/Banka ödeme yöntemli kasa hareketleri nakde dahil edilmez', () async {
      final acilis = DateTime(2026, 9, 13, 9, 0);
      await db.insert('kasa_hareketleri', {
        'hareket_tipi': 'Satış', 'tutar': 500, 'odeme_yontemi': 'Kredi Kartı',
        'tarih': acilis.add(const Duration(hours: 1)).toIso8601String(),
      });

      final sonuc = await _nakitDegisimi(db, acilis);

      expect(sonuc, 0.0);
    });

    test('silinmiş (deleted_at dolu) kasa hareketi sayılmaz', () async {
      final acilis = DateTime(2026, 9, 13, 9, 0);
      await db.insert('kasa_hareketleri', {
        'hareket_tipi': 'Tahsilat', 'tutar': 100,
        'tarih': acilis.add(const Duration(hours: 1)).toIso8601String(),
        'deleted_at': DateTime.now().toIso8601String(),
      });

      final sonuc = await _nakitDegisimi(db, acilis);

      expect(sonuc, 0.0);
    });
  });

  group('KasaDeposu.nakitDegisimiKirilim (Madde 12 — itemize edilmiş kalemler)', () {
    test('Tahsilat/Gider/Ödeme/Virman ayrı kategoriler olarak döner', () async {
      final acilis = DateTime(2026, 9, 13, 9, 0);
      final t = (Duration d) => acilis.add(d).toIso8601String();
      await db.insert('kasa_hareketleri', {'hareket_tipi': 'Satış', 'tutar': 200, 'tarih': t(const Duration(hours: 1))});
      await db.insert('kasa_hareketleri', {'hareket_tipi': 'Tahsilat', 'tutar': 300, 'tarih': t(const Duration(hours: 2))});
      await db.insert('kasa_hareketleri', {'hareket_tipi': 'Gider', 'tutar': 50, 'tarih': t(const Duration(hours: 3))});
      await db.insert('kasa_hareketleri', {'hareket_tipi': 'Ödeme', 'tutar': 20, 'tarih': t(const Duration(hours: 4))});
      await db.insert('kasa_hareketleri', {'hareket_tipi': 'Virman Giriş', 'tutar': 40, 'tarih': t(const Duration(hours: 5))});

      final kirilim = await _nakitDegisimiKirilim(db, acilis);

      // 'Satış' hariç tutulur (özette zaten ayrı satır) — kalan 4 kategori.
      expect(kirilim['Tahsilat'], 300.0);
      expect(kirilim['Gider'], -50.0);
      expect(kirilim['Ödeme'], -20.0);
      expect(kirilim['Virman'], 40.0);
      expect(kirilim.containsKey('Satış'), isFalse);
    });

    test('aynı kategorinin giriş+çıkış tipleri NETLEŞTİRİLİR (ör. Gider İptali)', () async {
      final acilis = DateTime(2026, 9, 13, 9, 0);
      final t = (Duration d) => acilis.add(d).toIso8601String();
      await db.insert('kasa_hareketleri', {'hareket_tipi': 'Gider', 'tutar': 100, 'tarih': t(const Duration(hours: 1))});
      await db.insert('kasa_hareketleri', {'hareket_tipi': 'Gider İptali', 'tutar': 100, 'tarih': t(const Duration(hours: 2))});

      final kirilim = await _nakitDegisimiKirilim(db, acilis);

      expect(kirilim['Gider'], 0.0, reason: '-100 (Gider) + 100 (Gider İptali) = 0');
    });

    test('toplam, nakitDegisimi (Satış hariç) ile TUTARLI olmalı', () async {
      final acilis = DateTime(2026, 9, 13, 9, 0);
      final t = (Duration d) => acilis.add(d).toIso8601String();
      await db.insert('kasa_hareketleri', {'hareket_tipi': 'Satış', 'tutar': 200, 'tarih': t(const Duration(hours: 1))});
      await db.insert('kasa_hareketleri', {'hareket_tipi': 'Tahsilat', 'tutar': 300, 'tarih': t(const Duration(hours: 2))});
      await db.insert('kasa_hareketleri', {'hareket_tipi': 'Gider', 'tutar': 50, 'tarih': t(const Duration(hours: 3))});

      final toplam = await _nakitDegisimi(db, acilis);
      final kirilim = await _nakitDegisimiKirilim(db, acilis);
      final kirilimToplami = kirilim.values.fold<double>(0, (s, v) => s + v);

      expect(kirilimToplami, toplam - 200.0,
          reason: 'kırılım Satış (200) hariç tutuyor, toplam-satış ile eşleşmeli');
    });

    test('deleted_at dolu hareket kırılıma dahil edilmez', () async {
      final acilis = DateTime(2026, 9, 13, 9, 0);
      await db.insert('kasa_hareketleri', {
        'hareket_tipi': 'Tahsilat', 'tutar': 100,
        'tarih': acilis.add(const Duration(hours: 1)).toIso8601String(),
        'deleted_at': DateTime.now().toIso8601String(),
      });

      final kirilim = await _nakitDegisimiKirilim(db, acilis);

      expect(kirilim.isEmpty || (kirilim['Tahsilat'] ?? 0) == 0, isTrue);
    });
  });
}
