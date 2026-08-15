-- ===================================================================
--  MarketPlus Ultimate - Tam Veritabanı Şeması (SQLite 3)
--  Versiyon: 2.0  |  Tarih: 2026
--  Tüm tablolar yeniden oluşturulur (DROP IF EXISTS)
--  Offline-first, çoklu şube, senkronizasyon, e-fatura, lot/seri, promosyon, vb.
-- ===================================================================

PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA cache_size = -16000;
PRAGMA temp_store = MEMORY;

-- ===================================================================
--  ÖNCE TABLOLARI TEMİZLE (sırayla, foreign key uyumu için)
-- ===================================================================
DROP TABLE IF EXISTS sync_queue;
DROP TABLE IF EXISTS sync_meta;
DROP TABLE IF EXISTS stok_fifo;
DROP TABLE IF EXISTS gunluk_rapor_ozet;
DROP TABLE IF EXISTS fis_seri;
DROP TABLE IF EXISTS rol_yetkileri;
DROP TABLE IF EXISTS promosyon_aksiyon;
DROP TABLE IF EXISTS promosyon_kosul;
DROP TABLE IF EXISTS promosyon_tanim;
DROP TABLE IF EXISTS sube_fiyat_gecmis;
DROP TABLE IF EXISTS sube_urun;
DROP TABLE IF EXISTS fiyat_gecmis;
DROP TABLE IF EXISTS fiyat_gecmis;  -- tekrar
DROP TABLE IF EXISTS lot_seri;
DROP TABLE IF EXISTS stok_hareket;
DROP TABLE IF EXISTS gecici_sayim;
DROP TABLE IF EXISTS satis_kalem;
DROP TABLE IF EXISTS satislar;
DROP TABLE IF EXISTS iade_kalem;
DROP TABLE IF EXISTS iade;
DROP TABLE IF EXISTS tedarikci_siparis_kalem;
DROP TABLE IF EXISTS tedarikci_siparisler;
DROP TABLE IF EXISTS cari_hareket;
DROP TABLE IF EXISTS cari_adres;
DROP TABLE IF EXISTS cari;
DROP TABLE IF EXISTS promosyonlar;
DROP TABLE IF EXISTS fatura_detaylari;
DROP TABLE IF EXISTS faturalar;
DROP TABLE IF EXISTS kasa_hareketleri;
DROP TABLE IF EXISTS vardiyalar;
DROP TABLE IF EXISTS giderler;
DROP TABLE IF EXISTS gider_kategoriler;
DROP TABLE IF EXISTS bildirimler;
DROP TABLE IF EXISTS yazicilar;
DROP TABLE IF EXISTS ayarlar;
DROP TABLE IF EXISTS urunler;
DROP TABLE IF EXISTS kategoriler;
DROP TABLE IF EXISTS subeler;
DROP TABLE IF EXISTS roller_yetki;
DROP TABLE IF EXISTS kullanicilar;

-- ===================================================================
--  TABLO OLUŞTURMA (sıralı, foreign key'ler dikkate alınarak)
-- ===================================================================

-- 1. Şubeler
CREATE TABLE subeler (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    global_id   TEXT UNIQUE,
    sube_kodu   TEXT NOT NULL UNIQUE,
    sube_adi    TEXT NOT NULL,
    adres       TEXT,
    telefon     TEXT,
    email       TEXT,
    vergi_no    TEXT,
    aktif       INTEGER NOT NULL DEFAULT 1,
    created_at  TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at  TEXT DEFAULT CURRENT_TIMESTAMP,
    deleted     INTEGER DEFAULT 0
);

-- 2. Kullanıcılar
CREATE TABLE kullanicilar (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    global_id       TEXT UNIQUE,
    sube_id         INTEGER,
    kullanici_adi   TEXT NOT NULL UNIQUE COLLATE NOCASE,
    sifre_hash      TEXT NOT NULL,
    ad_soyad        TEXT NOT NULL,
    rol             TEXT NOT NULL DEFAULT 'personel' CHECK(rol IN ('admin','mudur','kasiyer','personel','depocu')),
    email           TEXT,
    telefon         TEXT,
    aktif           INTEGER NOT NULL DEFAULT 1,
    son_giris       DATETIME,
    kayit_tarihi    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_updated    DATETIME DEFAULT CURRENT_TIMESTAMP,
    sync_status     TEXT DEFAULT 'synced',
    is_deleted      INTEGER DEFAULT 0,
    FOREIGN KEY(sube_id) REFERENCES subeler(id)
);

-- 3. Rol yetkileri (detaylı)
CREATE TABLE roller_yetki (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    kullanici_id INTEGER NOT NULL,
    yetki_kodu  TEXT NOT NULL,
    FOREIGN KEY(kullanici_id) REFERENCES kullanicilar(id) ON DELETE CASCADE,
    UNIQUE(kullanici_id, yetki_kodu)
);

-- 4. Kategoriler
CREATE TABLE kategoriler (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    ad              TEXT NOT NULL UNIQUE COLLATE NOCASE,
    ust_kategori_id INTEGER,
    sira            INTEGER DEFAULT 0,
    FOREIGN KEY(ust_kategori_id) REFERENCES kategoriler(id)
);

-- 5. Ürünler (ana tablo, tüm özelliklerle)
CREATE TABLE urunler (
    id                          INTEGER PRIMARY KEY AUTOINCREMENT,
    global_id                   TEXT UNIQUE,
    kod                         TEXT UNIQUE COLLATE NOCASE,
    barkod                      TEXT UNIQUE COLLATE NOCASE,
    barkodlar                   TEXT,   -- JSON array
    urun_adi                    TEXT NOT NULL COLLATE NOCASE,
    alternatif_urun_adi         TEXT COLLATE NOCASE,
    birim_adi                   TEXT NOT NULL DEFAULT 'Adet',
    alis_fiyat                  REAL NOT NULL DEFAULT 0,
    alis_fiyat_kdv_dahil        REAL NOT NULL DEFAULT 0,
    satis_fiyati                REAL NOT NULL DEFAULT 0,
    stok                        REAL NOT NULL DEFAULT 0,
    toplam_maliyet              REAL NOT NULL DEFAULT 0,
    toplam_stok                 REAL NOT NULL DEFAULT 0,
    alis_kdv_oran               REAL NOT NULL DEFAULT 18,
    kdv_oran                    TEXT NOT NULL DEFAULT '18' CHECK(kdv_oran IN ('0','1','8','10','18','20')),
    ana_grup                    TEXT COLLATE NOCASE,
    alt_grup                    TEXT COLLATE NOCASE,
    aktif                       INTEGER NOT NULL DEFAULT 1,
    seri_no_takibi              INTEGER NOT NULL DEFAULT 0,
    lot_takibi                  INTEGER NOT NULL DEFAULT 0,
    lot_no                      TEXT,
    son_kullanma_tarihi         DATE,
    alan1                       TEXT,
    alan2                       TEXT,
    alan3                       TEXT,
    alan4                       TEXT,
    para_birimi                 TEXT NOT NULL DEFAULT 'TRY',
    indirim_orani               REAL NOT NULL DEFAULT 0,
    otomatik_indirim            INTEGER NOT NULL DEFAULT 0,
    son_alim_indirim_oran       REAL DEFAULT 0,
    minimum_stok                REAL NOT NULL DEFAULT 0,
    maksimum_stok               REAL NOT NULL DEFAULT 0,
    maksimum_satir_miktari      REAL DEFAULT 0,
    renk                        TEXT,
    beden                       TEXT,
    sube                        TEXT,
    resim_yolu                  TEXT,
    uretici                     TEXT COLLATE NOCASE,
    marka                       TEXT COLLATE NOCASE,
    model                       TEXT,
    grup_sorumlusu              TEXT,
    mensei                      TEXT,
    raf_numarasi                TEXT,
    raf_omru                    INTEGER,
    plu_numarasi                TEXT,
    puan_orani                  REAL DEFAULT 0,
    muhasebe_kodu               TEXT,
    muafiyet_kodu               TEXT,
    resmi_bakiye                REAL DEFAULT 0,
    barkod_olcu_birimi          TEXT,
    en                          REAL DEFAULT 0,
    boy                         REAL DEFAULT 0,
    yukseklik                   REAL DEFAULT 0,
    agirlik                     REAL DEFAULT 0,
    eski_kodu                   TEXT,
    kart_tipi                   TEXT DEFAULT 'Standart' CHECK(kart_tipi IN ('Standart','Hizmet','Masraf','Set','Demirbaş')),
    seri_numarasi               TEXT,
    fiyat_guncelleme_tarih      DATETIME,
    fiyat_guncelleyen_kullanici TEXT,
    barkod_yazdirma_tarih       DATETIME,
    barkod_yazdiran_kullanici   TEXT,
    maliyet_guncelleme_tarih    DATETIME,
    maliyet_guncelleyen_kullanici TEXT,
    guncelleme_tarihi           DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    kayit_tarihi                DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    guncelleyen_kullanici       TEXT,
    kaydeden_kullanici          TEXT,
    last_updated                DATETIME DEFAULT CURRENT_TIMESTAMP,
    sync_status                 TEXT DEFAULT 'synced',
    is_deleted                  INTEGER DEFAULT 0,
    FOREIGN KEY(ana_grup) REFERENCES kategoriler(ad)
);

-- 6. Fiyat geçmişi
CREATE TABLE fiyat_gecmis (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    urun_id         INTEGER NOT NULL,
    eski_alis       REAL,
    yeni_alis       REAL,
    eski_satis      REAL,
    yeni_satis      REAL,
    degistiren      TEXT,
    tarih           DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(urun_id) REFERENCES urunler(id) ON DELETE CASCADE
);

-- 7. Lot/Seri takip
CREATE TABLE lot_seri (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    global_id           TEXT UNIQUE,
    urun_id             INTEGER NOT NULL,
    lot_no              TEXT,
    seri_no             TEXT,
    miktar              REAL NOT NULL DEFAULT 0,
    son_kullanma_tarihi DATE,
    uretim_tarihi       DATE,
    tedarikci_cari_id   INTEGER,
    aciklama            TEXT,
    aktif               INTEGER NOT NULL DEFAULT 1,
    kayit_tarihi        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(urun_id) REFERENCES urunler(id) ON DELETE CASCADE
);

-- 8. Cari (Müşteri/Tedarikçi)
CREATE TABLE cari (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    global_id           TEXT UNIQUE,
    cari_kodu           TEXT UNIQUE COLLATE NOCASE,
    unvan               TEXT NOT NULL COLLATE NOCASE,
    cari_tipi           TEXT NOT NULL CHECK(cari_tipi IN ('Müşteri','Tedarikçi','Hem Müşteri Hem Tedarikçi')),
    telefon             TEXT,
    telefon2            TEXT,
    email               TEXT,
    email2              TEXT,
    vergi_dairesi       TEXT,
    vergi_no            TEXT,
    tc_kimlik           TEXT,
    bakiye              REAL NOT NULL DEFAULT 0,
    limit_tutari        REAL NOT NULL DEFAULT 0,
    vade_gun            INTEGER DEFAULT 0,
    ana_grup            TEXT,
    alt_grup            TEXT,
    temsilci            TEXT,
    notlar              TEXT,
    web_sitesi          TEXT,
    aktif               INTEGER NOT NULL DEFAULT 1,
    olusturma_tarihi    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    guncelleyen         TEXT,
    sube_id             INTEGER,
    last_updated        DATETIME DEFAULT CURRENT_TIMESTAMP,
    sync_status         TEXT DEFAULT 'synced',
    is_deleted          INTEGER DEFAULT 0,
    FOREIGN KEY(sube_id) REFERENCES subeler(id)
);

-- 9. Cari adres
CREATE TABLE cari_adres (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    cari_id     INTEGER NOT NULL,
    adres_tipi  TEXT NOT NULL DEFAULT 'Fatura' CHECK(adres_tipi IN ('Fatura','Teslimat','Merkez','Diğer')),
    adres       TEXT NOT NULL,
    il          TEXT,
    ilce        TEXT,
    posta_kodu  TEXT,
    varsayilan  INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY(cari_id) REFERENCES cari(id) ON DELETE CASCADE
);

-- 10. Cari hareket
CREATE TABLE cari_hareket (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    cari_id     INTEGER NOT NULL,
    tarih       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fis_tipi    TEXT NOT NULL CHECK(fis_tipi IN ('Satış','Alış','Tahsilat','Ödeme','İade','İskonto','Açılış','Diğer')),
    fis_id      INTEGER,
    fis_no      TEXT,
    aciklama    TEXT NOT NULL,
    borc        REAL NOT NULL DEFAULT 0,
    alacak      REAL NOT NULL DEFAULT 0,
    bakiye      REAL,
    odeme_turu  TEXT,
    kullanici   TEXT,
    FOREIGN KEY(cari_id) REFERENCES cari(id) ON DELETE CASCADE
);

-- 11. Satışlar
CREATE TABLE satislar (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    global_id       TEXT UNIQUE,
    fis_no          TEXT UNIQUE,
    tarih           DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    cari_id         INTEGER,
    toplam_tutar    REAL NOT NULL DEFAULT 0,
    iskonto_tutar   REAL NOT NULL DEFAULT 0,
    iskonto_oran    REAL NOT NULL DEFAULT 0,
    kdv_tutar       REAL NOT NULL DEFAULT 0,
    genel_toplam    REAL NOT NULL DEFAULT 0,
    odenen_tutar    REAL NOT NULL DEFAULT 0,
    odeme_yontemi   TEXT NOT NULL DEFAULT 'Nakit' CHECK(odeme_yontemi IN ('Nakit','Kredi Kartı','Cari','Havale','Çek','Karma','QR')),
    fis_tipi        TEXT NOT NULL DEFAULT 'Satış' CHECK(fis_tipi IN ('Satış','İade','Teklif')),
    aciklama        TEXT,
    kargo_ucreti    REAL NOT NULL DEFAULT 0,
    kasiyer_id      INTEGER,
    vardiya_id      INTEGER,
    sube_id         INTEGER,
    iptal           INTEGER NOT NULL DEFAULT 0,
    iptal_tarihi    DATETIME,
    iptal_nedeni    TEXT,
    last_updated    DATETIME DEFAULT CURRENT_TIMESTAMP,
    sync_status     TEXT DEFAULT 'synced',
    is_deleted      INTEGER DEFAULT 0,
    FOREIGN KEY(cari_id)    REFERENCES cari(id),
    FOREIGN KEY(kasiyer_id) REFERENCES kullanicilar(id),
    FOREIGN KEY(sube_id)    REFERENCES subeler(id)
);

-- 12. Satış kalemleri
CREATE TABLE satis_kalem (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    satis_id        INTEGER NOT NULL,
    urun_id         INTEGER NOT NULL,
    urun_adi        TEXT NOT NULL,
    barkod          TEXT,
    miktar          REAL NOT NULL,
    birim_fiyat     REAL NOT NULL,
    iskonto_oran    REAL NOT NULL DEFAULT 0,
    iskonto_tutar   REAL NOT NULL DEFAULT 0,
    kdv_oran        REAL NOT NULL DEFAULT 18,
    kdv_tutar       REAL NOT NULL DEFAULT 0,
    net_fiyat       REAL NOT NULL DEFAULT 0,
    toplam_tutar    REAL NOT NULL DEFAULT 0,
    lot_id          INTEGER,
    seri_no         TEXT,
    FOREIGN KEY(satis_id) REFERENCES satislar(id) ON DELETE CASCADE,
    FOREIGN KEY(urun_id)  REFERENCES urunler(id),
    FOREIGN KEY(lot_id)   REFERENCES lot_seri(id)
);

-- 13. Stok hareketleri
CREATE TABLE stok_hareket (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    global_id       TEXT UNIQUE,
    urun_id         INTEGER NOT NULL,
    hareket_turu    TEXT NOT NULL CHECK(hareket_turu IN ('Giriş','Çıkış','Sayım','İade','Devir','Fire','Transfer')),
    miktar          REAL NOT NULL,
    onceki_stok     REAL NOT NULL DEFAULT 0,
    sonraki_stok    REAL NOT NULL DEFAULT 0,
    birim_maliyet   REAL DEFAULT 0,
    tarih           DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    referans_id     INTEGER,
    referans_turu   TEXT,
    lot_id          INTEGER,
    belge_turu      TEXT,
    aciklama        TEXT,
    kullanici_id    INTEGER,
    sube_id         INTEGER,
    FOREIGN KEY(urun_id)     REFERENCES urunler(id),
    FOREIGN KEY(kullanici_id) REFERENCES kullanicilar(id),
    FOREIGN KEY(lot_id)      REFERENCES lot_seri(id)
);

-- 14. Geçici sayım
CREATE TABLE gecici_sayim (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    urun_id     INTEGER NOT NULL UNIQUE,
    mevcut_stok REAL NOT NULL DEFAULT 0,
    yeni_stok   REAL NOT NULL DEFAULT 0,
    notlar      TEXT,
    kullanici_id INTEGER,
    FOREIGN KEY(urun_id)      REFERENCES urunler(id) ON DELETE CASCADE,
    FOREIGN KEY(kullanici_id) REFERENCES kullanicilar(id)
);

-- 15. İade
CREATE TABLE iade (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    satis_id        INTEGER,
    cari_id         INTEGER,
    fis_no          TEXT,
    tarih           DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    toplam_tutar    REAL NOT NULL DEFAULT 0,
    iade_nedeni     TEXT,
    durum           TEXT NOT NULL DEFAULT 'beklemede' CHECK(durum IN ('beklemede','onaylandi','reddedildi')),
    kasiyer_id      INTEGER,
    FOREIGN KEY(satis_id)   REFERENCES satislar(id),
    FOREIGN KEY(cari_id)    REFERENCES cari(id),
    FOREIGN KEY(kasiyer_id) REFERENCES kullanicilar(id)
);

-- 16. İade kalemleri
CREATE TABLE iade_kalem (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    iade_id     INTEGER NOT NULL,
    urun_id     INTEGER NOT NULL,
    urun_adi    TEXT NOT NULL,
    miktar      REAL NOT NULL,
    birim_fiyat REAL NOT NULL,
    toplam      REAL NOT NULL,
    FOREIGN KEY(iade_id) REFERENCES iade(id) ON DELETE CASCADE,
    FOREIGN KEY(urun_id) REFERENCES urunler(id)
);

-- 17. Tedarikçi siparişleri
CREATE TABLE tedarikci_siparisler (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    cari_id         INTEGER NOT NULL,
    siparis_no      TEXT UNIQUE,
    siparis_tarihi  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    teslim_tarihi   DATETIME,
    toplam_tutar    REAL NOT NULL DEFAULT 0,
    durum           TEXT NOT NULL DEFAULT 'beklemede' CHECK(durum IN ('beklemede','onaylandi','teslim_edildi','kismi','iptal')),
    notlar          TEXT,
    olusturan_id    INTEGER,
    FOREIGN KEY(cari_id)     REFERENCES cari(id),
    FOREIGN KEY(olusturan_id) REFERENCES kullanicilar(id)
);

-- 18. Tedarikçi sipariş kalemleri
CREATE TABLE tedarikci_siparis_kalem (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    siparis_id      INTEGER NOT NULL,
    urun_id         INTEGER NOT NULL,
    siparis_mik     REAL NOT NULL,
    teslim_mik      REAL NOT NULL DEFAULT 0,
    birim_fiyat     REAL NOT NULL,
    kdv_oran        REAL NOT NULL DEFAULT 18,
    toplam_tutar    REAL NOT NULL,
    FOREIGN KEY(siparis_id) REFERENCES tedarikci_siparisler(id) ON DELETE CASCADE,
    FOREIGN KEY(urun_id)    REFERENCES urunler(id)
);

-- 19. Faturalar (e-fatura entegrasyonlu)
CREATE TABLE faturalar (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    global_id           TEXT UNIQUE,
    fatura_no           TEXT UNIQUE,
    fatura_tipi         TEXT,
    satis_id            INTEGER,
    cari_id             INTEGER,
    sube_id             INTEGER,
    tarih               TEXT DEFAULT CURRENT_TIMESTAMP,
    duzenlenme_tarihi   TEXT,
    sevk_tarihi         TEXT,
    vade_tarihi         TEXT,
    malin_nereye        TEXT,
    teslim_eden         TEXT,
    teslim_alan         TEXT,
    toplam_ara_toplam   REAL,
    toplam_iskonto      REAL,
    toplam_kdv          REAL,
    genel_toplam        REAL,
    odenen_tutar        REAL DEFAULT 0,
    kalan_tutar         REAL DEFAULT 0,
    odeme_durumu        TEXT DEFAULT 'beklemede',
    e_fatura_uuid       TEXT,
    e_fatura_durum      TEXT DEFAULT 'hazir',
    e_fatura_html       TEXT,
    e_fatura_xml        TEXT,
    gonderim_tarihi     DATETIME,
    uygulama_yaniti     TEXT,
    html_icerik         TEXT,
    xml_icerik          TEXT,
    durum               TEXT DEFAULT 'aktif',
    created_at          TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at          TEXT DEFAULT CURRENT_TIMESTAMP
);

-- 20. Fatura detayları
CREATE TABLE fatura_detaylari (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    global_id       TEXT UNIQUE,
    fatura_id       INTEGER,
    urun_id         INTEGER,
    urun_adi        TEXT,
    barkod          TEXT,
    miktar          REAL,
    birim_fiyat     REAL,
    iskonto_orani   REAL DEFAULT 0,
    iskonto_tutari  REAL DEFAULT 0,
    kdv_orani       REAL,
    kdv_tutari      REAL,
    ara_toplam      REAL,
    toplam_tutar    REAL,
    lot_seri_no     TEXT,
    created_at      TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(fatura_id) REFERENCES faturalar(id)
);

-- 21. Promosyonlar (eski sistem, basit)
CREATE TABLE promosyonlar (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    urun_id             INTEGER NOT NULL,
    promosyon_adi       TEXT NOT NULL,
    iskonto_oran        REAL NOT NULL DEFAULT 0,
    iskonto_tutar       REAL NOT NULL DEFAULT 0,
    min_miktar          REAL DEFAULT 1,
    baslangic_tarihi    DATETIME,
    bitis_tarihi        DATETIME,
    aktif               INTEGER NOT NULL DEFAULT 1,
    FOREIGN KEY(urun_id) REFERENCES urunler(id) ON DELETE CASCADE
);

-- 22. Yeni gelişmiş promosyonlar
CREATE TABLE promosyon_tanim (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    global_id           TEXT UNIQUE,
    promosyon_adi       TEXT NOT NULL,
    promosyon_tipi      TEXT NOT NULL CHECK(promosyon_tipi IN ('indirim','hediye','kupon','sepet_indirim')),
    baslangic_tarihi    DATETIME,
    bitis_tarihi        DATETIME,
    aktif               INTEGER DEFAULT 1,
    tum_subeler         INTEGER DEFAULT 1,
    min_sepet_tutari    REAL DEFAULT 0,
    max_indirim_tutari  REAL DEFAULT 0,
    aciklama            TEXT,
    created_at          DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE promosyon_kosul (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    promosyon_id        INTEGER NOT NULL,
    kosul_tipi          TEXT NOT NULL CHECK(kosul_tipi IN ('urun','kategori','marka','cari_grup')),
    hedef_id            INTEGER,
    min_miktar          REAL DEFAULT 1,
    FOREIGN KEY(promosyon_id) REFERENCES promosyon_tanim(id) ON DELETE CASCADE
);

CREATE TABLE promosyon_aksiyon (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    promosyon_id        INTEGER NOT NULL,
    aksiyon_tipi        TEXT NOT NULL CHECK(aksiyon_tipi IN ('indirim_oran','indirim_tutar','hediye_urun','oto_kampanya')),
    deger               REAL,
    hediye_miktar       REAL DEFAULT 1,
    FOREIGN KEY(promosyon_id) REFERENCES promosyon_tanim(id) ON DELETE CASCADE
);

-- 23. Şube bazlı stok ve fiyat
CREATE TABLE sube_urun (
    urun_id         INTEGER NOT NULL,
    sube_id         INTEGER NOT NULL,
    stok            REAL NOT NULL DEFAULT 0,
    rezerve_stok    REAL NOT NULL DEFAULT 0,
    kritik_stok     REAL DEFAULT 0,
    satis_fiyati    REAL,
    alis_fiyati     REAL,
    raf_kodu        TEXT,
    son_guncelleme  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (urun_id, sube_id),
    FOREIGN KEY(urun_id) REFERENCES urunler(id) ON DELETE CASCADE,
    FOREIGN KEY(sube_id) REFERENCES subeler(id) ON DELETE CASCADE
);

-- 24. Şube bazlı fiyat geçmişi
CREATE TABLE sube_fiyat_gecmis (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    urun_id         INTEGER NOT NULL,
    sube_id         INTEGER NOT NULL,
    onceki_fiyat    REAL,
    yeni_fiyat      REAL,
    degisim_tarihi  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    degistiren_kullanici_id INTEGER,
    FOREIGN KEY(urun_id, sube_id) REFERENCES sube_urun(urun_id, sube_id)
);

-- 25. FIFO stok eşleştirme
CREATE TABLE stok_fifo (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    giris_hareket_id INTEGER NOT NULL,
    cikis_hareket_id INTEGER NOT NULL,
    kullanilan_miktar REAL NOT NULL,
    FOREIGN KEY(giris_hareket_id) REFERENCES stok_hareket(id),
    FOREIGN KEY(cikis_hareket_id) REFERENCES stok_hareket(id)
);

-- 26. Kasa hareketleri
CREATE TABLE kasa_hareketleri (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    hareket_tipi    TEXT NOT NULL CHECK(hareket_tipi IN ('Satış','İade','Gider','Tahsilat','Ödeme','AçılışKasa','KapanışKasa','Diğer')),
    tutar           REAL NOT NULL,
    bakiye_sonrasi  REAL,
    referans_id     INTEGER,
    referans_turu   TEXT,
    tarih           DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    aciklama        TEXT,
    kullanici_id    INTEGER,
    sube_id         INTEGER,
    FOREIGN KEY(kullanici_id) REFERENCES kullanicilar(id)
);

-- 27. Vardiyalar (kasa yönetimi)
CREATE TABLE vardiyalar (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    kullanici_id    INTEGER NOT NULL,
    sube_id         INTEGER,
    acilis_tarihi   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    kapanis_tarihi  DATETIME,
    acilis_kasasi   REAL NOT NULL DEFAULT 0,
    kapanis_kasasi  REAL,
    baslangic_bakiye REAL DEFAULT 0,
    bitis_bakiye    REAL,
    nakit_sayim     REAL,
    kart_toplam     REAL,
    fark            REAL,
    rapor_pdf       TEXT,
    notlar          TEXT,
    durum           TEXT NOT NULL DEFAULT 'acik' CHECK(durum IN ('acik','kapali')),
    FOREIGN KEY(kullanici_id) REFERENCES kullanicilar(id),
    FOREIGN KEY(sube_id)      REFERENCES subeler(id)
);

-- 28. Gider kategorileri
CREATE TABLE gider_kategoriler (
    id      INTEGER PRIMARY KEY AUTOINCREMENT,
    ad      TEXT NOT NULL UNIQUE
);

-- Varsayılan gider kategorileri
INSERT OR IGNORE INTO gider_kategoriler(ad) VALUES
    ('Kira'),('Elektrik'),('Su'),('Doğalgaz'),('İnternet'),
    ('Personel'),('Sigorta'),('Vergi'),('Bakım'),('Diğer');

-- 29. Giderler
CREATE TABLE giderler (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    kategori_id     INTEGER NOT NULL,
    tutar           REAL NOT NULL,
    aciklama        TEXT,
    tarih           DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    belge_no        TEXT,
    odeme_yontemi   TEXT NOT NULL DEFAULT 'Nakit' CHECK(odeme_yontemi IN ('Nakit','Banka','Kart','Çek')),
    cari_id         INTEGER,
    kullanici_id    INTEGER,
    sube_id         INTEGER,
    FOREIGN KEY(kategori_id) REFERENCES gider_kategoriler(id),
    FOREIGN KEY(cari_id)     REFERENCES cari(id),
    FOREIGN KEY(kullanici_id) REFERENCES kullanicilar(id)
);

-- 30. Bildirimler
CREATE TABLE bildirimler (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    baslik      TEXT NOT NULL,
    mesaj       TEXT NOT NULL,
    tip         TEXT NOT NULL DEFAULT 'bilgi' CHECK(tip IN ('bilgi','uyari','hata','basari','stok','odeme')),
    okundu      INTEGER NOT NULL DEFAULT 0,
    tarih       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    hedef_id    INTEGER,
    hedef_turu  TEXT,
    kullanici_id INTEGER,
    FOREIGN KEY(kullanici_id) REFERENCES kullanicilar(id)
);

-- 31. Yazıcılar
CREATE TABLE yazicilar (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    tur         TEXT NOT NULL CHECK(tur IN ('bluetooth','ag','usb')),
    adi         TEXT NOT NULL,
    cihaz_id    TEXT,
    ip          TEXT,
    port        INTEGER DEFAULT 9100,
    kategori    TEXT NOT NULL DEFAULT 'fis' CHECK(kategori IN ('fis','etiket','a4')),
    varsayilan  INTEGER NOT NULL DEFAULT 0,
    aktif       INTEGER NOT NULL DEFAULT 1,
    kayit_tarihi DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- 32. Ayarlar
CREATE TABLE ayarlar (
    anahtar     TEXT PRIMARY KEY,
    deger       TEXT NOT NULL,
    aciklama    TEXT,
    guncelleme  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT OR IGNORE INTO ayarlar(anahtar, deger, aciklama) VALUES
    ('firma_adi',       'MarketPlus',   'Firma adı'),
    ('firma_adres',     '',             'Firma adresi'),
    ('firma_telefon',   '',             'Firma telefonu'),
    ('firma_vergi_no',  '',             'Vergi numarası'),
    ('kdv_orani',       '18',           'Varsayılan KDV oranı'),
    ('para_birimi',     'TRY',          'Para birimi'),
    ('tema',            'light',        'Uygulama teması'),
    ('dil',             'tr',           'Uygulama dili'),
    ('otomatik_yedek',  '1',            'Otomatik yedekleme'),
    ('fis_alt_yazi',    '',             'Fiş alt yazısı'),
    ('min_stok_uyari',  '1',            'Minimum stok uyarısı');

-- 33. Fiş numara serisi (şube bazlı)
CREATE TABLE fis_seri (
    sube_id         INTEGER NOT NULL,
    fis_tipi        TEXT NOT NULL CHECK(fis_tipi IN ('satis','iade','alim','transfer')),
    son_fis_no      INTEGER DEFAULT 0,
    PRIMARY KEY (sube_id, fis_tipi),
    FOREIGN KEY(sube_id) REFERENCES subeler(id)
);

-- 34. Rol tabanlı yetkiler (genel)
CREATE TABLE rol_yetkileri (
    rol             TEXT NOT NULL,
    tablo_adi       TEXT NOT NULL,
    yetki_turu      TEXT NOT NULL CHECK(yetki_turu IN ('okuma','yazma','guncelleme','silme')),
    PRIMARY KEY (rol, tablo_adi, yetki_turu)
);

INSERT OR IGNORE INTO rol_yetkileri VALUES
    ('admin','*','okuma'),('admin','*','yazma'),('admin','*','guncelleme'),('admin','*','silme'),
    ('mudur','urunler','okuma'),('mudur','urunler','yazma'),('mudur','urunler','guncelleme'),
    ('mudur','cari','okuma'),('mudur','cari','yazma'),
    ('kasiyer','satislar','okuma'),('kasiyer','satislar','yazma');

-- 35. Günlük rapor özet tablosu (materyalize görünüm)
CREATE TABLE gunluk_rapor_ozet (
    rapor_tarihi       DATE PRIMARY KEY,
    toplam_satis_tutar REAL,
    toplam_iade_tutar  REAL,
    toplam_gider       REAL,
    nakit_tahsilat     REAL,
    kart_tahsilat      REAL,
    cari_tahsilat      REAL,
    kasa_son_bakiye    REAL,
    olusturma_zamani   DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- 36. Senkronizasyon kuyruğu (offline-first)
CREATE TABLE sync_queue (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    tablo_adi       TEXT NOT NULL,
    kayit_global_id TEXT,
    kayit_id        INTEGER,
    islem_tipi      TEXT NOT NULL CHECK(islem_tipi IN ('INSERT','UPDATE','DELETE')),
    veri_json       TEXT NOT NULL,
    deneme_sayisi   INTEGER DEFAULT 0,
    son_deneme      DATETIME,
    durum           TEXT DEFAULT 'beklemede' CHECK(durum IN ('beklemede','gonderildi','hata')),
    created_at      DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- 37. Senkronizasyon meta verisi
CREATE TABLE sync_meta (
    tablo_adi       TEXT PRIMARY KEY,
    son_senkron     DATETIME,
    son_id          INTEGER,
    deleted_records TEXT
);

-- ===================================================================
--  TRIGGER'LAR
-- ===================================================================
-- Ürün güncelleme tarihi
CREATE TRIGGER IF NOT EXISTS trg_urun_guncelle AFTER UPDATE ON urunler
BEGIN
    UPDATE urunler SET guncelleme_tarihi = CURRENT_TIMESTAMP, last_updated = CURRENT_TIMESTAMP
    WHERE id = NEW.id;
END;

-- Fiyat değişince geçmişe kayıt
CREATE TRIGGER IF NOT EXISTS trg_fiyat_gecmis AFTER UPDATE OF alis_fiyat, satis_fiyati ON urunler
WHEN OLD.alis_fiyat <> NEW.alis_fiyat OR OLD.satis_fiyati <> NEW.satis_fiyati
BEGIN
    INSERT INTO fiyat_gecmis(urun_id, eski_alis, yeni_alis, eski_satis, yeni_satis, degistiren, tarih)
    VALUES(NEW.id, OLD.alis_fiyat, NEW.alis_fiyat, OLD.satis_fiyati, NEW.satis_fiyati, NEW.fiyat_guncelleyen_kullanici, CURRENT_TIMESTAMP);
END;

-- Satış sonrası cari bakiyesi
CREATE TRIGGER IF NOT EXISTS trg_satis_cari_bakiye AFTER INSERT ON satislar
WHEN NEW.cari_id IS NOT NULL AND NEW.fis_tipi = 'Satış'
BEGIN
    UPDATE cari SET bakiye = bakiye + NEW.genel_toplam - NEW.odenen_tutar WHERE id = NEW.cari_id;
END;

-- İade onaylanınca cari bakiyesi
CREATE TRIGGER IF NOT EXISTS trg_iade_cari_bakiye AFTER UPDATE OF durum ON iade
WHEN NEW.durum = 'onaylandi' AND OLD.durum <> 'onaylandi' AND NEW.cari_id IS NOT NULL
BEGIN
    UPDATE cari SET bakiye = bakiye - NEW.toplam_tutar WHERE id = NEW.cari_id;
END;

-- ===================================================================
--  İNDEX'LER (performans)
-- ===================================================================
CREATE INDEX IF NOT EXISTS idx_urun_barkod ON urunler(barkod);
CREATE INDEX IF NOT EXISTS idx_urun_kod ON urunler(kod);
CREATE INDEX IF NOT EXISTS idx_urun_adi ON urunler(urun_adi);
CREATE INDEX IF NOT EXISTS idx_urun_ana_grup ON urunler(ana_grup);
CREATE INDEX IF NOT EXISTS idx_urun_alt_grup ON urunler(alt_grup);
CREATE INDEX IF NOT EXISTS idx_urun_marka ON urunler(marka);
CREATE INDEX IF NOT EXISTS idx_urun_aktif ON urunler(aktif);
CREATE INDEX IF NOT EXISTS idx_urun_stok ON urunler(stok);
CREATE INDEX IF NOT EXISTS idx_urun_raf ON urunler(raf_numarasi);
CREATE INDEX IF NOT EXISTS idx_urun_kayit ON urunler(kayit_tarihi);
CREATE INDEX IF NOT EXISTS idx_urun_last_updated ON urunler(last_updated);

CREATE INDEX IF NOT EXISTS idx_fiyat_gecmis_urun ON fiyat_gecmis(urun_id);
CREATE INDEX IF NOT EXISTS idx_fiyat_gecmis_tarih ON fiyat_gecmis(tarih);

CREATE INDEX IF NOT EXISTS idx_lot_urun ON lot_seri(urun_id);
CREATE INDEX IF NOT EXISTS idx_lot_no ON lot_seri(lot_no);
CREATE INDEX IF NOT EXISTS idx_lot_seri_no ON lot_seri(seri_no);
CREATE INDEX IF NOT EXISTS idx_lot_son_kullanma ON lot_seri(son_kullanma_tarihi);

CREATE INDEX IF NOT EXISTS idx_cari_unvan ON cari(unvan);
CREATE INDEX IF NOT EXISTS idx_cari_kodu ON cari(cari_kodu);
CREATE INDEX IF NOT EXISTS idx_cari_tipi ON cari(cari_tipi);
CREATE INDEX IF NOT EXISTS idx_cari_aktif ON cari(aktif);

CREATE INDEX IF NOT EXISTS idx_carih_cari ON cari_hareket(cari_id);
CREATE INDEX IF NOT EXISTS idx_carih_tarih ON cari_hareket(tarih);
CREATE INDEX IF NOT EXISTS idx_carih_fis_tipi ON cari_hareket(fis_tipi);

CREATE INDEX IF NOT EXISTS idx_satis_tarih ON satislar(tarih);
CREATE INDEX IF NOT EXISTS idx_satis_cari ON satislar(cari_id);
CREATE INDEX IF NOT EXISTS idx_satis_fis_no ON satislar(fis_no);
CREATE INDEX IF NOT EXISTS idx_satis_kasiyer ON satislar(kasiyer_id);
CREATE INDEX IF NOT EXISTS idx_satis_vardiya ON satislar(vardiya_id);
CREATE INDEX IF NOT EXISTS idx_satis_iptal ON satislar(iptal);
CREATE INDEX IF NOT EXISTS idx_satis_last_updated ON satislar(last_updated);

CREATE INDEX IF NOT EXISTS idx_satisk_satis ON satis_kalem(satis_id);
CREATE INDEX IF NOT EXISTS idx_satisk_urun ON satis_kalem(urun_id);
CREATE INDEX IF NOT EXISTS idx_satisk_barkod ON satis_kalem(barkod);

CREATE INDEX IF NOT EXISTS idx_stokh_urun ON stok_hareket(urun_id);
CREATE INDEX IF NOT EXISTS idx_stokh_tarih ON stok_hareket(tarih);
CREATE INDEX IF NOT EXISTS idx_stokh_tur ON stok_hareket(hareket_turu);

CREATE INDEX IF NOT EXISTS idx_iade_satis ON iade(satis_id);
CREATE INDEX IF NOT EXISTS idx_iade_cari ON iade(cari_id);
CREATE INDEX IF NOT EXISTS idx_iade_tarih ON iade(tarih);
CREATE INDEX IF NOT EXISTS idx_iade_durum ON iade(durum);

CREATE INDEX IF NOT EXISTS idx_promo_urun ON promosyonlar(urun_id);
CREATE INDEX IF NOT EXISTS idx_promo_aktif ON promosyonlar(aktif);

CREATE INDEX IF NOT EXISTS idx_promosyon_tarih ON promosyon_tanim(baslangic_tarihi, bitis_tarihi);

CREATE INDEX IF NOT EXISTS idx_sube_urun_stok ON sube_urun(sube_id, stok);

CREATE INDEX IF NOT EXISTS idx_gider_tarih ON giderler(tarih);
CREATE INDEX IF NOT EXISTS idx_gider_kategori ON giderler(kategori_id);

CREATE INDEX IF NOT EXISTS idx_kasa_tarih ON kasa_hareketleri(tarih);
CREATE INDEX IF NOT EXISTS idx_kasa_tipi ON kasa_hareketleri(hareket_tipi);

CREATE INDEX IF NOT EXISTS idx_vardiya_kullanici ON vardiyalar(kullanici_id);
CREATE INDEX IF NOT EXISTS idx_vardiya_durum ON vardiyalar(durum);

CREATE INDEX IF NOT EXISTS idx_tedsip_cari ON tedarikci_siparisler(cari_id);
CREATE INDEX IF NOT EXISTS idx_tedsip_durum ON tedarikci_siparisler(durum);

CREATE INDEX IF NOT EXISTS idx_bildiri_okundu ON bildirimler(okundu);
CREATE INDEX IF NOT EXISTS idx_bildiri_tarih ON bildirimler(tarih);

CREATE INDEX IF NOT EXISTS idx_sync_queue_durum ON sync_queue(durum);
CREATE INDEX IF NOT EXISTS idx_sync_queue_tablo ON sync_queue(tablo_adi);

-- ===================================================================
--  GÖRÜNÜMLER (View) – hızlı sorgular için
-- ===================================================================
CREATE VIEW IF NOT EXISTS v_urun_stok AS
SELECT
    u.id, u.kod, u.barkod, u.urun_adi, u.ana_grup, u.alt_grup,
    u.marka, u.birim_adi, u.stok, u.minimum_stok, u.maksimum_stok,
    u.alis_fiyat, u.satis_fiyati,
    CASE WHEN u.stok <= u.minimum_stok THEN 1 ELSE 0 END AS kritik_stok
FROM urunler u WHERE u.aktif = 1;

CREATE VIEW IF NOT EXISTS v_cari_bakiye AS
SELECT c.id, c.cari_kodu, c.unvan, c.cari_tipi, c.telefon, c.bakiye,
       c.limit_tutari, c.limit_tutari - c.bakiye AS kullanilabilir_limit, c.aktif
FROM cari c;

CREATE VIEW IF NOT EXISTS v_bugun_satis AS
SELECT s.id, s.fis_no, s.tarih, c.unvan AS musteri, s.genel_toplam,
       s.odenen_tutar, s.kalan_tutar, s.odeme_yontemi, k.ad_soyad AS kasiyer
FROM satislar s
LEFT JOIN cari c ON s.cari_id = c.id
LEFT JOIN kullanicilar k ON s.kasiyer_id = k.id
WHERE DATE(s.tarih) = DATE('now') AND s.iptal = 0;

CREATE VIEW IF NOT EXISTS v_kritik_stok AS
SELECT u.id, u.barkod, u.urun_adi, u.ana_grup, u.stok, u.minimum_stok,
       u.minimum_stok - u.stok AS eksik_miktar
FROM urunler u
WHERE u.aktif = 1 AND u.stok <= u.minimum_stok
ORDER BY eksik_miktar DESC;

CREATE VIEW IF NOT EXISTS v_gun_sonu_ozet AS
SELECT DATE(s.tarih) AS gun, COUNT(*) AS satis_sayisi, SUM(s.genel_toplam) AS toplam_ciro,
       SUM(s.iskonto_tutar) AS toplam_iskonto, SUM(s.kdv_tutar) AS toplam_kdv,
       SUM(CASE WHEN s.odeme_yontemi='Nakit' THEN s.odenen_tutar ELSE 0 END) AS nakit,
       SUM(CASE WHEN s.odeme_yontemi='Kredi Kartı' THEN s.odenen_tutar ELSE 0 END) AS kart,
       SUM(CASE WHEN s.odeme_yontemi='Cari' THEN s.odenen_tutar ELSE 0 END) AS cari_tahsilat
FROM satislar s WHERE s.iptal = 0 GROUP BY DATE(s.tarih) ORDER BY gun DESC;

-- ===================================================================
--  VARSAYILAN VERİLER
-- ===================================================================
INSERT OR IGNORE INTO kullanicilar(kullanici_adi, sifre_hash, ad_soyad, rol)
VALUES('admin', '03ac674216f3e15c761ee1a5e255f067953623c8b388b4459e13f978d7c846f4', 'Sistem Yöneticisi', 'admin');

INSERT OR IGNORE INTO subeler(sube_kodu, sube_adi) VALUES('MERKEZ', 'Merkez Şube');

INSERT OR IGNORE INTO kategoriler(ad) VALUES
    ('Gıda'),('İçecek'),('Temizlik'),('Kişisel Bakım'),
    ('Elektronik'),('Kırtasiye'),('Ev & Yaşam'),('Diğer');
-- ===================================================================
-- TÜM TABLOLAR IF NOT EXISTS İLE GÜVENLİ OLUŞTURMA
-- (Daha önce varsa hata vermez, sadece yoksa oluşturur)
-- ===================================================================

-- 36. Senkronizasyon kuyruğu
CREATE TABLE IF NOT EXISTS sync_queue (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    tablo_adi       TEXT NOT NULL,
    kayit_global_id TEXT,
    kayit_id        INTEGER,
    islem_tipi      TEXT NOT NULL CHECK(islem_tipi IN ('INSERT','UPDATE','DELETE')),
    veri_json       TEXT NOT NULL,
    deneme_sayisi   INTEGER DEFAULT 0,
    son_deneme      DATETIME,
    durum           TEXT DEFAULT 'beklemede' CHECK(durum IN ('beklemede','gonderildi','hata')),
    created_at      DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- 37. Senkronizasyon meta verisi
CREATE TABLE IF NOT EXISTS sync_meta (
    tablo_adi       TEXT PRIMARY KEY,
    son_senkron     DATETIME,
    son_id          INTEGER,
    deleted_records TEXT
);
-- ===================================================================
--  BİTTİ
-- ===================================================================