// lib/veri/database/migrasyon_yonetici_v12_v36.dart
// migrasyon_yonetici.dart'ın parçası — bkz. migrasyon_yonetici_v1_v12.dart
// başındaki not.
part of 'migrasyon_yonetici.dart';

// ==================== v12 -> v13 (Masa Detay + Adisyon log) ====================
Future<void> _v12denV13e(Database db) async {
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
Future<void> _v13denV14e(Database db) async {
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
Future<void> _v14denV15e(Database db) async {
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
Future<void> _v15denV16ya(Database db) async {
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
Future<void> _v16denV17ye(Database db) async {
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
Future<void> _v17denV18e(Database db) async {
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
Future<void> _v18denV19a(Database db) async {
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
Future<void> _v19denV20ye(Database db) async {
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
Future<void> _v20denV21e(Database db) async {
  await DovizSemasi.olustur(db);
}

// ==================== v21 -> v22 (PLU sıralama kalıcılığı) ====================
Future<void> _v21denV22ye(Database db) async {
  await _calistir(db,
      'ALTER TABLE urunler ADD COLUMN plu_sira INTEGER NOT NULL DEFAULT 0');
}

// ==================== v22 -> v23 (Personel iletişim bilgileri) ====================
Future<void> _v22denV23e(Database db) async {
  await _calistir(db, 'ALTER TABLE personel ADD COLUMN telefon TEXT');
  await _calistir(db, 'ALTER TABLE personel ADD COLUMN email TEXT');
}

// ==================== v23 -> v24 (Cari: e-Fatura mükellefi durumu) ====================
Future<void> _v23denV24e(Database db) async {
  await _calistir(db, "ALTER TABLE cari ADD COLUMN mukellef_durumu TEXT");
  await _calistir(
      db, "ALTER TABLE cari ADD COLUMN mukellef_sorgu_tarihi TEXT");
}

// ==================== v24 -> v25 (Fatura: ödeme şekli) ====================
Future<void> _v24denV25e(Database db) async {
  await _calistir(db, "ALTER TABLE faturalar ADD COLUMN odeme_sekli TEXT");
}

// ==================== v25 -> v26 (Ürün: döviz bazlı fiyatlandırma) ====================
Future<void> _v25denV26ya(Database db) async {
  await _calistir(db, "ALTER TABLE urunler ADD COLUMN doviz_kodu TEXT");
  await _calistir(db, "ALTER TABLE urunler ADD COLUMN doviz_tutari REAL");
}

// ==================== v26 -> v27 (Şifre güvenliği: tuzlu hash) ====================
Future<void> _v26danV27ye(Database db) async {
  // 'tuz' (salt) NULL bırakılıyor — mevcut kullanıcılar bir sonraki
  // başarılı girişte OTOMATİK olarak yeni, tuzlu şemaya yükseltilir
  // (bkz. KullaniciDeposu.girisKontrol). Kimsenin şifresini sıfırlamaya
  // gerek yok, kullanıcı hiçbir şey fark etmez.
  await _calistir(db, "ALTER TABLE kullanicilar ADD COLUMN tuz TEXT");
}

// ==================== v27 -> v28 (GİB şifresi güvenli depolamaya taşınıyor) ====================
Future<void> _v27denV28e(Database db) async {
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
Future<void> _v28denV29a(Database db) async {
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
Future<void> _v29danV30a(Database db) async {
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
Future<void> _v30danV31e(Database db) async {
  try {
    await _calistir(db, "ALTER TABLE urunler ADD COLUMN resim_url TEXT");
  } catch (_) {
    /* kolon zaten eklenmişse SQLite hata verir — migrasyon devam etmeli */
  }
}

// ==================== v31 -> v32 (QR menü ürün seçimi) ====================
Future<void> _v31denV32ye(Database db) async {
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
Future<void> _v32denV33e(Database db) async {
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
Future<void> _v33denV34e(Database db) async {
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
Future<void> _v34denV35e(Database db) async {
  await _calistir(
      db, "ALTER TABLE borc_odemeler ADD COLUMN last_updated DATETIME");
  await _calistir(
      db, "ALTER TABLE adisyon_log ADD COLUMN last_updated DATETIME");
}

// ==================== v35 -> v36 ====================
// Kullanıcı isteği: "audit log (kim ne yaptı ne zaman)" ve
// "bildirim merkezi" (stok azaldı, borç günü geldi vb.) sistemleri.
Future<void> _v35denV36e(Database db) async {
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

