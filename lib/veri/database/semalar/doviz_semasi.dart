// lib/veri/database/semalar/doviz_semasi.dart
//
// ÇOKLU PARA BİRİMİ MODÜLÜ
// ------------------------------------------------------------------
// Bu uygulamanın TEK muhasebe para birimi hâlâ TRY'dir (Türk Lirası) —
// tüm satış/stok/kasa hesaplamaları TRY üzerinden yapılmaya devam eder.
// Bu tablo, kullanıcının manuel olarak girdiği güncel kurları saklar;
// ürün/ödeme ekranlarında "yabancı para birimi karşılığını göster"
// amacıyla kullanılır — otomatik döviz muhasebesi YAPMAZ (bilinçli
// tasarım tercihi: yanlış/geç kur nedeniyle hatalı muhasebe riski almamak
// için TRY tutarlar her zaman elle/normal şekilde girilir, döviz sadece
// referans/bilgi amaçlıdır).
import 'package:sqflite/sqflite.dart';
import '../../../cekirdek/sabitler/db_sabitleri.dart';

class DovizSemasi {
  static Future<void> olustur(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.dovizKurlari} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        kod TEXT NOT NULL UNIQUE,
        ad TEXT NOT NULL,
        sembol TEXT NOT NULL,
        alis_kuru REAL NOT NULL DEFAULT 0,
        satis_kuru REAL NOT NULL DEFAULT 0,
        guncelleme_tarihi TEXT,
        aktif INTEGER NOT NULL DEFAULT 1
      )
    ''');

    // Sık kullanılan 3 döviz için başlangıç satırları (kur değerleri 0 —
    // kullanıcı Kur Ayarları ekranından güncel değeri kendisi girer,
    // biz tahmini/sahte bir kur değeri koymuyoruz).
    for (final d in [
      {'kod': 'USD', 'ad': 'Amerikan Doları', 'sembol': '\$'},
      {'kod': 'EUR', 'ad': 'Euro', 'sembol': '€'},
      {'kod': 'GBP', 'ad': 'İngiliz Sterlini', 'sembol': '£'},
    ]) {
      await db.insert(DbSabitler.dovizKurlari, {
        'kod': d['kod'],
        'ad': d['ad'],
        'sembol': d['sembol'],
        'alis_kuru': 0,
        'satis_kuru': 0,
        'aktif': 1,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }
}
