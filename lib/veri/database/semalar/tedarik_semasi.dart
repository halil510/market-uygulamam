// lib/veri/database/semalar/tedarik_semasi.dart
// OTOMATİK AYRIŞTIRILDI — tablo_olusturucu.dart içindeki _tedarik() bloğundan
// birebir taşındı. Amaç: 1097 satırlık tek dosya yerine modüler,
// domain bazlı şema dosyaları (Logo Yazılım tarzı katmanlı mimari).
//
// Tedarikçi sipariş ve sipariş kalemleri
import 'package:sqflite/sqflite.dart';
import '../../../cekirdek/sabitler/db_sabitleri.dart';

class TedarikSemasi {
  static Future<void> olustur(Database db) async {

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.tedarikciSiparisler} (
        id INTEGER PRIMARY KEY AUTOINCREMENT, global_id TEXT UNIQUE,
        cari_id INTEGER NOT NULL, siparis_no TEXT UNIQUE,
        siparis_tarihi DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        teslim_tarihi DATETIME, toplam_tutar REAL NOT NULL DEFAULT 0,
        durum TEXT NOT NULL DEFAULT 'beklemede', notlar TEXT, olusturan_id INTEGER,
        last_updated DATETIME, is_deleted INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY(cari_id) REFERENCES ${DbSabitler.cari}(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.tedarikciSiparisKalem} (
        id INTEGER PRIMARY KEY AUTOINCREMENT, global_id TEXT UNIQUE,
        siparis_id INTEGER NOT NULL,
        urun_id INTEGER NOT NULL, siparis_mik REAL NOT NULL,
        teslim_mik REAL NOT NULL DEFAULT 0, birim_fiyat REAL NOT NULL,
        kdv_oran REAL NOT NULL DEFAULT 18, toplam_tutar REAL NOT NULL,
        last_updated DATETIME,
        FOREIGN KEY(siparis_id) REFERENCES ${DbSabitler.tedarikciSiparisler}(id) ON DELETE CASCADE,
        FOREIGN KEY(urun_id) REFERENCES ${DbSabitler.urunler}(id)
      )
    ''');
  
  }
}
