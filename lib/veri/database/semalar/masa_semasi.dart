// lib/veri/database/semalar/masa_semasi.dart
// OTOMATİK AYRIŞTIRILDI — tablo_olusturucu.dart içindeki MasaTablolari sınıfından
// birebir taşındı.
//
// Masa/restoran modülü: masalar, masa siparişleri, sipariş kalemleri
import 'package:sqflite/sqflite.dart';
import '../../../cekirdek/sabitler/db_sabitleri.dart';

class MasaSemasi {
  static Future<void> olustur(Database db) async {

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.masalar} (
        id INTEGER PRIMARY KEY AUTOINCREMENT, 
        global_id TEXT UNIQUE,
        ad TEXT NOT NULL, 
        kategori TEXT NOT NULL DEFAULT 'Salon',
        kapasite INTEGER NOT NULL DEFAULT 4,
        durum TEXT NOT NULL DEFAULT 'bos',
        sira INTEGER NOT NULL DEFAULT 0,
        sube_id INTEGER,
        last_updated DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY(sube_id) REFERENCES ${DbSabitler.subeler}(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.masaSiparisleri} (
        id INTEGER PRIMARY KEY AUTOINCREMENT, 
        global_id TEXT UNIQUE,
        masa_id INTEGER NOT NULL,
        cari_id INTEGER, 
        cari_adi TEXT,
        durum TEXT NOT NULL DEFAULT 'acik',
        acilis_zamani DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        kapanis_zamani DATETIME,
        toplam_tutar REAL NOT NULL DEFAULT 0,
        not_ TEXT,
        kullanici_id INTEGER,
        satis_id INTEGER,
        garson_id INTEGER,
        garson_adi TEXT,
        last_updated DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY(masa_id)  REFERENCES ${DbSabitler.masalar}(id),
        FOREIGN KEY(cari_id)  REFERENCES ${DbSabitler.cari}(id),
        FOREIGN KEY(satis_id) REFERENCES ${DbSabitler.satislar}(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.masaSiparisKalem} (
        id INTEGER PRIMARY KEY AUTOINCREMENT, 
        global_id TEXT UNIQUE,
        siparis_id INTEGER NOT NULL,
        urun_id INTEGER NOT NULL, 
        urun_adi TEXT NOT NULL,
        miktar REAL NOT NULL DEFAULT 1,
        birim_fiyat REAL NOT NULL DEFAULT 0,
        kdv_oran REAL NOT NULL DEFAULT 18,
        not_ TEXT,
        durum TEXT NOT NULL DEFAULT 'beklemede',
        eklenme_zamani DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        last_updated DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY(siparis_id) REFERENCES ${DbSabitler.masaSiparisleri}(id) ON DELETE CASCADE,
        FOREIGN KEY(urun_id) REFERENCES ${DbSabitler.urunler}(id)
      )
    ''');

    await db.execute('CREATE INDEX IF NOT EXISTS idx_masa_siparis_masa  ON ${DbSabitler.masaSiparisleri}(masa_id, durum)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_masa_siparis_kalem ON ${DbSabitler.masaSiparisKalem}(siparis_id)');
  
  }
}
