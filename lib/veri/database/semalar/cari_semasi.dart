// lib/veri/database/semalar/cari_semasi.dart
// OTOMATİK AYRIŞTIRILDI — tablo_olusturucu.dart içindeki _cari() bloğundan
// birebir taşındı. Amaç: 1097 satırlık tek dosya yerine modüler,
// domain bazlı şema dosyaları (Logo Yazılım tarzı katmanlı mimari).
//
// Cari (müşteri/tedarikçi), cari adres, cari hareket, müşteri puan tabloları
import 'package:sqflite/sqflite.dart';
import '../../../cekirdek/sabitler/db_sabitleri.dart';

class CariSemasi {
  static Future<void> olustur(Database db) async {

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.cari} (
        id INTEGER PRIMARY KEY AUTOINCREMENT, global_id TEXT UNIQUE,
        cari_kodu TEXT UNIQUE COLLATE NOCASE, unvan TEXT NOT NULL COLLATE NOCASE,
        cari_tipi TEXT NOT NULL CHECK(cari_tipi IN ('Müşteri','Tedarikçi','Hem Müşteri Hem Tedarikçi')),
        telefon TEXT, telefon2 TEXT, email TEXT, email2 TEXT,
        vergi_dairesi TEXT, vergi_no TEXT, tc_kimlik TEXT,
        mukellef_durumu TEXT, mukellef_sorgu_tarihi TEXT,
        bakiye REAL NOT NULL DEFAULT 0, limit_tutari REAL NOT NULL DEFAULT 0,
        vade_gun INTEGER NOT NULL DEFAULT 0,
        ana_grup TEXT, alt_grup TEXT, temsilci TEXT, notlar TEXT, web_sitesi TEXT,
        aktif INTEGER NOT NULL DEFAULT 1,
        olusturma_tarihi DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        guncelleyen TEXT, sube_id INTEGER,
        last_updated DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        deleted_at DATETIME, cihaz_id TEXT,
        fiyat_grubu_id INTEGER,
        musteri_tipi TEXT NOT NULL DEFAULT 'Perakende',
        FOREIGN KEY(sube_id) REFERENCES ${DbSabitler.subeler}(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.cariAdres} (
        id INTEGER PRIMARY KEY AUTOINCREMENT, global_id TEXT UNIQUE,
        cari_id INTEGER NOT NULL,
        adres_tipi TEXT NOT NULL DEFAULT 'Fatura', adres TEXT NOT NULL,
        il TEXT, ilce TEXT, posta_kodu TEXT, varsayilan INTEGER NOT NULL DEFAULT 0,
        last_updated DATETIME,
        FOREIGN KEY(cari_id) REFERENCES ${DbSabitler.cari}(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.cariHareket} (
        id INTEGER PRIMARY KEY AUTOINCREMENT, global_id TEXT UNIQUE,
        cari_id INTEGER NOT NULL,
        tarih DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        fis_tipi TEXT NOT NULL, fis_id INTEGER, fis_no TEXT,
        aciklama TEXT NOT NULL DEFAULT '',
        borc REAL NOT NULL DEFAULT 0, alacak REAL NOT NULL DEFAULT 0,
        bakiye REAL, odeme_turu TEXT, kullanici TEXT,
        last_updated DATETIME, is_deleted INTEGER NOT NULL DEFAULT 0, cihaz_id TEXT,
        FOREIGN KEY(cari_id) REFERENCES ${DbSabitler.cari}(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
  CREATE TABLE IF NOT EXISTS ${DbSabitler.musteriPuan} (
    id INTEGER PRIMARY KEY AUTOINCREMENT, 
    global_id TEXT UNIQUE,
    cari_id INTEGER,  -- 🔥 NOT NULL kaldırıldı
    toplam_puan REAL NOT NULL DEFAULT 0,
    kullanilan REAL NOT NULL DEFAULT 0, 
    son_islem DATETIME,
    last_updated DATETIME,
    FOREIGN KEY(cari_id) REFERENCES ${DbSabitler.cari}(id) ON DELETE CASCADE
  )
''');


    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.puanHareket} (
        id INTEGER PRIMARY KEY AUTOINCREMENT, global_id TEXT UNIQUE,
        cari_id INTEGER NOT NULL,
        islem_tipi TEXT NOT NULL, puan REAL NOT NULL, referans_id INTEGER,
        tarih DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, aciklama TEXT,
        last_updated DATETIME,
        FOREIGN KEY(cari_id) REFERENCES ${DbSabitler.cari}(id)
      )
    ''');
  
  }
}
