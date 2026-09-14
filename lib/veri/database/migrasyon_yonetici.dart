// lib/veri/database/migrasyon_yonetici.dart
import 'package:sqflite/sqflite.dart';
import 'semalar/kolon_tamamlayici.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';
import 'semalar/masa_semasi.dart';
import 'semalar/doviz_semasi.dart';

class MigrasyonYonetici {
  static Future<void> guncelle(
      Database db, int eskiVersiyon, int yeniVersiyon) async {
    // v1'den v2'ye
    if (eskiVersiyon < 2) await _v1denV2ye(db);

    // v2'den v3'e
    if (eskiVersiyon < 3) await _v2denV3e(db);

    // v3'ten v4'e
    if (eskiVersiyon < 4) await _v3denV4e(db);

    // v4'ten v5'e
    if (eskiVersiyon < 5) await _v4denV5e(db);

    // v5'ten v6'ya
    if (eskiVersiyon < 6) await _v5denV6ya(db);

    // v6'dan v7'ye
    if (eskiVersiyon < 7) await _v6denV7ye(db);

    // v7'den v8'e (İade Faturası)
    if (eskiVersiyon < 8) await _v7denV8e(db);

    // v8'den v9'a (Masa/Restoran)
    if (eskiVersiyon < 9) await _v8denV9a(db);

    // v9'dan v10'a (PLU)
    if (eskiVersiyon < 10) await _v9denV10a(db);

    // v10'dan v11'e (Rezervasyon + Garson Çağrı)
    if (eskiVersiyon < 11) await _v10denV11e(db);

    // v11'den v12'ye (Masa rapor indexleri)
    if (eskiVersiyon < 12) await _v11denV12e(db);

    // v12'den v13'e (Masa Detay + Adisyon log)
    if (eskiVersiyon < 13) await _v12denV13e(db);

    //  YENİ: v13'ten v14'e (Tüm eksik sütunlar)
    if (eskiVersiyon < 14) await _v13denV14e(db);

    //  YENİ: v14'ten v15'e (Tüm eksik sütunlar)
    if (eskiVersiyon < 15) await _v14denV15e(db);

    //  YENİ: v15'ten v16'ya (Borc Takip)
    if (eskiVersiyon < 16) await _v15denV16ya(db);

    //  YENİ: v16'ten v17'ye (Banka, Kredi Kartı, Mail)
    if (eskiVersiyon < 17) await _v16denV17ye(db);

    // YENI: v17'den v18'e (duzeltme: cift bakiye guncellemesi + bozuk
    if (eskiVersiyon < 18) await _v17denV18e(db);

    if (eskiVersiyon < 19) await _v18denV19a(db);

    // GÜVENLİK: v19'dan v20'ye — kredi kartı numarası artık maskelenmiş
    // saklanıyor, CVC hiç saklanmıyor (bkz. _v19denV20ye yorumu)
    if (eskiVersiyon < 20) await _v19denV20ye(db);

    // v20'den v21'e — çoklu para birimi (döviz kurları) tablosu eklendi
    if (eskiVersiyon < 21) await _v20denV21e(db);

    // v21'den v22'ye — PLU panelinde sürükle-bırak sıralaması artık
    // kalıcı (önceden sadece görsel olarak değişiyordu, veritabanına
    // hiç kaydedilmiyordu, ekran yenilenince kayboluyordu).
    if (eskiVersiyon < 22) await _v21denV22ye(db);

    // v22'den v23'e — Personel telefon/e-posta alanları (form bu
    // bilgileri topluyordu ama veritabanında sütun hiç yoktu, sessizce
    // kayboluyordu).
    if (eskiVersiyon < 23) await _v22denV23e(db);

    // v23'ten v24'e — Cari kartlarda "e-Fatura Mükellefi mi?" durumu
    // (LOGO gibi profesyonel yazılımlardaki gibi, GİB Kayıtlı Kullanıcılar
    // Listesi sorgusu sonucu önbelleğe alınıyor).
    if (eskiVersiyon < 24) await _v23denV24e(db);

    // v24'ten v25'e — Fatura "Ödeme Şekli" alanı (Nakit/Kart/Havale vb.
    // — hem basılan faturada hem UBL-TR XML'inde eksikti).
    if (eskiVersiyon < 25) await _v24denV25e(db);

    // v25'ten v26'ya — Ürün "döviz bazlı fiyatlandırma" (kur değişince
    // toplu yeniden fiyatlandırma için).
    if (eskiVersiyon < 26) await _v25denV26ya(db);

    // v26'dan v27'ye — Şifre güvenliği: tuzsuz düz SHA-256 yerine
    // kullanıcı başına rastgele tuz (salt) + çok turlu hash. Bu
    // oturumda tespit edilen güvenlik açığının düzeltmesi.
    if (eskiVersiyon < 27) await _v26danV27ye(db);

    // v27'den v28'e — GİB şifresi ve mali mühür şifresi SQLite'tan
    // (düz metin) güvenli depolamaya (flutter_secure_storage) taşınıyor.
    if (eskiVersiyon < 28) await _v27denV28e(db);

    // v28'den v29'a — Borç ödemeleri artık hareket-bazlı (event
    // sourcing), önceki oku-hesapla-yaz riskini ortadan kaldırıyor.
    if (eskiVersiyon < 29) await _v28denV29a(db);

    // v29'dan v30'a — Kredi kartı limit kullanımı hareket-bazlı oldu.
    if (eskiVersiyon < 30) await _v29danV30a(db);

    // v30'dan v31'e — Ürün görselinin bulut adresi için sütun eklendi.
    if (eskiVersiyon < 31) await _v30danV31e(db);

    // v31'den v32'ye — QR menüde gösterilecek ürünler için sütun eklendi.
    if (eskiVersiyon < 32) await _v31denV32ye(db);
    if (eskiVersiyon < 33) await _v32denV33e(db);
    if (eskiVersiyon < 34) await _v33denV34e(db);
    if (eskiVersiyon < 35) await _v34denV35e(db);
    if (eskiVersiyon < 36) await _v35denV36e(db);
    if (eskiVersiyon < 37) await _v36denV37e(db);
    if (eskiVersiyon < 38) await _v37denV38e(db);
    if (eskiVersiyon < 39) await _v38denV39a(db);
    if (eskiVersiyon < 40) await _v39danV40a(db);
    if (eskiVersiyon < 41) await _v40danV41a(db);
    if (eskiVersiyon < 42) await _v41denV42e(db);
    if (eskiVersiyon < 43) await _v42denV43e(db);
    if (eskiVersiyon < 44) await _v43denV44e(db);
    if (eskiVersiyon < 45) await _v44denV45e(db);
    if (eskiVersiyon < 46) await _v45denV46e(db);
    if (eskiVersiyon < 47) await _v46denV47e(db);
    if (eskiVersiyon < 48) await _v47denV48e(db);
    if (eskiVersiyon < 49) await _v48denV49a(db);
    if (eskiVersiyon < 50) await _v49danV50ye(db);
    if (eskiVersiyon < 51) await _v50denV51e(db);

    // v51'den v52'ye
    if (eskiVersiyon < 52) await _v51denV52ye(db);

    // v52'den v53'e
    if (eskiVersiyon < 53) await _v52denV53e(db);

    // v53'ten v54'e — Sync Çakışmaları tablosu (protokol §12)
    if (eskiVersiyon < 54) await _v53denV54e(db);

    // v54'ten v55'e — bozuk 'last_updated' tetikleyicileri kaldırıldı
    if (eskiVersiyon < 55) await _v54denV55e(db);

    // v55'ten v56'ya — kasa_hareketleri.odeme_yontemi eklendi (Vardiya/Kasa mutabakatı)
    if (eskiVersiyon < 56) await _v55denV56ya(db);

    // v56'dan v57'ye — Onay Merkezi (FAZ 9, kullanıcı onayıyla)
    if (eskiVersiyon < 57) await _v56denV57ye(db);

    // v57'den v58'e — Bayi Portalı (kullanıcı onayıyla)
    if (eskiVersiyon < 58) await _v57denV58e(db);
    if (eskiVersiyon < 59) await _v58denV59a(db);
    if (eskiVersiyon < 60) await _v59denV60a(db);
    if (eskiVersiyon < 61) await _v60danV61e(db);
    if (eskiVersiyon < 62) await _v61denV62ye(db);
    if (eskiVersiyon < 63) await _v62denV63e(db);
  }

  // ==================== v1 -> v2 ====================
  static Future<void> _v1denV2ye(Database db) async {
    await _calistir(db,
        'ALTER TABLE urunler ADD COLUMN kdv_dahil INTEGER NOT NULL DEFAULT 1');
    await _calistir(db,
        'ALTER TABLE urunler ADD COLUMN barkod_tipi TEXT NOT NULL DEFAULT "CODE128"');
    await _calistir(db,
        'ALTER TABLE satislar ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0');
  }

  // ==================== v2 -> v3 ====================
  static Future<void> _v2denV3e(Database db) async {
    await _calistir(db,
        'ALTER TABLE urunler ADD COLUMN indirimli_fiyat REAL NOT NULL DEFAULT 0');
    await _calistir(db, 'ALTER TABLE satislar ADD COLUMN cari_id INTEGER');
    await _calistir(db, 'ALTER TABLE cari ADD COLUMN global_id TEXT UNIQUE');

    await _calistir(db, """
      CREATE TABLE IF NOT EXISTS promosyonlar (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        ad          TEXT    NOT NULL,
        urun_id     INTEGER,
        min_miktar  REAL    NOT NULL DEFAULT 1,
        iskonto_oran REAL   NOT NULL DEFAULT 0,
        baslangic_tarihi TEXT,
        bitis_tarihi     TEXT,
        aktif       INTEGER NOT NULL DEFAULT 1,
        created_at  TEXT    NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    """);
  }

  // ==================== v3 -> v4 ====================
  static Future<void> _v3denV4e(Database db) async {
    await _calistir(db,
        'ALTER TABLE satis_kalem ADD COLUMN alis_fiyat REAL NOT NULL DEFAULT 0');
    await _calistir(db,
        'ALTER TABLE satis_kalem ADD COLUMN alis_fiyat_kdv REAL NOT NULL DEFAULT 0');
    await _calistir(db, 'ALTER TABLE satislar ADD COLUMN efatura_uuid TEXT');
    await _calistir(
        db, 'ALTER TABLE satislar ADD COLUMN efatura_durum TEXT DEFAULT NULL');
    await _calistir(db,
        'ALTER TABLE satislar ADD COLUMN efatura_gonderim_tarihi TEXT DEFAULT NULL');
    await _calistir(
        db, 'ALTER TABLE satislar ADD COLUMN efatura_yanit TEXT DEFAULT NULL');
    await _calistir(db, 'ALTER TABLE cari ADD COLUMN vergi_no TEXT');
    await _calistir(db, 'ALTER TABLE cari ADD COLUMN vergi_dairesi TEXT');
    await _calistir(db, 'ALTER TABLE faturalar ADD COLUMN efatura_uuid TEXT');
    await _calistir(
        db, 'ALTER TABLE faturalar ADD COLUMN efatura_durum TEXT DEFAULT NULL');
    await _calistir(db, 'ALTER TABLE faturalar ADD COLUMN efatura_tipi TEXT');
    await _calistir(db, 'ALTER TABLE roller_yetki ADD COLUMN created_at TEXT');
    await _calistir(db,
        'ALTER TABLE urunler ADD COLUMN eski_fiyat REAL NOT NULL DEFAULT 0');
    await _calistir(
        db, 'ALTER TABLE urunler ADD COLUMN eski_fiyat_tarih DATETIME');
    await _calistir(db, 'ALTER TABLE urunler ADD COLUMN promosyon_grup TEXT');
    await _calistir(db,
        'ALTER TABLE urunler ADD COLUMN promosyon_aktif INTEGER NOT NULL DEFAULT 0');
    await _calistir(db,
        'ALTER TABLE urunler ADD COLUMN net_alis_fiyat REAL NOT NULL DEFAULT 0');

    await _calistir(db, """
      CREATE TABLE IF NOT EXISTS app_log (
        id      INTEGER PRIMARY KEY AUTOINCREMENT,
        seviye  TEXT NOT NULL,
        mesaj   TEXT NOT NULL,
        hata    TEXT,
        yigin   TEXT,
        ek      TEXT,
        zaman   TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    """);

    await _calistir(db, """
      CREATE TABLE IF NOT EXISTS irsaliyeler (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        irsaliye_no   TEXT    NOT NULL,
        cari_id       INTEGER,
        tarih         TEXT    NOT NULL,
        tip           TEXT    NOT NULL DEFAULT 'Cikis',
        toplam_tutar  REAL    NOT NULL DEFAULT 0,
        durum         TEXT    NOT NULL DEFAULT 'Bekliyor',
        kullanici_id  INTEGER,
        created_at    TEXT DEFAULT CURRENT_TIMESTAMP
      )
    """);

    await _calistir(db, """
      CREATE TABLE IF NOT EXISTS irsaliye_kalem (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        irsaliye_id   INTEGER NOT NULL,
        urun_id       INTEGER,
        urun_adi      TEXT    NOT NULL,
        miktar        REAL    NOT NULL DEFAULT 1,
        birim_fiyat   REAL    NOT NULL DEFAULT 0,
        toplam_tutar  REAL    NOT NULL DEFAULT 0
      )
    """);

    await _calistir(db, """
      UPDATE satis_kalem
      SET alis_fiyat = COALESCE(
        (SELECT alis_fiyat FROM urunler WHERE id = satis_kalem.urun_id), 0)
      WHERE alis_fiyat = 0
    """);
  }

  // ==================== v4 -> v5 ====================
  static Future<void> _v4denV5e(Database db) async {
    await _calistir(db, """
      CREATE TABLE IF NOT EXISTS bildirim_tercihleri (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        kullanici_id    INTEGER,
        olay_turu       TEXT NOT NULL,
        aktif           INTEGER NOT NULL DEFAULT 1,
        esik_deger      REAL,
        bildirim_saati  TEXT,
        son_tetikleme   TEXT,
        created_at      TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY(kullanici_id) REFERENCES kullanicilar(id)
      )
    """);

    final olaylar = [
      'kritik_stok',
      'gunluk_rapor',
      'kasa_kapanisi',
      'vadesi_gelen_cari',
      'yedekleme_hatirlatma'
    ];
    for (final olay in olaylar) {
      await _calistir(db,
          "INSERT OR IGNORE INTO bildirim_tercihleri(olay_turu, aktif) VALUES('$olay', 1)");
    }

    await _calistir(
        db, 'ALTER TABLE urunler ADD COLUMN max_stok REAL NOT NULL DEFAULT 0');
    await _calistir(db,
        'ALTER TABLE satislar ADD COLUMN servis_ucreti REAL NOT NULL DEFAULT 0');

    await _calistir(db, """
      CREATE TABLE IF NOT EXISTS vardiya_detay (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        vardiya_id  INTEGER NOT NULL,
        saat        INTEGER NOT NULL,
        satis_sayisi INTEGER NOT NULL DEFAULT 0,
        toplam_ciro REAL    NOT NULL DEFAULT 0,
        ortalama    REAL    NOT NULL DEFAULT 0,
        created_at  TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY(vardiya_id) REFERENCES vardiyalar(id)
      )
    """);

    await _calistir(
        db, 'ALTER TABLE personel ADD COLUMN maas REAL NOT NULL DEFAULT 0');
    await _calistir(db,
        'ALTER TABLE personel ADD COLUMN calisma_saati REAL NOT NULL DEFAULT 0');
    await _calistir(
        db, 'ALTER TABLE personel ADD COLUMN ise_baslama_tarihi TEXT');
    await _calistir(db, 'ALTER TABLE personel ADD COLUMN departman TEXT');

    await _calistir(db, """
      CREATE TABLE IF NOT EXISTS favori_urunler (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        kullanici_id INTEGER NOT NULL,
        urun_id      INTEGER NOT NULL,
        sira         INTEGER NOT NULL DEFAULT 0,
        created_at   TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        UNIQUE(kullanici_id, urun_id),
        FOREIGN KEY(kullanici_id) REFERENCES kullanicilar(id),
        FOREIGN KEY(urun_id)      REFERENCES urunler(id)
      )
    """);

    await _v5Ek(db);

    // Indexler
    final indexler = [
      'CREATE INDEX IF NOT EXISTS idx_satislar_tarih       ON satislar(tarih)',
      'CREATE INDEX IF NOT EXISTS idx_satislar_kullanici   ON satislar(kullanici_id)',
      'CREATE INDEX IF NOT EXISTS idx_satislar_iptal       ON satislar(iptal, tarih)',
      'CREATE INDEX IF NOT EXISTS idx_satis_kalem_urun     ON satis_kalem(urun_id)',
      'CREATE INDEX IF NOT EXISTS idx_satis_kalem_satis    ON satis_kalem(satis_id)',
      'CREATE INDEX IF NOT EXISTS idx_stok_hareket_urun    ON stok_hareket(urun_id)',
      'CREATE INDEX IF NOT EXISTS idx_stok_hareket_tarih   ON stok_hareket(tarih)',
      'CREATE INDEX IF NOT EXISTS idx_urunler_barkod       ON urunler(barkod)',
      'CREATE INDEX IF NOT EXISTS idx_urunler_kategori     ON urunler(kategori_id)',
      'CREATE INDEX IF NOT EXISTS idx_urunler_stok         ON urunler(stok)',
      'CREATE INDEX IF NOT EXISTS idx_cari_hareket_cari    ON cari_hareket(cari_id)',
      'CREATE INDEX IF NOT EXISTS idx_cari_hareket_tarih   ON cari_hareket(tarih)',
      'CREATE INDEX IF NOT EXISTS idx_kasa_tarih           ON kasa_hareketleri(tarih)',
      'CREATE INDEX IF NOT EXISTS idx_giderler_tarih       ON giderler(tarih)',
      'CREATE INDEX IF NOT EXISTS idx_faturalar_tarih      ON faturalar(tarih)',
      'CREATE INDEX IF NOT EXISTS idx_faturalar_cari       ON faturalar(cari_id)',
    ];
    for (final idx in indexler) {
      try {
        await _calistir(db, idx);
      } catch (e) {}
    }

    await _calistir(
        db, 'CREATE INDEX IF NOT EXISTS idx_app_log_zaman ON app_log(zaman)');
    await _calistir(db,
        "UPDATE stok_hareket SET tarih = CURRENT_TIMESTAMP WHERE tarih IS NULL OR tarih = ''");
  }

  static Future<void> _v5Ek(Database db) async {
    await _calistir(db, 'ALTER TABLE personel ADD COLUMN ise_baslama DATE');
    await _calistir(
        db, "ALTER TABLE bildirimler ADD COLUMN tip TEXT DEFAULT 'bilgi'");
    await _calistir(db, 'ALTER TABLE urunler ADD COLUMN kategori_id INTEGER');
    await _calistir(db, 'ALTER TABLE satislar ADD COLUMN kullanici_id INTEGER');
    await _calistir(db,
        "ALTER TABLE faturalar ADD COLUMN e_fatura_durum TEXT DEFAULT 'hazir'");
    await _calistir(db, 'ALTER TABLE faturalar ADD COLUMN e_fatura_uuid TEXT');
    await _calistir(db, 'ALTER TABLE faturalar ADD COLUMN e_fatura_html TEXT');
    await _calistir(db, 'ALTER TABLE faturalar ADD COLUMN e_fatura_xml TEXT');
    await _calistir(
        db, 'ALTER TABLE faturalar ADD COLUMN gonderim_tarihi TEXT');
    await _calistir(
        db, 'ALTER TABLE faturalar ADD COLUMN uygulama_yaniti TEXT');
  }

  // ==================== v5 -> v6 ====================
  static Future<void> _v5denV6ya(Database db) async {
    await _calistir(db,
        'ALTER TABLE urunler ADD COLUMN alis_fiyat_kdv_dahil REAL NOT NULL DEFAULT 0');
    await _calistir(
        db, 'ALTER TABLE urunler ADD COLUMN barkod_olcu_birimi TEXT');
    await _calistir(
        db, 'ALTER TABLE urunler ADD COLUMN en REAL NOT NULL DEFAULT 0');
    await _calistir(
        db, 'ALTER TABLE urunler ADD COLUMN boy REAL NOT NULL DEFAULT 0');
    await _calistir(
        db, 'ALTER TABLE urunler ADD COLUMN yukseklik REAL NOT NULL DEFAULT 0');
    await _calistir(
        db, 'ALTER TABLE urunler ADD COLUMN agirlik REAL NOT NULL DEFAULT 0');
    await _calistir(db, 'ALTER TABLE urunler ADD COLUMN eski_kodu TEXT');
    await _calistir(
        db, 'ALTER TABLE urunler ADD COLUMN kart_tipi TEXT DEFAULT "Standart"');
    await _calistir(db, 'ALTER TABLE urunler ADD COLUMN seri_numarasi TEXT');
    await _calistir(
        db, 'ALTER TABLE urunler ADD COLUMN fiyat_guncelleme_tarih TEXT');
    await _calistir(
        db, 'ALTER TABLE urunler ADD COLUMN fiyat_guncelleyen_kullanici TEXT');
    await _calistir(
        db, 'ALTER TABLE urunler ADD COLUMN barkod_yazdirma_tarih TEXT');
    await _calistir(
        db, 'ALTER TABLE urunler ADD COLUMN barkod_yazdiran_kullanici TEXT');
    await _calistir(
        db, 'ALTER TABLE urunler ADD COLUMN maliyet_guncelleme_tarih TEXT');
    await _calistir(db,
        'ALTER TABLE urunler ADD COLUMN maliyet_guncelleyen_kullanici TEXT');
    await _calistir(
        db, 'ALTER TABLE urunler ADD COLUMN guncelleyen_kullanici TEXT');
    await _calistir(
        db, 'ALTER TABLE urunler ADD COLUMN kaydeden_kullanici TEXT');

    await _calistir(db, '''
      CREATE TABLE IF NOT EXISTS efatura_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fatura_id INTEGER,
        tarih DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        islem_tipi TEXT NOT NULL,
        durum TEXT NOT NULL,
        uuid TEXT,
        hata_kodu TEXT,
        hata_mesaji TEXT,
        istek_json TEXT,
        yanit_json TEXT
      )
    ''');

    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_satislar_cari    ON satislar(cari_id)');
    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_satislar_fis_no  ON satislar(fis_no)');
    await _calistir(
        db, 'CREATE INDEX IF NOT EXISTS idx_cari_unvan       ON cari(unvan)');
    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_urunler_ana_grup ON urunler(ana_grup)');
    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_urunler_aktif    ON urunler(aktif, stok)');
    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_faturalar_cari   ON faturalar(cari_id)');
    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_efatura_log      ON efatura_log(fatura_id)');
  }

  // ==================== v6 -> v7 ====================
  static Future<void> _v6denV7ye(Database db) async {
    // Kategoriler
    await _calistir(
        db, 'ALTER TABLE kategoriler ADD COLUMN last_updated DATETIME');
    await _calistir(db,
        "UPDATE kategoriler SET last_updated = datetime('now') WHERE last_updated IS NULL");
    await _calistir(
        db, 'ALTER TABLE birimler ADD COLUMN last_updated DATETIME');
    await _calistir(db,
        "UPDATE birimler SET last_updated = datetime('now') WHERE last_updated IS NULL");
    await _calistir(
        db, 'ALTER TABLE gider_kategoriler ADD COLUMN last_updated DATETIME');
    await _calistir(db,
        "UPDATE gider_kategoriler SET last_updated = datetime('now') WHERE last_updated IS NULL");
    await _calistir(
        db, 'ALTER TABLE stok_hareket ADD COLUMN last_updated DATETIME');
    await _calistir(db,
        "UPDATE stok_hareket SET last_updated = datetime('now') WHERE last_updated IS NULL");

    // Global ID'ler
    await _calistir(db, 'ALTER TABLE giderler ADD COLUMN global_id TEXT');
    await _calistir(
        db, 'ALTER TABLE kasa_hareketleri ADD COLUMN global_id TEXT');
    await _calistir(db, 'ALTER TABLE promosyonlar ADD COLUMN global_id TEXT');
    await _calistir(db, 'ALTER TABLE vardiyalar ADD COLUMN global_id TEXT');
    await _calistir(db, 'ALTER TABLE personel ADD COLUMN global_id TEXT');
    await _calistir(db, 'ALTER TABLE musteri_puan ADD COLUMN global_id TEXT');
    await _calistir(db, 'ALTER TABLE iade ADD COLUMN global_id TEXT');

    // Sync tabloları
    await _calistir(db, """
      CREATE TABLE IF NOT EXISTS sync_queue (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        tablo_adi       TEXT NOT NULL,
        kayit_global_id TEXT,
        kayit_id        INTEGER,
        islem_tipi      TEXT NOT NULL,
        veri_json       TEXT NOT NULL,
        deneme_sayisi   INTEGER DEFAULT 0,
        son_deneme      DATETIME,
        durum           TEXT DEFAULT 'beklemede',
        created_at      DATETIME DEFAULT CURRENT_TIMESTAMP
      )
    """);

    await _calistir(db, """
      CREATE TABLE IF NOT EXISTS sync_meta (
        tablo_adi   TEXT PRIMARY KEY,
        son_senkron DATETIME,
        son_id      INTEGER,
        deleted_records TEXT
      )
    """);

    await _calistir(db, """
      CREATE TABLE IF NOT EXISTS stok_fifo (
        id                INTEGER PRIMARY KEY AUTOINCREMENT,
        giris_hareket_id  INTEGER NOT NULL,
        cikis_hareket_id  INTEGER NOT NULL,
        kullanilan_miktar REAL NOT NULL
      )
    """);

    await _calistir(db, """
      CREATE TABLE IF NOT EXISTS sube_fiyat_gecmis (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        urun_id     INTEGER NOT NULL,
        sube_id     INTEGER NOT NULL,
        eski_fiyat  REAL,
        yeni_fiyat  REAL,
        tarih       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        degistiren  TEXT
      )
    """);

    // Urunler ekstralar
    await _calistir(db,
        'ALTER TABLE urunler ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0');
    await _calistir(db, 'ALTER TABLE urunler ADD COLUMN global_id TEXT');
    await _calistir(db, 'ALTER TABLE urunler ADD COLUMN last_updated DATETIME');
    await _calistir(db,
        "UPDATE urunler SET last_updated = datetime('now') WHERE last_updated IS NULL");
    await _calistir(db, 'ALTER TABLE urunler ADD COLUMN deleted_at DATETIME');
    await _calistir(db, 'ALTER TABLE urunler ADD COLUMN cihaz_id TEXT');
    await _calistir(
        db, 'ALTER TABLE urunler ADD COLUMN zaman_fiyat_id INTEGER');

    // Satislar ekstralar
    await _calistir(
        db, 'ALTER TABLE satislar ADD COLUMN last_updated DATETIME');
    await _calistir(db,
        "UPDATE satislar SET last_updated = datetime('now') WHERE last_updated IS NULL");
    await _calistir(db, 'ALTER TABLE satislar ADD COLUMN deleted_at DATETIME');
    await _calistir(db, 'ALTER TABLE satislar ADD COLUMN cihaz_id TEXT');
    await _calistir(db, 'ALTER TABLE satislar ADD COLUMN sube_id INTEGER');
    await _calistir(db,
        'ALTER TABLE satislar ADD COLUMN kargo_ucreti REAL NOT NULL DEFAULT 0');

    // Satis kalem ekstralar
    await _calistir(db, 'ALTER TABLE satis_kalem ADD COLUMN global_id TEXT');
    await _calistir(db, 'ALTER TABLE satis_kalem ADD COLUMN cihaz_id TEXT');
    await _calistir(
        db, 'ALTER TABLE satis_kalem ADD COLUMN last_updated DATETIME');

    // Cari ekstralar
    await _calistir(db, 'ALTER TABLE cari ADD COLUMN last_updated DATETIME');
    await _calistir(db,
        "UPDATE cari SET last_updated = datetime('now') WHERE last_updated IS NULL");
    await _calistir(db,
        'ALTER TABLE cari ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0');
    await _calistir(db, 'ALTER TABLE cari ADD COLUMN deleted_at DATETIME');
    await _calistir(db, 'ALTER TABLE cari ADD COLUMN cihaz_id TEXT');
    await _calistir(db, 'ALTER TABLE cari ADD COLUMN telefon2 TEXT');
    await _calistir(db, 'ALTER TABLE cari ADD COLUMN email2 TEXT');
    await _calistir(db, 'ALTER TABLE cari ADD COLUMN ana_grup TEXT');
    await _calistir(db, 'ALTER TABLE cari ADD COLUMN alt_grup TEXT');
    await _calistir(db, 'ALTER TABLE cari ADD COLUMN temsilci TEXT');
    await _calistir(db, 'ALTER TABLE cari ADD COLUMN web_sitesi TEXT');
    await _calistir(db, 'ALTER TABLE cari ADD COLUMN guncelleyen TEXT');
    await _calistir(db, 'ALTER TABLE cari ADD COLUMN sube_id INTEGER');

    // Cari hareket ekstralar
    await _calistir(
        db, 'ALTER TABLE cari_hareket ADD COLUMN last_updated DATETIME');
    await _calistir(db, 'ALTER TABLE cari_hareket ADD COLUMN cihaz_id TEXT');
    await _calistir(db,
        'ALTER TABLE cari_hareket ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0');

    // Stok hareket ekstralar
    await _calistir(db, 'ALTER TABLE stok_hareket ADD COLUMN global_id TEXT');
    await _calistir(db, 'ALTER TABLE stok_hareket ADD COLUMN cihaz_id TEXT');

    // Kasa hareketleri ekstralar
    await _calistir(
        db, 'ALTER TABLE kasa_hareketleri ADD COLUMN last_updated DATETIME');
    await _calistir(
        db, 'ALTER TABLE kasa_hareketleri ADD COLUMN deleted_at DATETIME');
    await _calistir(
        db, 'ALTER TABLE kasa_hareketleri ADD COLUMN bakiye_sonrasi REAL');

    // Giderler ekstralar
    await _calistir(
        db, 'ALTER TABLE giderler ADD COLUMN last_updated DATETIME');
    await _calistir(db, 'ALTER TABLE giderler ADD COLUMN deleted_at DATETIME');

    // Faturalar ekstralar
    await _calistir(
        db, 'ALTER TABLE faturalar ADD COLUMN last_updated DATETIME');
    await _calistir(db, 'ALTER TABLE faturalar ADD COLUMN deleted_at DATETIME');
    await _calistir(db, 'ALTER TABLE faturalar ADD COLUMN global_id TEXT');
    await _calistir(
        db, 'ALTER TABLE faturalar ADD COLUMN duzenlenme_tarihi TEXT');
    await _calistir(db, 'ALTER TABLE faturalar ADD COLUMN sevk_tarihi TEXT');
    await _calistir(db, 'ALTER TABLE faturalar ADD COLUMN vade_tarihi TEXT');
    await _calistir(db, 'ALTER TABLE faturalar ADD COLUMN malin_nereye TEXT');
    await _calistir(db, 'ALTER TABLE faturalar ADD COLUMN teslim_eden TEXT');
    await _calistir(db, 'ALTER TABLE faturalar ADD COLUMN teslim_alan TEXT');
    await _calistir(db,
        'ALTER TABLE faturalar ADD COLUMN toplam_ara_toplam REAL DEFAULT 0');
    await _calistir(
        db, 'ALTER TABLE faturalar ADD COLUMN toplam_iskonto REAL DEFAULT 0');
    await _calistir(
        db, 'ALTER TABLE faturalar ADD COLUMN toplam_kdv REAL DEFAULT 0');
    await _calistir(
        db, 'ALTER TABLE faturalar ADD COLUMN genel_toplam REAL DEFAULT 0');
    await _calistir(
        db, 'ALTER TABLE faturalar ADD COLUMN odenen_tutar REAL DEFAULT 0');
    await _calistir(
        db, 'ALTER TABLE faturalar ADD COLUMN kalan_tutar REAL DEFAULT 0');
    await _calistir(db,
        'ALTER TABLE faturalar ADD COLUMN odeme_durumu TEXT DEFAULT "beklemede"');
    await _calistir(db, 'ALTER TABLE faturalar ADD COLUMN html_icerik TEXT');
    await _calistir(db, 'ALTER TABLE faturalar ADD COLUMN xml_icerik TEXT');
    await _calistir(
        db, 'ALTER TABLE faturalar ADD COLUMN durum TEXT DEFAULT "aktif"');
    await _calistir(db,
        'ALTER TABLE faturalar ADD COLUMN created_at TEXT DEFAULT CURRENT_TIMESTAMP');
    await _calistir(db,
        'ALTER TABLE faturalar ADD COLUMN updated_at TEXT DEFAULT CURRENT_TIMESTAMP');

    // Fatura detaylari ekstralar
    await _calistir(
        db, 'ALTER TABLE fatura_detaylari ADD COLUMN last_updated DATETIME');
    await _calistir(
        db, 'ALTER TABLE fatura_detaylari ADD COLUMN cihaz_id TEXT');

    // Iade ekstralar
    await _calistir(db, 'ALTER TABLE iade ADD COLUMN last_updated DATETIME');
    await _calistir(db, 'ALTER TABLE iade ADD COLUMN deleted_at DATETIME');
    await _calistir(db, 'ALTER TABLE iade ADD COLUMN cihaz_id TEXT');

    // Irsaliyeler ekstralar
    await _calistir(
        db, 'ALTER TABLE irsaliyeler ADD COLUMN deleted_at DATETIME');
    await _calistir(db, 'ALTER TABLE irsaliyeler ADD COLUMN global_id TEXT');

    // Promosyonlar ekstralar
    await _calistir(
        db, 'ALTER TABLE promosyonlar ADD COLUMN last_updated DATETIME');
    await _calistir(
        db, 'ALTER TABLE promosyonlar ADD COLUMN deleted_at DATETIME');

    // Tedarikci siparisler ekstralar
    await _calistir(db,
        'ALTER TABLE tedarikci_siparisler ADD COLUMN last_updated DATETIME');
    await _calistir(db,
        'ALTER TABLE tedarikci_siparisler ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0');
    await _calistir(db,
        'ALTER TABLE tedarikci_siparis_kalem ADD COLUMN last_updated DATETIME');

    // Lot seri ekstralar
    await _calistir(
        db, 'ALTER TABLE lot_seri ADD COLUMN last_updated DATETIME');
    await _calistir(db, 'ALTER TABLE lot_seri ADD COLUMN cihaz_id TEXT');

    // Vardiyalar ekstralar
    await _calistir(
        db, 'ALTER TABLE vardiyalar ADD COLUMN last_updated DATETIME');

    // Musteri puan ekstralar
    await _calistir(
        db, 'ALTER TABLE musteri_puan ADD COLUMN last_updated DATETIME');
    await _calistir(
        db, 'ALTER TABLE puan_hareket ADD COLUMN last_updated DATETIME');

    // Personel ekstralar
    await _calistir(
        db, 'ALTER TABLE personel ADD COLUMN last_updated DATETIME');
    await _calistir(db,
        'ALTER TABLE personel ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0');
    await _calistir(db, 'ALTER TABLE personel ADD COLUMN kullanici_id INTEGER');
    await _calistir(db, 'ALTER TABLE personel ADD COLUMN tc_kimlik TEXT');
    await _calistir(db, 'ALTER TABLE personel ADD COLUMN pozisyon TEXT');
    await _calistir(db, 'ALTER TABLE personel ADD COLUMN isten_cikis DATE');
    await _calistir(db, 'ALTER TABLE personel ADD COLUMN notlar TEXT');

    // Kullanicilar ekstralar
    await _calistir(db,
        'ALTER TABLE kullanicilar ADD COLUMN plu INTEGER NOT NULL DEFAULT 0');
    await _calistir(db,
        'ALTER TABLE kullanicilar ADD COLUMN plu_kart_boyut INTEGER NOT NULL DEFAULT 2');
    await _calistir(
        db, 'ALTER TABLE kullanicilar ADD COLUMN last_updated DATETIME');
    await _calistir(db,
        "UPDATE kullanicilar SET last_updated = datetime('now') WHERE last_updated IS NULL");

    // Yeni tablolar
    await _calistir(db, """
      CREATE TABLE IF NOT EXISTS fiyat_gecmis (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        urun_id INTEGER NOT NULL, eski_alis REAL, yeni_alis REAL,
        eski_satis REAL, yeni_satis REAL, degistiren TEXT,
        tarih DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY(urun_id) REFERENCES urunler(id) ON DELETE CASCADE
      )
    """);

    await _calistir(db, """
      CREATE TABLE IF NOT EXISTS zaman_fiyat (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        urun_id INTEGER NOT NULL REFERENCES urunler(id) ON DELETE CASCADE,
        gun_listesi TEXT NOT NULL DEFAULT '1,2,3,4,5,6,7',
        baslangic_saat TEXT NOT NULL DEFAULT '00:00',
        bitis_saat TEXT NOT NULL DEFAULT '23:59',
        fiyat_turu TEXT NOT NULL DEFAULT 'sabit',
        deger REAL NOT NULL, aktif INTEGER NOT NULL DEFAULT 1,
        aciklama TEXT, olusturma DATETIME, guncelleme DATETIME
      )
    """);

    await _calistir(db, """
      CREATE TABLE IF NOT EXISTS cari_adres (
        id INTEGER PRIMARY KEY AUTOINCREMENT, global_id TEXT UNIQUE,
        cari_id INTEGER NOT NULL, adres_tipi TEXT NOT NULL DEFAULT 'Fatura',
        adres TEXT NOT NULL, il TEXT, ilce TEXT, posta_kodu TEXT,
        varsayilan INTEGER NOT NULL DEFAULT 0, last_updated DATETIME,
        FOREIGN KEY(cari_id) REFERENCES cari(id) ON DELETE CASCADE
      )
    """);

    await _calistir(db, """
      CREATE TABLE IF NOT EXISTS promosyon_tanim (
        id INTEGER PRIMARY KEY AUTOINCREMENT, global_id TEXT,
        ad TEXT NOT NULL, aciklama TEXT, tip TEXT NOT NULL DEFAULT 'iskonto',
        baslangic DATETIME, bitis DATETIME,
        aktif INTEGER NOT NULL DEFAULT 1, oncelik INTEGER NOT NULL DEFAULT 0,
        created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    """);

    await _calistir(db, """
      CREATE TABLE IF NOT EXISTS promosyon_kosul (
        id INTEGER PRIMARY KEY AUTOINCREMENT, tanim_id INTEGER NOT NULL,
        kosul_tipi TEXT NOT NULL, kosul_degeri TEXT NOT NULL,
        FOREIGN KEY(tanim_id) REFERENCES promosyon_tanim(id) ON DELETE CASCADE
      )
    """);

    await _calistir(db, """
      CREATE TABLE IF NOT EXISTS promosyon_aksiyon (
        id INTEGER PRIMARY KEY AUTOINCREMENT, tanim_id INTEGER NOT NULL,
        aksiyon_tipi TEXT NOT NULL, aksiyon_degeri TEXT NOT NULL,
        FOREIGN KEY(tanim_id) REFERENCES promosyon_tanim(id) ON DELETE CASCADE
      )
    """);

    await _calistir(db, """
      CREATE TABLE IF NOT EXISTS sube_urun (
        urun_id INTEGER NOT NULL, sube_id INTEGER NOT NULL,
        stok REAL NOT NULL DEFAULT 0, rezerve_stok REAL NOT NULL DEFAULT 0,
        kritik_stok REAL DEFAULT 0, satis_fiyati REAL, raf_kodu TEXT,
        son_guncelleme DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (urun_id, sube_id)
      )
    """);

    await _calistir(db, """
      CREATE TABLE IF NOT EXISTS rol_yetkileri (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        rol TEXT NOT NULL, yetki_kodu TEXT NOT NULL,
        UNIQUE(rol, yetki_kodu)
      )
    """);

    // Indexler
    await _calistir(
        db, 'CREATE INDEX IF NOT EXISTS idx_urunler_barkod ON urunler(barkod)');
    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_urunler_updated ON urunler(last_updated)');
    await _calistir(
        db, 'CREATE INDEX IF NOT EXISTS idx_satislar_tarih ON satislar(tarih)');
    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_satislar_cari ON satislar(cari_id)');
    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_satislar_deleted ON satislar(is_deleted, tarih)');
    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_satis_kalem_satis ON satis_kalem(satis_id)');
    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_satis_kalem_urun ON satis_kalem(urun_id)');
    await _calistir(
        db, 'CREATE INDEX IF NOT EXISTS idx_cari_unvan ON cari(unvan)');
    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_carih_cari ON cari_hareket(cari_id)');
    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_stokh_urun ON stok_hareket(urun_id)');
    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_stokh_tarih ON stok_hareket(tarih)');
    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_kasa_tarih ON kasa_hareketleri(tarih)');
    await _calistir(
        db, 'CREATE INDEX IF NOT EXISTS idx_gider_tarih ON giderler(tarih)');
    await _calistir(
        db, 'CREATE INDEX IF NOT EXISTS idx_fatura_cari ON faturalar(cari_id)');
    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_promo_urun ON promosyonlar(urun_id, aktif)');
    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_zaman_fiyat_urun ON zaman_fiyat(urun_id, aktif)');
    await _calistir(
        db, 'CREATE INDEX IF NOT EXISTS idx_sync_durum ON sync_queue(durum)');

    // Triggerlar
    await _calistir(db, """CREATE TRIGGER IF NOT EXISTS trg_urun_fiyat_gecmis
      AFTER UPDATE OF alis_fiyat, satis_fiyati ON urunler BEGIN
      INSERT INTO fiyat_gecmis(urun_id, eski_alis, yeni_alis, eski_satis, yeni_satis)
      SELECT NEW.id, OLD.alis_fiyat, NEW.alis_fiyat, OLD.satis_fiyati, NEW.satis_fiyati
      WHERE OLD.alis_fiyat != NEW.alis_fiyat OR OLD.satis_fiyati != NEW.satis_fiyati; END""");

    await _calistir(db, """CREATE TRIGGER IF NOT EXISTS trg_urun_updated
      AFTER UPDATE ON urunler BEGIN
      UPDATE urunler SET last_updated = datetime('now') WHERE id = NEW.id; END""");

    await _calistir(db, """CREATE TRIGGER IF NOT EXISTS trg_cari_bakiye_ins
      AFTER INSERT ON cari_hareket BEGIN
      UPDATE cari SET bakiye = (
        SELECT COALESCE(SUM(borc - alacak), 0) FROM cari_hareket WHERE cari_id = NEW.cari_id
      ) WHERE id = NEW.cari_id; END""");

    await _calistir(db, """CREATE TRIGGER IF NOT EXISTS trg_soft_delete_satis
      AFTER UPDATE OF is_deleted ON satislar BEGIN
      UPDATE satislar SET deleted_at = CASE WHEN NEW.is_deleted=1 THEN datetime('now') ELSE NULL END
      WHERE id = NEW.id; END""");
  }

  // ==================== v7 -> v8 (İade Faturası) ====================
  static Future<void> _v7denV8e(Database db) async {
    await _calistir(db, 'ALTER TABLE faturalar ADD COLUMN iade_id INTEGER');
    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_faturalar_iade ON faturalar(iade_id)');
  }

  // ==================== v8 -> v9 (Masa/Restoran) ====================
  static Future<void> _v8denV9a(Database db) async {
    await MasaSemasi.olustur(db);
  }

  // ==================== v9 -> v10 (PLU) ====================
  static Future<void> _v9denV10a(Database db) async {
    await _calistir(
        db, 'ALTER TABLE urunler ADD COLUMN plu INTEGER NOT NULL DEFAULT 0');
    await _calistir(db,
        'ALTER TABLE urunler ADD COLUMN plu_kart_boyut INTEGER NOT NULL DEFAULT 2');
  }

  // ==================== v10 -> v11 (Rezervasyon + Garson Çağrı) ====================
  static Future<void> _v10denV11e(Database db) async {
    await _calistir(db, """
      CREATE TABLE IF NOT EXISTS masa_rezervasyon (
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
        FOREIGN KEY(masa_id) REFERENCES masalar(id) ON DELETE CASCADE
      )
    """);

    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_rezervasyon_tarih ON masa_rezervasyon(tarih, saat)');
    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_rezervasyon_masa ON masa_rezervasyon(masa_id, durum)');
    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_rezervasyon_musteri ON masa_rezervasyon(musteri_adi)');

    await _calistir(
        db, 'ALTER TABLE masa_siparisleri ADD COLUMN garson_id INTEGER');
    await _calistir(
        db, 'ALTER TABLE masa_siparisleri ADD COLUMN garson_adi TEXT');

    await _calistir(db, """
      CREATE TABLE IF NOT EXISTS garson_cagri_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        masa_id INTEGER NOT NULL,
        masa_adi TEXT,
        cagri_zamani DATETIME DEFAULT CURRENT_TIMESTAMP,
        yanit_zamani DATETIME,
        yanitlayan_id INTEGER,
        durum TEXT DEFAULT 'beklemede',
        FOREIGN KEY(masa_id) REFERENCES masalar(id)
      )
    """);

    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_garson_cagri_durum ON garson_cagri_log(durum)');
  }

  // ==================== v11 -> v12 (Masa rapor indexleri) ====================
  static Future<void> _v11denV12e(Database db) async {
    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_masa_siparis_durum_acilis ON masa_siparisleri(durum, acilis_zamani)');
    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_masa_kalem_durum ON masa_siparis_kalem(durum)');
    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_masa_siparis_kapanis ON masa_siparisleri(kapanis_zamani)');
    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_rezervasyon_durum_saat ON masa_rezervasyon(durum, saat)');
  }

  // ==================== v12 -> v13 (Masa Detay + Adisyon log) ====================
  static Future<void> _v12denV13e(Database db) async {
    await _calistir(db, """
      CREATE TABLE IF NOT EXISTS adisyon_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        siparis_id INTEGER NOT NULL,
        adisyon_no TEXT NOT NULL,
        yazdiran_kullanici_id INTEGER,
        yazdirma_zamani DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        printer_turu TEXT DEFAULT 'termal',
        FOREIGN KEY(siparis_id) REFERENCES masa_siparisleri(id) ON DELETE CASCADE
      )
    """);

    await _calistir(db, """
      CREATE TABLE IF NOT EXISTS masa_hareket_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        kaynak_masa_id INTEGER,
        hedef_masa_id INTEGER,
        islem_tipi TEXT NOT NULL,
        siparis_id INTEGER,
        yapan_kullanici_id INTEGER,
        islem_zamani DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY(kaynak_masa_id) REFERENCES masalar(id),
        FOREIGN KEY(hedef_masa_id) REFERENCES masalar(id)
      )
    """);

    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_adisyon_siparis ON adisyon_log(siparis_id)');
    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_masa_hareket_zamani ON masa_hareket_log(islem_zamani)');

    // Masa tablosuna eksik sütunları ekle
    await _calistir(db,
        'ALTER TABLE masalar ADD COLUMN kategori TEXT NOT NULL DEFAULT "Salon"');
    await _calistir(db,
        'ALTER TABLE masalar ADD COLUMN kapasite INTEGER NOT NULL DEFAULT 4');
    await _calistir(
        db, 'ALTER TABLE masalar ADD COLUMN sira INTEGER NOT NULL DEFAULT 0');
  }

  //  YENİ: v13 -> v14 (Tüm eksik sütunlar)
  static Future<void> _v13denV14e(Database db) async {
    // ==================== URUNLER EKSİK SÜTUNLAR ====================
    await _calistir(
        db, 'ALTER TABLE urunler ADD COLUMN kod TEXT UNIQUE COLLATE NOCASE');
    await _calistir(db, 'ALTER TABLE urunler ADD COLUMN barkodlar TEXT');
    await _calistir(db,
        'ALTER TABLE urunler ADD COLUMN alternatif_urun_adi TEXT COLLATE NOCASE');
    await _calistir(db,
        'ALTER TABLE urunler ADD COLUMN toplam_maliyet REAL NOT NULL DEFAULT 0');
    await _calistir(db,
        'ALTER TABLE urunler ADD COLUMN toplam_stok REAL NOT NULL DEFAULT 0');
    await _calistir(db,
        'ALTER TABLE urunler ADD COLUMN alis_kdv_oran REAL NOT NULL DEFAULT 18');
    await _calistir(
        db, 'ALTER TABLE urunler ADD COLUMN ana_grup TEXT COLLATE NOCASE');
    await _calistir(
        db, 'ALTER TABLE urunler ADD COLUMN alt_grup TEXT COLLATE NOCASE');
    await _calistir(
        db, 'ALTER TABLE urunler ADD COLUMN marka TEXT COLLATE NOCASE');
    await _calistir(db, 'ALTER TABLE urunler ADD COLUMN resim_yolu TEXT');
    await _calistir(db,
        'ALTER TABLE urunler ADD COLUMN para_birimi TEXT NOT NULL DEFAULT "TRY"');
    await _calistir(db,
        'ALTER TABLE urunler ADD COLUMN guncelleme_tarihi DATETIME DEFAULT CURRENT_TIMESTAMP');
    await _calistir(db,
        'ALTER TABLE urunler ADD COLUMN kayit_tarihi DATETIME DEFAULT CURRENT_TIMESTAMP');
    await _calistir(db,
        'ALTER TABLE urunler ADD COLUMN seri_no_takibi INTEGER NOT NULL DEFAULT 0');
    await _calistir(db,
        'ALTER TABLE urunler ADD COLUMN lot_takibi INTEGER NOT NULL DEFAULT 0');
    await _calistir(db, 'ALTER TABLE urunler ADD COLUMN lot_no TEXT');
    await _calistir(
        db, 'ALTER TABLE urunler ADD COLUMN son_kullanma_tarihi DATE');
    await _calistir(db, 'ALTER TABLE urunler ADD COLUMN alan1 TEXT');
    await _calistir(db, 'ALTER TABLE urunler ADD COLUMN alan2 TEXT');
    await _calistir(db, 'ALTER TABLE urunler ADD COLUMN alan3 TEXT');
    await _calistir(db, 'ALTER TABLE urunler ADD COLUMN alan4 TEXT');
    await _calistir(db,
        'ALTER TABLE urunler ADD COLUMN otomatik_indirim INTEGER NOT NULL DEFAULT 0');
    await _calistir(db,
        'ALTER TABLE urunler ADD COLUMN son_alim_indirim_oran REAL NOT NULL DEFAULT 0');
    await _calistir(db,
        'ALTER TABLE urunler ADD COLUMN minimum_stok REAL NOT NULL DEFAULT 0');
    await _calistir(db,
        'ALTER TABLE urunler ADD COLUMN maksimum_stok REAL NOT NULL DEFAULT 0');
    await _calistir(db,
        'ALTER TABLE urunler ADD COLUMN maksimum_satir_miktari REAL NOT NULL DEFAULT 0');
    await _calistir(db, 'ALTER TABLE urunler ADD COLUMN renk TEXT');
    await _calistir(db, 'ALTER TABLE urunler ADD COLUMN beden TEXT');
    await _calistir(db, 'ALTER TABLE urunler ADD COLUMN sube TEXT');
    await _calistir(
        db, 'ALTER TABLE urunler ADD COLUMN uretici TEXT COLLATE NOCASE');
    await _calistir(db, 'ALTER TABLE urunler ADD COLUMN model TEXT');
    await _calistir(db, 'ALTER TABLE urunler ADD COLUMN grup_sorumlusu TEXT');
    await _calistir(db, 'ALTER TABLE urunler ADD COLUMN mensei TEXT');
    await _calistir(db, 'ALTER TABLE urunler ADD COLUMN raf_numarasi TEXT');
    await _calistir(db, 'ALTER TABLE urunler ADD COLUMN raf_omru INTEGER');
    await _calistir(db, 'ALTER TABLE urunler ADD COLUMN plu_numarasi TEXT');
    await _calistir(db,
        'ALTER TABLE urunler ADD COLUMN puan_orani REAL NOT NULL DEFAULT 0');
    await _calistir(db, 'ALTER TABLE urunler ADD COLUMN muhasebe_kodu TEXT');
    await _calistir(db, 'ALTER TABLE urunler ADD COLUMN muafiyet_kodu TEXT');
    await _calistir(db,
        'ALTER TABLE urunler ADD COLUMN resmi_bakiye REAL NOT NULL DEFAULT 0');
    await _calistir(
        db, 'ALTER TABLE urunler ADD COLUMN hacim REAL NOT NULL DEFAULT 0');
    await _calistir(db,
        'ALTER TABLE urunler ADD COLUMN evrak_kontrol_aktif INTEGER NOT NULL DEFAULT 0');
    await _calistir(db, 'ALTER TABLE urunler ADD COLUMN lot_aciklama TEXT');
    await _calistir(db,
        'ALTER TABLE urunler ADD COLUMN recete_katsayi REAL NOT NULL DEFAULT 1');

    // ==================== INDEXLER ====================
    await _calistir(
        db, 'CREATE INDEX IF NOT EXISTS idx_urunler_kod ON urunler(kod)');
    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_urunler_ana_grup ON urunler(ana_grup)');
    await _calistir(
        db, 'CREATE INDEX IF NOT EXISTS idx_urunler_marka ON urunler(marka)');

    // ==================== EKSİK GLOBAL ID'LER ====================
    await _calistir(db, 'ALTER TABLE iade_kalem ADD COLUMN global_id TEXT');
    await _calistir(db, 'ALTER TABLE irsaliye_kalem ADD COLUMN global_id TEXT');
    await _calistir(
        db, 'ALTER TABLE promosyon_kosul ADD COLUMN global_id TEXT');
    await _calistir(
        db, 'ALTER TABLE promosyon_aksiyon ADD COLUMN global_id TEXT');
    await _calistir(
        db, 'ALTER TABLE garson_cagri_log ADD COLUMN global_id TEXT');
    await _calistir(db, 'ALTER TABLE adisyon_log ADD COLUMN global_id TEXT');
    await _calistir(
        db, 'ALTER TABLE masa_hareket_log ADD COLUMN global_id TEXT');
    await _calistir(
        db, 'ALTER TABLE bildirim_tercihleri ADD COLUMN global_id TEXT');
    await _calistir(db, 'ALTER TABLE favori_urunler ADD COLUMN global_id TEXT');
    await _calistir(db, 'ALTER TABLE gecici_sayim ADD COLUMN global_id TEXT');
    await _calistir(db, 'ALTER TABLE stok_fifo ADD COLUMN global_id TEXT');
    await _calistir(
        db, 'ALTER TABLE sube_fiyat_gecmis ADD COLUMN global_id TEXT');
    await _calistir(db, 'ALTER TABLE fiyat_gecmis ADD COLUMN global_id TEXT');
    await _calistir(db, 'ALTER TABLE zaman_fiyat ADD COLUMN global_id TEXT');
    await _calistir(db, 'ALTER TABLE rol_yetkileri ADD COLUMN global_id TEXT');
    await _calistir(db, 'ALTER TABLE efatura_log ADD COLUMN global_id TEXT');

    // Global ID index'leri
    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_iade_kalem_global ON iade_kalem(global_id)');
    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_irsaliye_kalem_global ON irsaliye_kalem(global_id)');
    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_promosyon_kosul_global ON promosyon_kosul(global_id)');
    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_promosyon_aksiyon_global ON promosyon_aksiyon(global_id)');
    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_garson_cagri_global ON garson_cagri_log(global_id)');
    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_adisyon_log_global ON adisyon_log(global_id)');
    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_masa_hareket_global ON masa_hareket_log(global_id)');
  }

  //  YENİ: v14 -> v15
  static Future<void> _v14denV15e(Database db) async {
    await _calistir(db, 'ALTER TABLE cari_hareket ADD COLUMN global_id TEXT');
    await _calistir(db, 'ALTER TABLE puan_hareket ADD COLUMN global_id TEXT');
    await _calistir(db, 'ALTER TABLE sube_urun ADD COLUMN global_id TEXT');
    await _calistir(
        db, 'ALTER TABLE tedarikci_siparis_kalem ADD COLUMN global_id TEXT');

    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_cari_hareket_global ON cari_hareket(global_id)');
    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_puan_hareket_global ON puan_hareket(global_id)');
  }

  //  YENİ: v15 -> v16 (Borc Takip)
  static Future<void> _v15denV16ya(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS borclar (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        global_id TEXT UNIQUE,
        baslik TEXT NOT NULL,
        tur TEXT NOT NULL,
        alt_tur TEXT,
        tutar REAL NOT NULL,
        odenen_tutar REAL NOT NULL DEFAULT 0,
        kesim_tarihi TEXT NOT NULL,
        son_odeme_tarihi TEXT NOT NULL,
        odeme_tarihi TEXT,
        taksit_sayisi INTEGER NOT NULL DEFAULT 1,
        odenen_taksit INTEGER NOT NULL DEFAULT 0,
        aciklama TEXT,
        dosya_no TEXT,
        referans_no TEXT,
        odendi INTEGER NOT NULL DEFAULT 0,
        hatirlatma_gonderildi INTEGER NOT NULL DEFAULT 0,
        oncelik INTEGER NOT NULL DEFAULT 2,
        notlar TEXT,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_borc_tarih ON borclar(son_odeme_tarihi)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_borc_tur ON borclar(tur)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_borc_durum ON borclar(odendi)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_borc_son_odeme ON borclar(son_odeme_tarihi, odendi)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_borc_global ON borclar(global_id)');
  }

  // ==================== v16 -> v17 (Banka, Kredi Kartı, Mail) ====================
  static Future<void> _v16denV17ye(Database db) async {
    await _calistir(db, '''
      CREATE TABLE IF NOT EXISTS bankalar (
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

    await _calistir(db, '''
      CREATE TABLE IF NOT EXISTS banka_hesaplar (
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
        FOREIGN KEY(banka_id) REFERENCES bankalar(id)
      )
    ''');

    await _calistir(db, '''
      CREATE TABLE IF NOT EXISTS kredi_kartlari (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        global_id TEXT UNIQUE,
        banka_id INTEGER NOT NULL,
        kart_adi TEXT NOT NULL,
        kart_no TEXT NOT NULL,
        son_kullanma TEXT,
        cvc TEXT,
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
        FOREIGN KEY(banka_id) REFERENCES bankalar(id)
      )
    ''');

    await _calistir(db, '''
      CREATE TABLE IF NOT EXISTS banka_hareketler (
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
        FOREIGN KEY(banka_hesap_id) REFERENCES banka_hesaplar(id),
        FOREIGN KEY(kredi_karti_id) REFERENCES kredi_kartlari(id)
      )
    ''');

    await _calistir(db, '''
      CREATE TABLE IF NOT EXISTS borc_odemeler (
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
        FOREIGN KEY(borc_id) REFERENCES borclar(id),
        FOREIGN KEY(banka_hesap_id) REFERENCES banka_hesaplar(id),
        FOREIGN KEY(kredi_karti_id) REFERENCES kredi_kartlari(id)
      )
    ''');

    await _calistir(
        db, 'CREATE INDEX IF NOT EXISTS idx_banka_aktif ON bankalar(aktif)');
    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_banka_hesap_banka ON banka_hesaplar(banka_id)');
    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_banka_hesap_aktif ON banka_hesaplar(aktif)');
    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_kredi_karti_banka ON kredi_kartlari(banka_id)');
    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_kredi_karti_aktif ON kredi_kartlari(aktif)');
    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_banka_hareket_hesap ON banka_hareketler(banka_hesap_id)');
    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_banka_hareket_tarih ON banka_hareketler(tarih)');
    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_banka_hareket_kart ON banka_hareketler(kredi_karti_id)');
    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_borc_odeme_borc ON borc_odemeler(borc_id)');
    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_borc_odeme_tarih ON borc_odemeler(tarih)');

    await _calistir(
        db, 'ALTER TABLE bankalar ADD COLUMN aktif INTEGER NOT NULL DEFAULT 1');
    await _calistir(db,
        'ALTER TABLE banka_hesaplar ADD COLUMN aktif INTEGER NOT NULL DEFAULT 1');
    await _calistir(db,
        'ALTER TABLE kredi_kartlari ADD COLUMN aktif INTEGER NOT NULL DEFAULT 1');
  }

  // ==================== v17 -> v18 (düzeltme) ====================
  static Future<void> _v17denV18e(Database db) async {
    await _calistir(db, 'DROP TRIGGER IF EXISTS trg_banka_hareket_bakiye');
    await _calistir(db, 'DROP TRIGGER IF EXISTS trg_kredi_karti_limit');

    await _calistir(db, '''
      CREATE TRIGGER IF NOT EXISTS trg_kredi_karti_limit
      AFTER INSERT ON kredi_kartlari
      WHEN NEW.kartlimit > 0
      BEGIN
        UPDATE kredi_kartlari
        SET kalan_limit = NEW.kartlimit - NEW.kullanilan_limit
        WHERE id = NEW.id;
      END
    ''');

    await _calistir(db, '''
      CREATE TRIGGER IF NOT EXISTS trg_kredi_karti_limit_upd
      AFTER UPDATE OF kartlimit, kullanilan_limit ON kredi_kartlari
      BEGIN
        UPDATE kredi_kartlari
        SET kalan_limit = NEW.kartlimit - NEW.kullanilan_limit
        WHERE id = NEW.id;
      END
    ''');
  }

  // ==================== v18 -> v19 (Eksik Banka/Kredi Kartı tabloları) ====================
  static Future<void> _v18denV19a(Database db) async {
    // Banka tabloları (zaten varsa atla)
    await _calistir(db, '''
    CREATE TABLE IF NOT EXISTS bankalar (
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

    await _calistir(db, '''
    CREATE TABLE IF NOT EXISTS banka_hesaplar (
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
      FOREIGN KEY(banka_id) REFERENCES bankalar(id)
    )
  ''');

    await _calistir(db, '''
    CREATE TABLE IF NOT EXISTS kredi_kartlari (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      global_id TEXT UNIQUE,
      banka_id INTEGER NOT NULL,
      kart_adi TEXT NOT NULL,
      kart_no TEXT NOT NULL,
      son_kullanma TEXT,
      cvc TEXT,
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
      FOREIGN KEY(banka_id) REFERENCES bankalar(id)
    )
  ''');

    await _calistir(db, '''
    CREATE TABLE IF NOT EXISTS banka_hareketler (
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
      FOREIGN KEY(banka_hesap_id) REFERENCES banka_hesaplar(id),
      FOREIGN KEY(kredi_karti_id) REFERENCES kredi_kartlari(id)
    )
  ''');

    await _calistir(db, '''
    CREATE TABLE IF NOT EXISTS borc_odemeler (
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
      FOREIGN KEY(borc_id) REFERENCES borclar(id),
      FOREIGN KEY(banka_hesap_id) REFERENCES banka_hesaplar(id),
      FOREIGN KEY(kredi_karti_id) REFERENCES kredi_kartlari(id)
    )
  ''');

    // Indexler (zaten varsa atla)
    await _calistir(
        db, 'CREATE INDEX IF NOT EXISTS idx_banka_aktif ON bankalar(aktif)');
    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_banka_hesap_banka ON banka_hesaplar(banka_id)');
    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_kredi_karti_banka ON kredi_kartlari(banka_id)');
    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_banka_hareket_hesap ON banka_hareketler(banka_hesap_id)');
    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_banka_hareket_tarih ON banka_hareketler(tarih)');
    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_borc_odeme_borc ON borc_odemeler(borc_id)');
  }

  // ==================== YARDIMCI METOD ====================
  // ==================== GÜVENLİK: v19 -> v20 ====================
  // Kredi kartı numarası artık düz metin değil, maskelenmiş (son 4 hane)
  // saklanıyor; CVC hiçbir zaman saklanmamalı — mevcut kayıtlar temizlenir.
  static Future<void> _v19denV20ye(Database db) async {
    // 1) Yeni maskeli kolon ekle (varsa atla)
    await _calistir(db,
        "ALTER TABLE kredi_kartlari ADD COLUMN kart_no_maskeli TEXT NOT NULL DEFAULT ''");

    // 2) Mevcut kart_no varsa, son 4 haneyi maskeli kolona taşı
    try {
      final kartlar = await db.query('kredi_kartlari');
      for (final k in kartlar) {
        final eskiNo = (k['kart_no'] as String?) ?? '';
        final temiz = eskiNo.replaceAll(RegExp(r'\s'), '');
        final son4 =
            temiz.length >= 4 ? temiz.substring(temiz.length - 4) : temiz;
        final maskeli =
            son4.isEmpty ? '**** **** **** ????' : '**** **** **** $son4';
        await db.update('kredi_kartlari', {'kart_no_maskeli': maskeli},
            where: 'id = ?', whereArgs: [k['id']]);
      }
    } catch (_) {
      // kart_no kolonu zaten yoksa (temiz kurulum) sorun değil
    }

    // 3) CVC ve düz metin kart numarasını KALICI olarak temizle.
    // (SQLite eski sürümlerde DROP COLUMN desteklemeyebilir, bu yüzden
    // kolonları silmek yerine içeriklerini boşaltıyoruz — en kritik olan
    // hassas verinin diskte kalmaması.)
    await _calistir(db, "UPDATE kredi_kartlari SET cvc = NULL");
    await _calistir(db, "UPDATE kredi_kartlari SET kart_no = '****'");
    // Modern SQLite (3.35+) DROP COLUMN destekler; desteklemiyorsa sessizce atlanır.
    await _calistir(db, "ALTER TABLE kredi_kartlari DROP COLUMN cvc");
    await _calistir(db, "ALTER TABLE kredi_kartlari DROP COLUMN kart_no");
  }

  // ==================== v20 -> v21 (çoklu para birimi) ====================
  static Future<void> _v20denV21e(Database db) async {
    await DovizSemasi.olustur(db);
  }

  // ==================== v21 -> v22 (PLU sıralama kalıcılığı) ====================
  static Future<void> _v21denV22ye(Database db) async {
    await _calistir(db,
        'ALTER TABLE urunler ADD COLUMN plu_sira INTEGER NOT NULL DEFAULT 0');
  }

  // ==================== v22 -> v23 (Personel iletişim bilgileri) ====================
  static Future<void> _v22denV23e(Database db) async {
    await _calistir(db, 'ALTER TABLE personel ADD COLUMN telefon TEXT');
    await _calistir(db, 'ALTER TABLE personel ADD COLUMN email TEXT');
  }

  // ==================== v23 -> v24 (Cari: e-Fatura mükellefi durumu) ====================
  static Future<void> _v23denV24e(Database db) async {
    await _calistir(db, "ALTER TABLE cari ADD COLUMN mukellef_durumu TEXT");
    await _calistir(
        db, "ALTER TABLE cari ADD COLUMN mukellef_sorgu_tarihi TEXT");
  }

  // ==================== v24 -> v25 (Fatura: ödeme şekli) ====================
  static Future<void> _v24denV25e(Database db) async {
    await _calistir(db, "ALTER TABLE faturalar ADD COLUMN odeme_sekli TEXT");
  }

  // ==================== v25 -> v26 (Ürün: döviz bazlı fiyatlandırma) ====================
  static Future<void> _v25denV26ya(Database db) async {
    await _calistir(db, "ALTER TABLE urunler ADD COLUMN doviz_kodu TEXT");
    await _calistir(db, "ALTER TABLE urunler ADD COLUMN doviz_tutari REAL");
  }

  // ==================== v26 -> v27 (Şifre güvenliği: tuzlu hash) ====================
  static Future<void> _v26danV27ye(Database db) async {
    // 'tuz' (salt) NULL bırakılıyor — mevcut kullanıcılar bir sonraki
    // başarılı girişte OTOMATİK olarak yeni, tuzlu şemaya yükseltilir
    // (bkz. KullaniciDeposu.girisKontrol). Kimsenin şifresini sıfırlamaya
    // gerek yok, kullanıcı hiçbir şey fark etmez.
    await _calistir(db, "ALTER TABLE kullanicilar ADD COLUMN tuz TEXT");
  }

  // ==================== v27 -> v28 (GİB şifresi güvenli depolamaya taşınıyor) ====================
  static Future<void> _v27denV28e(Database db) async {
    // ÖNCEDEN GİB entegratör şifresi ve mali mühür şifresi SQLite
    // 'ayarlar' tablosunda DÜZ METİN olarak duruyordu — cihaza dosya
    // erişimi olan biri tarafından okunabilirdi. Bu geçiş, mevcut
    // kullanıcılarda (varsa) bu değerleri flutter_secure_storage'a
    // TAŞIYIP, SQLite'tan SİLİYOR — kimse şifresini yeniden girmek
    // zorunda kalmıyor, sadece daha güvenli bir yerde saklanıyor.
    try {
      const secure = FlutterSecureStorage();
      final rows = await db.query('ayarlar',
          where: "anahtar IN ('gib_sifre','gib_mali_muhur_sifre')");
      for (final r in rows) {
        final anahtar = r['anahtar'] as String;
        final deger = r['deger'] as String?;
        if (deger != null && deger.isNotEmpty) {
          await secure.write(key: anahtar, value: deger);
        }
      }
      await db.delete('ayarlar',
          where: "anahtar IN ('gib_sifre','gib_mali_muhur_sifre')");
    } catch (e) {
      // Geçiş başarısız olsa bile uygulama açılmaya devam etmeli —
      // kullanıcı GİB ayarlarını elle tekrar girebilir.
    }
  }

  // ==================== v28 -> v29 (borclar.last_updated eklendi) ====================
  static Future<void> _v28denV29a(Database db) async {
    // ÖNCEDEN BURADA yanlışlıkla YENİ, YİNELENEN bir "borc_odeme_hareket"
    // tablosu oluşturuluyordu — meğer AYNI işi yapan, zaten var olan ve
    // ZATEN KULLANILAN bir "borc_odemeler" tablosu/BorcOdemeDeposu sınıfı
    // varmış (kredi kartı ödeme akışı zaten onu kullanıyordu). Kendi
    // hatamı fark edip düzelttim — gerçekte SADECE eksik olan
    // last_updated sütunu ekleniyor, "borclar" tablosunun senkronizasyon
    // çakışma korumasını (diğer tüm tablolarla tutarlı) alabilmesi için.
    try {
      await _calistir(db, "ALTER TABLE borclar ADD COLUMN last_updated TEXT");
    } catch (_) {
      /* kolon zaten eklenmişse SQLite hata verir — migrasyon devam etmeli */
    }
  }

  // ==================== v29 -> v30 (Kredi kartı limiti hareket-bazlı oldu) ====================
  static Future<void> _v29danV30a(Database db) async {
    await _calistir(db, '''
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
        FOREIGN KEY(kredi_karti_id) REFERENCES kredi_kartlari(id) ON DELETE CASCADE
      )
    ''');
    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_kk_hareket_kart ON kredi_karti_hareket(kredi_karti_id)');

    // Mevcut kartlarda zaten girilmiş "kullanilan_limit" varsa, geriye
    // dönük bir "İlk Kullanım" hareketi oluştur — yeni hareket-bazlı
    // sistem eski veriyle de tutarlı başlasın (stokta "İlk Stok"
    // hareketiyle aynı mantık).
    try {
      final kartlar =
          await db.query('kredi_kartlari', where: 'kullanilan_limit > 0');
      for (final k in kartlar) {
        final kartId = k['id'] as int;
        final kullanilan = (k['kullanilan_limit'] as num).toDouble();
        final mevcutHareket = await db.query('kredi_karti_hareket',
            where: 'kredi_karti_id = ?', whereArgs: [kartId]);
        if (mevcutHareket.isEmpty) {
          await db.insert('kredi_karti_hareket', {
            'kredi_karti_id': kartId,
            'tutar': kullanilan,
            'yon': 'harcama',
            'tarih': DateTime.now().toIso8601String(),
            'aciklama': 'Geçmiş kullanım bakiyesi (sistem geçişi)',
          });
        }
      }
    } catch (_) {
      // Geçiş verisi oluşturulamasa bile uygulama açılmaya devam etmeli.
    }
  }

  // ==================== v30 -> v31 (Ürün görseli için bulut adresi sütunu) ====================
  static Future<void> _v30danV31e(Database db) async {
    try {
      await _calistir(db, "ALTER TABLE urunler ADD COLUMN resim_url TEXT");
    } catch (_) {
      /* kolon zaten eklenmişse SQLite hata verir — migrasyon devam etmeli */
    }
  }

  // ==================== v31 -> v32 (QR menü ürün seçimi) ====================
  static Future<void> _v31denV32ye(Database db) async {
    try {
      await _calistir(db,
          "ALTER TABLE urunler ADD COLUMN qr_menude INTEGER NOT NULL DEFAULT 0");
    } catch (_) {
      /* kolon zaten eklenmişse SQLite hata verir — migrasyon devam etmeli */
    }
  }

  // ==================== v32 -> v33 (Banka hareketleri çoklu cihaz senkronu) ====================
  // Kullanıcı isteği: kredi kartı/banka hareketlerinin birden fazla
  // cihazda senkron olması. banka_hareketler tablosunda last_updated
  // ve is_deleted sütunları HİÇ yoktu — senkronizasyon mekanizması bu
  // ikisine ihtiyaç duyuyor (last_updated: hangi kayıtların yeni
  // olduğunu bilmek için, is_deleted: silinen kayıtları diğer
  // cihazlara da yansıtmak için). Bu olmadan tablo senkron listesine
  // eklenemezdi.
  static Future<void> _v32denV33e(Database db) async {
    try {
      await _calistir(
          db, "ALTER TABLE banka_hareketler ADD COLUMN last_updated TEXT");
      await _calistir(db,
          "ALTER TABLE banka_hareketler ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0");
    } catch (_) {
      /* kolon zaten eklenmişse SQLite hata verir — migrasyon devam etmeli */
    }
  }

  // ==================== v33 -> v34 ====================
  // Derin Supabase senkron analizinde bulundu: aşağıdaki 6 tabloda
  // 'last_updated' sütunu HİÇ YOKTU. Bulut senkronundaki kalıcı kimlik
  // atama mekanizması (backfill), bu sütuna yazmaya çalıştığında
  // sessizce başarısız oluyor ve o tablo o turda TAMAMEN ATLANIYORDU
  // (bir daha da hiç senkron olmuyordu — sütun kalıcı olarak eksik
  // kaldığı için hata da hep tekrarlanıyordu). Bu migrasyon sütunu
  // fiziksel olarak ekliyor; artık delta senkron ve kimlik ataması bu
  // tablolarda da düzgün çalışacak.
  static Future<void> _v33denV34e(Database db) async {
    for (final tablo in [
      'fiyat_gecmis',
      'iade_kalem',
      'irsaliye_kalem',
      'promosyon_kosul',
      'promosyon_aksiyon',
      'rol_yetkileri',
    ]) {
      await _calistir(
          db, "ALTER TABLE $tablo ADD COLUMN last_updated DATETIME");
    }
  }

  // ==================== v34 -> v35 ====================
  // 1) borç modülü (borc_odemeler) senkron sistemine dahil edildi ama
  //    last_updated sütunu hiç yoktu.
  // 2) adisyon_log senkron haritalarında zaten 'global_id' olarak
  //    tanımlıydı AMA last_updated sütunu fiziksel olarak hiç yoktu —
  //    bu yüzden kimlik atama (backfill) kodu yazamayıp tabloyu her
  //    turda atlıyordu ("kimlik ataması LOKALE YAZILAMADI" hatası).
  static Future<void> _v34denV35e(Database db) async {
    await _calistir(
        db, "ALTER TABLE borc_odemeler ADD COLUMN last_updated DATETIME");
    await _calistir(
        db, "ALTER TABLE adisyon_log ADD COLUMN last_updated DATETIME");
  }

  // ==================== v35 -> v36 ====================
  // Kullanıcı isteği: "audit log (kim ne yaptı ne zaman)" ve
  // "bildirim merkezi" (stok azaldı, borç günü geldi vb.) sistemleri.
  static Future<void> _v35denV36e(Database db) async {
    await _calistir(db, """
      CREATE TABLE IF NOT EXISTS audit_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        global_id TEXT UNIQUE,
        tablo_adi TEXT NOT NULL,
        kayit_id TEXT,
        islem_turu TEXT NOT NULL,
        ozet TEXT,
        kullanici_id INTEGER,
        kullanici_adi TEXT,
        cihaz_id TEXT,
        sube_id INTEGER,
        tarih DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        last_updated DATETIME
      )
    """);
    await _calistir(db,
        "CREATE INDEX IF NOT EXISTS idx_audit_log_tarih ON audit_log(tarih DESC)");
    await _calistir(db,
        "CREATE INDEX IF NOT EXISTS idx_audit_log_tablo ON audit_log(tablo_adi)");

    // Bildirim merkezi: kullanıcının "okundu/gizlendi" işaretlediği
    // bildirimleri hatırlamak için (aynı uyarı her açılışta tekrar
    // rahatsız etmesin).
    await _calistir(db, """
      CREATE TABLE IF NOT EXISTS bildirim_okundu (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        bildirim_anahtari TEXT UNIQUE NOT NULL,
        okundu_tarihi DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    """);
  }

  // ==================== v36 -> v37 ====================
  // Kullanıcı isteği: "toptan satış — Ülker gibi firmaların kullandığı
  // profesyonel sistem." Araştırma sonucu üç katmanlı fiyatlandırma
  // (fiyat grubu + miktar kademesi + genel toptan fiyatı) ve koli/
  // adet/kg karma birim desteği tasarlandı.
  static Future<void> _v36denV37e(Database db) async {
    // 1) Fiyat grupları (Altın Bayi, Gümüş Bayi, Standart Toptan gibi)
    await _calistir(db, """
      CREATE TABLE IF NOT EXISTS fiyat_gruplari (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        global_id TEXT UNIQUE,
        ad TEXT NOT NULL,
        aciklama TEXT,
        varsayilan_iskonto_orani REAL NOT NULL DEFAULT 0,
        aktif INTEGER NOT NULL DEFAULT 1,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        last_updated DATETIME
      )
    """);

    // 2) Ürün × fiyat grubu özel fiyatı (girilmezse grubun varsayılan
    //    iskonto oranı perakende fiyata uygulanır)
    await _calistir(db, """
      CREATE TABLE IF NOT EXISTS urun_fiyat_gruplari (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        global_id TEXT UNIQUE,
        urun_id INTEGER NOT NULL,
        fiyat_grubu_id INTEGER NOT NULL,
        fiyat REAL NOT NULL,
        last_updated DATETIME,
        UNIQUE(urun_id, fiyat_grubu_id)
      )
    """);
    await _calistir(db,
        "CREATE INDEX IF NOT EXISTS idx_ufg_urun ON urun_fiyat_gruplari(urun_id)");

    // 3) Miktar bazlı kademeli fiyat (10+ adet X, 50+ adet Y gibi).
    //    fiyat_grubu_id NULL ise TÜM toptan/bayi müşterileri için geçerli.
    await _calistir(db, """
      CREATE TABLE IF NOT EXISTS fiyat_kademeleri (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        global_id TEXT UNIQUE,
        urun_id INTEGER NOT NULL,
        fiyat_grubu_id INTEGER,
        min_miktar REAL NOT NULL,
        birim TEXT NOT NULL DEFAULT 'adet',
        fiyat REAL NOT NULL,
        last_updated DATETIME
      )
    """);
    await _calistir(db,
        "CREATE INDEX IF NOT EXISTS idx_fk_urun ON fiyat_kademeleri(urun_id)");

    // 4) Ürün kartına toptan satış alanları
    await _calistir(db,
        "ALTER TABLE urunler ADD COLUMN toptan_fiyat REAL NOT NULL DEFAULT 0");
    await _calistir(db,
        "ALTER TABLE urunler ADD COLUMN koli_ici_miktar REAL NOT NULL DEFAULT 0");
    await _calistir(db,
        "ALTER TABLE urunler ADD COLUMN koli_birim_adi TEXT NOT NULL DEFAULT 'Koli'");
    await _calistir(db,
        "ALTER TABLE urunler ADD COLUMN satis_birimi_tipi TEXT NOT NULL DEFAULT 'adet'");

    // 5) Cari karta bayi/fiyat grubu bağlantısı
    await _calistir(db, "ALTER TABLE cari ADD COLUMN fiyat_grubu_id INTEGER");
    await _calistir(db,
        "ALTER TABLE cari ADD COLUMN musteri_tipi TEXT NOT NULL DEFAULT 'Perakende'");
    // NOT: kredi limiti (limit_tutari) ve vade (vade_gun) ZATEN vardı —
    // bu migrasyon onları eklemiyor, sadece artık AKTİF OLARAK
    // (satış sırasında) kontrol edilecekler (kod tarafında).
  }

  // ==================== v37 -> v38 ====================
  // Kullanıcı isteği: "ürünlerde de buton eklesek — toptan satış
  // tıkladık, o listede gözüksün, diğerleri gözükmesin." QR Menü'deki
  // 'qr_menude' desenine BİREBİR benzer bir alan.
  static Future<void> _v37denV38e(Database db) async {
    await _calistir(db,
        "ALTER TABLE urunler ADD COLUMN toptan_satista INTEGER NOT NULL DEFAULT 0");
    await _calistir(db,
        "CREATE INDEX IF NOT EXISTS idx_urunler_toptan_satista ON urunler(toptan_satista)");
  }

  // ==================== v38 -> v39 ====================
  // 🔴🔴 GÜVENLİK AĞI MİGRASYONU: Kullanıcı hâlâ "adisyon_log kimlik
  // ataması LOKALE YAZILAMADI" hatası alıyordu — bu, düzeltmenin daha
  // önce YANLIŞ bir dbVersiyon numarasıyla (kullanıcının cihazı zaten
  // o numaraya ulaşmış olabileceği için migrasyon hiç TETİKLENMEDEN)
  // paketlenmiş olabileceğini gösteriyor. SQLite migrasyonları sadece
  // eskiVersiyon < yeniVersiyon olduğunda çalışır — cihazdaki sürüm
  // numarası koddan ilerideyse, ALTER TABLE'lar hiç işlenmez.
  //
  // Çözüm: dbVersiyon'u YENİ bir numaraya (39) çıkarmak — bu, cihazın
  // önceki durumu ne olursa olsun migrasyonun KESİN çalışmasını
  // garantiler. Ayrıca, bu oturumda eklenen TÜM last_updated
  // sütunları burada TEKRAR (güvenli/idempotent — _calistir zaten
  // "duplicate column" hatasını yutuyor) uygulanıyor; böylece
  // hangisinin gerçekten eksik kaldığından bağımsız olarak hepsi
  // garanti altına alınmış oluyor.
  static Future<void> _v38denV39a(Database db) async {
    for (final sql in [
      "ALTER TABLE adisyon_log ADD COLUMN last_updated DATETIME",
      // 🔴 Aynı sınıf hata — bu ikisi de hiç last_updated almamıştı.
      "ALTER TABLE garson_cagri_log ADD COLUMN last_updated DATETIME",
      "ALTER TABLE masa_hareket_log ADD COLUMN last_updated DATETIME",
      "ALTER TABLE borc_odemeler ADD COLUMN last_updated DATETIME",
      "ALTER TABLE borc_odemeler ADD COLUMN tarih DATETIME",
      "ALTER TABLE borc_odemeler ADD COLUMN odeme_yontemi TEXT DEFAULT 'Nakit'",
      "ALTER TABLE borc_odemeler ADD COLUMN referans_no TEXT",
      "ALTER TABLE urunler ADD COLUMN toptan_satista INTEGER NOT NULL DEFAULT 0",
      "ALTER TABLE urunler ADD COLUMN toptan_fiyat REAL NOT NULL DEFAULT 0",
      "ALTER TABLE urunler ADD COLUMN koli_ici_miktar REAL NOT NULL DEFAULT 0",
      "ALTER TABLE urunler ADD COLUMN koli_birim_adi TEXT NOT NULL DEFAULT 'Koli'",
      "ALTER TABLE urunler ADD COLUMN satis_birimi_tipi TEXT NOT NULL DEFAULT 'adet'",
      "ALTER TABLE cari ADD COLUMN fiyat_grubu_id INTEGER",
      "ALTER TABLE cari ADD COLUMN musteri_tipi TEXT NOT NULL DEFAULT 'Perakende'",
    ]) {
      await _calistir(db, sql);
    }
    // audit_log / bildirim_okundu / fiyat_gruplari / urun_fiyat_gruplari /
    // fiyat_kademeleri tabloları da aynı güvenlik ağı mantığıyla
    // garantiye alınıyor (zaten varsa CREATE TABLE IF NOT EXISTS
    // hiçbir şey yapmaz, zararsız).
    await _calistir(db, """
      CREATE TABLE IF NOT EXISTS fiyat_gruplari (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        global_id TEXT UNIQUE,
        ad TEXT NOT NULL,
        aciklama TEXT,
        varsayilan_iskonto_orani REAL NOT NULL DEFAULT 0,
        aktif INTEGER NOT NULL DEFAULT 1,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        last_updated DATETIME
      )
    """);
    await _calistir(db, """
      CREATE TABLE IF NOT EXISTS urun_fiyat_gruplari (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        global_id TEXT UNIQUE,
        urun_id INTEGER NOT NULL,
        fiyat_grubu_id INTEGER NOT NULL,
        fiyat REAL NOT NULL,
        last_updated DATETIME,
        UNIQUE(urun_id, fiyat_grubu_id)
      )
    """);
    await _calistir(db, """
      CREATE TABLE IF NOT EXISTS fiyat_kademeleri (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        global_id TEXT UNIQUE,
        urun_id INTEGER NOT NULL,
        fiyat_grubu_id INTEGER,
        min_miktar REAL NOT NULL,
        birim TEXT NOT NULL DEFAULT 'adet',
        fiyat REAL NOT NULL,
        last_updated DATETIME
      )
    """);
    await _calistir(db, """
      CREATE TABLE IF NOT EXISTS audit_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        global_id TEXT UNIQUE,
        tablo_adi TEXT NOT NULL,
        kayit_id TEXT,
        islem_turu TEXT NOT NULL,
        ozet TEXT,
        kullanici_id INTEGER,
        kullanici_adi TEXT,
        cihaz_id TEXT,
        sube_id INTEGER,
        tarih DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        last_updated DATETIME
      )
    """);
  }

  // ==================== v39 -> v40 ====================
  // 🔴🔴 Derin analizde bulundu: 'cari_hareket' tablosunda HİÇ silme
  // takip sütunu yoktu — CariDeposu.hareketSil() gerçek bir HARD
  // DELETE yapıyordu. Bu, senkron sistemi için ciddi bir sorun: silinen
  // kayıt buluta hiç bildirilemiyor (silindiğini gösterecek bir alan
  // yok), ve bulut→yerel çekişte aynı kayıt "dirilebilir". Bu turda
  // bulunan diğer kök neden: hem CariDeposu.hareketEkle() hem de
  // SatisDeposu.satisIptal()'daki cari_hareket eklemeleri global_id
  // atamıyordu ve BulutManager'ı hiç çağırmıyordu.
  static Future<void> _v39danV40a(Database db) async {
    await _calistir(db,
        "ALTER TABLE cari_hareket ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0");
    await _calistir(db,
        "CREATE INDEX IF NOT EXISTS idx_cari_hareket_deleted ON cari_hareket(is_deleted)");
  }

  // ==================== v40 -> v41 ====================
  // 🔴 Derin analizde bulundu: 'kategoriler' tablosunda hiç silme
  // takibi (is_deleted/aktif) yoktu — kategori silme ekranı gerçek
  // HARD DELETE yapıyordu, onay istemeden. 'markalar' tablosunda ise
  // last_updated sütunu HİÇ yoktu — bu tablo senkron sisteminde olduğu
  // halde değişiklikler asla algılanamıyordu.
  static Future<void> _v40danV41a(Database db) async {
    await _calistir(db,
        "ALTER TABLE kategoriler ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0");
    await _calistir(
        db, "ALTER TABLE markalar ADD COLUMN last_updated DATETIME");
  }

  // ==================== v41 -> v42 ====================
  // 🔴🔴 KRİTİK/SİSTEMİK DÜZELTME: 'ayarlar' tablosu senkron sisteminde
  // olduğu halde SADECE 'guncelleme' sütununa sahipti — ama TÜM
  // senkron mekanizması (supabase_sync_servisi.dart) evrensel olarak
  // 'last_updated' sütununu arıyor. Bu isim uyuşmazlığı yüzünden
  // 'ayarlar' tablosundaki değişikliklerin senkron zamanlaması
  // güvenilir çalışmıyordu. last_updated eklendi; mevcut 'guncelleme'
  // değerleri ilk migrasyonda kopyalanıyor (veri kaybı olmasın diye).
  static Future<void> _v41denV42e(Database db) async {
    await _calistir(db, "ALTER TABLE ayarlar ADD COLUMN last_updated DATETIME");
    await _calistir(db,
        "UPDATE ayarlar SET last_updated = guncelleme WHERE last_updated IS NULL");
  }

  // ==================== v42 -> v43 ====================
  // 🔴🔴 KRİTİK GÜVENLİK BULGUSU: 'roller_yetki' (kullanıcıya özel
  // yetki override'ları — "bu kullanıcıya normal rolünün dışında şu
  // ekstra yetkiyi ver" gibi) tablosu 'rol_yetkileri' (rol şablonları)
  // ile KARIŞTIRILMAMALI — bunlar farklı tablolar ve 'roller_yetki'
  // senkron sisteminde HİÇ yoktu. Sonuç: bir yönetici bir çalışana
  // özel yetki verdiğinde, bu SADECE o cihazda geçerli oluyordu — aynı
  // çalışan BAŞKA bir terminalden giriş yaparsa farklı (varsayılan
  // rol) yetkilerle karşılaşabiliyordu.
  static Future<void> _v42denV43e(Database db) async {
    await _calistir(db, "ALTER TABLE roller_yetki ADD COLUMN global_id TEXT");
    await _calistir(
        db, "ALTER TABLE roller_yetki ADD COLUMN last_updated DATETIME");
  }

  // ==================== v43 -> v44 ====================
  // 🔴🔴 SİSTEMİK DÜZELTME (ayarlar.guncelleme ile AYNI hata sınıfı):
  // 'subeler' tablosu senkron sisteminde olduğu halde 'updated_at'/
  // 'deleted' kullanıyordu — senkron mekanizması evrensel olarak
  // 'last_updated'/'is_deleted' arıyor. Şubeler çok şubeli işletmelerde
  // EN TEMEL veri — bu isim uyuşmazlığı yüzünden yeni şube eklemek
  // diğer cihazlara hiç yansımıyordu.
  static Future<void> _v43denV44e(Database db) async {
    await _calistir(db, "ALTER TABLE subeler ADD COLUMN last_updated DATETIME");
    await _calistir(db,
        "ALTER TABLE subeler ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0");
    await _calistir(db,
        "UPDATE subeler SET last_updated = updated_at WHERE last_updated IS NULL");
    await _calistir(db,
        "UPDATE subeler SET is_deleted = deleted WHERE deleted IS NOT NULL");
  }

  // ==================== v44 -> v45 ====================
  // 🔴🔴 Derin analizde bulundu: 'masa_rezervasyon' (masa senkron
  // sisteminde zaten kayıtlı) tablosunda hiç is_deleted sütunu yoktu —
  // RezervasyonServisi.sil() gerçek HARD DELETE yapıyordu ve HİÇBİR
  // fonksiyon BulutManager çağırmıyordu. Restoran rezervasyonları
  // birden fazla terminal arasında hiç senkronize olmuyordu.
  static Future<void> _v44denV45e(Database db) async {
    await _calistir(db,
        "ALTER TABLE masa_rezervasyon ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0");
  }

  // ==================== v45 -> v46 (şube bazlı stok) ====================
  // 🔴🔴 Derin analizde bulundu: 'sube_urun' (per-şube stok) tablosu
  // şemada VARDI (global_id bile v14→v15'te eklenmişti) ama HİÇBİR
  // depo/servis/ekran onu kullanmıyordu — tamamen atıl bir özellikti.
  // Ayrıca senkron sisteminin evrensel olarak beklediği 'last_updated'
  // yerine 'son_guncelleme' kullanıyordu (ayarlar.guncelleme ile AYNI
  // hata sınıfı). Bu migrasyon, tabloyu gerçekten kullanılabilir hale
  // getiriyor: last_updated ekleniyor, ve HER ürün için HER aktif
  // şubede bir başlangıç satırı oluşturuluyor (mevcut urunler.stok
  // değeri, o an aktif tek şubeye ilk değer olarak aktarılıyor —
  // birden fazla şube varsa, ilk şubeye tam değer, diğerlerine 0
  // verilir; bu sadece bir BAŞLANGIÇ noktasıdır, gerçek dağılımı
  // kullanıcı Stok Sayımı ile düzeltmelidir).
  static Future<void> _v45denV46e(Database db) async {
    await _calistir(
        db, "ALTER TABLE sube_urun ADD COLUMN last_updated DATETIME");
    await _calistir(db,
        "UPDATE sube_urun SET last_updated = son_guncelleme WHERE last_updated IS NULL");
    await _calistir(db,
        "CREATE INDEX IF NOT EXISTS idx_sube_urun_urun ON sube_urun(urun_id)");
    await _calistir(db,
        "CREATE INDEX IF NOT EXISTS idx_sube_urun_sube ON sube_urun(sube_id)");

    try {
      final subeler = await db.query('subeler',
          columns: ['id'], where: 'is_deleted = 0 AND aktif = 1');
      if (subeler.isEmpty)
        return; // Tek şubeli / şube hiç kurulmamış kurulumlarda gerek yok
      final ilkSubeId = subeler.first['id'] as int;
      final urunler = await db.query('urunler',
          columns: ['id', 'stok'], where: 'is_deleted = 0');
      final now = DateTime.now().toIso8601String();
      for (final u in urunler) {
        final urunId = u['id'] as int;
        final toplamStok = (u['stok'] as num?)?.toDouble() ?? 0;
        for (final s in subeler) {
          final subeId = s['id'] as int;
          final mevcut = await db.query('sube_urun',
              where: 'urun_id = ? AND sube_id = ?',
              whereArgs: [urunId, subeId],
              limit: 1);
          if (mevcut.isNotEmpty) continue; // Zaten satırı varsa dokunma
          await db.insert('sube_urun', {
            'urun_id': urunId,
            'sube_id': subeId,
            'stok': subeId == ilkSubeId ? toplamStok : 0,
            'last_updated': now,
            'son_guncelleme': now,
          });
        }
      }
    } catch (_) {
      // Başlangıç verisi oluşturulamazsa sessizce geç — tablo yine de
      // kullanılabilir durumda, sadece başlangıç satırları eksik kalır
      // (StokDeposu ilk hareket sırasında zaten satırı oluşturacak).
    }
  }

  // ==================== v46 -> v47 ====================
  // 🔴🔴 Derin analizde bulundu (gerçek Supabase hatasından):
  // 'kredi_kartlari.kart_no_maskeli' bazı (muhtemelen eski/senkronla
  // başka cihazdan gelmiş) kayıtlarda NULL kalmıştı — sütun yerelde
  // NOT NULL olmasa da, bulut şemasında NOT NULL olduğu için senkron
  // "23502 null value violates not-null constraint" hatasıyla
  // sürekli başarısız oluyordu. Bu migrasyon, NULL kalan tüm
  // kayıtları güvenli bir yer tutucuyla dolduruyor.
  static Future<void> _v46denV47e(Database db) async {
    await _calistir(
        db,
        "UPDATE kredi_kartlari SET kart_no_maskeli = '**** **** **** ????', last_updated = datetime('now') "
        "WHERE kart_no_maskeli IS NULL OR kart_no_maskeli = ''");
  }

  // ==================== v47 -> v48 ====================
  // 🔴🔴 Derin analizde bulundu (kullanıcı bulgusu — "toptan bölümde
  // bayi/müşteri/tedarikçi doğru mu"): 'cari_ekle_ekrani.dart'ta
  // "Müşteri Tipi" (Perakende/Bayi/Toptan) alanı cari_tipi ne olursa
  // olsun HER ZAMAN gösteriliyordu — saf bir TEDARİKÇİ'ye
  // "Bayi"/"Toptan" musteri_tipi atanabiliyordu. Toptan modülü SADECE
  // musteri_tipi'ne bakıp cari_tipi'ni HİÇ kontrol etmediği için, bu
  // tedarikçiler mantıksız şekilde "toptan satış yapılabilecek bayi"
  // listesinde görünüyordu. Form artık bunu engelliyor (yeni
  // kayıtlar için); bu migrasyon MEVCUT hatalı kayıtları temizliyor.
  static Future<void> _v47denV48e(Database db) async {
    await _calistir(db, '''
      UPDATE cari SET musteri_tipi = 'Perakende', last_updated = datetime('now')
      WHERE cari_tipi NOT LIKE '%Müşteri%' AND musteri_tipi IN ('Bayi', 'Toptan')
    ''');
  }

  // ==================== v48 -> v49 ====================
  // 🔴 DERİN ANALİZDE BULUNDU (kullanıcı isteği üzerine ikinci bir
  // derinlemesine inceleme): 'irsaliyeler' tablosunda 'last_updated'
  // sütunu HİÇ YOKTU (ne ilk kurulum şemasında, ne önceki
  // migrasyonlarda) — ama irsaliye_ekrani.dart'taki _durumGuncelle()
  // fonksiyonu bu sütuna YAZMAYA ÇALIŞIYORDU. Sonuç: bir irsaliyenin
  // durumunu (Bekliyor/Tamamlandı/İptal) değiştirmeye çalışan HER
  // kullanıcı "no such column: last_updated" SQL hatası alıyordu —
  // durum hiç güncellenmiyor, buluta da hiç gönderilmiyordu (hata,
  // BulutManager().upsert() çağrılmadan ÖNCE fırlıyordu). Ayrıca bu
  // sütun olmadığı için 'irsaliyeler' _lastUpdatedVar'a hiç
  // eklenememişti — bulut şemasında last_updated OLDUĞU HALDE, bu
  // tablo için delta (sadece değişenler) senkronu hiç çalışmıyor,
  // her "Hızlı Sync"te TÜM irsaliyeler baştan indiriliyordu.
  static Future<void> _v48denV49a(Database db) async {
    await _calistir(
        db, 'ALTER TABLE irsaliyeler ADD COLUMN last_updated DATETIME');
  }

  // ==================== v49 -> v50 ====================
  // 🔴🔴🔴 KRİTİK DÜZELTME (kullanıcı bulgusu — "kredi kartlarında
  // sorun var, Supabase'e göndermemiş"): Kök neden bulundu.
  // 'bankalar', 'banka_hesaplar', 'kredi_kartlari' (ve aynı şekilde
  // 'borclar', 'fiyat_gruplari', 'promosyon_tanim') tabloları bulut
  // senkron sistemine SONRADAN eklendi (bkz. supabase_sync_servisi.dart
  // içindeki "bu tablolar daha önce hiç senkron listesinde değildi"
  // notları). 'global_id' sütunu bu tablolarda EN BAŞTAN beri vardı,
  // ama o zamanlar hiçbir kod bu sütuna yazmıyordu — yani senkron
  // eklenmeden ÖNCE oluşturulmuş TÜM eski kayıtların global_id'si
  // NULL. Model katmanı (BankaModel/KrediKartiModel...toMap()) da
  // global_id'yi SADECE zaten doluysa gönderiyor — yani bir eski
  // banka/kart düzenlense BİLE global_id hâlâ boş kalıyor.
  //
  // Somut etki: bir kullanıcı ESKİ bir bankaya (global_id'si NULL)
  // bağlı YENİ bir kredi kartı eklediğinde, otomatik (anlık) senkron
  // yolu FK dönüşümü için bankanın global_id'sini arıyor, bulamıyor
  // (_fkLokalGidCache sadece dolu global_id'li satırları içeriyor) ve
  // kredi_kartlari.banka_id'yi OLDUĞU GİBİ (yerel SQLite id'si olarak)
  // buluta gönderiyordu. Bulutta banka_id NOT NULL + FOREIGN KEY
  // kısıtlaması olduğundan (REFERENCES bankalar(id)), bu kayıt ya
  // tamamen REDDEDİLİYOR ya da yanlış bir bankaya bağlanıyordu — kart
  // hiç Supabase'e gitmiyordu ya da orada görünmüyordu. Sadece elle
  // "Tam Sync — Buluta Gönder" çalıştırmak bunu (o an için) düzeltiyordu
  // çünkü SupabaseSyncServisi.bulutaGonder() eksik global_id'leri
  // göndermeden önce otomatik dolduruyor — ama otomatik/anlık senkron
  // yolu bunu hiç yapmıyordu.
  //
  // Kalıcı çözüm: bu 6 tabloda global_id'si eksik olan TÜM satırlara,
  // bir daha hiç tekrarlanmasın diye, uygulama ilk açılışta KALICI
  // bir kimlik atıyor.
  static Future<void> _v49danV50ye(Database db) async {
    const tablolar = [
      'bankalar',
      'banka_hesaplar',
      'kredi_kartlari',
      'borclar',
      'fiyat_gruplari',
      'promosyon_tanim',
    ];
    for (final tablo in tablolar) {
      try {
        final eksikler = await db.query(
          tablo,
          columns: ['id'],
          where: "global_id IS NULL OR global_id = ''",
        );
        if (eksikler.isEmpty) continue;
        final batch = db.batch();
        for (final row in eksikler) {
          batch.update(
            tablo,
            {'global_id': const Uuid().v4()},
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        }
        await batch.commit(noResult: true);
      } catch (_) {
        // Tablo bu cihazda yoksa/farklıysa sessizce atla — diğer
        // tabloların düzeltilmesini engellemesin.
      }
    }
  }

  // ==================== v50 -> v51 ====================
  // Kullanıcı isteği: "Bayilerden Sipariş Alma" ekranı — ürün arama +
  // barkod ile bayiye sipariş alınabilsin, alış fiyatı (maliyet)
  // görünür olsun, kalem bazında iskonto yapılabilsin, Adet/Koli/Paket
  // gibi birimler için Ölçü Birimleri ekranından tanımlı çarpanlar
  // kullanılsın. Sipariş önce "Bekleyen Sipariş" olarak kaydedilir,
  // ayrı bir onay ekranından satışa/faturaya/irsaliyeye dönüştürülür.
  static Future<void> _v50denV51e(Database db) async {
    // 1) Ölçü Birimleri: her birime (Adet, Koli, Paket, Kutu...) kendi
    // çarpanı — "1 Paket = 24 Adet" gibi — tanımlanabilsin. Ana birim
    // (ör. Adet) çarpanı 1 kalır.
    await _calistir(
        db, 'ALTER TABLE birimler ADD COLUMN carpan REAL NOT NULL DEFAULT 1');

    // 2) Bekleyen sipariş başlığı
    await _calistir(db, '''
      CREATE TABLE IF NOT EXISTS bekleyen_siparisler (
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
        FOREIGN KEY(cari_id) REFERENCES cari(id)
      )
    ''');

    // 3) Bekleyen sipariş kalemleri
    await _calistir(db, '''
      CREATE TABLE IF NOT EXISTS bekleyen_siparis_kalem (
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
        FOREIGN KEY(siparis_id) REFERENCES bekleyen_siparisler(id) ON DELETE CASCADE,
        FOREIGN KEY(urun_id) REFERENCES urunler(id)
      )
    ''');

    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_bekleyen_sip_kalem ON bekleyen_siparis_kalem(siparis_id)');
    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_bekleyen_sip_cari ON bekleyen_siparisler(cari_id)');
  }

  static Future<void> _calistir(Database db, String sql) async {
    try {
      await db.execute(sql);
    } catch (e) {
      final mesaj = e.toString().toLowerCase();
      // 🔴 Derin analizde bulundu: 'syntax error' bu "zararsız/beklenen"
      // listesindeydi — ama bir ALTER/CREATE ifadesindeki gerçek bir SQL
      // yazım hatası HİÇBİR ZAMAN zararsız/idempotent bir durum değildir
      // (aksine 'duplicate column'/'already exists'/'no such column'/
      // 'no such table' — bunlar hep "bu değişiklik zaten uygulanmış"
      // anlamına gelir). 'syntax error'ı burada yutmak, gelecekteki
      // gerçekten bozuk bir migration ifadesini sessizce no-op'a
      // çevirip şemayı eksik bırakabilir — hata çok daha sonra, ilgisiz
      // bir "no such column" çökmesi olarak ve çok daha zor teşhis
      // edilebilir şekilde ortaya çıkardı.
      final bilinen = mesaj.contains('duplicate column') ||
          mesaj.contains('already exists') ||
          mesaj.contains('table already') ||
          mesaj.contains('no such column') ||
          mesaj.contains('no such table');
      if (!bilinen) rethrow;
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // v51 → v52  (26.07.2026)
  //
  // SENKRON SÜTUN KAYMASI DÜZELTMESİ
  //
  // `supabase_sync_servisi._lastUpdatedVar` 9 tabloda 'last_updated'
  // olduğunu varsayıyordu ama yerel şemada yoktu. Gönderimde kod sütunu
  // payload'a ekliyor (bulutta var, kabul ediliyor), ÇEKERKEN yerel tablo
  // kabul etmiyor → "no such column: last_updated" → o tablonun tüm
  // partisi düşüyordu. Ayrıca değer yerelde saklanamadığı için delta
  // hiç ilerlemiyor, her senkronda tablo baştan iniyordu.
  //
  // Sütunlar KolonTamamlayici'da tek yerde tanımlı; taze kurulum
  // (TabloOlusturucu) ve bu migrasyon aynı listeyi kullanır.
  // ══════════════════════════════════════════════════════════════════════
  static Future<void> _v51denV52ye(Database db) async {
    await KolonTamamlayici.tamamla(db);
    await KolonTamamlayici.indeksle(db);
  }

  // ══════════════════════════════════════════════════════════════════════
  // v53: Toptan satış — "asgari sipariş miktarı" (MOQ). Profesyonel B2B
  // sistemlerin standart kuralı: bayi bir üründen tanımlı asgari miktarın
  // altında sipariş veremez. 0 = sınır yok (mevcut ürünler etkilenmez).
  // ══════════════════════════════════════════════════════════════════════
  static Future<void> _v52denV53e(Database db) async {
    await _calistir(db,
        "ALTER TABLE urunler ADD COLUMN asgari_siparis_miktari REAL NOT NULL DEFAULT 0");
  }

  // ══════════════════════════════════════════════════════════════════════
  // v54: Sync Çakışmaları — iki cihaz aynı kaydı bağımsız değiştirdiğinde
  // (ör. Cihaz A fiyatı 125, Cihaz B aynı anda 129 yapmışsa), senkron
  // pull akışı önceden bunu SESSİZCE "son-yazan-kazanır" ile çözüyordu —
  // kaybeden değişiklik hiçbir iz bırakmadan kayboluyordu. Artık üzerine
  // yazmadan ÖNCE bu tabloya bir çakışma kaydı düşülüyor (Ayarlar → Sync
  // Çakışmaları ekranından görülüp A/B/manuel çözülebiliyor); senkron
  // DAVRANIŞI (hangi değerin kazanacağı) DEĞİŞMEDİ — sadece artık
  // görünür ve denetlenebilir.
  // ══════════════════════════════════════════════════════════════════════
  static Future<void> _v53denV54e(Database db) async {
    await _calistir(db, '''
      CREATE TABLE IF NOT EXISTS sync_cakismalar (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tablo TEXT NOT NULL,
        kayit_global_id TEXT,
        alan_farklari TEXT,
        yerel_kayit TEXT,
        gelen_kayit TEXT,
        tarih DATETIME NOT NULL,
        cozuldu INTEGER NOT NULL DEFAULT 0,
        cozum_tipi TEXT,
        cozen_kullanici TEXT,
        cozum_tarihi DATETIME
      )
    ''');
    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_sync_cakisma_cozuldu ON sync_cakismalar(cozuldu)');
  }

  // ==================== v54 -> v55 ====================
  // 🔴🔴 KRİTİK SENKRON HATASI (derin analizde bulundu): 'urunler'
  // tablosunda İKİ ayrı tetikleyici (trg_urun_updated — yükseltilen
  // kurulumlarda, trg_urun_guncelle — yeni kurulumlarda) her UPDATE
  // sonrası last_updated'ı datetime('now') ile YENİDEN yazıyordu.
  // SQLite'ın datetime('now') fonksiyonu VARSAYILAN OLARAK UTC döner ve
  // saat dilimi işareti (Z/±hh:mm) İÇERMEZ — ama uygulama kodu (ör.
  // UrunDeposu.guncelle()) last_updated'ı zaten DOĞRU şekilde
  // DateTime.now().toIso8601String() (YEREL saat) ile set ediyordu.
  // Tetikleyici bu doğru değerin üzerine, saat dilimsiz UTC bir değer
  // yazıyordu — Dart'ın DateTime.tryParse()'ı saat dilimi işareti
  // olmayan bir string'i YEREL saat olarak yorumlar, yani Türkiye
  // (UTC+3) için her ürün güncellemesinin last_updated'ı GERÇEKTEN
  // OLDUĞUNDAN ~3 SAAT ESKİ görünüyordu. Bu, last_updated'a dayanan TÜM
  // senkron çakışma çözümünü (last-write-wins) etkiliyordu: yerelde
  // yapılan gerçekten daha YENİ bir değişiklik, buluttaki daha ESKİ bir
  // sürüme karşı yanlışlıkla "kaybedebiliyordu". Uygulama kodu
  // last_updated'ı zaten her yazma yolunda doğru şekilde set ettiği
  // için bu tetikleyiciler gereksizdi (ve zararlıydı) — kaldırıldı.
  static Future<void> _v54denV55e(Database db) async {
    await _calistir(db, 'DROP TRIGGER IF EXISTS trg_urun_updated');
    await _calistir(db, 'DROP TRIGGER IF EXISTS trg_urun_guncelle');
  }

  // v55'ten v56'ya — FAZ 1 madde 2 (Vardiya/Kasa Mutabakatı, kullanıcı
  // onayıyla): kasa_hareketleri'nde ödeme yöntemi ayrımı YOKTU — bir satış
  // Nakit mi Kart mı ödenmiş fark etmeksizin (Cari hariç) aynı 'Satış'
  // hareketine, aynı zincire yazılıyordu. Bu, "kasa bakiyesi" olarak
  // gösterilen değerin aslında Nakit+Kart karışımı olmasına yol açıyordu
  // (fiziksel kasadaki gerçek nakit değil). Nullable, default'suz TEK
  // sütun — mevcut hiçbir sorgu/rapor bu sütunu okumadığı için sessizce
  // NULL kalır, davranış değişmez. Eski kayıtlar KASITLI OLARAK NULL
  // bırakıldı (geriye dönük "tahmin" yapılmadı — bkz. rapor: karma
  // ödemeli eski satışlarda hangi kasa hareketinin hangi ödeme parçasına
  // ait olduğu bilgisi kayıp, yanlış backfill'den kaçınıldı).
  static Future<void> _v55denV56ya(Database db) async {
    await _calistir(
        db, 'ALTER TABLE kasa_hareketleri ADD COLUMN odeme_yontemi TEXT');
  }

  // v56'dan v57'ye — FAZ 9 (Onay Merkezi, kullanıcı onayıyla): sekiz
  // riskli akışta (yüksek iskonto, yüksek iade, risk limiti aşımı, kasa
  // çıkışı, fiyat değişimi, stok düzeltme, yüksek gider, borç silme)
  // eşik aşıldığında işlem NORMAL TAMAMLANIR — bu tablo sadece BİLDİRİM
  // amaçlı, hiçbir akışı ENGELLEMEZ/kesintiye uğratmaz. Mevcut hiçbir
  // tabloya dokunmuyor, tamamen izole yeni bir tablo.
  static Future<void> _v56denV57ye(Database db) async {
    await _calistir(db, '''
      CREATE TABLE IF NOT EXISTS onay_talepleri (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        global_id TEXT UNIQUE,
        tur TEXT NOT NULL,
        referans_turu TEXT,
        referans_id INTEGER,
        tutar REAL,
        esik_tutar REAL,
        aciklama TEXT,
        kullanici_id INTEGER,
        kullanici_adi TEXT,
        sube_id INTEGER,
        tarih DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        goruldu INTEGER NOT NULL DEFAULT 0,
        goren_kullanici_id INTEGER,
        goruldu_tarihi DATETIME,
        last_updated DATETIME,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_onay_talepleri_goruldu ON onay_talepleri(goruldu, tarih DESC)');
    await _calistir(db,
        'CREATE INDEX IF NOT EXISTS idx_onay_talepleri_tur ON onay_talepleri(tur)');
  }

  // v58 — Bayi Portalı (erp_roadmap madde 39, kullanıcı onayıyla "aynı
  // uygulama içinde Bayi rolü"): kullanicilar.rol'ün CHECK kısıtına
  // dokunmadan (mevcut tabloyu yeniden oluşturmak riskli olurdu), yeni
  // nullable bir kolon — bir kullanıcı bu alanda bir cari.id taşıyorsa
  // "bayi" modundadır (rol hâlâ 'personel' kalabilir, CHECK ihlali yok).
  static Future<void> _v57denV58e(Database db) async {
    await _calistir(db,
        'ALTER TABLE kullanicilar ADD COLUMN bayi_cari_id INTEGER REFERENCES cari(id)');
  }

  // 🔴🔴 KRİTİK DÜZELTME (Borç Silme özelliği eklenirken bulundu — dosya
  // yolları arası şema sapması): fresh-install şeması (semalar/borc_semasi
  // .dart) 'borclar' tablosuna is_deleted sütununu baştan koyuyordu, ama
  // BU migrasyon zincirindeki CREATE TABLE (yukarıda ~satır 1096, borç
  // takip modülü ilk eklendiğinde) is_deleted'i HİÇ İÇERMİYORDU ve hiçbir
  // sonraki migrasyon adımı da eklemiyordu. Sonuç: borç takip modülü bir
  // önceki sürümden YÜKSELTİLEREK gelen (yani neredeyse tüm gerçek
  // kullanıcı) cihazlarda is_deleted sütunu HİÇ YOKTU — BorcDeposu.sil()
  // (ve is_deleted=0 filtresi kullanan tumunuGetir/idileGetir/
  // vadesiGecenleriGetir/yaklasanlariGetir) bu cihazlarda "no such column:
  // is_deleted" hatasıyla çökerdi. Borç Silme özelliği bu sütuna bağımlı
  // olduğu için önce bu kök neden düzeltildi.
  static Future<void> _v58denV59a(Database db) async {
    await _calistir(db,
        'ALTER TABLE borclar ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0');
  }

  // v59'dan v60'a — güvenlik düzeltmesi: parmak izi ile giriş ÖNCEDEN
  // kullanıcının ham şifresini FlutterSecureStorage'a yazıyordu (OS
  // seviyesinde şifreli ama yine de düz metin şifre). Artık şifre hiç
  // saklanmıyor; her cihaz için rastgele üretilen 256-bit bir "biyometrik
  // token" tuzlanıp hash'i bu YENİ, tamamen İZOLE ve bilerek Supabase'e
  // senkron EDİLMEYEN tabloya yazılıyor (cihaza özel bir sır — başka
  // cihaza/kullanıcıya sızması anlamsız/riskli olurdu, bu yüzden
  // supabase_sync_servisi.dart'ın tablo listesine BİLİNÇLİ OLARAK
  // eklenmedi). kullanicilar tablosuna dokunulmuyor.
  static Future<void> _v59denV60a(Database db) async {
    await _calistir(db, '''
      CREATE TABLE IF NOT EXISTS biyometrik_kayitlar (
        kullanici_id INTEGER PRIMARY KEY REFERENCES kullanicilar(id),
        token_hash TEXT NOT NULL,
        tuz TEXT NOT NULL,
        olusturma_tarihi DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');
  }

  // v60'tan v61'e — e-Belge durum makinesi genişletmesi (erp_roadmap madde
  // 38, 2026-09-14 derin analiz). GİB bir e-Faturayı REDDEDERSE, kullanıcı
  // aynı faturayı düzeltip yeniden göndermek isteyebilir. Ama gib_servisi
  // .dart'taki ETTN, faturanın global_id'sinden DETERMİNİSTİK üretiliyor
  // (mükerrer gönderim korumasının kalbi — bkz. o dosyadaki not) — yani
  // düzeltmeden sonra yeniden gönderilse bile AYNI ETTN kullanılırdı, ki
  // bu bir entegratörün "zaten reddedilmiş bu belgeyi" diye ikinci kez
  // reddetmesine ya da kafa karışıklığına yol açabilir. Bu sayaç, SADECE
  // bir RET sonrası yeniden gönderimde artırılıp ETTN'ye karıştırılıyor —
  // network hatası sonrası yapılan (GİB'e hiç ulaşmamış) normal
  // tekrar denemelerde sayaç ARTMIYOR, o yüzden mevcut "kazara çift
  // gönderim" koruması BOZULMUYOR.
  static Future<void> _v60danV61e(Database db) async {
    await _calistir(db,
        'ALTER TABLE faturalar ADD COLUMN e_fatura_deneme_no INTEGER NOT NULL DEFAULT 0');
  }

  // v61'den v62'ye — e-İrsaliye GİB gönderimi (kullanıcı isteği, 2026-09-14
  // derin analiz: "e irsaliye türkiyeye göre tam doğru olmalı"). Ayarlar'da
  // ÖNCEDEN "e-İrsaliye Aktif" anahtarı vardı ama hiçbir kod göndermiyordu —
  // tamamen süslemelikti. faturalar tablosuyla AYNI desende (e_fatura_*)
  // yeni sütunlar eklendi.
  static Future<void> _v61denV62ye(Database db) async {
    await _calistir(db, "ALTER TABLE irsaliyeler ADD COLUMN e_irsaliye_durum TEXT DEFAULT 'hazir'");
    await _calistir(db, 'ALTER TABLE irsaliyeler ADD COLUMN e_irsaliye_uuid TEXT');
    await _calistir(db, 'ALTER TABLE irsaliyeler ADD COLUMN e_irsaliye_xml TEXT');
    await _calistir(db, 'ALTER TABLE irsaliyeler ADD COLUMN e_irsaliye_deneme_no INTEGER NOT NULL DEFAULT 0');
    await _calistir(db, 'ALTER TABLE irsaliyeler ADD COLUMN e_irsaliye_gonderim_tarihi DATETIME');
  }

  // ==================== v62 -> v63 ====================
  // 🔴🔴🔴 KRİTİK VERİ BOZULMASI (komple uygulama derin analizinde
  // bulundu — v54→v55'teki 'trg_urun_updated' düzeltmesiyle AYNI SINIF
  // hata, farklı bir tetikleyicide): 'cari' bakiyesini her yeni
  // cari_hareket eklendiğinde otomatik yeniden hesaplayan tetikleyici
  // (yükseltilen kurulumlarda 'trg_cari_bakiye_ins', taze kurulumlarda
  // 'trg_cari_hareket_bakiye' — semalar/diger_semasi.dart) SUM
  // sorgusunda 'is_deleted = 0' FİLTRESİ İÇERMİYORDU. Oysa uygulamanın
  // HER YERDEKİ (CariDeposu.hareketEkle/bakiyeYenidenHesapla, Veri
  // Sağlığı Merkezi mutabakatı, cari_hareket_ekrani.dart'taki iptal
  // akışı, iade_ekrani_gecmis.dart'taki 3 iade-iptal noktası) KANONİK
  // kuralı şudur: soft-delete edilmiş (is_deleted=1, ör. iptal edilmiş
  // bir tahsilat/iade) bir hareket bakiyeye HİÇ katkı vermemeli.
  //
  // Bu "kanonik" uygulama kodu yollarının HEPSİ, kendi INSERT'lerinden
  // HEMEN SONRA, AYNI transaction içinde, DOĞRU (is_deleted=0 filtreli)
  // bir UPDATE ile bakiyeyi kendileri yeniden hesaplıyor — bu yüzden
  // tetikleyicinin ürettiği YANLIŞ ara değer, o an İÇİN her zaman
  // hemen üzerine yazılıp gizleniyordu.
  //
  // AMA TEK BİR YOL bunu YAPMIYOR: Veritabani.supaKayitlariEkle() —
  // yani BULUTTAN GELEN cari_hareket satırlarını (başka bir cihazda
  // oluşturulmuş) bu cihaza EKLERKEN kullanılan GENEL/JENERİK toplu
  // ekleme yolu. Bu yol, hiçbir tabloya özel takip mantığı içermez;
  // sadece INSERT eder. Sonuç: bir müşterinin GEÇMİŞTE iptal edilmiş
  // (is_deleted=1) bir hareketi varsa, o müşteri için BAŞKA bir
  // cihazdan senkronize olan HERHANGİ bir YENİ cari_hareket (normal bir
  // satış, tahsilat, ödeme — iptalle hiç ilgisi olmayan bir işlem),
  // "Hızlı Al"/"Tam Al" sırasında bu tetikleyiciyi ateşleyip müşterinin
  // bakiyesini o ESKİ, İPTAL EDİLMİŞ tutar kadar YANLIŞ şişiriyordu —
  // sessizce, kalıcı olarak, sadece "Veri Sağlığı Merkezi > Cari
  // Mutabakat > Düzelt" ile fark edilip düzeltilebilecek şekilde.
  //
  // Düzeltme: her iki olası isimdeki eski, hatalı tetikleyici DROP
  // edilip, is_deleted=0 filtresi eklenmiş TEK bir doğru tetikleyici
  // (fresh-install ile AYNI ada sahip: trg_cari_hareket_bakiye) yeniden
  // oluşturuluyor. Kasıtlı olarak MEVCUT (muhtemelen zaten bozulmuş)
  // bakiye değerleri burada OTOMATİK toplu düzeltilmiyor — bu
  // dosyanın/protokolün "hiçbir kontrol kullanıcı onayı olmadan veri
  // değiştirmez" ilkesiyle tutarlı olarak, kullanıcı bunu Veri Sağlığı
  // Merkezi'nden kendi onayıyla çalıştırır.
  static Future<void> _v62denV63e(Database db) async {
    await _calistir(db, 'DROP TRIGGER IF EXISTS trg_cari_bakiye_ins');
    await _calistir(db, 'DROP TRIGGER IF EXISTS trg_cari_hareket_bakiye');
    await _calistir(db, """CREATE TRIGGER trg_cari_hareket_bakiye
      AFTER INSERT ON cari_hareket BEGIN
      UPDATE cari SET bakiye = (
        SELECT COALESCE(SUM(borc - alacak), 0) FROM cari_hareket
        WHERE cari_id = NEW.cari_id AND is_deleted = 0
      ) WHERE id = NEW.cari_id; END""");
  }
}
