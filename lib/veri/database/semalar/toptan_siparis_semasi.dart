// lib/veri/database/semalar/toptan_siparis_semasi.dart
//
// Kullanıcı isteği: "Bayilerden Sipariş Alma" — ürün arama/barkod ile
// bayiye sipariş alınır, alış fiyatı (maliyet) görünür, kalem bazında
// iskonto yapılabilir. Sipariş önce "Bekleyen Sipariş" olarak
// kaydedilir (bu tablolar), ayrı bir onay ekranından satışa/faturaya/
// irsaliyeye dönüştürülür (bkz. bekleyen_siparis_deposu.dart).
import 'package:sqflite/sqflite.dart';
import '../../../cekirdek/sabitler/db_sabitleri.dart';

class ToptanSiparisSemasi {
  static Future<void> olustur(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.bekleyenSiparisler} (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        global_id     TEXT UNIQUE,
        cari_id       INTEGER NOT NULL,
        sube_id       INTEGER,
        kullanici_id  INTEGER,
        tarih         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        durum         TEXT NOT NULL DEFAULT 'bekliyor',
        not_          TEXT,
        ara_toplam    REAL NOT NULL DEFAULT 0,
        iskonto_toplam REAL NOT NULL DEFAULT 0,
        kdv_toplam    REAL NOT NULL DEFAULT 0,
        genel_toplam  REAL NOT NULL DEFAULT 0,
        alis_toplam   REAL NOT NULL DEFAULT 0,
        satis_id      INTEGER,
        created_at    DATETIME DEFAULT CURRENT_TIMESTAMP,
        last_updated  DATETIME,
        deleted_at    DATETIME,
        FOREIGN KEY(cari_id) REFERENCES ${DbSabitler.cari}(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.bekleyenSiparisKalem} (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        global_id     TEXT UNIQUE,
        siparis_id    INTEGER NOT NULL,
        urun_id       INTEGER NOT NULL,
        urun_adi      TEXT NOT NULL,
        birim_adi     TEXT NOT NULL DEFAULT 'Adet',
        birim_carpani REAL NOT NULL DEFAULT 1,
        miktar        REAL NOT NULL,
        toplam_miktar REAL NOT NULL,
        birim_fiyat   REAL NOT NULL,
        alis_fiyat    REAL NOT NULL DEFAULT 0,
        iskonto_oran  REAL NOT NULL DEFAULT 0,
        iskonto_tutar REAL NOT NULL DEFAULT 0,
        kdv_oran      REAL NOT NULL DEFAULT 18,
        toplam_tutar  REAL NOT NULL,
        last_updated  DATETIME,
        FOREIGN KEY(siparis_id) REFERENCES ${DbSabitler.bekleyenSiparisler}(id) ON DELETE CASCADE,
        FOREIGN KEY(urun_id) REFERENCES ${DbSabitler.urunler}(id)
      )
    ''');

    await db.execute('CREATE INDEX IF NOT EXISTS idx_bekleyen_sip_kalem ON ${DbSabitler.bekleyenSiparisKalem}(siparis_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_bekleyen_sip_cari ON ${DbSabitler.bekleyenSiparisler}(cari_id)');
  }
}
