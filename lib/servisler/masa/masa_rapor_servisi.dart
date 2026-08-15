// lib/servisler/masa/masa_rapor_servisi.dart
import 'package:sqflite/sqflite.dart';
import '../../veri/database/veritabani.dart';

class MasaRaporServisi {
  Future<Database> get _db async => Veritabani().db;
  
  /// Masa performans analizi (ciro, sipariş sayısı, ortalama)
  Future<List<Map<String, dynamic>>> masaPerformansAnalizi() async {
    final db = await _db;
    return db.rawQuery('''
      SELECT 
        m.id,
        m.ad as masa_adi,
        COALESCE(SUM(s.toplam_tutar), 0) as ciro,
        COUNT(DISTINCT s.id) as siparis_sayisi,
        COALESCE(AVG(s.toplam_tutar), 0) as ortalama_tutar
      FROM masalar m
      LEFT JOIN masa_siparisleri s ON m.id = s.masa_id AND s.durum = 'odendi'
      WHERE m.is_deleted = 0
      GROUP BY m.id
      ORDER BY ciro DESC
    ''');
  }
  
  /// Doluluk oranı analizi
  Future<Map<String, double>> dolulukOraniAnalizi(DateTime tarih) async {
    final db = await _db;
    final toplam = await db.rawQuery('SELECT COUNT(*) as sayi FROM masalar WHERE is_deleted = 0');
    final toplamSayi = (toplam.first['sayi'] as int).toDouble();
    
    final dolu = await db.rawQuery('''
      SELECT COUNT(*) as sayi FROM masalar 
      WHERE is_deleted = 0 AND durum != 'bos'
    ''');
    final doluSayi = (dolu.first['sayi'] as int).toDouble();
    
    final hesapIstendi = await db.rawQuery('''
      SELECT COUNT(*) as sayi FROM masalar 
      WHERE is_deleted = 0 AND durum = 'hesap_istendi'
    ''');
    final hesapSayi = (hesapIstendi.first['sayi'] as int).toDouble();
    
    return {
      'Dolu': (doluSayi / toplamSayi) * 100,
      'Boş': ((toplamSayi - doluSayi) / toplamSayi) * 100,
      'Hesap İstendi': (hesapSayi / toplamSayi) * 100,
    };
  }
  
  /// Günlük masa cirosu
  Future<List<Map<String, dynamic>>> gunlukMasaCiro(DateTime tarih) async {
    final db = await _db;
    final bas = DateTime(tarih.year, tarih.month, tarih.day);
    final bit = DateTime(tarih.year, tarih.month, tarih.day, 23, 59, 59);
    return db.rawQuery('''
      SELECT 
        m.ad as masa_adi,
        COALESCE(SUM(s.toplam_tutar), 0) as ciro,
        COUNT(DISTINCT s.id) as siparis_sayisi
      FROM masalar m
      LEFT JOIN masa_siparisleri s ON m.id = s.masa_id 
        AND s.durum = 'odendi'
        AND s.kapanis_zamani BETWEEN ? AND ?
      WHERE m.is_deleted = 0
      GROUP BY m.id
      HAVING ciro > 0
      ORDER BY ciro DESC
    ''', [bas.toIso8601String(), bit.toIso8601String()]);
  }
  
  /// Ortalama oturma süresi (dakika)
  Future<double> ortalamaOturmaSuresi() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT AVG(
        CAST((JULIANDAY(kapanis_zamani) - JULIANDAY(acilis_zamani)) * 24 * 60 AS REAL)
      ) as ortalama
      FROM masa_siparisleri
      WHERE durum = 'odendi' AND kapanis_zamani IS NOT NULL
    ''');
    return (rows.first['ortalama'] as num?)?.toDouble() ?? 0;
  }
  
  /// Toplam masa cirosu
  Future<double> toplamMasaCiro(DateTime tarih) async {
    final db = await _db;
    final bas = DateTime(tarih.year, tarih.month, tarih.day);
    final bit = DateTime(tarih.year, tarih.month, tarih.day, 23, 59, 59);
    final rows = await db.rawQuery('''
      SELECT COALESCE(SUM(toplam_tutar), 0) as toplam
      FROM masa_siparisleri
      WHERE durum = 'odendi' 
        AND kapanis_zamani BETWEEN ? AND ?
    ''', [bas.toIso8601String(), bit.toIso8601String()]);
    return (rows.first['toplam'] as num?)?.toDouble() ?? 0;
  }
}