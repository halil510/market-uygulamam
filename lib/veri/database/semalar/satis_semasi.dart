// lib/veri/database/semalar/satis_semasi.dart
// OTOMATİK AYRIŞTIRILDI — tablo_olusturucu.dart içindeki _satis() bloğundan
// birebir taşındı. Amaç: 1097 satırlık tek dosya yerine modüler,
// domain bazlı şema dosyaları (Logo Yazılım tarzı katmanlı mimari).
//
// Satış fişi ve satış kalemleri
import 'package:sqflite/sqflite.dart';
import '../../../cekirdek/sabitler/db_sabitleri.dart';

class SatisSemasi {
  static Future<void> olustur(Database db) async {

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.satislar} (
        id INTEGER PRIMARY KEY AUTOINCREMENT, global_id TEXT UNIQUE,
        fis_no TEXT UNIQUE, tarih DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        cari_id INTEGER, toplam_tutar REAL NOT NULL DEFAULT 0,
        iskonto_tutar REAL NOT NULL DEFAULT 0, iskonto_oran REAL NOT NULL DEFAULT 0,
        kdv_tutar REAL NOT NULL DEFAULT 0, genel_toplam REAL NOT NULL DEFAULT 0,
        odenen_tutar REAL NOT NULL DEFAULT 0,
        odeme_yontemi TEXT NOT NULL DEFAULT 'Nakit',
        fis_tipi TEXT NOT NULL DEFAULT 'Satış', aciklama TEXT,
        kargo_ucreti REAL NOT NULL DEFAULT 0,
        kasiyer_id INTEGER, kullanici_id INTEGER, vardiya_id INTEGER, sube_id INTEGER,
        iptal INTEGER NOT NULL DEFAULT 0, iptal_tarihi DATETIME, iptal_nedeni TEXT,
        last_updated DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        efatura_uuid TEXT, efatura_durum TEXT, efatura_gonderim_tarihi TEXT,
        efatura_yanit TEXT, servis_ucreti REAL NOT NULL DEFAULT 0,
        deleted_at DATETIME, cihaz_id TEXT,
        sync_cakisma_kopyasi INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY(cari_id) REFERENCES ${DbSabitler.cari}(id),
        FOREIGN KEY(kasiyer_id) REFERENCES ${DbSabitler.kullanicilar}(id),
        FOREIGN KEY(kullanici_id) REFERENCES ${DbSabitler.kullanicilar}(id),
        FOREIGN KEY(sube_id) REFERENCES ${DbSabitler.subeler}(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.satisKalem} (
        id INTEGER PRIMARY KEY AUTOINCREMENT, 
        global_id TEXT UNIQUE,
        satis_id INTEGER NOT NULL,
        urun_id INTEGER NOT NULL, 
        urun_adi TEXT NOT NULL, 
        barkod TEXT,
        miktar REAL NOT NULL, 
        birim_fiyat REAL NOT NULL,
        iskonto_oran REAL NOT NULL DEFAULT 0, 
        iskonto_tutar REAL NOT NULL DEFAULT 0,
        kdv_oran REAL NOT NULL DEFAULT 18, 
        kdv_tutar REAL NOT NULL DEFAULT 0,
        net_fiyat REAL NOT NULL DEFAULT 0, 
        toplam_tutar REAL NOT NULL DEFAULT 0,
        lot_id INTEGER, 
        seri_no TEXT,
        alis_fiyat REAL NOT NULL DEFAULT 0, 
        alis_fiyat_kdv REAL NOT NULL DEFAULT 0,
        last_updated DATETIME,
        cihaz_id TEXT,
        FOREIGN KEY(satis_id) REFERENCES ${DbSabitler.satislar}(id) ON DELETE CASCADE,
        FOREIGN KEY(urun_id) REFERENCES ${DbSabitler.urunler}(id)
      )
    ''');
  
  }
}
