// lib/veri/database/semalar/temel_semasi.dart
// OTOMATİK AYRIŞTIRILDI — tablo_olusturucu.dart içindeki _temel() bloğundan
// birebir taşındı. Amaç: 1097 satırlık tek dosya yerine modüler,
// domain bazlı şema dosyaları (Logo Yazılım tarzı katmanlı mimari).
//
// Şube, kullanıcı, kategori, birim, marka tabloları
import 'package:sqflite/sqflite.dart';
import '../../../cekirdek/sabitler/db_sabitleri.dart';

class TemelSemasi {
  static Future<void> olustur(Database db) async {

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.subeler} (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        global_id  TEXT UNIQUE,
        sube_kodu  TEXT NOT NULL UNIQUE,
        sube_adi   TEXT NOT NULL,
        adres      TEXT, telefon TEXT, email TEXT, vergi_no TEXT,
        aktif      INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        last_updated DATETIME,
        deleted    INTEGER NOT NULL DEFAULT 0,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.kullanicilar} (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        global_id       TEXT UNIQUE,
        sube_id         INTEGER,
        kullanici_adi   TEXT NOT NULL UNIQUE COLLATE NOCASE,
        sifre_hash      TEXT NOT NULL,
        ad_soyad        TEXT NOT NULL,
        rol             TEXT NOT NULL DEFAULT 'personel'
                        CHECK(rol IN ('admin','mudur','kasiyer','personel','depocu')),
        email TEXT, telefon TEXT,
        aktif           INTEGER NOT NULL DEFAULT 1,
        tuz             TEXT,
        plu             INTEGER NOT NULL DEFAULT 0,
        plu_kart_boyut  INTEGER NOT NULL DEFAULT 2,
        son_giris       DATETIME,
        kayit_tarihi    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        last_updated    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        is_deleted      INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY(sube_id) REFERENCES ${DbSabitler.subeler}(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.kategoriler} (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        ad              TEXT NOT NULL UNIQUE COLLATE NOCASE,
        ust_kategori_id INTEGER,
        sira            INTEGER NOT NULL DEFAULT 0,
        last_updated    DATETIME,
        is_deleted      INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY(ust_kategori_id) REFERENCES ${DbSabitler.kategoriler}(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.birimler} (
        id        INTEGER PRIMARY KEY AUTOINCREMENT,
        ad        TEXT NOT NULL UNIQUE COLLATE NOCASE,
        kisaltma  TEXT,
        aktif     INTEGER NOT NULL DEFAULT 1,
        carpan    REAL NOT NULL DEFAULT 1,
        last_updated DATETIME
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.markalar} (
        id     INTEGER PRIMARY KEY AUTOINCREMENT,
        ad     TEXT NOT NULL UNIQUE COLLATE NOCASE,
        aktif  INTEGER NOT NULL DEFAULT 1,
        last_updated DATETIME
      )
    ''');
  
  }
}
