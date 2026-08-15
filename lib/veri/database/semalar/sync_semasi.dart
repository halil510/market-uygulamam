// lib/veri/database/semalar/sync_semasi.dart
// OTOMATİK AYRIŞTIRILDI — tablo_olusturucu.dart içindeki _sync() bloğundan
// birebir taşındı. Amaç: 1097 satırlık tek dosya yerine modüler,
// domain bazlı şema dosyaları (Logo Yazılım tarzı katmanlı mimari).
//
// Bulut senkronizasyon kuyruğu ve meta tabloları
import 'package:sqflite/sqflite.dart';
import '../../../cekirdek/sabitler/db_sabitleri.dart';

class SyncSemasi {
  static Future<void> olustur(Database db) async {

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.syncQueue} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tablo_adi TEXT NOT NULL, kayit_global_id TEXT, kayit_id INTEGER,
        islem_tipi TEXT NOT NULL, veri_json TEXT NOT NULL,
        deneme_sayisi INTEGER DEFAULT 0, son_deneme DATETIME,
        durum TEXT DEFAULT 'beklemede',
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.syncMeta} (
        tablo_adi TEXT PRIMARY KEY, son_senkron DATETIME,
        son_id INTEGER, deleted_records TEXT
      )
    ''');
  
  }
}
