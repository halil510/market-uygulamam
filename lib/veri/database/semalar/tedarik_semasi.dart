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

    await iadeTablolariniOlustur(db);
  }

  /// Tedarikçiye (toptancıya) mal iadesi — ALIŞ iadesi. Müşteri/bayi
  /// iadelerinin tutulduğu `iade` tablosundan BİLİNÇLİ OLARAK ayrı: yönü
  /// tersidir (stok azalır, tedarikçiye olan borç düşer). Aynı tabloda
  /// dursaydı İade Geçmişi'nin silme/düzenleme mantığı ve iade raporları
  /// onu müşteri iadesi sanıp ters yönde işlerdi.
  ///
  /// Kalem fiyat alanları tedarikci_siparis_kalem ile aynı anlamdadır:
  /// birim_fiyat KDV HARİÇ birim maliyet (son alış fiyatı), toplam_tutar
  /// KDV DAHİL (tedarikçiye borç KDV dahil yazıldığı için).
  ///
  /// Hem sıfırdan kurulum hem v81 migrasyonu bu metodu kullanır.
  static Future<void> iadeTablolariniOlustur(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.tedarikciIadeler} (
        id INTEGER PRIMARY KEY AUTOINCREMENT, global_id TEXT UNIQUE,
        cari_id INTEGER NOT NULL, iade_no TEXT UNIQUE,
        tarih DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        toplam_tutar REAL NOT NULL DEFAULT 0, aciklama TEXT,
        olusturan_id INTEGER, sube_id INTEGER,
        last_updated DATETIME, is_deleted INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY(cari_id) REFERENCES ${DbSabitler.cari}(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.tedarikciIadeKalem} (
        id INTEGER PRIMARY KEY AUTOINCREMENT, global_id TEXT UNIQUE,
        iade_id INTEGER NOT NULL, urun_id INTEGER NOT NULL, urun_adi TEXT,
        miktar REAL NOT NULL, birim_fiyat REAL NOT NULL,
        kdv_oran REAL NOT NULL DEFAULT 0, toplam_tutar REAL NOT NULL,
        last_updated DATETIME,
        FOREIGN KEY(iade_id) REFERENCES ${DbSabitler.tedarikciIadeler}(id) ON DELETE CASCADE,
        FOREIGN KEY(urun_id) REFERENCES ${DbSabitler.urunler}(id)
      )
    ''');
    for (final sql in iadeIndeksleri) {
      await db.execute(sql);
    }
  }

  static const iadeIndeksleri = [
    'CREATE INDEX IF NOT EXISTS idx_ted_iade_cari ON tedarikci_iadeler(cari_id)',
    'CREATE INDEX IF NOT EXISTS idx_ted_iade_kalem_iade ON tedarikci_iade_kalem(iade_id)',
    'CREATE INDEX IF NOT EXISTS idx_ted_iade_kalem_urun ON tedarikci_iade_kalem(urun_id)',
  ];
}
