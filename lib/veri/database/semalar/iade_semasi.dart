// lib/veri/database/semalar/iade_semasi.dart
// OTOMATİK AYRIŞTIRILDI — tablo_olusturucu.dart içindeki _iade() bloğundan
// birebir taşındı. Amaç: 1097 satırlık tek dosya yerine modüler,
// domain bazlı şema dosyaları (Logo Yazılım tarzı katmanlı mimari).
//
// İade ve irsaliye tabloları
import 'package:sqflite/sqflite.dart';
import '../../../cekirdek/sabitler/db_sabitleri.dart';

class IadeSemasi {
  static Future<void> olustur(Database db) async {

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.iade} (
        id INTEGER PRIMARY KEY AUTOINCREMENT, global_id TEXT UNIQUE,
        satis_id INTEGER, cari_id INTEGER, fis_no TEXT,
        tarih DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        toplam_tutar REAL NOT NULL DEFAULT 0, iade_nedeni TEXT,
        durum TEXT NOT NULL DEFAULT 'beklemede', kasiyer_id INTEGER,
        last_updated DATETIME, deleted_at DATETIME, cihaz_id TEXT,
        FOREIGN KEY(satis_id) REFERENCES ${DbSabitler.satislar}(id),
        FOREIGN KEY(cari_id) REFERENCES ${DbSabitler.cari}(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.iadeKalem} (
        id INTEGER PRIMARY KEY AUTOINCREMENT, global_id TEXT UNIQUE,
        iade_id INTEGER NOT NULL,
        urun_id INTEGER NOT NULL, urun_adi TEXT NOT NULL,
        miktar REAL NOT NULL, birim_fiyat REAL NOT NULL, toplam REAL NOT NULL,
        last_updated DATETIME,
        FOREIGN KEY(iade_id) REFERENCES ${DbSabitler.iade}(id) ON DELETE CASCADE,
        FOREIGN KEY(urun_id) REFERENCES ${DbSabitler.urunler}(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.irsaliyeler} (
        id INTEGER PRIMARY KEY AUTOINCREMENT, global_id TEXT UNIQUE,
        irsaliye_no TEXT UNIQUE, cari_id INTEGER, tarih DATETIME DEFAULT CURRENT_TIMESTAMP,
        tip TEXT NOT NULL DEFAULT 'Çıkış',
        toplam_tutar REAL NOT NULL DEFAULT 0, durum TEXT NOT NULL DEFAULT 'Tamamlandı',
        kullanici_id INTEGER, aciklama TEXT, created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        deleted_at DATETIME, last_updated DATETIME,
        FOREIGN KEY(cari_id) REFERENCES ${DbSabitler.cari}(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.irsaliyeKalem} (
        id INTEGER PRIMARY KEY AUTOINCREMENT, global_id TEXT, irsaliye_id INTEGER NOT NULL,
        urun_id INTEGER, urun_adi TEXT NOT NULL, miktar REAL NOT NULL,
        birim_fiyat REAL NOT NULL DEFAULT 0, toplam_tutar REAL NOT NULL DEFAULT 0,
        last_updated DATETIME,
        FOREIGN KEY(irsaliye_id) REFERENCES ${DbSabitler.irsaliyeler}(id) ON DELETE CASCADE
      )
    ''');
  
  }
}
