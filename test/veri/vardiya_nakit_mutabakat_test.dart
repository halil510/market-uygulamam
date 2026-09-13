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

const _girisTipleri = {
  'Satış', 'Tahsilat', 'AçılışKasa', 'Giriş', 'Virman Giriş',
  'Iade Iptali', 'İade İptali', 'Ödeme Girişi',
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
}
