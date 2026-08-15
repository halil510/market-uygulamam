// lib/veri/database/semalar/urun_semasi.dart
// OTOMATİK AYRIŞTIRILDI — tablo_olusturucu.dart içindeki _urun() bloğundan
// birebir taşındı. Amaç: 1097 satırlık tek dosya yerine modüler,
// domain bazlı şema dosyaları (Logo Yazılım tarzı katmanlı mimari).
//
// Ürün kartı, fiyat geçmişi, lot/seri, zaman bazlı fiyat tabloları
import 'package:sqflite/sqflite.dart';
import '../../../cekirdek/sabitler/db_sabitleri.dart';

class UrunSemasi {
  static Future<void> olustur(Database db) async {

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.urunler} (
        id                              INTEGER PRIMARY KEY AUTOINCREMENT,
        global_id                       TEXT UNIQUE,
        kod                             TEXT UNIQUE COLLATE NOCASE,
        barkod                          TEXT UNIQUE COLLATE NOCASE,
        barkodlar                       TEXT,
        urun_adi                        TEXT NOT NULL COLLATE NOCASE,
        alternatif_urun_adi             TEXT COLLATE NOCASE,
        birim_adi                       TEXT NOT NULL DEFAULT 'Adet',
        alis_fiyat                      REAL NOT NULL DEFAULT 0,
        alis_fiyat_kdv_dahil            REAL NOT NULL DEFAULT 0,
        satis_fiyati                    REAL NOT NULL DEFAULT 0,
        stok                            REAL NOT NULL DEFAULT 0,
        toplam_maliyet                  REAL NOT NULL DEFAULT 0,
        toplam_stok                     REAL NOT NULL DEFAULT 0,
        alis_kdv_oran                   REAL NOT NULL DEFAULT 18,
        kdv_oran                        TEXT NOT NULL DEFAULT '18',
        kategori_id                     INTEGER,
        ana_grup                        TEXT COLLATE NOCASE,
        alt_grup                        TEXT COLLATE NOCASE,
        aktif                           INTEGER NOT NULL DEFAULT 1,
        seri_no_takibi                  INTEGER NOT NULL DEFAULT 0,
        lot_takibi                      INTEGER NOT NULL DEFAULT 0,
        lot_no TEXT, son_kullanma_tarihi DATE,
        alan1 TEXT, alan2 TEXT, alan3 TEXT, alan4 TEXT,
        para_birimi                     TEXT NOT NULL DEFAULT 'TRY',
        indirim_orani                   REAL NOT NULL DEFAULT 0,
        otomatik_indirim                INTEGER NOT NULL DEFAULT 0,
        son_alim_indirim_oran           REAL NOT NULL DEFAULT 0,
        minimum_stok                    REAL NOT NULL DEFAULT 0,
        maksimum_stok                   REAL NOT NULL DEFAULT 0,
        maksimum_satir_miktari          REAL NOT NULL DEFAULT 0,
        renk TEXT, beden TEXT, sube TEXT, resim_yolu TEXT,
        -- Kullanıcı isteği: QR bulut menüde ürün görseli gösterilsin.
        -- "resim_yolu" cihazın KENDİ dosya sistemindeki yerel bir yol
        -- olduğu için (müşterinin telefonundan erişilemez), görsel
        -- buluta (Supabase Storage) yüklendiğinde oluşan HERKESE AÇIK
        -- adres burada ayrıca saklanıyor.
        resim_url TEXT,
        -- Kullanıcı isteği: 400 üründen sadece Kafe/Restoran ürünleri
        -- QR menüde görünsün, market/yöresel ürünler görünmesin.
        -- Varsayılan 0 (kapalı) — mevcut 400 ürünün TAMAMI aniden QR
        -- menüde belirmesin diye, kullanıcı hangisini istiyorsa
        -- TEK TEK işaretlemesi gerekiyor.
        qr_menude INTEGER NOT NULL DEFAULT 0,
        uretici TEXT COLLATE NOCASE, marka TEXT COLLATE NOCASE,
        model TEXT, grup_sorumlusu TEXT, mensei TEXT,
        raf_numarasi TEXT, raf_omru INTEGER,
        plu_numarasi TEXT, puan_orani REAL NOT NULL DEFAULT 0,
        plu INTEGER NOT NULL DEFAULT 0, plu_kart_boyut INTEGER NOT NULL DEFAULT 2,
        plu_sira INTEGER NOT NULL DEFAULT 0,
        doviz_kodu TEXT, doviz_tutari REAL,
        muhasebe_kodu TEXT, muafiyet_kodu TEXT,
        resmi_bakiye                    REAL NOT NULL DEFAULT 0,
        barkod_olcu_birimi TEXT,
        en REAL NOT NULL DEFAULT 0, boy REAL NOT NULL DEFAULT 0,
        yukseklik REAL NOT NULL DEFAULT 0, agirlik REAL NOT NULL DEFAULT 0,
        eski_kodu TEXT, kart_tipi TEXT NOT NULL DEFAULT 'Standart',
        seri_numarasi TEXT,
        fiyat_guncelleme_tarih DATETIME, fiyat_guncelleyen_kullanici TEXT,
        barkod_yazdirma_tarih DATETIME, barkod_yazdiran_kullanici TEXT,
        maliyet_guncelleme_tarih DATETIME, maliyet_guncelleyen_kullanici TEXT,
        guncelleme_tarihi               DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        kayit_tarihi                    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        guncelleyen_kullanici TEXT, kaydeden_kullanici TEXT,
        last_updated                    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        sync_status                     TEXT NOT NULL DEFAULT 'synced',
        is_deleted                      INTEGER NOT NULL DEFAULT 0,
        kdv_dahil INTEGER NOT NULL DEFAULT 1, barkod_tipi TEXT,
        max_stok REAL NOT NULL DEFAULT 0, deleted_at DATETIME,
        cihaz_id TEXT, zaman_fiyat_id INTEGER,
        indirimli_fiyat                 REAL NOT NULL DEFAULT 0,
        hacim                           REAL NOT NULL DEFAULT 0,
        evrak_kontrol_aktif             INTEGER NOT NULL DEFAULT 0,
        lot_aciklama TEXT,
        eski_fiyat                      REAL NOT NULL DEFAULT 0,
        eski_fiyat_tarih DATETIME,
        promosyon_grup TEXT, promosyon_aktif INTEGER NOT NULL DEFAULT 0,
        recete_katsayi                  REAL NOT NULL DEFAULT 1,
        net_alis_fiyat                  REAL NOT NULL DEFAULT 0,
        toptan_fiyat REAL NOT NULL DEFAULT 0,
        koli_ici_miktar REAL NOT NULL DEFAULT 0,
        koli_birim_adi TEXT NOT NULL DEFAULT 'Koli',
        satis_birimi_tipi TEXT NOT NULL DEFAULT 'adet',
        toptan_satista INTEGER NOT NULL DEFAULT 0,
        asgari_siparis_miktari REAL NOT NULL DEFAULT 0,
        FOREIGN KEY(kategori_id) REFERENCES ${DbSabitler.kategoriler}(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.fiyatGecmis} (
        id INTEGER PRIMARY KEY AUTOINCREMENT, global_id TEXT,
        urun_id INTEGER NOT NULL,
        eski_alis REAL, yeni_alis REAL, eski_satis REAL, yeni_satis REAL,
        degistiren TEXT, tarih DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        last_updated DATETIME,
        FOREIGN KEY(urun_id) REFERENCES ${DbSabitler.urunler}(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.lotSeri} (
        id INTEGER PRIMARY KEY AUTOINCREMENT, global_id TEXT UNIQUE,
        cihaz_id TEXT,
        urun_id INTEGER NOT NULL, lot_no TEXT, seri_no TEXT,
        miktar REAL NOT NULL DEFAULT 0, son_kullanma_tarihi DATE,
        uretim_tarihi DATE, tedarikci_cari_id INTEGER, aciklama TEXT,
        aktif INTEGER NOT NULL DEFAULT 1,
        kayit_tarihi DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        last_updated DATETIME,
        FOREIGN KEY(urun_id) REFERENCES ${DbSabitler.urunler}(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSabitler.zamanFiyat} (
        id INTEGER PRIMARY KEY AUTOINCREMENT, global_id TEXT,
        urun_id INTEGER NOT NULL REFERENCES ${DbSabitler.urunler}(id) ON DELETE CASCADE,
        gun_listesi TEXT NOT NULL DEFAULT '1,2,3,4,5,6,7',
        baslangic_saat TEXT NOT NULL DEFAULT '00:00',
        bitis_saat TEXT NOT NULL DEFAULT '23:59',
        fiyat_turu TEXT NOT NULL DEFAULT 'sabit',
        deger REAL NOT NULL, aktif INTEGER NOT NULL DEFAULT 1, aciklama TEXT,
        olusturma DATETIME DEFAULT CURRENT_TIMESTAMP,
        guncelleme DATETIME DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // Favori ürünler — önceden sadece migrasyon zincirinde vardı, taze
    // kurulumlarda hiç oluşturulmuyordu.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS favori_urunler (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        global_id    TEXT,
        kullanici_id INTEGER NOT NULL,
        urun_id      INTEGER NOT NULL,
        sira         INTEGER NOT NULL DEFAULT 0,
        created_at   TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        UNIQUE(kullanici_id, urun_id),
        FOREIGN KEY(kullanici_id) REFERENCES kullanicilar(id),
        FOREIGN KEY(urun_id)      REFERENCES urunler(id)
      )
    ''');
  }
}
