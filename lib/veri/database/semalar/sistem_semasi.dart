// lib/veri/database/semalar/sistem_semasi.dart
// OTOMATİK AYRIŞTIRILDI — tablo_olusturucu.dart içindeki _sistem() bloğundan
// birebir taşındı. Amaç: 1097 satırlık tek dosya yerine modüler,
// domain bazlı şema dosyaları (Logo Yazılım tarzı katmanlı mimari).
//
// Bildirim, yazıcı, ayarlar, fiş serisi, günlük rapor, rol/yetki tabloları
import 'package:sqflite/sqflite.dart';
import '../../../cekirdek/sabitler/db_sabitleri.dart';

class SistemSemasi {
  static Future<void> olustur(Database db) async {

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.rollerYetki} (
        id INTEGER PRIMARY KEY AUTOINCREMENT, kullanici_id INTEGER NOT NULL,
        yetki_kodu TEXT NOT NULL, created_at TEXT,
        global_id TEXT, last_updated DATETIME,
        FOREIGN KEY(kullanici_id) REFERENCES ${DbSabitler.kullanicilar}(id) ON DELETE CASCADE,
        UNIQUE(kullanici_id, yetki_kodu)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.rolYetkileri} (
        id INTEGER PRIMARY KEY AUTOINCREMENT, global_id TEXT,
        rol TEXT NOT NULL, yetki_kodu TEXT NOT NULL,
        last_updated DATETIME,
        UNIQUE(rol, yetki_kodu)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.bildirimler} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        baslik TEXT NOT NULL, mesaj TEXT NOT NULL,
        tip TEXT NOT NULL DEFAULT 'bilgi', okundu INTEGER NOT NULL DEFAULT 0,
        tarih DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        hedef_id INTEGER, hedef_turu TEXT, kullanici_id INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.yazicilar} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tur TEXT NOT NULL, adi TEXT NOT NULL, cihaz_id TEXT,
        ip TEXT, port INTEGER DEFAULT 9100,
        kategori TEXT NOT NULL DEFAULT 'fis',
        varsayilan INTEGER NOT NULL DEFAULT 0, aktif INTEGER NOT NULL DEFAULT 1,
        kayit_tarihi DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.ayarlar} (
        anahtar TEXT PRIMARY KEY, deger TEXT NOT NULL,
        aciklama TEXT, guncelleme DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        last_updated DATETIME
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.fisSeri} (
        sube_id INTEGER NOT NULL DEFAULT 1,
        fis_tipi TEXT NOT NULL,
        son_fis_no INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (sube_id, fis_tipi),
        FOREIGN KEY(sube_id) REFERENCES ${DbSabitler.subeler}(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.personel} (
        id INTEGER PRIMARY KEY AUTOINCREMENT, global_id TEXT UNIQUE,
        kullanici_id INTEGER, ad_soyad TEXT NOT NULL,
        tc_kimlik TEXT, pozisyon TEXT, departman TEXT,
        telefon TEXT, email TEXT,
        maas REAL NOT NULL DEFAULT 0, calisma_saati REAL NOT NULL DEFAULT 0,
        ise_baslama DATE, isten_cikis DATE,
        aktif INTEGER NOT NULL DEFAULT 1, notlar TEXT,
        last_updated DATETIME, is_deleted INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY(kullanici_id) REFERENCES ${DbSabitler.kullanicilar}(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.eFaturaLog} (
        id INTEGER PRIMARY KEY AUTOINCREMENT, global_id TEXT, fatura_id INTEGER,
        tarih DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        islem_tipi TEXT NOT NULL, durum TEXT NOT NULL,
        uuid TEXT, hata_kodu TEXT, hata_mesaji TEXT,
        istek_json TEXT, yanit_json TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.appLog} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        seviye TEXT NOT NULL, mesaj TEXT NOT NULL, hata TEXT,
        zaman TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // Bildirim tercihleri — önceden sadece migrasyon zincirinde vardı,
    // taze kurulumlarda hiç oluşturulmuyordu (gerçek bir eksiklikti).
    await db.execute('''
      CREATE TABLE IF NOT EXISTS bildirim_tercihleri (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        global_id       TEXT,
        kullanici_id    INTEGER,
        olay_turu       TEXT NOT NULL,
        aktif           INTEGER NOT NULL DEFAULT 1,
        esik_deger      REAL,
        bildirim_saati  TEXT,
        son_tetikleme   TEXT,
        created_at      TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY(kullanici_id) REFERENCES kullanicilar(id)
      )
    ''');
    for (final olay in ['kritik_stok', 'gunluk_rapor', 'kasa_kapanisi', 'vadesi_gelen_cari', 'yedekleme_hatirlatma']) {
      await db.insert('bildirim_tercihleri', {'olay_turu': olay, 'aktif': 1},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }
}
