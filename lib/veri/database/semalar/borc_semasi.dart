// lib/veri/database/semalar/borc_semasi.dart
// OTOMATİK AYRIŞTIRILDI — tablo_olusturucu.dart içindeki BorcTablosu sınıfından
// birebir taşındı.
//
// Borç takip tablosu
import 'package:sqflite/sqflite.dart';
import '../../../cekirdek/sabitler/db_sabitleri.dart';

class BorcSemasi {
  static Future<void> olustur(Database db) async {

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.borclar} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        global_id TEXT UNIQUE,
        baslik TEXT NOT NULL,
        tur TEXT NOT NULL,
        alt_tur TEXT,
        tutar REAL NOT NULL,
        odenen_tutar REAL NOT NULL DEFAULT 0,
        kesim_tarihi TEXT,
        son_odeme_tarihi TEXT NOT NULL,
        odeme_tarihi TEXT,
        taksit_sayisi INTEGER NOT NULL DEFAULT 1,
        odenen_taksit INTEGER NOT NULL DEFAULT 0,
        aciklama TEXT,
        dosya_no TEXT,
        referans_no TEXT,
        odendi INTEGER NOT NULL DEFAULT 0,
        hatirlatma_gonderildi INTEGER NOT NULL DEFAULT 0,
        oncelik INTEGER NOT NULL DEFAULT 2,
        notlar TEXT,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        last_updated TEXT
      )
    ''');
    
    await db.execute('CREATE INDEX IF NOT EXISTS idx_borc_global ON ${DbSabitler.borclar}(global_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_borc_tarih ON ${DbSabitler.borclar}(son_odeme_tarihi)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_borc_tur ON ${DbSabitler.borclar}(tur)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_borc_durum ON ${DbSabitler.borclar}(odendi)');
  
  }
}
