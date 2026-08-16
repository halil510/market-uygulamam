// lib/veri/database/semalar/promosyon_semasi.dart
// OTOMATİK AYRIŞTIRILDI — tablo_olusturucu.dart içindeki _promosyon() bloğundan
// birebir taşındı. Amaç: 1097 satırlık tek dosya yerine modüler,
// domain bazlı şema dosyaları (Logo Yazılım tarzı katmanlı mimari).
//
// Promosyon tanım/koşul/aksiyon tabloları
import 'package:sqflite/sqflite.dart';
import '../../../cekirdek/sabitler/db_sabitleri.dart';

class PromosyonSemasi {
  static Future<void> olustur(Database db) async {

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.promosyonlar} (
        id INTEGER PRIMARY KEY AUTOINCREMENT, global_id TEXT UNIQUE,
        urun_id INTEGER NOT NULL, promosyon_adi TEXT NOT NULL,
        iskonto_oran REAL NOT NULL DEFAULT 0, iskonto_tutar REAL NOT NULL DEFAULT 0,
        min_miktar REAL NOT NULL DEFAULT 1,
        baslangic_tarihi TEXT, bitis_tarihi TEXT,
        aktif INTEGER NOT NULL DEFAULT 1, last_updated DATETIME, deleted_at DATETIME,
        FOREIGN KEY(urun_id) REFERENCES ${DbSabitler.urunler}(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.promosyonTanim} (
        id INTEGER PRIMARY KEY AUTOINCREMENT, global_id TEXT UNIQUE,
        ad TEXT NOT NULL, aciklama TEXT,
        tip TEXT NOT NULL DEFAULT 'iskonto', baslangic DATETIME, bitis DATETIME,
        aktif INTEGER NOT NULL DEFAULT 1, oncelik INTEGER NOT NULL DEFAULT 0,
        created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.promosyonKosul} (
        id INTEGER PRIMARY KEY AUTOINCREMENT, global_id TEXT, tanim_id INTEGER NOT NULL,
        kosul_tipi TEXT NOT NULL, kosul_degeri TEXT NOT NULL,
        last_updated DATETIME,
        FOREIGN KEY(tanim_id) REFERENCES ${DbSabitler.promosyonTanim}(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.promosyonAksiyon} (
        id INTEGER PRIMARY KEY AUTOINCREMENT, global_id TEXT, tanim_id INTEGER NOT NULL,
        aksiyon_tipi TEXT NOT NULL, aksiyon_degeri TEXT NOT NULL,
        last_updated DATETIME,
        FOREIGN KEY(tanim_id) REFERENCES ${DbSabitler.promosyonTanim}(id) ON DELETE CASCADE
      )
    ''');
  
  }
}
