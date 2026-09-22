// lib/veri/database/semalar/stok_semasi.dart
// OTOMATİK AYRIŞTIRILDI — tablo_olusturucu.dart içindeki _stok() bloğundan
// birebir taşındı. Amaç: 1097 satırlık tek dosya yerine modüler,
// domain bazlı şema dosyaları (Logo Yazılım tarzı katmanlı mimari).
//
// Stok hareketleri, geçici sayım, şube-ürün, FIFO, şube fiyat geçmişi
import 'package:sqflite/sqflite.dart';
import '../../../cekirdek/sabitler/db_sabitleri.dart';

class StokSemasi {
  static Future<void> olustur(Database db) async {

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.stokHareket} (
        id INTEGER PRIMARY KEY AUTOINCREMENT, 
        global_id TEXT UNIQUE,
        cihaz_id TEXT,
        urun_id INTEGER NOT NULL,
        hareket_turu TEXT NOT NULL, 
        miktar REAL NOT NULL,
        onceki_stok REAL NOT NULL DEFAULT 0, 
        sonraki_stok REAL NOT NULL DEFAULT 0,
        birim_maliyet REAL NOT NULL DEFAULT 0,
        tarih DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        referans_id INTEGER, 
        referans_turu TEXT, 
        lot_id INTEGER, 
        aciklama TEXT,
        kullanici_id INTEGER, 
        sube_id INTEGER, 
        last_updated DATETIME,
        FOREIGN KEY(urun_id) REFERENCES ${DbSabitler.urunler}(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.geciciSayim} (
        id INTEGER PRIMARY KEY AUTOINCREMENT, global_id TEXT,
        urun_id INTEGER NOT NULL UNIQUE,
        mevcut_stok REAL NOT NULL DEFAULT 0, yeni_stok REAL NOT NULL DEFAULT 0,
        notlar TEXT, kullanici_id INTEGER,
        FOREIGN KEY(urun_id) REFERENCES ${DbSabitler.urunler}(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.subeUrun} (
        global_id TEXT,
        urun_id INTEGER NOT NULL, sube_id INTEGER NOT NULL,
        stok REAL NOT NULL DEFAULT 0, rezerve_stok REAL NOT NULL DEFAULT 0,
        kritik_stok REAL DEFAULT 0, satis_fiyati REAL, alis_fiyati REAL,
        raf_kodu TEXT, son_guncelleme DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        last_updated DATETIME,
        PRIMARY KEY (urun_id, sube_id),
        FOREIGN KEY(urun_id) REFERENCES ${DbSabitler.urunler}(id) ON DELETE CASCADE,
        FOREIGN KEY(sube_id) REFERENCES ${DbSabitler.subeler}(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.stokFifo} (
        id INTEGER PRIMARY KEY AUTOINCREMENT, global_id TEXT,
        giris_hareket_id INTEGER NOT NULL, cikis_hareket_id INTEGER NOT NULL,
        kullanilan_miktar REAL NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.subeFiyatGecmis} (
        id INTEGER PRIMARY KEY AUTOINCREMENT, global_id TEXT,
        urun_id INTEGER NOT NULL, sube_id INTEGER NOT NULL,
        eski_fiyat REAL, yeni_fiyat REAL,
        tarih DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, degistiren TEXT
      )
    ''');
  
  }
}
