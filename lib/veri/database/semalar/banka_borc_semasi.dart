// lib/veri/database/semalar/banka_borc_semasi.dart
// OTOMATİK AYRIŞTIRILDI — tablo_olusturucu.dart içindeki _yeniTablolar() bloğundan
// birebir taşındı. Amaç: 1097 satırlık tek dosya yerine modüler,
// domain bazlı şema dosyaları (Logo Yazılım tarzı katmanlı mimari).
//
// Banka, kredi kartı, banka hareketleri, borç ödemeleri (yeni nesil finans modülü)
import 'package:sqflite/sqflite.dart';
import '../../../cekirdek/sabitler/db_sabitleri.dart';

class BankaBorcSemasi {
  static Future<void> olustur(Database db) async {

    // Rezervasyon tablosu
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.masaRezervasyon} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        global_id TEXT UNIQUE,
        masa_id INTEGER NOT NULL,
        musteri_adi TEXT NOT NULL,
        telefon TEXT NOT NULL,
        kisi_sayisi INTEGER NOT NULL DEFAULT 2,
        tarih DATETIME NOT NULL,
        saat DATETIME NOT NULL,
        not_ TEXT,
        durum TEXT NOT NULL DEFAULT 'beklemede',
        kullanici_id INTEGER,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        last_updated DATETIME DEFAULT CURRENT_TIMESTAMP,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY(masa_id) REFERENCES masalar(id) ON DELETE CASCADE
      )
    ''');
    
    await db.execute('CREATE INDEX IF NOT EXISTS idx_rezervasyon_tarih ON ${DbSabitler.masaRezervasyon}(tarih, saat)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_rezervasyon_masa ON ${DbSabitler.masaRezervasyon}(masa_id, durum)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_rezervasyon_musteri ON ${DbSabitler.masaRezervasyon}(musteri_adi)');
    
    // Garson çağrı log tablosu
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.garsonCagriLog} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        global_id TEXT UNIQUE,
        masa_id INTEGER NOT NULL,
        masa_adi TEXT,
        cagri_zamani DATETIME DEFAULT CURRENT_TIMESTAMP,
        yanit_zamani DATETIME,
        yanitlayan_id INTEGER,
        durum TEXT DEFAULT 'beklemede',
        FOREIGN KEY(masa_id) REFERENCES masalar(id)
      )
    ''');
    
    await db.execute('CREATE INDEX IF NOT EXISTS idx_garson_cagri_durum ON ${DbSabitler.garsonCagriLog}(durum)');
    
    // Masa siparişlerine garson_id ekle (varsa atla)
    try {
      await db.execute('ALTER TABLE masa_siparisleri ADD COLUMN garson_id INTEGER');
    } catch (e) { /* ignore */ }
    try {
      await db.execute('ALTER TABLE masa_siparisleri ADD COLUMN garson_adi TEXT');
    } catch (e) { /* ignore */ }
    
    // Adisyon log tablosu
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.adisyonLog} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        global_id TEXT UNIQUE,
        siparis_id INTEGER NOT NULL,
        adisyon_no TEXT NOT NULL,
        yazdiran_kullanici_id INTEGER,
        yazdirma_zamani DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        printer_turu TEXT DEFAULT 'termal',
        last_updated DATETIME,
        FOREIGN KEY(siparis_id) REFERENCES masa_siparisleri(id) ON DELETE CASCADE
      )
    ''');
    
    await db.execute('CREATE INDEX IF NOT EXISTS idx_adisyon_siparis ON ${DbSabitler.adisyonLog}(siparis_id)');
    
    // Masa hareket logu
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.masaHareketLog} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        global_id TEXT UNIQUE,
        kaynak_masa_id INTEGER,
        hedef_masa_id INTEGER,
        islem_tipi TEXT NOT NULL,
        siparis_id INTEGER,
        yapan_kullanici_id INTEGER,
        islem_zamani DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY(kaynak_masa_id) REFERENCES masalar(id),
        FOREIGN KEY(hedef_masa_id) REFERENCES masalar(id)
      )
    ''');
    
    await db.execute('CREATE INDEX IF NOT EXISTS idx_masa_hareket_zamani ON ${DbSabitler.masaHareketLog}(islem_zamani)');

    // Not: Borç tablosu artık ayrı modülde (borc_semasi.dart) ve
    // tablo_olusturucu.dart orkestratöründe BU dosyadan ÖNCE çağrılıyor —
    // burada tekrar oluşturmaya gerek yok.

    // ----------------- Yeni: Banka / Kredi Kartı / Borç Ödemeler tabloları -----------------
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.bankalar} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        global_id TEXT UNIQUE,
        ad TEXT NOT NULL,
        kod TEXT,
        tel TEXT,
        email TEXT,
        web TEXT,
        adres TEXT,
        logo TEXT,
        yetkili TEXT,
        aktif INTEGER NOT NULL DEFAULT 1,
        last_updated DATETIME DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.bankaHesaplar} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        global_id TEXT UNIQUE,
        banka_id INTEGER NOT NULL,
        hesap_adi TEXT NOT NULL,
        hesap_no TEXT NOT NULL,
        iban TEXT,
        sube_adi TEXT,
        sube_kodu TEXT,
        para_birimi TEXT DEFAULT 'TRY',
        bakiye REAL DEFAULT 0,
        kullanilabilir_bakiye REAL DEFAULT 0,
        hesap_turu TEXT,
        aktif INTEGER NOT NULL DEFAULT 1,
        last_updated DATETIME DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY(banka_id) REFERENCES ${DbSabitler.bankalar}(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.krediKartlari} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        global_id TEXT UNIQUE,
        banka_id INTEGER NOT NULL,
        kart_adi TEXT NOT NULL,
        kart_no_maskeli TEXT NOT NULL,
        son_kullanma TEXT,
        kart_tipi TEXT DEFAULT 'Diğer',
        kartlimit REAL DEFAULT 0,
        kullanilan_limit REAL DEFAULT 0,
        kalan_limit REAL DEFAULT 0,
        faiz_orani REAL DEFAULT 0,
        taksit_sayisi INTEGER DEFAULT 1,
        kesim_tarihi TEXT,
        son_odeme_tarihi TEXT,
        aktif INTEGER NOT NULL DEFAULT 1,
        last_updated DATETIME DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY(banka_id) REFERENCES ${DbSabitler.bankalar}(id)
      )
    ''');

    // Kullanıcı isteği: "detaylı analiz et, en iyi hale getir" — kredi
    // kartı limit kullanımı ÖNCEDEN "kullanilan_limit"i oku-hesapla-yaz
    // şeklinde güncelliyordu (borçta/stokta bulup düzelttiğim AYNI
    // "kayıp güncelleme" riski — 2 cihazdan aynı karta aynı anda işlem
    // girilirse biri kaybolabilirdi). Artık her işlem kendi hareket
    // kaydı — kullanılan limit bunların toplamından hesaplanıyor.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS kredi_karti_hareket (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        global_id TEXT UNIQUE,
        kredi_karti_id INTEGER NOT NULL,
        tutar REAL NOT NULL,
        yon TEXT NOT NULL DEFAULT 'harcama',
        aciklama TEXT,
        tarih DATETIME DEFAULT CURRENT_TIMESTAMP,
        last_updated DATETIME,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        referans_id INTEGER,
        referans_turu TEXT,
        FOREIGN KEY(kredi_karti_id) REFERENCES ${DbSabitler.krediKartlari}(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_kk_hareket_kart ON kredi_karti_hareket(kredi_karti_id)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.bankaHareketler} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        global_id TEXT UNIQUE,
        banka_hesap_id INTEGER NOT NULL,
        kredi_karti_id INTEGER,
        islem_tipi TEXT NOT NULL,
        tutar REAL NOT NULL,
        aciklama TEXT,
        tarih DATETIME DEFAULT CURRENT_TIMESTAMP,
        referans_no TEXT,
        karsi_hesap TEXT,
        onceki_bakiye REAL,
        sonraki_bakiye REAL,
        last_updated DATETIME,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        referans_id INTEGER,
        referans_turu TEXT,
        FOREIGN KEY(banka_hesap_id) REFERENCES ${DbSabitler.bankaHesaplar}(id),
        FOREIGN KEY(kredi_karti_id) REFERENCES ${DbSabitler.krediKartlari}(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.borcOdemeler} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        global_id TEXT UNIQUE,
        borc_id INTEGER NOT NULL,
        tutar REAL NOT NULL,
        tarih DATETIME DEFAULT CURRENT_TIMESTAMP,
        odeme_yontemi TEXT DEFAULT 'Nakit',
        aciklama TEXT,
        referans_no TEXT,
        banka_hesap_id INTEGER,
        kredi_karti_id INTEGER,
        last_updated DATETIME,
        FOREIGN KEY(borc_id) REFERENCES ${DbSabitler.borclar}(id),
        FOREIGN KEY(banka_hesap_id) REFERENCES ${DbSabitler.bankaHesaplar}(id),
        FOREIGN KEY(kredi_karti_id) REFERENCES ${DbSabitler.krediKartlari}(id)
      )
    ''');

    // Indexler for new finance tables
    try { await db.execute('CREATE INDEX IF NOT EXISTS idx_banka_aktif ON ${DbSabitler.bankalar}(aktif)'); } catch (_) { /* indeks zaten varsa veya tablo o sürümde yoksa atlanır — kurulumu bloklamaz */ }
    try { await db.execute('CREATE INDEX IF NOT EXISTS idx_banka_hesap_banka ON ${DbSabitler.bankaHesaplar}(banka_id)'); } catch (_) { /* indeks zaten varsa veya tablo o sürümde yoksa atlanır — kurulumu bloklamaz */ }
    try { await db.execute('CREATE INDEX IF NOT EXISTS idx_banka_hesap_aktif ON ${DbSabitler.bankaHesaplar}(aktif)'); } catch (_) { /* indeks zaten varsa veya tablo o sürümde yoksa atlanır — kurulumu bloklamaz */ }
    try { await db.execute('CREATE INDEX IF NOT EXISTS idx_kredi_karti_banka ON ${DbSabitler.krediKartlari}(banka_id)'); } catch (_) { /* indeks zaten varsa veya tablo o sürümde yoksa atlanır — kurulumu bloklamaz */ }
    try { await db.execute('CREATE INDEX IF NOT EXISTS idx_kredi_karti_aktif ON ${DbSabitler.krediKartlari}(aktif)'); } catch (_) { /* indeks zaten varsa veya tablo o sürümde yoksa atlanır — kurulumu bloklamaz */ }
    try { await db.execute('CREATE INDEX IF NOT EXISTS idx_banka_hareket_hesap ON ${DbSabitler.bankaHareketler}(banka_hesap_id)'); } catch (_) { /* indeks zaten varsa veya tablo o sürümde yoksa atlanır — kurulumu bloklamaz */ }
    try { await db.execute('CREATE INDEX IF NOT EXISTS idx_banka_hareket_tarih ON ${DbSabitler.bankaHareketler}(tarih)'); } catch (_) { /* indeks zaten varsa veya tablo o sürümde yoksa atlanır — kurulumu bloklamaz */ }
    try { await db.execute('CREATE INDEX IF NOT EXISTS idx_banka_hareket_kart ON ${DbSabitler.bankaHareketler}(kredi_karti_id)'); } catch (_) { /* indeks zaten varsa veya tablo o sürümde yoksa atlanır — kurulumu bloklamaz */ }
    // DEEP_AUDIT (kendi-keşif turu, 2026-09-21): cari hareket iptalinde
    // banka/kredi kartı tarafını bulup tersine çevirebilmek için (bkz.
    // CariDeposu.hareketIptalEt) eklenen referans_id/referans_turu için.
    try { await db.execute('CREATE INDEX IF NOT EXISTS idx_banka_hareket_referans ON ${DbSabitler.bankaHareketler}(referans_turu, referans_id)'); } catch (_) { /* atlanır */ }
    try { await db.execute('CREATE INDEX IF NOT EXISTS idx_kk_hareket_referans ON kredi_karti_hareket(referans_turu, referans_id)'); } catch (_) { /* atlanır */ }
    try { await db.execute('CREATE INDEX IF NOT EXISTS idx_borc_odeme_borc ON ${DbSabitler.borcOdemeler}(borc_id)'); } catch (_) { /* indeks zaten varsa veya tablo o sürümde yoksa atlanır — kurulumu bloklamaz */ }
    try { await db.execute('CREATE INDEX IF NOT EXISTS idx_borc_odeme_tarih ON ${DbSabitler.borcOdemeler}(tarih)'); } catch (_) { /* indeks zaten varsa veya tablo o sürümde yoksa atlanır — kurulumu bloklamaz */ }
  
  }
}
