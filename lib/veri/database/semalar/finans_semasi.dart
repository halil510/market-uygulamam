// lib/veri/database/semalar/finans_semasi.dart
// OTOMATİK AYRIŞTIRILDI — tablo_olusturucu.dart içindeki _finans() bloğundan
// birebir taşındı. Amaç: 1097 satırlık tek dosya yerine modüler,
// domain bazlı şema dosyaları (Logo Yazılım tarzı katmanlı mimari).
//
// Gider, kasa hareketleri, vardiya, fatura tabloları
import 'package:sqflite/sqflite.dart';
import '../../../cekirdek/sabitler/db_sabitleri.dart';

class FinansSemasi {
  static Future<void> olustur(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.giderKategoriler} (
        id INTEGER PRIMARY KEY AUTOINCREMENT, ad TEXT NOT NULL UNIQUE,
        last_updated DATETIME
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.giderler} (
        id INTEGER PRIMARY KEY AUTOINCREMENT, global_id TEXT UNIQUE,
        kategori_id INTEGER NOT NULL, tutar REAL NOT NULL, aciklama TEXT,
        tarih DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        belge_no TEXT, odeme_yontemi TEXT NOT NULL DEFAULT 'Nakit',
        cari_id INTEGER, kullanici_id INTEGER, sube_id INTEGER,
        last_updated DATETIME, deleted_at DATETIME,
        FOREIGN KEY(kategori_id) REFERENCES ${DbSabitler.giderKategoriler}(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.kasaHareketleri} (
        id INTEGER PRIMARY KEY AUTOINCREMENT, global_id TEXT UNIQUE,
        hareket_tipi TEXT NOT NULL, tutar REAL NOT NULL,
        bakiye_sonrasi REAL, referans_id INTEGER, referans_turu TEXT,
        tarih DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        aciklama TEXT, kullanici_id INTEGER, sube_id INTEGER,
        last_updated DATETIME, deleted_at DATETIME,
        odeme_yontemi TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.vardiyalar} (
        id INTEGER PRIMARY KEY AUTOINCREMENT, global_id TEXT UNIQUE,
        kullanici_id INTEGER NOT NULL, sube_id INTEGER,
        acilis_tarihi DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        kapanis_tarihi DATETIME, acilis_kasasi REAL NOT NULL DEFAULT 0,
        kapanis_kasasi REAL, baslangic_bakiye REAL NOT NULL DEFAULT 0,
        bitis_bakiye REAL, nakit_sayim REAL, kart_toplam REAL, fark REAL,
        notlar TEXT, durum TEXT NOT NULL DEFAULT 'acik',
        last_updated DATETIME,
        FOREIGN KEY(kullanici_id) REFERENCES ${DbSabitler.kullanicilar}(id)
      )
    ''');

    // Vardiya saatlik detay — önceden sadece migrasyon zincirinde vardı,
    // taze kurulumlarda hiç oluşturulmuyordu.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS vardiya_detay (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        vardiya_id  INTEGER NOT NULL,
        saat        INTEGER NOT NULL,
        satis_sayisi INTEGER NOT NULL DEFAULT 0,
        toplam_ciro REAL    NOT NULL DEFAULT 0,
        ortalama    REAL    NOT NULL DEFAULT 0,
        created_at  TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY(vardiya_id) REFERENCES ${DbSabitler.vardiyalar}(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.faturalar} (
        id INTEGER PRIMARY KEY AUTOINCREMENT, global_id TEXT UNIQUE,
        fatura_no TEXT UNIQUE, fatura_tipi TEXT NOT NULL DEFAULT 'Satış Faturası',
        odeme_sekli TEXT,
        satis_id INTEGER, iade_id INTEGER, cari_id INTEGER, sube_id INTEGER,
        tarih TEXT DEFAULT CURRENT_TIMESTAMP, duzenlenme_tarihi TEXT,
        sevk_tarihi TEXT, vade_tarihi TEXT,
        malin_nereye TEXT, teslim_eden TEXT, teslim_alan TEXT,
        toplam_ara_toplam REAL DEFAULT 0, toplam_iskonto REAL DEFAULT 0,
        toplam_kdv REAL DEFAULT 0, genel_toplam REAL DEFAULT 0,
        odenen_tutar REAL DEFAULT 0, kalan_tutar REAL DEFAULT 0,
        odeme_durumu TEXT DEFAULT 'beklemede',
        e_fatura_uuid TEXT, e_fatura_durum TEXT DEFAULT 'hazir',
        e_fatura_html TEXT, e_fatura_xml TEXT,
        gonderim_tarihi DATETIME, uygulama_yaniti TEXT,
        html_icerik TEXT, xml_icerik TEXT, durum TEXT DEFAULT 'aktif',
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
        last_updated DATETIME, deleted_at DATETIME,
        FOREIGN KEY(cari_id) REFERENCES ${DbSabitler.cari}(id),
        FOREIGN KEY(sube_id) REFERENCES ${DbSabitler.subeler}(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.faturaDetaylari} (
        id INTEGER PRIMARY KEY AUTOINCREMENT, global_id TEXT UNIQUE,
        fatura_id INTEGER, urun_id INTEGER,
        urun_adi TEXT, barkod TEXT, miktar REAL, birim_fiyat REAL,
        iskonto_orani REAL DEFAULT 0, iskonto_tutari REAL DEFAULT 0,
        kdv_orani REAL DEFAULT 18, kdv_tutari REAL DEFAULT 0,
        ara_toplam REAL DEFAULT 0, net_fiyat REAL DEFAULT 0,
        toplam_tutar REAL DEFAULT 0, lot_seri_no TEXT,
        last_updated DATETIME, cihaz_id TEXT,
        FOREIGN KEY(fatura_id) REFERENCES ${DbSabitler.faturalar}(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.gunlukRaporOzet} (
        rapor_tarihi DATE PRIMARY KEY,
        toplam_satis_tutar REAL NOT NULL DEFAULT 0,
        toplam_iade_tutar REAL NOT NULL DEFAULT 0,
        toplam_gider REAL NOT NULL DEFAULT 0,
        nakit_tahsilat REAL NOT NULL DEFAULT 0,
        kart_tahsilat REAL NOT NULL DEFAULT 0,
        cari_tahsilat REAL NOT NULL DEFAULT 0,
        kasa_son_bakiye REAL NOT NULL DEFAULT 0,
        olusturma_zamani DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');
  }
}
