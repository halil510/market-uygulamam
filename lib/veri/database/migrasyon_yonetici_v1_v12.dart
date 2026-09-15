// lib/veri/database/migrasyon_yonetici_v1_v12.dart
//
// migrasyon_yonetici.dart'ın parçası (part/part of) — dosya çok büyümüştü
// (2479 satır), her fonksiyon bağımsız bir versiyon geçişi olduğu için
// sürüm aralıklarına göre 3 dosyaya bölündü (v1-v12, v12-v36, v36-v63).
// Davranış BİREBİR AYNI — fonksiyonlar 'static' sınıf metodundan bu part
// dosyasındaki top-level (ama hâlâ private, kütüphane-içi) fonksiyonlara
// taşındı; guncelle() dispatcher'ı ana dosyada aynı şekilde çağırıyor.
part of 'migrasyon_yonetici.dart';

// ==================== v1 -> v2 ====================
Future<void> _v1denV2ye(Database db) async {
  await _calistir(db,
      'ALTER TABLE urunler ADD COLUMN kdv_dahil INTEGER NOT NULL DEFAULT 1');
  await _calistir(db,
      'ALTER TABLE urunler ADD COLUMN barkod_tipi TEXT NOT NULL DEFAULT "CODE128"');
  await _calistir(db,
      'ALTER TABLE satislar ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0');
}

// ==================== v2 -> v3 ====================
Future<void> _v2denV3e(Database db) async {
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
Future<void> _v3denV4e(Database db) async {
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
Future<void> _v4denV5e(Database db) async {
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

Future<void> _v5Ek(Database db) async {
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
Future<void> _v5denV6ya(Database db) async {
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
Future<void> _v6denV7ye(Database db) async {
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
Future<void> _v7denV8e(Database db) async {
  await _calistir(db, 'ALTER TABLE faturalar ADD COLUMN iade_id INTEGER');
  await _calistir(db,
      'CREATE INDEX IF NOT EXISTS idx_faturalar_iade ON faturalar(iade_id)');
}

// ==================== v8 -> v9 (Masa/Restoran) ====================
Future<void> _v8denV9a(Database db) async {
  await MasaSemasi.olustur(db);
}

// ==================== v9 -> v10 (PLU) ====================
Future<void> _v9denV10a(Database db) async {
  await _calistir(
      db, 'ALTER TABLE urunler ADD COLUMN plu INTEGER NOT NULL DEFAULT 0');
  await _calistir(db,
      'ALTER TABLE urunler ADD COLUMN plu_kart_boyut INTEGER NOT NULL DEFAULT 2');
}

// ==================== v10 -> v11 (Rezervasyon + Garson Çağrı) ====================
Future<void> _v10denV11e(Database db) async {
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
Future<void> _v11denV12e(Database db) async {
  await _calistir(db,
      'CREATE INDEX IF NOT EXISTS idx_masa_siparis_durum_acilis ON masa_siparisleri(durum, acilis_zamani)');
  await _calistir(db,
      'CREATE INDEX IF NOT EXISTS idx_masa_kalem_durum ON masa_siparis_kalem(durum)');
  await _calistir(db,
      'CREATE INDEX IF NOT EXISTS idx_masa_siparis_kapanis ON masa_siparisleri(kapanis_zamani)');
  await _calistir(db,
      'CREATE INDEX IF NOT EXISTS idx_rezervasyon_durum_saat ON masa_rezervasyon(durum, saat)');
}

