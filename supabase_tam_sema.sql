-- ═══════════════════════════════════════════════════════════════════════════
-- MARKETPLUS / BARKOPRO — TEK PARÇA BULUT ŞEMASI (PostgreSQL / Supabase)
-- Birleştirme: 2026-09-27
-- ═══════════════════════════════════════════════════════════════════════════
-- Bu dosya, daha önce ayrı ayrı çalıştırılan 7 dosyanın YERİNE geçer:
--   1) supabase tablolar önemli buluttaki tablolar.txt  → BÖLÜM A
--   2) supabase_fatura_seri_bloklari.sql                → BÖLÜM B
--   3) supabase_fatura_blok_tahsis_fix.sql              → BÖLÜM C'ye dahil (yerini C aldı)
--   4) supabase_terminal_aktif_kontrolu.sql             → BÖLÜM C
--   5) supabase_fatura_blok_tahsis_yetki_kisitla.sql    → BÖLÜM D
--   6) supabase_rls_sertlestirme.sql                    → BÖLÜM E
--   7) supabase_arsiv_plani.sql                         → BÖLÜM F
--   (2026-09-28) İşletme hesabıyla güvenli giriş        → BÖLÜM G
--
-- KULLANIM: Dosyanın TAMAMINI SQL Editor'e yapıştırıp çalıştırın. Her bölüm
-- "IF NOT EXISTS / CREATE OR REPLACE / DROP ... IF EXISTS" ile yazıldığı için
-- dolu bir veritabanında TEKRAR çalıştırmak güvenlidir: veri silmez, eksik
-- tablo/sütun/indeks/fonksiyonu tamamlar. Yeni bir projede sıfırdan kurulum
-- için de aynı dosya kullanılır.
--
-- BAŞKA BİR BULUTTA (Supabase dışı saf PostgreSQL) KULLANIM:
--   • BÖLÜM A–D ve F standart PostgreSQL'dir.
--   • 'anon', 'authenticated', 'service_role' Supabase'e özgü rollerdir.
--     Saf PostgreSQL'de bu rollere referans veren GRANT/REVOKE/POLICY
--     satırları "role does not exist" hatası verir — önce şunu çalıştırın:
--       CREATE ROLE anon NOLOGIN; CREATE ROLE authenticated NOLOGIN;
--       CREATE ROLE service_role NOLOGIN BYPASSRLS;
--     (ya da BÖLÜM E'yi ve RLS satırlarını atlayın).
--   • Uygulama tabloya PostgREST (REST) arayüzüyle bağlanır; Supabase dışı
--     bir sunucuda PostgREST'in kurulu olması gerekir.
--
-- ⚠️ Bölüm E öncesi: uygulamada kayıtlı anahtarın "sb_secret_" (service_role)
-- olduğundan emin olun — ayrıntı Bölüm E başlığında.
-- ⚠️ 2026-09-28: Bölüm G ile cihazlar işletme hesabıyla giriş yapar; Bölüm G
-- başlığındaki panel adımlarını (kayıt kapatma, kullanıcı ekleme) önce yapın.
-- ═══════════════════════════════════════════════════════════════════════════



-- ###########################################################################
-- BÖLÜM A — ANA ŞEMA: tablolar, sütunlar, kısıt temizliği, UNIQUE, indeks, RLS
-- (kaynak: supabase tablolar önemli buluttaki tablolar.txt)
-- ###########################################################################

-- ═══════════════════════════════════════════════════════════════════════
-- MARKETPLUS — SUPABASE ŞEMASI  (KENDİ KENDİNİ ONARAN SÜRÜM)
-- 68 senkron tablosu  ·  29.07.2026, son güncelleme 2026-09-21 (banka_hareketler/kredi_karti_hareket referans_id/referans_turu — cari hareket iptali artık bu tarafları da tersine çevirebiliyor)
--
-- 2026-09-20 GÜNCELLEMESİ — ERP Denetim Madde 21 & 22 (Supabase Arşiv
-- Mimarisi). Bu dosyaya YENİ TABLO EKLENMEDİ — yüksek hacimli hareket
-- tabloları (satislar, satis_kalem, stok_hareket, cari_hareket,
-- kasa_hareketleri, banka_hareketler) için 6 ayrı, salt-okunur *_arsiv
-- tablosu + arşivleme fonksiyonları + RLS AYRI bir dosyada:
-- 'supabase_arsiv_plani.sql' (proje kök dizini). Bilinçli olarak ayrı
-- tutuldu — bu script, yerel Yıl Sonu Devir motoru bir dönemi TAMAMEN
-- kapatıp arşivledikten SONRA, elle/manuel çalıştırılan opsiyonel bir
-- ek adımdır; bu ana şema dosyasının "her zaman baştan sona çalıştır"
-- modeline (BÖLÜM 1-9) uymuyor. Aktif tablolara (satislar, stok_hareket
-- vb.) TEK SATIR bile dokunmuyor — sadece ekliyor.
--
-- 2026-09-20 GÜNCELLEMESİ — ERP Denetim Madde 12 (Kasa Kapanış — Müdür
-- Onayı). vardiyalar tablosuna 2 yeni sütun: onaylayan_kullanici_id,
-- onaylanma_tarihi (yerel SQLite migrasyon v68→v69 ile BİREBİR aynı).
-- Vardiyayı kapatan kişi Müdür/Admin değilse, kapanış anında bir
-- yöneticinin kimlik bilgileriyle onayladığı kullanıcı burada tutulur.
--
-- 2026-09-16 GÜNCELLEMESİ — Yıl Sonu Devir / Dönem Kapatma / Arşivleme
-- sistemi FAZ 1 (kullanıcı onaylı mimari plan raporu, ERP_DENETIM_
-- KURALLARI.md.txt). 7 yeni tablo eklendi: donemler,
-- donem_sube_durumlari, devir_checkpoint, stok_kapanis_snapshot,
-- cari_kapanis_snapshot, kasa_kapanis_snapshot, banka_kapanis_snapshot.
-- Yerel SQLite tarafında donem_semasi.dart (fresh install) + migrasyon
-- v67→v68 ile BİREBİR aynı yapı. Devir motoru mantığı
-- (DevirYoneticiServisi) henüz YOK — bu turda sadece şema + DonemDeposu/
-- DevirCheckpointDeposu CRUD iskeleti eklendi. Kod tarafında
-- supabase_sync_servisi.dart'ın senkron listelerine de eklenmesi
-- GEREKİYOR — bkz. protokol_supabase_sema_guncel_tutma hafıza notu
-- madde 3 (bu oturumda yapıldı, bkz. commit geçmişi).
--
-- 2026-09-15 GÜNCELLEMESİ — Derin denetim P1 #11: fis_seri (fiş/
-- irsaliye/sipariş numara sayacı) tablosu senkron sisteminin TAMAMEN
-- DIŞINDAYDI (yerel DB v64). Bu tablonun global_id'si yok — doğal
-- anahtarı (sube_id, fis_tipi). UNIQUE (sube_id, fis_tipi) + BEFORE
-- UPDATE tetikleyicisi (trg_fis_seri_max_koru — son_fis_no'nun ASLA
-- küçülmemesini garanti eder, GREATEST) eklendi. Bu tablo BİLEREK
-- projenin genel _tabloSirasi (supabase_sync_servisi.dart) akışının
-- DIŞINDA tutuluyor — bir SAYAÇ için "son güncelleyen kazanır"
-- semantiği yanlıştır, kod tarafı (veritabani.dart) kendi özel
-- push/MAX-birleştirme mantığını kullanıyor.
--
-- 2026-09-13 GÜNCELLEMESİ — yerel uygulama şemasıyla karşılaştırılıp
-- 3 sapma bulundu ve düzeltildi:
--   • onay_talepleri tablosu HİÇ yoktu (Onay Merkezi / FAZ 9, DB v57).
--     Kod tarafında da supabase_sync_servisi.dart'ın senkron listelerinde
--     (_tabloSirasi ve kardeşleri) hiç yer almıyordu — yani bu tablo bu
--     dosya güncellenmiş olsa bile ASLA buluta gitmeyecekti. İkisi de
--     bu oturumda düzeltildi (bkz. commit geçmişi).
--   • kasa_hareketleri.odeme_yontemi eksikti (DB v56, vardiya/kasa
--     mutabakatı — Kart/Nakit ayrımı).
--   • kullanicilar.bayi_cari_id eksikti (DB v58, B2B Bayi Portalı).
--
-- 2026-09-13 İKİNCİ GÜNCELLEME — "Borç Silme" özelliği eklenirken
-- bulundu: borclar.is_deleted sütunu yerel YÜKSELTME (migrasyon)
-- zincirinde HİÇ yoktu (sadece fresh-install şemasında vardı) — DB v59
-- ile düzeltildi, bu dosyaya da eklendi. supabase_sync_servisi.dart bu
-- sütunu zaten "var" varsayıyordu (_softDeleteKolonu), yani soft-delete
-- senkronu bu tabloda muhtemelen sessizce çalışmıyordu.
--
-- ═══════════════════════════════════════════════════════════════════════
-- ÖNCEKİ DOSYA NEDEN İŞE YARAMADI — İTİRAF
--
-- Verdiğim önceki dosyada her tablo `CREATE TABLE IF NOT EXISTS` ile
-- başlıyordu. Bu komut, TABLO ZATEN VARSA HİÇBİR ŞEY YAPMAZ.
--
-- Yani eski tablolarınız (FK/NOT NULL/DEFAULT kısıtlı hâlleriyle)
-- yerinde durduğu için dosya çalışsa bile ŞEMA DEĞİŞMEDİ ve aynı
-- hatalar tekrarlandı. Temizleme bloğunu da yorum içinde bırakmıştım.
--
-- BU SÜRÜM FARKLI: mevcut tabloları SİLMEDEN, üzerlerindeki sorunlu
-- kısıtları TEK TEK KALDIRIR. Yani:
--   • Tablolar yoksa      -> oluşturur
--   • Tablolar varsa      -> kısıtlarını temizler, eksik sütunları ekler
--   • Veriniz varsa       -> KORUNUR (hiçbir DROP TABLE yok)
--   • Kaç kez çalıştırsanız -> aynı sonuç
--
-- ═══════════════════════════════════════════════════════════════════════
-- NE YAPAR (sırayla)
--   BÖLÜM 1  Eksik tabloları oluşturur          (kısıtsız)
--   BÖLÜM 2  Eksik sütunları ekler              (eski tablolara)
--   BÖLÜM 3  TÜM foreign key kısıtlarını kaldırır   -> 23503 biter
--   BÖLÜM 4  TÜM not-null kısıtlarını kaldırır      -> 23502 biter
--   BÖLÜM 5  TÜM default tanımlarını kaldırır       -> 42601 biter
--   BÖLÜM 6  Upsert için gereken UNIQUE'leri kurar
--   BÖLÜM 7  İndeksler
--   BÖLÜM 8  RLS
--   BÖLÜM 9  Doğrulama sorgusu
--
-- ═══════════════════════════════════════════════════════════════════════
-- NEDEN SIFIR KISIT
--
-- 23503 (FK): Senkron kodu, yerel id -> bulut id çevirisini
--   global_id üzerinden yapar. Çeviri bulunamazsa YEREL id'yi olduğu
--   gibi gönderir (supabase_sync_servisi.dart:1276-1280). Bu tasarım
--   gereğidir — ebeveyn kayıt henüz yüklenmemiş olabilir, sonraki
--   senkronda düzelir. Ama FK varsa PostgREST toplu upsert "ya hep ya
--   hiç" olduğu için 100 kayıtlık TÜM PARTİ düşer.
--
-- 23502 (NOT NULL): Cihazda boş olabilen bir alan (kart_no_maskeli)
--   bulutta zorunlu tutulunca tek bozuk satır tüm partiyi düşürüyordu.
--
-- 42601 (DEFAULT): PostgREST toplu upsert'te eksik sütunlar için
--   literal DEFAULT anahtar kelimesi üretiyor, PostgreSQL reddediyor.
--
-- Bulut bir AYNA'dır. Veri doğrulaması cihazdaki SQLite'ta yapılır.
-- ═══════════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════════
-- BÖLÜM 1 — TABLOLAR (yoksa oluştur)
-- ═══════════════════════════════════════════════════════════════════════


-- [ 1/58] adisyon_log
CREATE TABLE IF NOT EXISTS adisyon_log (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  siparis_id BIGINT,
  adisyon_no TEXT,
  yazdiran_kullanici_id BIGINT,
  yazdirma_zamani TIMESTAMPTZ,
  printer_turu TEXT,
  global_id TEXT,
  last_updated TIMESTAMPTZ
);

-- [ 2/58] audit_log
CREATE TABLE IF NOT EXISTS audit_log (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  global_id TEXT,
  tablo_adi TEXT,
  kayit_id TEXT,  -- 🔴 DÜZELTME: global_id (UUID) tutuyor, BIGINT değil
  islem_turu TEXT,
  ozet TEXT,
  kullanici_id BIGINT,
  kullanici_adi TEXT,
  cihaz_id TEXT,
  sube_id BIGINT,
  tarih TIMESTAMPTZ,
  last_updated TIMESTAMPTZ
);

-- [ 3/58] ayarlar
CREATE TABLE IF NOT EXISTS ayarlar (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  anahtar TEXT,
  deger TEXT,
  aciklama TEXT,
  guncelleme TIMESTAMPTZ,
  last_updated TIMESTAMPTZ
);

-- [ 4/58] banka_hareketler
CREATE TABLE IF NOT EXISTS banka_hareketler (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  global_id TEXT,
  banka_hesap_id BIGINT,
  kredi_karti_id BIGINT,
  islem_tipi TEXT,
  tutar DOUBLE PRECISION,
  aciklama TEXT,
  tarih TIMESTAMPTZ,
  referans_no TEXT,
  karsi_hesap TEXT,
  onceki_bakiye DOUBLE PRECISION,
  sonraki_bakiye DOUBLE PRECISION,
  last_updated TEXT,
  is_deleted BOOLEAN,
  referans_id BIGINT,
  referans_turu TEXT
);

-- [ 5/58] banka_hesaplar
CREATE TABLE IF NOT EXISTS banka_hesaplar (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  global_id TEXT,
  banka_id BIGINT,
  hesap_adi TEXT,
  hesap_no TEXT,
  iban TEXT,
  sube_adi TEXT,
  sube_kodu TEXT,
  para_birimi TEXT,
  bakiye DOUBLE PRECISION,
  kullanilabilir_bakiye DOUBLE PRECISION,
  hesap_turu TEXT,
  aktif BOOLEAN,
  last_updated TIMESTAMPTZ
);

-- [ 6/58] bankalar
CREATE TABLE IF NOT EXISTS bankalar (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  global_id TEXT,
  ad TEXT,
  kod TEXT,
  tel TEXT,
  email TEXT,
  web TEXT,
  adres TEXT,
  logo TEXT,
  yetkili TEXT,
  aktif BOOLEAN,
  last_updated TIMESTAMPTZ
);

-- [ 7/58] bekleyen_siparis_kalem
CREATE TABLE IF NOT EXISTS bekleyen_siparis_kalem (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  global_id TEXT,
  siparis_id BIGINT,
  urun_id BIGINT,
  urun_adi TEXT,
  birim_adi TEXT,
  birim_carpani DOUBLE PRECISION,
  miktar DOUBLE PRECISION,
  toplam_miktar DOUBLE PRECISION,
  birim_fiyat DOUBLE PRECISION,
  alis_fiyat DOUBLE PRECISION,
  iskonto_oran DOUBLE PRECISION,
  iskonto_tutar DOUBLE PRECISION,
  kdv_oran DOUBLE PRECISION,
  toplam_tutar DOUBLE PRECISION,
  last_updated TIMESTAMPTZ
);

-- [ 8/58] bekleyen_siparisler
CREATE TABLE IF NOT EXISTS bekleyen_siparisler (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  global_id TEXT,
  cari_id BIGINT,
  sube_id BIGINT,
  kullanici_id BIGINT,
  tarih TIMESTAMPTZ,
  durum TEXT,
  not_ TEXT,
  ara_toplam DOUBLE PRECISION,
  iskonto_toplam DOUBLE PRECISION,
  kdv_toplam DOUBLE PRECISION,
  genel_toplam DOUBLE PRECISION,
  alis_toplam DOUBLE PRECISION,
  satis_id BIGINT,
  created_at TIMESTAMPTZ,
  last_updated TIMESTAMPTZ,
  deleted_at TIMESTAMPTZ
);

-- [ 9/58] birimler
CREATE TABLE IF NOT EXISTS birimler (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ad TEXT,
  kisaltma TEXT,
  aktif BOOLEAN,
  carpan DOUBLE PRECISION,
  last_updated TIMESTAMPTZ
);

-- [10/58] borc_odemeler
CREATE TABLE IF NOT EXISTS borc_odemeler (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  global_id TEXT,
  borc_id BIGINT,
  tutar DOUBLE PRECISION,
  tarih TIMESTAMPTZ,
  odeme_yontemi TEXT,
  aciklama TEXT,
  referans_no TEXT,
  banka_hesap_id BIGINT,
  kredi_karti_id BIGINT,
  last_updated TIMESTAMPTZ
);

-- [11/58] borclar
CREATE TABLE IF NOT EXISTS borclar (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  global_id TEXT,
  baslik TEXT,
  tur TEXT,
  alt_tur TEXT,
  tutar DOUBLE PRECISION,
  odenen_tutar DOUBLE PRECISION,
  kesim_tarihi TEXT,
  son_odeme_tarihi TEXT,
  odeme_tarihi TEXT,
  taksit_sayisi BIGINT,
  odenen_taksit BIGINT,
  aciklama TEXT,
  dosya_no TEXT,
  referans_no TEXT,
  odendi BIGINT,
  hatirlatma_gonderildi BIGINT,
  oncelik BIGINT,
  notlar TEXT,
  created_at TEXT,
  updated_at TEXT,
  last_updated TEXT,
  is_deleted BOOLEAN  -- [YENİ — 2026-09-13] yerel DB v59, Borç Silme özelliği. NOT: bu sütun yerel migrasyon zincirinde de EKSİKTİ (sadece fresh-install şemasında vardı) — supabase_sync_servisi.dart'ın _softDeleteKolonu'nda 'borclar':'is_deleted' zaten TANIMLIYDI ama sütun çoğu cihazda hiç yoktu, senkron soft-delete algılaması sessizce çalışmıyordu. İkisi de bu oturumda düzeltildi.
);

-- [12/58] cari
CREATE TABLE IF NOT EXISTS cari (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  global_id TEXT,
  cari_kodu TEXT,
  unvan TEXT,
  cari_tipi TEXT,
  telefon TEXT,
  telefon2 TEXT,
  email TEXT,
  email2 TEXT,
  vergi_dairesi TEXT,
  vergi_no TEXT,
  tc_kimlik TEXT,
  mukellef_durumu TEXT,
  mukellef_sorgu_tarihi TEXT,
  bakiye DOUBLE PRECISION,
  limit_tutari DOUBLE PRECISION,
  vade_gun BIGINT,
  ana_grup TEXT,
  alt_grup TEXT,
  temsilci TEXT,
  notlar TEXT,
  web_sitesi TEXT,
  aktif BOOLEAN,
  olusturma_tarihi TIMESTAMPTZ,
  guncelleyen TEXT,
  sube_id BIGINT,
  last_updated TIMESTAMPTZ,
  is_deleted BOOLEAN,
  deleted_at TIMESTAMPTZ,
  cihaz_id TEXT,
  fiyat_grubu_id BIGINT,
  musteri_tipi TEXT
);

-- [13/58] cari_adres
CREATE TABLE IF NOT EXISTS cari_adres (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  global_id TEXT,
  cari_id BIGINT,
  adres_tipi TEXT,
  adres TEXT,
  il TEXT,
  ilce TEXT,
  posta_kodu TEXT,
  varsayilan BOOLEAN,
  last_updated TIMESTAMPTZ
);

-- [14/58] cari_hareket
CREATE TABLE IF NOT EXISTS cari_hareket (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  global_id TEXT,
  cari_id BIGINT,
  tarih TIMESTAMPTZ,
  fis_tipi TEXT,
  fis_id BIGINT,
  fis_no TEXT,
  aciklama TEXT,
  borc DOUBLE PRECISION,
  alacak DOUBLE PRECISION,
  bakiye DOUBLE PRECISION,
  odeme_turu TEXT,
  kullanici TEXT,
  last_updated TIMESTAMPTZ,
  is_deleted BOOLEAN,
  cihaz_id TEXT
);

-- [15/58] fatura_detaylari
CREATE TABLE IF NOT EXISTS fatura_detaylari (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  global_id TEXT,
  fatura_id BIGINT,
  urun_id BIGINT,
  urun_adi TEXT,
  barkod TEXT,
  miktar DOUBLE PRECISION,
  birim_fiyat DOUBLE PRECISION,
  iskonto_orani DOUBLE PRECISION,
  iskonto_tutari DOUBLE PRECISION,
  kdv_orani DOUBLE PRECISION,
  kdv_tutari DOUBLE PRECISION,
  ara_toplam DOUBLE PRECISION,
  net_fiyat DOUBLE PRECISION,
  toplam_tutar DOUBLE PRECISION,
  lot_seri_no TEXT,
  last_updated TIMESTAMPTZ,
  cihaz_id TEXT
);

-- [16/58] faturalar
CREATE TABLE IF NOT EXISTS faturalar (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  global_id TEXT,
  fatura_no TEXT,
  fatura_tipi TEXT,
  odeme_sekli TEXT,
  satis_id BIGINT,
  iade_id BIGINT,
  cari_id BIGINT,
  sube_id BIGINT,
  tarih TEXT,
  duzenlenme_tarihi TEXT,
  sevk_tarihi TEXT,
  vade_tarihi TEXT,
  malin_nereye TEXT,
  teslim_eden TEXT,
  teslim_alan TEXT,
  toplam_ara_toplam DOUBLE PRECISION,
  toplam_iskonto DOUBLE PRECISION,
  toplam_kdv DOUBLE PRECISION,
  genel_toplam DOUBLE PRECISION,
  odenen_tutar DOUBLE PRECISION,
  kalan_tutar DOUBLE PRECISION,
  odeme_durumu TEXT,
  e_fatura_uuid TEXT,
  e_fatura_durum TEXT,
  e_fatura_deneme_no BIGINT,
  e_fatura_html TEXT,
  e_fatura_xml TEXT,
  gonderim_tarihi TIMESTAMPTZ,
  uygulama_yaniti TEXT,
  html_icerik TEXT,
  xml_icerik TEXT,
  durum TEXT,
  created_at TEXT,
  updated_at TEXT,
  last_updated TIMESTAMPTZ,
  deleted_at TIMESTAMPTZ
  -- [DÜZELTME — 2026-09-13] 'efatura_uuid'/'efatura_durum'/'efatura_tipi'
  -- kaldırıldı: yerel 'faturalar' tablosunda bu isimlerle sütun hiç yok
  -- (gerçek sütunlar yukarıdaki 'e_fatura_uuid'/'e_fatura_durum' —
  -- fatura_detay_ekrani.dart'ın eFaturaDurumGuncelle()'si bunları
  -- yazıyor). Muhtemelen eski bir isimlendirme denemesinin kalıntısıydı.
);

-- [17/58] fiyat_gecmis
CREATE TABLE IF NOT EXISTS fiyat_gecmis (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  urun_id BIGINT,
  eski_alis DOUBLE PRECISION,
  yeni_alis DOUBLE PRECISION,
  eski_satis DOUBLE PRECISION,
  yeni_satis DOUBLE PRECISION,
  degistiren TEXT,
  tarih TIMESTAMPTZ,
  global_id TEXT,
  last_updated TIMESTAMPTZ
);

-- [18/58] fiyat_gruplari
CREATE TABLE IF NOT EXISTS fiyat_gruplari (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  global_id TEXT,
  ad TEXT,
  aciklama TEXT,
  varsayilan_iskonto_orani DOUBLE PRECISION,
  aktif BOOLEAN,
  is_deleted BOOLEAN,
  last_updated TIMESTAMPTZ
);

-- [19/58] fiyat_kademeleri
CREATE TABLE IF NOT EXISTS fiyat_kademeleri (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  global_id TEXT,
  urun_id BIGINT,
  fiyat_grubu_id BIGINT,
  min_miktar DOUBLE PRECISION,
  birim TEXT,
  fiyat DOUBLE PRECISION,
  last_updated TIMESTAMPTZ
);

-- [20/58] garson_cagri_log
CREATE TABLE IF NOT EXISTS garson_cagri_log (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  masa_id BIGINT,
  masa_adi TEXT,
  cagri_zamani TIMESTAMPTZ,
  yanit_zamani TIMESTAMPTZ,
  yanitlayan_id BIGINT,
  durum TEXT,
  global_id TEXT,
  last_updated TIMESTAMPTZ
);

-- [21/58] gider_kategoriler
CREATE TABLE IF NOT EXISTS gider_kategoriler (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ad TEXT,
  last_updated TIMESTAMPTZ
);

-- [22/58] giderler
CREATE TABLE IF NOT EXISTS giderler (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  global_id TEXT,
  kategori_id BIGINT,
  tutar DOUBLE PRECISION,
  aciklama TEXT,
  tarih TIMESTAMPTZ,
  belge_no TEXT,
  odeme_yontemi TEXT,
  cari_id BIGINT,
  kullanici_id BIGINT,
  sube_id BIGINT,
  last_updated TIMESTAMPTZ,
  deleted_at TIMESTAMPTZ,
  banka_hesap_id BIGINT,  -- [2026-09-27] yerel v76: gider bankadan ödendiyse
  kredi_karti_id BIGINT   -- [2026-09-27] yerel v76: gider kartla ödendiyse
);

-- [23/58] iade
CREATE TABLE IF NOT EXISTS iade (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  global_id TEXT,
  satis_id BIGINT,
  cari_id BIGINT,
  fis_no TEXT,
  tarih TIMESTAMPTZ,
  toplam_tutar DOUBLE PRECISION,
  iade_nedeni TEXT,
  durum TEXT,
  kasiyer_id BIGINT,
  last_updated TIMESTAMPTZ,
  deleted_at TIMESTAMPTZ,
  cihaz_id TEXT
);

-- [24/58] iade_kalem
CREATE TABLE IF NOT EXISTS iade_kalem (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  global_id TEXT,
  iade_id BIGINT,
  urun_id BIGINT,
  urun_adi TEXT,
  miktar DOUBLE PRECISION,
  birim_fiyat DOUBLE PRECISION,
  toplam DOUBLE PRECISION,
  last_updated TIMESTAMPTZ
);

-- [25/58] irsaliye_kalem
CREATE TABLE IF NOT EXISTS irsaliye_kalem (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  irsaliye_id BIGINT,
  urun_id BIGINT,
  urun_adi TEXT,
  miktar DOUBLE PRECISION,
  birim_fiyat DOUBLE PRECISION,
  toplam_tutar DOUBLE PRECISION,
  global_id TEXT,
  last_updated TIMESTAMPTZ
);

-- [26/58] irsaliyeler
CREATE TABLE IF NOT EXISTS irsaliyeler (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  irsaliye_no TEXT,
  cari_id BIGINT,
  tarih TEXT,
  tip TEXT,
  toplam_tutar DOUBLE PRECISION,
  durum TEXT,
  kullanici_id BIGINT,
  created_at TEXT,
  deleted_at TIMESTAMPTZ,
  global_id TEXT,
  last_updated TIMESTAMPTZ,
  aciklama TEXT,  -- [DÜZELTME — 2026-09-13] yerelde vardı, dosyada eksikti
  e_irsaliye_durum TEXT,  -- [YENİ — 2026-09-14] e-İrsaliye GİB gönderimi
  e_irsaliye_uuid TEXT,
  e_irsaliye_xml TEXT,
  e_irsaliye_deneme_no BIGINT,
  e_irsaliye_gonderim_tarihi TIMESTAMPTZ
);

-- [27/58] kasa_hareketleri
CREATE TABLE IF NOT EXISTS kasa_hareketleri (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  global_id TEXT,
  hareket_tipi TEXT,
  tutar DOUBLE PRECISION,
  bakiye_sonrasi DOUBLE PRECISION,
  referans_id BIGINT,
  referans_turu TEXT,
  tarih TIMESTAMPTZ,
  aciklama TEXT,
  kullanici_id BIGINT,
  sube_id BIGINT,
  last_updated TIMESTAMPTZ,
  deleted_at TIMESTAMPTZ,
  odeme_yontemi TEXT  -- [YENİ — 2026-09-13] yerel DB v56, FAZ 1 madde 2 (vardiya/kasa mutabakatı)
);

-- [28/58] kategoriler
CREATE TABLE IF NOT EXISTS kategoriler (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ad TEXT,
  ust_kategori_id BIGINT,
  sira BIGINT,
  last_updated TIMESTAMPTZ,
  is_deleted BOOLEAN
);

-- [29/58] kredi_karti_hareket
CREATE TABLE IF NOT EXISTS kredi_karti_hareket (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  global_id TEXT,
  kredi_karti_id BIGINT,
  tutar DOUBLE PRECISION,
  yon TEXT,
  aciklama TEXT,
  tarih TIMESTAMPTZ,
  last_updated TIMESTAMPTZ,
  is_deleted BOOLEAN,
  referans_id BIGINT,
  referans_turu TEXT
);

-- [30/58] kredi_kartlari
CREATE TABLE IF NOT EXISTS kredi_kartlari (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  global_id TEXT,
  banka_id BIGINT,
  kart_adi TEXT,
  son_kullanma TEXT,
  kart_tipi TEXT,
  kartlimit DOUBLE PRECISION,
  kullanilan_limit DOUBLE PRECISION,
  kalan_limit DOUBLE PRECISION,
  faiz_orani DOUBLE PRECISION,
  taksit_sayisi BIGINT,
  kesim_tarihi TEXT,
  son_odeme_tarihi TEXT,
  aktif BOOLEAN,
  last_updated TIMESTAMPTZ,
  kart_no_maskeli TEXT
);

-- [31/58] kullanicilar
CREATE TABLE IF NOT EXISTS kullanicilar (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  global_id TEXT,
  sube_id BIGINT,
  kullanici_adi TEXT,
  sifre_hash TEXT,
  ad_soyad TEXT,
  rol TEXT,
  email TEXT,
  telefon TEXT,
  aktif BOOLEAN,
  tuz TEXT,
  plu BIGINT,
  plu_kart_boyut BIGINT,
  son_giris TIMESTAMPTZ,
  kayit_tarihi TIMESTAMPTZ,
  last_updated TIMESTAMPTZ,
  is_deleted BOOLEAN,
  bayi_cari_id BIGINT  -- [YENİ — 2026-09-13] yerel DB v58, B2B Bayi Portalı: doluysa bu kullanıcı bir bayi girişidir, cari(id)'ye işaret eder (FK kısıtı BÖLÜM 3 gereği bilerek konmadı)
);

-- [32/58] lot_seri
CREATE TABLE IF NOT EXISTS lot_seri (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  global_id TEXT,
  cihaz_id TEXT,
  urun_id BIGINT,
  lot_no TEXT,
  seri_no TEXT,
  miktar DOUBLE PRECISION,
  son_kullanma_tarihi TIMESTAMPTZ,
  uretim_tarihi TIMESTAMPTZ,
  tedarikci_cari_id BIGINT,
  aciklama TEXT,
  aktif BOOLEAN,
  kayit_tarihi TIMESTAMPTZ,
  last_updated TIMESTAMPTZ
);

-- [33/58] markalar
CREATE TABLE IF NOT EXISTS markalar (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ad TEXT,
  aktif BOOLEAN,
  last_updated TIMESTAMPTZ
);

-- [34/58] masa_hareket_log
CREATE TABLE IF NOT EXISTS masa_hareket_log (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  kaynak_masa_id BIGINT,
  hedef_masa_id BIGINT,
  islem_tipi TEXT,
  siparis_id BIGINT,
  yapan_kullanici_id BIGINT,
  islem_zamani TIMESTAMPTZ,
  global_id TEXT,
  last_updated TIMESTAMPTZ
);

-- [35/58] masa_rezervasyon
CREATE TABLE IF NOT EXISTS masa_rezervasyon (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  global_id TEXT,
  masa_id BIGINT,
  musteri_adi TEXT,
  telefon TEXT,
  kisi_sayisi BIGINT,
  tarih TIMESTAMPTZ,
  saat TIMESTAMPTZ,
  not_ TEXT,
  durum TEXT,
  kullanici_id BIGINT,
  created_at TIMESTAMPTZ,
  last_updated TIMESTAMPTZ,
  is_deleted BOOLEAN
);

-- [36/58] masa_siparis_kalem
CREATE TABLE IF NOT EXISTS masa_siparis_kalem (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  global_id TEXT,
  siparis_id BIGINT,
  urun_id BIGINT,
  urun_adi TEXT,
  miktar DOUBLE PRECISION,
  birim_fiyat DOUBLE PRECISION,
  kdv_oran DOUBLE PRECISION,
  not_ TEXT,
  durum TEXT,
  eklenme_zamani TIMESTAMPTZ,
  last_updated TIMESTAMPTZ,
  is_deleted BOOLEAN
);

-- [37/58] masa_siparisleri
CREATE TABLE IF NOT EXISTS masa_siparisleri (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  global_id TEXT,
  masa_id BIGINT,
  cari_id BIGINT,
  cari_adi TEXT,
  durum TEXT,
  acilis_zamani TIMESTAMPTZ,
  kapanis_zamani TIMESTAMPTZ,
  toplam_tutar DOUBLE PRECISION,
  not_ TEXT,
  kullanici_id BIGINT,
  satis_id BIGINT,
  garson_id BIGINT,
  garson_adi TEXT,
  last_updated TIMESTAMPTZ,
  is_deleted BOOLEAN
);

-- [38/58] masalar
CREATE TABLE IF NOT EXISTS masalar (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  global_id TEXT,
  ad TEXT,
  kategori TEXT,
  kapasite BIGINT,
  durum TEXT,
  sira BIGINT,
  sube_id BIGINT,
  last_updated TIMESTAMPTZ,
  is_deleted BOOLEAN
);

-- [39/58] musteri_puan
CREATE TABLE IF NOT EXISTS musteri_puan (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  global_id TEXT,
  cari_id BIGINT,
  toplam_puan DOUBLE PRECISION,
  kullanilan DOUBLE PRECISION,
  son_islem TIMESTAMPTZ,
  last_updated TIMESTAMPTZ
);

-- [YENİ — 2026-09-13] onay_talepleri (Onay Merkezi, FAZ 9, yerel DB v57)
-- Önceden bu tablo _tabloSirasi'nde (supabase_sync_servisi.dart) hiç
-- yoktu — BulutManager().upsert() ile sync_queue'ya düşüyordu ama
-- gerçekte asla buluta gönderilmiyordu. Kod tarafı da bu oturumda
-- düzeltildi, tablo artık gerçekten senkronize oluyor.
CREATE TABLE IF NOT EXISTS onay_talepleri (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  global_id TEXT,
  tur TEXT,
  referans_turu TEXT,
  referans_id BIGINT,
  tutar DOUBLE PRECISION,
  esik_tutar DOUBLE PRECISION,
  aciklama TEXT,
  kullanici_id BIGINT,
  kullanici_adi TEXT,
  sube_id BIGINT,
  tarih TIMESTAMPTZ,
  goruldu BOOLEAN,
  goren_kullanici_id BIGINT,
  goruldu_tarihi TIMESTAMPTZ,
  last_updated TIMESTAMPTZ,
  is_deleted BOOLEAN
);

-- [40/58] personel
CREATE TABLE IF NOT EXISTS personel (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  global_id TEXT,
  kullanici_id BIGINT,
  ad_soyad TEXT,
  tc_kimlik TEXT,
  pozisyon TEXT,
  departman TEXT,
  telefon TEXT,
  email TEXT,
  maas DOUBLE PRECISION,
  calisma_saati DOUBLE PRECISION,
  ise_baslama TIMESTAMPTZ,
  isten_cikis TIMESTAMPTZ,
  aktif BOOLEAN,
  notlar TEXT,
  last_updated TIMESTAMPTZ,
  is_deleted BOOLEAN
  -- [DÜZELTME — 2026-09-13] 'ise_baslama_tarihi' kaldırıldı: eski/terk
  -- edilmiş bir migrasyon adımının kalıntısıydı, güncel yerel şemada
  -- (sistem_semasi.dart) hiç yok, hiçbir Dart kodu artık yazmıyor —
  -- 'ise_baslama' (yukarıda) onun yerini aldı.
);

-- [41/58] promosyon_aksiyon
CREATE TABLE IF NOT EXISTS promosyon_aksiyon (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tanim_id BIGINT,
  aksiyon_tipi TEXT,
  aksiyon_degeri TEXT,
  global_id TEXT,
  last_updated TIMESTAMPTZ
);

-- [42/58] promosyon_kosul
CREATE TABLE IF NOT EXISTS promosyon_kosul (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tanim_id BIGINT,
  kosul_tipi TEXT,
  kosul_degeri TEXT,
  global_id TEXT,
  last_updated TIMESTAMPTZ
);

-- [43/58] promosyon_tanim
CREATE TABLE IF NOT EXISTS promosyon_tanim (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  global_id TEXT,
  ad TEXT,
  aciklama TEXT,
  tip TEXT,
  baslangic TIMESTAMPTZ,
  bitis TIMESTAMPTZ,
  aktif BOOLEAN,
  oncelik BIGINT,
  created_at TIMESTAMPTZ,
  last_updated TIMESTAMPTZ
);

-- [44/58] promosyonlar
CREATE TABLE IF NOT EXISTS promosyonlar (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  urun_id BIGINT,
  min_miktar DOUBLE PRECISION,
  iskonto_oran DOUBLE PRECISION,
  baslangic_tarihi TEXT,
  bitis_tarihi TEXT,
  aktif BOOLEAN,
  global_id TEXT,
  last_updated TIMESTAMPTZ,
  deleted_at TIMESTAMPTZ,
  promosyon_adi TEXT,  -- [DÜZELTME — 2026-09-13] yerelde GERÇEKTEN kullanılan sütun buydu, dosyada hiç yoktu
  iskonto_tutar DOUBLE PRECISION  -- [DÜZELTME — 2026-09-13] yerelde vardı, dosyada eksikti
  -- [DÜZELTME — 2026-09-13] 'ad' ve 'created_at' kaldırıldı: yerel
  -- şemada bu isimlerle sütun yok (gerçek ad sütunu 'promosyon_adi',
  -- yukarıda) — eski bir isimlendirme kalıntısıydı.
);

-- [45/58] puan_hareket
CREATE TABLE IF NOT EXISTS puan_hareket (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  global_id TEXT,
  cari_id BIGINT,
  islem_tipi TEXT,
  puan DOUBLE PRECISION,
  referans_id BIGINT,
  tarih TIMESTAMPTZ,
  aciklama TEXT,
  last_updated TIMESTAMPTZ
);

-- [46/58] rol_yetkileri
CREATE TABLE IF NOT EXISTS rol_yetkileri (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  rol TEXT,
  yetki_kodu TEXT,
  global_id TEXT,
  last_updated TIMESTAMPTZ
);

-- [47/58] roller_yetki
CREATE TABLE IF NOT EXISTS roller_yetki (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  kullanici_id BIGINT,
  yetki_kodu TEXT,
  created_at TEXT,
  global_id TEXT,
  last_updated TIMESTAMPTZ
);

-- [48/58] satis_kalem
CREATE TABLE IF NOT EXISTS satis_kalem (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  global_id TEXT,
  satis_id BIGINT,
  urun_id BIGINT,
  urun_adi TEXT,
  barkod TEXT,
  miktar DOUBLE PRECISION,
  birim_fiyat DOUBLE PRECISION,
  iskonto_oran DOUBLE PRECISION,
  iskonto_tutar DOUBLE PRECISION,
  kdv_oran DOUBLE PRECISION,
  kdv_tutar DOUBLE PRECISION,
  net_fiyat DOUBLE PRECISION,
  toplam_tutar DOUBLE PRECISION,
  lot_id BIGINT,
  seri_no TEXT,
  alis_fiyat DOUBLE PRECISION,
  alis_fiyat_kdv DOUBLE PRECISION,
  last_updated TIMESTAMPTZ,
  cihaz_id TEXT
);

-- [49/58] satislar
CREATE TABLE IF NOT EXISTS satislar (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  global_id TEXT,
  fis_no TEXT,
  tarih TIMESTAMPTZ,
  cari_id BIGINT,
  toplam_tutar DOUBLE PRECISION,
  iskonto_tutar DOUBLE PRECISION,
  iskonto_oran DOUBLE PRECISION,
  kdv_tutar DOUBLE PRECISION,
  genel_toplam DOUBLE PRECISION,
  odenen_tutar DOUBLE PRECISION,
  odeme_yontemi TEXT,
  fis_tipi TEXT,
  aciklama TEXT,
  kargo_ucreti DOUBLE PRECISION,
  kasiyer_id BIGINT,
  kullanici_id BIGINT,
  vardiya_id BIGINT,
  sube_id BIGINT,
  iptal BOOLEAN,
  iptal_tarihi TIMESTAMPTZ,
  iptal_nedeni TEXT,
  last_updated TIMESTAMPTZ,
  is_deleted BOOLEAN,
  efatura_uuid TEXT,
  efatura_durum TEXT,
  efatura_gonderim_tarihi TEXT,
  efatura_yanit TEXT,
  servis_ucreti DOUBLE PRECISION,
  deleted_at TIMESTAMPTZ,
  cihaz_id TEXT
);

-- [50/58] stok_hareket
CREATE TABLE IF NOT EXISTS stok_hareket (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  global_id TEXT,
  cihaz_id TEXT,
  urun_id BIGINT,
  hareket_turu TEXT,
  miktar DOUBLE PRECISION,
  onceki_stok DOUBLE PRECISION,
  sonraki_stok DOUBLE PRECISION,
  birim_maliyet DOUBLE PRECISION,
  tarih TIMESTAMPTZ,
  referans_id BIGINT,
  referans_turu TEXT,
  lot_id BIGINT,
  aciklama TEXT,
  kullanici_id BIGINT,
  sube_id BIGINT,
  last_updated TIMESTAMPTZ
);

-- [51/58] sube_urun
CREATE TABLE IF NOT EXISTS sube_urun (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  urun_id BIGINT,
  sube_id BIGINT,
  stok DOUBLE PRECISION,
  rezerve_stok DOUBLE PRECISION,
  kritik_stok DOUBLE PRECISION,
  satis_fiyati DOUBLE PRECISION,
  raf_kodu TEXT,
  son_guncelleme TIMESTAMPTZ,
  global_id TEXT,
  last_updated TIMESTAMPTZ,
  alis_fiyati DOUBLE PRECISION  -- [DÜZELTME — 2026-09-13] yerelde vardı, dosyada eksikti
);

-- [52/58] subeler
CREATE TABLE IF NOT EXISTS subeler (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  global_id TEXT,
  sube_kodu TEXT,
  sube_adi TEXT,
  adres TEXT,
  telefon TEXT,
  email TEXT,
  vergi_no TEXT,
  aktif BOOLEAN,
  created_at TEXT,
  updated_at TEXT,
  last_updated TIMESTAMPTZ,
  deleted BIGINT,
  is_deleted BOOLEAN
);

-- [53/58] tedarikci_siparis_kalem
CREATE TABLE IF NOT EXISTS tedarikci_siparis_kalem (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  global_id TEXT,
  siparis_id BIGINT,
  urun_id BIGINT,
  siparis_mik DOUBLE PRECISION,
  teslim_mik DOUBLE PRECISION,
  birim_fiyat DOUBLE PRECISION,
  kdv_oran DOUBLE PRECISION,
  toplam_tutar DOUBLE PRECISION,
  last_updated TIMESTAMPTZ
);

-- [54/58] tedarikci_siparisler
CREATE TABLE IF NOT EXISTS tedarikci_siparisler (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  global_id TEXT,
  cari_id BIGINT,
  siparis_no TEXT,
  siparis_tarihi TIMESTAMPTZ,
  teslim_tarihi TIMESTAMPTZ,
  toplam_tutar DOUBLE PRECISION,
  durum TEXT,
  notlar TEXT,
  olusturan_id BIGINT,
  last_updated TIMESTAMPTZ,
  is_deleted BOOLEAN
);

-- [55/58] urun_fiyat_gruplari
CREATE TABLE IF NOT EXISTS urun_fiyat_gruplari (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  global_id TEXT,
  urun_id BIGINT,
  fiyat_grubu_id BIGINT,
  fiyat DOUBLE PRECISION,
  last_updated TIMESTAMPTZ
);

-- [56/58] urunler
CREATE TABLE IF NOT EXISTS urunler (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  global_id TEXT,
  kod TEXT,
  barkod TEXT,
  barkodlar TEXT,
  urun_adi TEXT,
  alternatif_urun_adi TEXT,
  birim_adi TEXT,
  alis_fiyat DOUBLE PRECISION,
  alis_fiyat_kdv_dahil DOUBLE PRECISION,
  satis_fiyati DOUBLE PRECISION,
  stok DOUBLE PRECISION,
  toplam_maliyet DOUBLE PRECISION,
  toplam_stok DOUBLE PRECISION,
  alis_kdv_oran DOUBLE PRECISION,
  kdv_oran TEXT,
  kategori_id BIGINT,
  ana_grup TEXT,
  alt_grup TEXT,
  aktif BOOLEAN,
  seri_no_takibi BOOLEAN,
  lot_takibi BOOLEAN,
  lot_no TEXT,
  son_kullanma_tarihi TIMESTAMPTZ,
  alan1 TEXT,
  alan2 TEXT,
  alan3 TEXT,
  alan4 TEXT,
  para_birimi TEXT,
  indirim_orani DOUBLE PRECISION,
  otomatik_indirim BOOLEAN,
  son_alim_indirim_oran DOUBLE PRECISION,
  minimum_stok DOUBLE PRECISION,
  maksimum_stok DOUBLE PRECISION,
  maksimum_satir_miktari DOUBLE PRECISION,
  renk TEXT,
  beden TEXT,
  sube TEXT,
  resim_yolu TEXT,
  resim_url TEXT,
  qr_menude BIGINT,
  uretici TEXT,
  marka TEXT,
  model TEXT,
  grup_sorumlusu TEXT,
  mensei TEXT,
  raf_numarasi TEXT,
  raf_omru BIGINT,
  plu_numarasi TEXT,
  puan_orani DOUBLE PRECISION,
  plu BIGINT,
  plu_kart_boyut BIGINT,
  plu_sira BIGINT,
  doviz_kodu TEXT,
  doviz_tutari DOUBLE PRECISION,
  muhasebe_kodu TEXT,
  muafiyet_kodu TEXT,
  resmi_bakiye DOUBLE PRECISION,
  barkod_olcu_birimi TEXT,
  en DOUBLE PRECISION,
  boy DOUBLE PRECISION,
  yukseklik DOUBLE PRECISION,
  agirlik DOUBLE PRECISION,
  eski_kodu TEXT,
  kart_tipi TEXT,
  seri_numarasi TEXT,
  fiyat_guncelleme_tarih TIMESTAMPTZ,
  fiyat_guncelleyen_kullanici TEXT,
  barkod_yazdirma_tarih TIMESTAMPTZ,
  barkod_yazdiran_kullanici TEXT,
  maliyet_guncelleme_tarih TIMESTAMPTZ,
  maliyet_guncelleyen_kullanici TEXT,
  guncelleme_tarihi TIMESTAMPTZ,
  kayit_tarihi TIMESTAMPTZ,
  guncelleyen_kullanici TEXT,
  kaydeden_kullanici TEXT,
  last_updated TIMESTAMPTZ,
  sync_status TEXT,
  is_deleted BOOLEAN,
  kdv_dahil BIGINT,
  barkod_tipi TEXT,
  max_stok DOUBLE PRECISION,
  deleted_at TIMESTAMPTZ,
  cihaz_id TEXT,
  zaman_fiyat_id BIGINT,
  indirimli_fiyat DOUBLE PRECISION,
  hacim DOUBLE PRECISION,
  evrak_kontrol_aktif BOOLEAN,
  lot_aciklama TEXT,
  eski_fiyat DOUBLE PRECISION,
  eski_fiyat_tarih TIMESTAMPTZ,
  promosyon_grup TEXT,
  promosyon_aktif BOOLEAN,
  recete_katsayi DOUBLE PRECISION,
  net_alis_fiyat DOUBLE PRECISION,
  toptan_fiyat DOUBLE PRECISION,
  koli_ici_miktar DOUBLE PRECISION,
  koli_birim_adi TEXT,
  satis_birimi_tipi TEXT,
  toptan_satista BIGINT,
  asgari_siparis_miktari DOUBLE PRECISION  -- [DÜZELTME — 2026-09-13] yerelde vardı (Bayi Portalı ile ilgili), dosyada eksikti
);

-- [57/58] vardiyalar
CREATE TABLE IF NOT EXISTS vardiyalar (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  global_id TEXT,
  kullanici_id BIGINT,
  sube_id BIGINT,
  acilis_tarihi TIMESTAMPTZ,
  kapanis_tarihi TIMESTAMPTZ,
  acilis_kasasi DOUBLE PRECISION,
  kapanis_kasasi DOUBLE PRECISION,
  baslangic_bakiye DOUBLE PRECISION,
  bitis_bakiye DOUBLE PRECISION,
  nakit_sayim DOUBLE PRECISION,
  kart_toplam DOUBLE PRECISION,
  fark DOUBLE PRECISION,
  notlar TEXT,
  durum TEXT,
  onaylayan_kullanici_id BIGINT,
  onaylanma_tarihi TIMESTAMPTZ,
  last_updated TIMESTAMPTZ,
  deleted_at TIMESTAMPTZ  -- [2026-09-27] yerelde vardı, bulutta eksikti
);

-- [58/58] zaman_fiyat
CREATE TABLE IF NOT EXISTS zaman_fiyat (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  urun_id BIGINT,
  gun_listesi TEXT,
  baslangic_saat TEXT,
  bitis_saat TEXT,
  fiyat_turu TEXT,
  deger DOUBLE PRECISION,
  aktif BOOLEAN,
  aciklama TEXT,
  olusturma TIMESTAMPTZ,
  guncelleme TIMESTAMPTZ,
  global_id TEXT,
  last_updated TIMESTAMPTZ
);

-- [YENİ — 2026-09-15] fis_seri (fiş/irsaliye/sipariş numara sayacı)
-- Derin analizde bulundu (P1 #11): bu tablo senkron sisteminin
-- TAMAMEN DIŞINDAYDI — aynı şubede birden fazla POS terminali
-- kullanılıyorsa her biri kendi lokal sayacını tutuyordu, biri
-- diğerinin ürettiği numaradan habersizdi. Artık yeni bir numara
-- üretildikten sonra best-effort buluta itiliyor (veritabani.dart —
-- _fisSeriBulutaPushla) ve periyodik olarak MAX-birleştirmeyle geri
-- çekiliyor (_fisSeriBulutlaUyumla). Doğal anahtarı (sube_id, fis_tipi)
-- çifti — global_id YOK, bu yüzden BİLEREK projenin genel
-- _tabloSirasi/global_id senkron akışının (supabase_sync_servisi.dart)
-- DIŞINDA tutuluyor. Bir SAYAÇ için "son güncelleyen kazanır" (last-
-- write-wins) semantiği YANLIŞTIR — geç senkron olan bir cihazın DAHA
-- KÜÇÜK yerel değeri, zaten kullanılmış BÜYÜK bir numarayı sessizce
-- geri alıp aynı numaranın tekrar üretilmesine yol açabilir. Bunun
-- yerine aşağıdaki BEFORE UPDATE tetikleyicisi son_fis_no'nun ASLA
-- küçülmemesini (GREATEST(eski, yeni)) garanti eder.
CREATE TABLE IF NOT EXISTS fis_seri (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  sube_id BIGINT,
  fis_tipi TEXT,
  son_fis_no BIGINT,
  last_updated TIMESTAMPTZ
);

-- fis_seri.son_fis_no'nun bir UPDATE ile asla küçülmemesini garanti
-- eden tetikleyici — üstteki nota bkz. Sadece bu tabloya özel; diğer
-- hiçbir tabloda böyle bir kısıt yok (onlarda last-write-wins doğru).
CREATE OR REPLACE FUNCTION trg_fis_seri_max_koru() RETURNS TRIGGER AS $$
BEGIN
  NEW.son_fis_no := GREATEST(OLD.son_fis_no, NEW.son_fis_no);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_fis_seri_max_koru ON fis_seri;
CREATE TRIGGER trg_fis_seri_max_koru
  BEFORE UPDATE ON fis_seri
  FOR EACH ROW EXECUTE FUNCTION trg_fis_seri_max_koru();

-- ═══════════════════════════════════════════════════════════════════════
-- YIL SONU DEVİR / DÖNEM KAPATMA / ARŞİVLEME SİSTEMİ — FAZ 1 (2026-09-16,
-- kullanıcı onaylı mimari plan raporu). 7 yeni tablo — SQLite tarafıyla
-- (donem_semasi.dart) birebir aynı yapı. Devir motoru mantığı
-- (DevirYoneticiServisi) İLERİKİ bir fazda gelecek, bu SADECE şema.
-- ═══════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS donemler (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  global_id TEXT,
  donem_yili BIGINT,
  baslangic_tarihi TEXT,
  bitis_tarihi TEXT,
  durum TEXT,
  kapanis_tarihi TEXT,
  kapanisi_yapan_kullanici_id BIGINT,
  kapanis_cihazi TEXT,
  backup_durumu TEXT,
  arsiv_durumu TEXT,
  devir_durumu TEXT,
  created_at TEXT,
  last_updated TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS donem_sube_durumlari (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  global_id TEXT,
  donem_id BIGINT,
  sube_id BIGINT,
  durum TEXT,
  kapanis_tarihi TEXT,
  kapanisi_yapan_kullanici_id BIGINT,
  kapanis_cihazi TEXT,
  backup_durumu TEXT,
  arsiv_durumu TEXT,
  devir_durumu TEXT,
  last_updated TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS devir_checkpoint (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  global_id TEXT,
  devir_id TEXT,
  kaynak_donem_id BIGINT,
  hedef_donem_id BIGINT,
  sube_id BIGINT,
  durum TEXT,
  mevcut_faz BIGINT,
  faz_ilerleme_json TEXT,
  baslangic_zamani TEXT,
  son_guncelleme TEXT,
  tamamlanma_zamani TEXT,
  hata_mesaji TEXT,
  last_updated TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS stok_kapanis_snapshot (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  global_id TEXT,
  devir_id TEXT,
  donem_id BIGINT,
  sube_id BIGINT,
  urun_id BIGINT,
  miktar DOUBLE PRECISION,
  kaynak_hash TEXT,
  olusturma_tarihi TEXT,
  last_updated TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS cari_kapanis_snapshot (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  global_id TEXT,
  devir_id TEXT,
  donem_id BIGINT,
  cari_id BIGINT,
  bakiye DOUBLE PRECISION,
  kaynak_hash TEXT,
  olusturma_tarihi TEXT,
  last_updated TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS kasa_kapanis_snapshot (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  global_id TEXT,
  devir_id TEXT,
  donem_id BIGINT,
  sube_id BIGINT,
  bakiye DOUBLE PRECISION,
  kaynak_hash TEXT,
  olusturma_tarihi TEXT,
  last_updated TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS banka_kapanis_snapshot (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  global_id TEXT,
  devir_id TEXT,
  donem_id BIGINT,
  banka_hesap_id BIGINT,
  bakiye DOUBLE PRECISION,
  kaynak_hash TEXT,
  olusturma_tarihi TEXT,
  last_updated TIMESTAMPTZ
);

-- [YENİ — 2026-09-21] Yıl Sonu Devir çoklu cihaz kilidi (FAZ 4).
CREATE TABLE IF NOT EXISTS donem_kilit (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  global_id TEXT,
  donem_id BIGINT,
  sube_id BIGINT,
  cihaz_id TEXT,
  kilit_zamani TEXT,
  son_yenileme TEXT,
  last_updated TIMESTAMPTZ
);


-- ═══════════════════════════════════════════════════════════════════════
-- BÖLÜM 2 — EKSİK SÜTUNLARI EKLE
-- Eski şemadan kalan tablolarda sütun eksikse tamamlar.
-- ═══════════════════════════════════════════════════════════════════════

ALTER TABLE adisyon_log ADD COLUMN IF NOT EXISTS siparis_id BIGINT;
ALTER TABLE adisyon_log ADD COLUMN IF NOT EXISTS adisyon_no TEXT;
ALTER TABLE adisyon_log ADD COLUMN IF NOT EXISTS yazdiran_kullanici_id BIGINT;
ALTER TABLE adisyon_log ADD COLUMN IF NOT EXISTS yazdirma_zamani TIMESTAMPTZ;
ALTER TABLE adisyon_log ADD COLUMN IF NOT EXISTS printer_turu TEXT;
ALTER TABLE adisyon_log ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE adisyon_log ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE audit_log ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE audit_log ADD COLUMN IF NOT EXISTS tablo_adi TEXT;
ALTER TABLE audit_log ADD COLUMN IF NOT EXISTS kayit_id TEXT;
-- 🔴 GERÇEK ÜRETİM HATASI (kullanıcının paylaştığı log — 94/95 hata):
-- 'audit_log.kayit_id' önceki sürümde yanlışlıkla BIGINT olarak
-- oluşturulmuştu, ama uygulama buraya HER ZAMAN bir UUID (global_id)
-- metni yazıyor — "invalid input syntax for type bigint: <uuid>".
-- Zaten BIGINT olarak var olan sütunu TEXT'e çeviriyor; sütun daha
-- önce hiç oluşmadıysa (yeni kurulum) üstteki ADD COLUMN zaten TEXT
-- ile ekliyor, bu blok o durumda hiçbir şey yapmaz (koşul false).
DO $$ BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='audit_log'
      AND column_name='kayit_id' AND data_type='bigint'
  ) THEN
    ALTER TABLE audit_log ALTER COLUMN kayit_id TYPE TEXT USING kayit_id::TEXT;
  END IF;
END $$;
ALTER TABLE audit_log ADD COLUMN IF NOT EXISTS islem_turu TEXT;
ALTER TABLE audit_log ADD COLUMN IF NOT EXISTS ozet TEXT;
ALTER TABLE audit_log ADD COLUMN IF NOT EXISTS kullanici_id BIGINT;
ALTER TABLE audit_log ADD COLUMN IF NOT EXISTS kullanici_adi TEXT;
ALTER TABLE audit_log ADD COLUMN IF NOT EXISTS cihaz_id TEXT;
ALTER TABLE audit_log ADD COLUMN IF NOT EXISTS sube_id BIGINT;
ALTER TABLE audit_log ADD COLUMN IF NOT EXISTS tarih TIMESTAMPTZ;
ALTER TABLE audit_log ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE ayarlar ADD COLUMN IF NOT EXISTS anahtar TEXT;
ALTER TABLE ayarlar ADD COLUMN IF NOT EXISTS deger TEXT;
ALTER TABLE ayarlar ADD COLUMN IF NOT EXISTS aciklama TEXT;
ALTER TABLE ayarlar ADD COLUMN IF NOT EXISTS guncelleme TIMESTAMPTZ;
ALTER TABLE ayarlar ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE banka_hareketler ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE banka_hareketler ADD COLUMN IF NOT EXISTS banka_hesap_id BIGINT;
ALTER TABLE banka_hareketler ADD COLUMN IF NOT EXISTS kredi_karti_id BIGINT;
ALTER TABLE banka_hareketler ADD COLUMN IF NOT EXISTS islem_tipi TEXT;
ALTER TABLE banka_hareketler ADD COLUMN IF NOT EXISTS tutar DOUBLE PRECISION;
ALTER TABLE banka_hareketler ADD COLUMN IF NOT EXISTS aciklama TEXT;
ALTER TABLE banka_hareketler ADD COLUMN IF NOT EXISTS tarih TIMESTAMPTZ;
ALTER TABLE banka_hareketler ADD COLUMN IF NOT EXISTS referans_no TEXT;
ALTER TABLE banka_hareketler ADD COLUMN IF NOT EXISTS karsi_hesap TEXT;
ALTER TABLE banka_hareketler ADD COLUMN IF NOT EXISTS onceki_bakiye DOUBLE PRECISION;
ALTER TABLE banka_hareketler ADD COLUMN IF NOT EXISTS sonraki_bakiye DOUBLE PRECISION;
ALTER TABLE banka_hareketler ADD COLUMN IF NOT EXISTS last_updated TEXT;
ALTER TABLE banka_hareketler ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN;
ALTER TABLE banka_hareketler ADD COLUMN IF NOT EXISTS referans_id BIGINT;
ALTER TABLE banka_hareketler ADD COLUMN IF NOT EXISTS referans_turu TEXT;
ALTER TABLE banka_hesaplar ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE banka_hesaplar ADD COLUMN IF NOT EXISTS banka_id BIGINT;
ALTER TABLE banka_hesaplar ADD COLUMN IF NOT EXISTS hesap_adi TEXT;
ALTER TABLE banka_hesaplar ADD COLUMN IF NOT EXISTS hesap_no TEXT;
ALTER TABLE banka_hesaplar ADD COLUMN IF NOT EXISTS iban TEXT;
ALTER TABLE banka_hesaplar ADD COLUMN IF NOT EXISTS sube_adi TEXT;
ALTER TABLE banka_hesaplar ADD COLUMN IF NOT EXISTS sube_kodu TEXT;
ALTER TABLE banka_hesaplar ADD COLUMN IF NOT EXISTS para_birimi TEXT;
ALTER TABLE banka_hesaplar ADD COLUMN IF NOT EXISTS bakiye DOUBLE PRECISION;
ALTER TABLE banka_hesaplar ADD COLUMN IF NOT EXISTS kullanilabilir_bakiye DOUBLE PRECISION;
ALTER TABLE banka_hesaplar ADD COLUMN IF NOT EXISTS hesap_turu TEXT;
ALTER TABLE banka_hesaplar ADD COLUMN IF NOT EXISTS aktif BOOLEAN;
ALTER TABLE banka_hesaplar ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE bankalar ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE bankalar ADD COLUMN IF NOT EXISTS ad TEXT;
ALTER TABLE bankalar ADD COLUMN IF NOT EXISTS kod TEXT;
ALTER TABLE bankalar ADD COLUMN IF NOT EXISTS tel TEXT;
ALTER TABLE bankalar ADD COLUMN IF NOT EXISTS email TEXT;
ALTER TABLE bankalar ADD COLUMN IF NOT EXISTS web TEXT;
ALTER TABLE bankalar ADD COLUMN IF NOT EXISTS adres TEXT;
ALTER TABLE bankalar ADD COLUMN IF NOT EXISTS logo TEXT;
ALTER TABLE bankalar ADD COLUMN IF NOT EXISTS yetkili TEXT;
ALTER TABLE bankalar ADD COLUMN IF NOT EXISTS aktif BOOLEAN;
ALTER TABLE bankalar ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE bekleyen_siparis_kalem ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE bekleyen_siparis_kalem ADD COLUMN IF NOT EXISTS siparis_id BIGINT;
ALTER TABLE bekleyen_siparis_kalem ADD COLUMN IF NOT EXISTS urun_id BIGINT;
ALTER TABLE bekleyen_siparis_kalem ADD COLUMN IF NOT EXISTS urun_adi TEXT;
ALTER TABLE bekleyen_siparis_kalem ADD COLUMN IF NOT EXISTS birim_adi TEXT;
ALTER TABLE bekleyen_siparis_kalem ADD COLUMN IF NOT EXISTS birim_carpani DOUBLE PRECISION;
ALTER TABLE bekleyen_siparis_kalem ADD COLUMN IF NOT EXISTS miktar DOUBLE PRECISION;
ALTER TABLE bekleyen_siparis_kalem ADD COLUMN IF NOT EXISTS toplam_miktar DOUBLE PRECISION;
ALTER TABLE bekleyen_siparis_kalem ADD COLUMN IF NOT EXISTS birim_fiyat DOUBLE PRECISION;
ALTER TABLE bekleyen_siparis_kalem ADD COLUMN IF NOT EXISTS alis_fiyat DOUBLE PRECISION;
ALTER TABLE bekleyen_siparis_kalem ADD COLUMN IF NOT EXISTS iskonto_oran DOUBLE PRECISION;
ALTER TABLE bekleyen_siparis_kalem ADD COLUMN IF NOT EXISTS iskonto_tutar DOUBLE PRECISION;
ALTER TABLE bekleyen_siparis_kalem ADD COLUMN IF NOT EXISTS kdv_oran DOUBLE PRECISION;
ALTER TABLE bekleyen_siparis_kalem ADD COLUMN IF NOT EXISTS toplam_tutar DOUBLE PRECISION;
ALTER TABLE bekleyen_siparis_kalem ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE bekleyen_siparisler ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE bekleyen_siparisler ADD COLUMN IF NOT EXISTS cari_id BIGINT;
ALTER TABLE bekleyen_siparisler ADD COLUMN IF NOT EXISTS sube_id BIGINT;
ALTER TABLE bekleyen_siparisler ADD COLUMN IF NOT EXISTS kullanici_id BIGINT;
ALTER TABLE bekleyen_siparisler ADD COLUMN IF NOT EXISTS tarih TIMESTAMPTZ;
ALTER TABLE bekleyen_siparisler ADD COLUMN IF NOT EXISTS durum TEXT;
ALTER TABLE bekleyen_siparisler ADD COLUMN IF NOT EXISTS not_ TEXT;
ALTER TABLE bekleyen_siparisler ADD COLUMN IF NOT EXISTS ara_toplam DOUBLE PRECISION;
ALTER TABLE bekleyen_siparisler ADD COLUMN IF NOT EXISTS iskonto_toplam DOUBLE PRECISION;
ALTER TABLE bekleyen_siparisler ADD COLUMN IF NOT EXISTS kdv_toplam DOUBLE PRECISION;
ALTER TABLE bekleyen_siparisler ADD COLUMN IF NOT EXISTS genel_toplam DOUBLE PRECISION;
ALTER TABLE bekleyen_siparisler ADD COLUMN IF NOT EXISTS alis_toplam DOUBLE PRECISION;
ALTER TABLE bekleyen_siparisler ADD COLUMN IF NOT EXISTS satis_id BIGINT;
ALTER TABLE bekleyen_siparisler ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ;
ALTER TABLE bekleyen_siparisler ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE bekleyen_siparisler ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
ALTER TABLE birimler ADD COLUMN IF NOT EXISTS ad TEXT;
ALTER TABLE birimler ADD COLUMN IF NOT EXISTS kisaltma TEXT;
ALTER TABLE birimler ADD COLUMN IF NOT EXISTS aktif BOOLEAN;
ALTER TABLE birimler ADD COLUMN IF NOT EXISTS carpan DOUBLE PRECISION;
ALTER TABLE birimler ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE borc_odemeler ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE borc_odemeler ADD COLUMN IF NOT EXISTS borc_id BIGINT;
ALTER TABLE borc_odemeler ADD COLUMN IF NOT EXISTS tutar DOUBLE PRECISION;
ALTER TABLE borc_odemeler ADD COLUMN IF NOT EXISTS tarih TIMESTAMPTZ;
ALTER TABLE borc_odemeler ADD COLUMN IF NOT EXISTS odeme_yontemi TEXT;
ALTER TABLE borc_odemeler ADD COLUMN IF NOT EXISTS aciklama TEXT;
ALTER TABLE borc_odemeler ADD COLUMN IF NOT EXISTS referans_no TEXT;
ALTER TABLE borc_odemeler ADD COLUMN IF NOT EXISTS banka_hesap_id BIGINT;
ALTER TABLE borc_odemeler ADD COLUMN IF NOT EXISTS kredi_karti_id BIGINT;
ALTER TABLE borc_odemeler ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE borclar ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE borclar ADD COLUMN IF NOT EXISTS baslik TEXT;
ALTER TABLE borclar ADD COLUMN IF NOT EXISTS tur TEXT;
ALTER TABLE borclar ADD COLUMN IF NOT EXISTS alt_tur TEXT;
ALTER TABLE borclar ADD COLUMN IF NOT EXISTS tutar DOUBLE PRECISION;
ALTER TABLE borclar ADD COLUMN IF NOT EXISTS odenen_tutar DOUBLE PRECISION;
ALTER TABLE borclar ADD COLUMN IF NOT EXISTS kesim_tarihi TEXT;
ALTER TABLE borclar ADD COLUMN IF NOT EXISTS son_odeme_tarihi TEXT;
ALTER TABLE borclar ADD COLUMN IF NOT EXISTS odeme_tarihi TEXT;
ALTER TABLE borclar ADD COLUMN IF NOT EXISTS taksit_sayisi BIGINT;
ALTER TABLE borclar ADD COLUMN IF NOT EXISTS odenen_taksit BIGINT;
ALTER TABLE borclar ADD COLUMN IF NOT EXISTS aciklama TEXT;
ALTER TABLE borclar ADD COLUMN IF NOT EXISTS dosya_no TEXT;
ALTER TABLE borclar ADD COLUMN IF NOT EXISTS referans_no TEXT;
ALTER TABLE borclar ADD COLUMN IF NOT EXISTS odendi BIGINT;
ALTER TABLE borclar ADD COLUMN IF NOT EXISTS hatirlatma_gonderildi BIGINT;
ALTER TABLE borclar ADD COLUMN IF NOT EXISTS oncelik BIGINT;
ALTER TABLE borclar ADD COLUMN IF NOT EXISTS notlar TEXT;
ALTER TABLE borclar ADD COLUMN IF NOT EXISTS created_at TEXT;
ALTER TABLE borclar ADD COLUMN IF NOT EXISTS updated_at TEXT;
ALTER TABLE borclar ADD COLUMN IF NOT EXISTS last_updated TEXT;
ALTER TABLE borclar ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN;
-- 🔴 GERÇEK ÜRETİM HATASI (kullanıcı logu): 'is_deleted' bu şemada
-- HER YERDE (16 farklı tabloda) BOOLEAN olarak tanımlı — burada
-- tek istisna olarak yanlışlıkla BIGINT yapılmıştı. BOOLEAN,
-- PostgREST üzerinden hem true/false hem 0/1 kabul eder; BIGINT
-- 'false' metnini kabul etmiyordu ("invalid input syntax for
-- type bigint: 'false'"). Aşağıdaki blok, sütun zaten yanlış
-- (bigint) tipte oluşmuşsa güvenli şekilde BOOLEAN'a çeviriyor.
ALTER TABLE borclar ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN;
DO $$ BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='borclar'
      AND column_name='is_deleted' AND data_type='bigint'
  ) THEN
    ALTER TABLE borclar ALTER COLUMN is_deleted TYPE BOOLEAN
      USING (is_deleted IS NOT NULL AND is_deleted <> 0);
  END IF;
END $$;
ALTER TABLE cari ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE cari ADD COLUMN IF NOT EXISTS cari_kodu TEXT;
ALTER TABLE cari ADD COLUMN IF NOT EXISTS unvan TEXT;
ALTER TABLE cari ADD COLUMN IF NOT EXISTS cari_tipi TEXT;
ALTER TABLE cari ADD COLUMN IF NOT EXISTS telefon TEXT;
ALTER TABLE cari ADD COLUMN IF NOT EXISTS telefon2 TEXT;
ALTER TABLE cari ADD COLUMN IF NOT EXISTS email TEXT;
ALTER TABLE cari ADD COLUMN IF NOT EXISTS email2 TEXT;
ALTER TABLE cari ADD COLUMN IF NOT EXISTS vergi_dairesi TEXT;
ALTER TABLE cari ADD COLUMN IF NOT EXISTS vergi_no TEXT;
ALTER TABLE cari ADD COLUMN IF NOT EXISTS tc_kimlik TEXT;
ALTER TABLE cari ADD COLUMN IF NOT EXISTS mukellef_durumu TEXT;
ALTER TABLE cari ADD COLUMN IF NOT EXISTS mukellef_sorgu_tarihi TEXT;
ALTER TABLE cari ADD COLUMN IF NOT EXISTS bakiye DOUBLE PRECISION;
ALTER TABLE cari ADD COLUMN IF NOT EXISTS limit_tutari DOUBLE PRECISION;
ALTER TABLE cari ADD COLUMN IF NOT EXISTS vade_gun BIGINT;
ALTER TABLE cari ADD COLUMN IF NOT EXISTS ana_grup TEXT;
ALTER TABLE cari ADD COLUMN IF NOT EXISTS alt_grup TEXT;
ALTER TABLE cari ADD COLUMN IF NOT EXISTS temsilci TEXT;
ALTER TABLE cari ADD COLUMN IF NOT EXISTS notlar TEXT;
ALTER TABLE cari ADD COLUMN IF NOT EXISTS web_sitesi TEXT;
ALTER TABLE cari ADD COLUMN IF NOT EXISTS aktif BOOLEAN;
ALTER TABLE cari ADD COLUMN IF NOT EXISTS olusturma_tarihi TIMESTAMPTZ;
ALTER TABLE cari ADD COLUMN IF NOT EXISTS guncelleyen TEXT;
ALTER TABLE cari ADD COLUMN IF NOT EXISTS sube_id BIGINT;
ALTER TABLE cari ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE cari ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN;
ALTER TABLE cari ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
ALTER TABLE cari ADD COLUMN IF NOT EXISTS cihaz_id TEXT;
ALTER TABLE cari ADD COLUMN IF NOT EXISTS fiyat_grubu_id BIGINT;
ALTER TABLE cari ADD COLUMN IF NOT EXISTS musteri_tipi TEXT;
ALTER TABLE cari_adres ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE cari_adres ADD COLUMN IF NOT EXISTS cari_id BIGINT;
ALTER TABLE cari_adres ADD COLUMN IF NOT EXISTS adres_tipi TEXT;
ALTER TABLE cari_adres ADD COLUMN IF NOT EXISTS adres TEXT;
ALTER TABLE cari_adres ADD COLUMN IF NOT EXISTS il TEXT;
ALTER TABLE cari_adres ADD COLUMN IF NOT EXISTS ilce TEXT;
ALTER TABLE cari_adres ADD COLUMN IF NOT EXISTS posta_kodu TEXT;
ALTER TABLE cari_adres ADD COLUMN IF NOT EXISTS varsayilan BOOLEAN;
ALTER TABLE cari_adres ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE cari_hareket ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE cari_hareket ADD COLUMN IF NOT EXISTS cari_id BIGINT;
ALTER TABLE cari_hareket ADD COLUMN IF NOT EXISTS tarih TIMESTAMPTZ;
ALTER TABLE cari_hareket ADD COLUMN IF NOT EXISTS fis_tipi TEXT;
ALTER TABLE cari_hareket ADD COLUMN IF NOT EXISTS fis_id BIGINT;
ALTER TABLE cari_hareket ADD COLUMN IF NOT EXISTS fis_no TEXT;
ALTER TABLE cari_hareket ADD COLUMN IF NOT EXISTS aciklama TEXT;
ALTER TABLE cari_hareket ADD COLUMN IF NOT EXISTS borc DOUBLE PRECISION;
ALTER TABLE cari_hareket ADD COLUMN IF NOT EXISTS alacak DOUBLE PRECISION;
ALTER TABLE cari_hareket ADD COLUMN IF NOT EXISTS bakiye DOUBLE PRECISION;
ALTER TABLE cari_hareket ADD COLUMN IF NOT EXISTS odeme_turu TEXT;
ALTER TABLE cari_hareket ADD COLUMN IF NOT EXISTS kullanici TEXT;
ALTER TABLE cari_hareket ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE cari_hareket ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN;
ALTER TABLE cari_hareket ADD COLUMN IF NOT EXISTS cihaz_id TEXT;
ALTER TABLE fatura_detaylari ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE fatura_detaylari ADD COLUMN IF NOT EXISTS fatura_id BIGINT;
ALTER TABLE fatura_detaylari ADD COLUMN IF NOT EXISTS urun_id BIGINT;
ALTER TABLE fatura_detaylari ADD COLUMN IF NOT EXISTS urun_adi TEXT;
ALTER TABLE fatura_detaylari ADD COLUMN IF NOT EXISTS barkod TEXT;
ALTER TABLE fatura_detaylari ADD COLUMN IF NOT EXISTS miktar DOUBLE PRECISION;
ALTER TABLE fatura_detaylari ADD COLUMN IF NOT EXISTS birim_fiyat DOUBLE PRECISION;
ALTER TABLE fatura_detaylari ADD COLUMN IF NOT EXISTS iskonto_orani DOUBLE PRECISION;
ALTER TABLE fatura_detaylari ADD COLUMN IF NOT EXISTS iskonto_tutari DOUBLE PRECISION;
ALTER TABLE fatura_detaylari ADD COLUMN IF NOT EXISTS kdv_orani DOUBLE PRECISION;
ALTER TABLE fatura_detaylari ADD COLUMN IF NOT EXISTS kdv_tutari DOUBLE PRECISION;
ALTER TABLE fatura_detaylari ADD COLUMN IF NOT EXISTS ara_toplam DOUBLE PRECISION;
ALTER TABLE fatura_detaylari ADD COLUMN IF NOT EXISTS net_fiyat DOUBLE PRECISION;
ALTER TABLE fatura_detaylari ADD COLUMN IF NOT EXISTS toplam_tutar DOUBLE PRECISION;
ALTER TABLE fatura_detaylari ADD COLUMN IF NOT EXISTS lot_seri_no TEXT;
ALTER TABLE fatura_detaylari ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE fatura_detaylari ADD COLUMN IF NOT EXISTS cihaz_id TEXT;
ALTER TABLE faturalar ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE faturalar ADD COLUMN IF NOT EXISTS fatura_no TEXT;
ALTER TABLE faturalar ADD COLUMN IF NOT EXISTS fatura_tipi TEXT;
ALTER TABLE faturalar ADD COLUMN IF NOT EXISTS odeme_sekli TEXT;
ALTER TABLE faturalar ADD COLUMN IF NOT EXISTS satis_id BIGINT;
ALTER TABLE faturalar ADD COLUMN IF NOT EXISTS iade_id BIGINT;
ALTER TABLE faturalar ADD COLUMN IF NOT EXISTS cari_id BIGINT;
ALTER TABLE faturalar ADD COLUMN IF NOT EXISTS sube_id BIGINT;
ALTER TABLE faturalar ADD COLUMN IF NOT EXISTS tarih TEXT;
ALTER TABLE faturalar ADD COLUMN IF NOT EXISTS duzenlenme_tarihi TEXT;
ALTER TABLE faturalar ADD COLUMN IF NOT EXISTS sevk_tarihi TEXT;
ALTER TABLE faturalar ADD COLUMN IF NOT EXISTS vade_tarihi TEXT;
ALTER TABLE faturalar ADD COLUMN IF NOT EXISTS malin_nereye TEXT;
ALTER TABLE faturalar ADD COLUMN IF NOT EXISTS teslim_eden TEXT;
ALTER TABLE faturalar ADD COLUMN IF NOT EXISTS teslim_alan TEXT;
ALTER TABLE faturalar ADD COLUMN IF NOT EXISTS toplam_ara_toplam DOUBLE PRECISION;
ALTER TABLE faturalar ADD COLUMN IF NOT EXISTS toplam_iskonto DOUBLE PRECISION;
ALTER TABLE faturalar ADD COLUMN IF NOT EXISTS toplam_kdv DOUBLE PRECISION;
ALTER TABLE faturalar ADD COLUMN IF NOT EXISTS genel_toplam DOUBLE PRECISION;
ALTER TABLE faturalar ADD COLUMN IF NOT EXISTS odenen_tutar DOUBLE PRECISION;
ALTER TABLE faturalar ADD COLUMN IF NOT EXISTS kalan_tutar DOUBLE PRECISION;
ALTER TABLE faturalar ADD COLUMN IF NOT EXISTS odeme_durumu TEXT;
ALTER TABLE faturalar ADD COLUMN IF NOT EXISTS e_fatura_uuid TEXT;
ALTER TABLE faturalar ADD COLUMN IF NOT EXISTS e_fatura_durum TEXT;
ALTER TABLE faturalar ADD COLUMN IF NOT EXISTS e_fatura_deneme_no BIGINT;
ALTER TABLE faturalar ADD COLUMN IF NOT EXISTS e_fatura_html TEXT;
ALTER TABLE faturalar ADD COLUMN IF NOT EXISTS e_fatura_xml TEXT;
ALTER TABLE faturalar ADD COLUMN IF NOT EXISTS gonderim_tarihi TIMESTAMPTZ;
ALTER TABLE faturalar ADD COLUMN IF NOT EXISTS uygulama_yaniti TEXT;
ALTER TABLE faturalar ADD COLUMN IF NOT EXISTS html_icerik TEXT;
ALTER TABLE faturalar ADD COLUMN IF NOT EXISTS xml_icerik TEXT;
ALTER TABLE faturalar ADD COLUMN IF NOT EXISTS durum TEXT;
ALTER TABLE faturalar ADD COLUMN IF NOT EXISTS created_at TEXT;
ALTER TABLE faturalar ADD COLUMN IF NOT EXISTS updated_at TEXT;
ALTER TABLE faturalar ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE faturalar ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
ALTER TABLE fiyat_gecmis ADD COLUMN IF NOT EXISTS urun_id BIGINT;
ALTER TABLE fiyat_gecmis ADD COLUMN IF NOT EXISTS eski_alis DOUBLE PRECISION;
ALTER TABLE fiyat_gecmis ADD COLUMN IF NOT EXISTS yeni_alis DOUBLE PRECISION;
ALTER TABLE fiyat_gecmis ADD COLUMN IF NOT EXISTS eski_satis DOUBLE PRECISION;
ALTER TABLE fiyat_gecmis ADD COLUMN IF NOT EXISTS yeni_satis DOUBLE PRECISION;
ALTER TABLE fiyat_gecmis ADD COLUMN IF NOT EXISTS degistiren TEXT;
ALTER TABLE fiyat_gecmis ADD COLUMN IF NOT EXISTS tarih TIMESTAMPTZ;
ALTER TABLE fiyat_gecmis ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE fiyat_gecmis ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE fiyat_gruplari ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE fiyat_gruplari ADD COLUMN IF NOT EXISTS ad TEXT;
ALTER TABLE fiyat_gruplari ADD COLUMN IF NOT EXISTS aciklama TEXT;
ALTER TABLE fiyat_gruplari ADD COLUMN IF NOT EXISTS varsayilan_iskonto_orani DOUBLE PRECISION;
ALTER TABLE fiyat_gruplari ADD COLUMN IF NOT EXISTS aktif BOOLEAN;
ALTER TABLE fiyat_gruplari ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN;
ALTER TABLE fiyat_gruplari ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE fiyat_kademeleri ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE fiyat_kademeleri ADD COLUMN IF NOT EXISTS urun_id BIGINT;
ALTER TABLE fiyat_kademeleri ADD COLUMN IF NOT EXISTS fiyat_grubu_id BIGINT;
ALTER TABLE fiyat_kademeleri ADD COLUMN IF NOT EXISTS min_miktar DOUBLE PRECISION;
ALTER TABLE fiyat_kademeleri ADD COLUMN IF NOT EXISTS birim TEXT;
ALTER TABLE fiyat_kademeleri ADD COLUMN IF NOT EXISTS fiyat DOUBLE PRECISION;
ALTER TABLE fiyat_kademeleri ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE garson_cagri_log ADD COLUMN IF NOT EXISTS masa_id BIGINT;
ALTER TABLE garson_cagri_log ADD COLUMN IF NOT EXISTS masa_adi TEXT;
ALTER TABLE garson_cagri_log ADD COLUMN IF NOT EXISTS cagri_zamani TIMESTAMPTZ;
ALTER TABLE garson_cagri_log ADD COLUMN IF NOT EXISTS yanit_zamani TIMESTAMPTZ;
ALTER TABLE garson_cagri_log ADD COLUMN IF NOT EXISTS yanitlayan_id BIGINT;
ALTER TABLE garson_cagri_log ADD COLUMN IF NOT EXISTS durum TEXT;
ALTER TABLE garson_cagri_log ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE garson_cagri_log ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE gider_kategoriler ADD COLUMN IF NOT EXISTS ad TEXT;
ALTER TABLE gider_kategoriler ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE giderler ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE giderler ADD COLUMN IF NOT EXISTS kategori_id BIGINT;
ALTER TABLE giderler ADD COLUMN IF NOT EXISTS tutar DOUBLE PRECISION;
ALTER TABLE giderler ADD COLUMN IF NOT EXISTS aciklama TEXT;
ALTER TABLE giderler ADD COLUMN IF NOT EXISTS tarih TIMESTAMPTZ;
ALTER TABLE giderler ADD COLUMN IF NOT EXISTS belge_no TEXT;
ALTER TABLE giderler ADD COLUMN IF NOT EXISTS odeme_yontemi TEXT;
ALTER TABLE giderler ADD COLUMN IF NOT EXISTS cari_id BIGINT;
ALTER TABLE giderler ADD COLUMN IF NOT EXISTS kullanici_id BIGINT;
ALTER TABLE giderler ADD COLUMN IF NOT EXISTS sube_id BIGINT;
ALTER TABLE giderler ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE giderler ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
ALTER TABLE giderler ADD COLUMN IF NOT EXISTS banka_hesap_id BIGINT;
ALTER TABLE giderler ADD COLUMN IF NOT EXISTS kredi_karti_id BIGINT;
ALTER TABLE iade ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE iade ADD COLUMN IF NOT EXISTS satis_id BIGINT;
ALTER TABLE iade ADD COLUMN IF NOT EXISTS cari_id BIGINT;
ALTER TABLE iade ADD COLUMN IF NOT EXISTS fis_no TEXT;
ALTER TABLE iade ADD COLUMN IF NOT EXISTS tarih TIMESTAMPTZ;
ALTER TABLE iade ADD COLUMN IF NOT EXISTS toplam_tutar DOUBLE PRECISION;
ALTER TABLE iade ADD COLUMN IF NOT EXISTS iade_nedeni TEXT;
ALTER TABLE iade ADD COLUMN IF NOT EXISTS durum TEXT;
ALTER TABLE iade ADD COLUMN IF NOT EXISTS kasiyer_id BIGINT;
ALTER TABLE iade ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE iade ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
ALTER TABLE iade ADD COLUMN IF NOT EXISTS cihaz_id TEXT;
ALTER TABLE iade_kalem ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE iade_kalem ADD COLUMN IF NOT EXISTS iade_id BIGINT;
ALTER TABLE iade_kalem ADD COLUMN IF NOT EXISTS urun_id BIGINT;
ALTER TABLE iade_kalem ADD COLUMN IF NOT EXISTS urun_adi TEXT;
ALTER TABLE iade_kalem ADD COLUMN IF NOT EXISTS miktar DOUBLE PRECISION;
ALTER TABLE iade_kalem ADD COLUMN IF NOT EXISTS birim_fiyat DOUBLE PRECISION;
ALTER TABLE iade_kalem ADD COLUMN IF NOT EXISTS toplam DOUBLE PRECISION;
ALTER TABLE iade_kalem ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE irsaliye_kalem ADD COLUMN IF NOT EXISTS irsaliye_id BIGINT;
ALTER TABLE irsaliye_kalem ADD COLUMN IF NOT EXISTS urun_id BIGINT;
ALTER TABLE irsaliye_kalem ADD COLUMN IF NOT EXISTS urun_adi TEXT;
ALTER TABLE irsaliye_kalem ADD COLUMN IF NOT EXISTS miktar DOUBLE PRECISION;
ALTER TABLE irsaliye_kalem ADD COLUMN IF NOT EXISTS birim_fiyat DOUBLE PRECISION;
ALTER TABLE irsaliye_kalem ADD COLUMN IF NOT EXISTS toplam_tutar DOUBLE PRECISION;
ALTER TABLE irsaliye_kalem ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE irsaliye_kalem ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE irsaliyeler ADD COLUMN IF NOT EXISTS irsaliye_no TEXT;
ALTER TABLE irsaliyeler ADD COLUMN IF NOT EXISTS cari_id BIGINT;
ALTER TABLE irsaliyeler ADD COLUMN IF NOT EXISTS tarih TEXT;
ALTER TABLE irsaliyeler ADD COLUMN IF NOT EXISTS tip TEXT;
ALTER TABLE irsaliyeler ADD COLUMN IF NOT EXISTS toplam_tutar DOUBLE PRECISION;
ALTER TABLE irsaliyeler ADD COLUMN IF NOT EXISTS durum TEXT;
ALTER TABLE irsaliyeler ADD COLUMN IF NOT EXISTS kullanici_id BIGINT;
ALTER TABLE irsaliyeler ADD COLUMN IF NOT EXISTS created_at TEXT;
ALTER TABLE irsaliyeler ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
ALTER TABLE irsaliyeler ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE irsaliyeler ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE irsaliyeler ADD COLUMN IF NOT EXISTS aciklama TEXT;
ALTER TABLE irsaliyeler ADD COLUMN IF NOT EXISTS aciklama TEXT;  -- ➕ yerelde vardı, buluttan eksikti
ALTER TABLE irsaliyeler ADD COLUMN IF NOT EXISTS e_irsaliye_durum TEXT;
ALTER TABLE irsaliyeler ADD COLUMN IF NOT EXISTS e_irsaliye_uuid TEXT;
ALTER TABLE irsaliyeler ADD COLUMN IF NOT EXISTS e_irsaliye_xml TEXT;
ALTER TABLE irsaliyeler ADD COLUMN IF NOT EXISTS e_irsaliye_deneme_no BIGINT;
ALTER TABLE irsaliyeler ADD COLUMN IF NOT EXISTS e_irsaliye_gonderim_tarihi TIMESTAMPTZ;
ALTER TABLE kasa_hareketleri ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE kasa_hareketleri ADD COLUMN IF NOT EXISTS hareket_tipi TEXT;
ALTER TABLE kasa_hareketleri ADD COLUMN IF NOT EXISTS tutar DOUBLE PRECISION;
ALTER TABLE kasa_hareketleri ADD COLUMN IF NOT EXISTS bakiye_sonrasi DOUBLE PRECISION;
ALTER TABLE kasa_hareketleri ADD COLUMN IF NOT EXISTS referans_id BIGINT;
ALTER TABLE kasa_hareketleri ADD COLUMN IF NOT EXISTS referans_turu TEXT;
ALTER TABLE kasa_hareketleri ADD COLUMN IF NOT EXISTS tarih TIMESTAMPTZ;
ALTER TABLE kasa_hareketleri ADD COLUMN IF NOT EXISTS aciklama TEXT;
ALTER TABLE kasa_hareketleri ADD COLUMN IF NOT EXISTS kullanici_id BIGINT;
ALTER TABLE kasa_hareketleri ADD COLUMN IF NOT EXISTS sube_id BIGINT;
ALTER TABLE kasa_hareketleri ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE kasa_hareketleri ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
ALTER TABLE kasa_hareketleri ADD COLUMN IF NOT EXISTS odeme_yontemi TEXT;
ALTER TABLE kategoriler ADD COLUMN IF NOT EXISTS ad TEXT;
ALTER TABLE kategoriler ADD COLUMN IF NOT EXISTS ust_kategori_id BIGINT;
ALTER TABLE kategoriler ADD COLUMN IF NOT EXISTS sira BIGINT;
ALTER TABLE kategoriler ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE kategoriler ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN;
ALTER TABLE kredi_karti_hareket ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE kredi_karti_hareket ADD COLUMN IF NOT EXISTS kredi_karti_id BIGINT;
ALTER TABLE kredi_karti_hareket ADD COLUMN IF NOT EXISTS tutar DOUBLE PRECISION;
ALTER TABLE kredi_karti_hareket ADD COLUMN IF NOT EXISTS yon TEXT;
ALTER TABLE kredi_karti_hareket ADD COLUMN IF NOT EXISTS aciklama TEXT;
ALTER TABLE kredi_karti_hareket ADD COLUMN IF NOT EXISTS tarih TIMESTAMPTZ;
ALTER TABLE kredi_karti_hareket ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE kredi_karti_hareket ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN;
ALTER TABLE kredi_karti_hareket ADD COLUMN IF NOT EXISTS referans_id BIGINT;
ALTER TABLE kredi_karti_hareket ADD COLUMN IF NOT EXISTS referans_turu TEXT;
ALTER TABLE kredi_kartlari ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE kredi_kartlari ADD COLUMN IF NOT EXISTS banka_id BIGINT;
ALTER TABLE kredi_kartlari ADD COLUMN IF NOT EXISTS kart_adi TEXT;
ALTER TABLE kredi_kartlari ADD COLUMN IF NOT EXISTS son_kullanma TEXT;
ALTER TABLE kredi_kartlari ADD COLUMN IF NOT EXISTS kart_tipi TEXT;
ALTER TABLE kredi_kartlari ADD COLUMN IF NOT EXISTS kartlimit DOUBLE PRECISION;
ALTER TABLE kredi_kartlari ADD COLUMN IF NOT EXISTS kullanilan_limit DOUBLE PRECISION;
ALTER TABLE kredi_kartlari ADD COLUMN IF NOT EXISTS kalan_limit DOUBLE PRECISION;
ALTER TABLE kredi_kartlari ADD COLUMN IF NOT EXISTS faiz_orani DOUBLE PRECISION;
ALTER TABLE kredi_kartlari ADD COLUMN IF NOT EXISTS taksit_sayisi BIGINT;
ALTER TABLE kredi_kartlari ADD COLUMN IF NOT EXISTS kesim_tarihi TEXT;
ALTER TABLE kredi_kartlari ADD COLUMN IF NOT EXISTS son_odeme_tarihi TEXT;
ALTER TABLE kredi_kartlari ADD COLUMN IF NOT EXISTS aktif BOOLEAN;
ALTER TABLE kredi_kartlari ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE kredi_kartlari ADD COLUMN IF NOT EXISTS kart_no_maskeli TEXT;
ALTER TABLE kullanicilar ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE kullanicilar ADD COLUMN IF NOT EXISTS sube_id BIGINT;
ALTER TABLE kullanicilar ADD COLUMN IF NOT EXISTS kullanici_adi TEXT;
ALTER TABLE kullanicilar ADD COLUMN IF NOT EXISTS sifre_hash TEXT;
ALTER TABLE kullanicilar ADD COLUMN IF NOT EXISTS ad_soyad TEXT;
ALTER TABLE kullanicilar ADD COLUMN IF NOT EXISTS rol TEXT;
ALTER TABLE kullanicilar ADD COLUMN IF NOT EXISTS email TEXT;
ALTER TABLE kullanicilar ADD COLUMN IF NOT EXISTS telefon TEXT;
ALTER TABLE kullanicilar ADD COLUMN IF NOT EXISTS aktif BOOLEAN;
ALTER TABLE kullanicilar ADD COLUMN IF NOT EXISTS tuz TEXT;
ALTER TABLE kullanicilar ADD COLUMN IF NOT EXISTS plu BIGINT;
ALTER TABLE kullanicilar ADD COLUMN IF NOT EXISTS plu_kart_boyut BIGINT;
ALTER TABLE kullanicilar ADD COLUMN IF NOT EXISTS son_giris TIMESTAMPTZ;
ALTER TABLE kullanicilar ADD COLUMN IF NOT EXISTS kayit_tarihi TIMESTAMPTZ;
ALTER TABLE kullanicilar ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE kullanicilar ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN;
ALTER TABLE kullanicilar ADD COLUMN IF NOT EXISTS bayi_cari_id BIGINT;
ALTER TABLE lot_seri ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE lot_seri ADD COLUMN IF NOT EXISTS cihaz_id TEXT;
ALTER TABLE lot_seri ADD COLUMN IF NOT EXISTS urun_id BIGINT;
ALTER TABLE lot_seri ADD COLUMN IF NOT EXISTS lot_no TEXT;
ALTER TABLE lot_seri ADD COLUMN IF NOT EXISTS seri_no TEXT;
ALTER TABLE lot_seri ADD COLUMN IF NOT EXISTS miktar DOUBLE PRECISION;
ALTER TABLE lot_seri ADD COLUMN IF NOT EXISTS son_kullanma_tarihi TIMESTAMPTZ;
ALTER TABLE lot_seri ADD COLUMN IF NOT EXISTS uretim_tarihi TIMESTAMPTZ;
ALTER TABLE lot_seri ADD COLUMN IF NOT EXISTS tedarikci_cari_id BIGINT;
ALTER TABLE lot_seri ADD COLUMN IF NOT EXISTS aciklama TEXT;
ALTER TABLE lot_seri ADD COLUMN IF NOT EXISTS aktif BOOLEAN;
ALTER TABLE lot_seri ADD COLUMN IF NOT EXISTS kayit_tarihi TIMESTAMPTZ;
ALTER TABLE lot_seri ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE markalar ADD COLUMN IF NOT EXISTS ad TEXT;
ALTER TABLE markalar ADD COLUMN IF NOT EXISTS aktif BOOLEAN;
ALTER TABLE markalar ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE masa_hareket_log ADD COLUMN IF NOT EXISTS kaynak_masa_id BIGINT;
ALTER TABLE masa_hareket_log ADD COLUMN IF NOT EXISTS hedef_masa_id BIGINT;
ALTER TABLE masa_hareket_log ADD COLUMN IF NOT EXISTS islem_tipi TEXT;
ALTER TABLE masa_hareket_log ADD COLUMN IF NOT EXISTS siparis_id BIGINT;
ALTER TABLE masa_hareket_log ADD COLUMN IF NOT EXISTS yapan_kullanici_id BIGINT;
ALTER TABLE masa_hareket_log ADD COLUMN IF NOT EXISTS islem_zamani TIMESTAMPTZ;
ALTER TABLE masa_hareket_log ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE masa_hareket_log ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE masa_rezervasyon ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE masa_rezervasyon ADD COLUMN IF NOT EXISTS masa_id BIGINT;
ALTER TABLE masa_rezervasyon ADD COLUMN IF NOT EXISTS musteri_adi TEXT;
ALTER TABLE masa_rezervasyon ADD COLUMN IF NOT EXISTS telefon TEXT;
ALTER TABLE masa_rezervasyon ADD COLUMN IF NOT EXISTS kisi_sayisi BIGINT;
ALTER TABLE masa_rezervasyon ADD COLUMN IF NOT EXISTS tarih TIMESTAMPTZ;
ALTER TABLE masa_rezervasyon ADD COLUMN IF NOT EXISTS saat TIMESTAMPTZ;
ALTER TABLE masa_rezervasyon ADD COLUMN IF NOT EXISTS not_ TEXT;
ALTER TABLE masa_rezervasyon ADD COLUMN IF NOT EXISTS durum TEXT;
ALTER TABLE masa_rezervasyon ADD COLUMN IF NOT EXISTS kullanici_id BIGINT;
ALTER TABLE masa_rezervasyon ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ;
ALTER TABLE masa_rezervasyon ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE masa_rezervasyon ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN;
ALTER TABLE masa_siparis_kalem ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE masa_siparis_kalem ADD COLUMN IF NOT EXISTS siparis_id BIGINT;
ALTER TABLE masa_siparis_kalem ADD COLUMN IF NOT EXISTS urun_id BIGINT;
ALTER TABLE masa_siparis_kalem ADD COLUMN IF NOT EXISTS urun_adi TEXT;
ALTER TABLE masa_siparis_kalem ADD COLUMN IF NOT EXISTS miktar DOUBLE PRECISION;
ALTER TABLE masa_siparis_kalem ADD COLUMN IF NOT EXISTS birim_fiyat DOUBLE PRECISION;
ALTER TABLE masa_siparis_kalem ADD COLUMN IF NOT EXISTS kdv_oran DOUBLE PRECISION;
ALTER TABLE masa_siparis_kalem ADD COLUMN IF NOT EXISTS not_ TEXT;
ALTER TABLE masa_siparis_kalem ADD COLUMN IF NOT EXISTS durum TEXT;
ALTER TABLE masa_siparis_kalem ADD COLUMN IF NOT EXISTS eklenme_zamani TIMESTAMPTZ;
ALTER TABLE masa_siparis_kalem ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE masa_siparis_kalem ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN;
ALTER TABLE masa_siparisleri ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE masa_siparisleri ADD COLUMN IF NOT EXISTS masa_id BIGINT;
ALTER TABLE masa_siparisleri ADD COLUMN IF NOT EXISTS cari_id BIGINT;
ALTER TABLE masa_siparisleri ADD COLUMN IF NOT EXISTS cari_adi TEXT;
ALTER TABLE masa_siparisleri ADD COLUMN IF NOT EXISTS durum TEXT;
ALTER TABLE masa_siparisleri ADD COLUMN IF NOT EXISTS acilis_zamani TIMESTAMPTZ;
ALTER TABLE masa_siparisleri ADD COLUMN IF NOT EXISTS kapanis_zamani TIMESTAMPTZ;
ALTER TABLE masa_siparisleri ADD COLUMN IF NOT EXISTS toplam_tutar DOUBLE PRECISION;
ALTER TABLE masa_siparisleri ADD COLUMN IF NOT EXISTS not_ TEXT;
ALTER TABLE masa_siparisleri ADD COLUMN IF NOT EXISTS kullanici_id BIGINT;
ALTER TABLE masa_siparisleri ADD COLUMN IF NOT EXISTS satis_id BIGINT;
ALTER TABLE masa_siparisleri ADD COLUMN IF NOT EXISTS garson_id BIGINT;
ALTER TABLE masa_siparisleri ADD COLUMN IF NOT EXISTS garson_adi TEXT;
ALTER TABLE masa_siparisleri ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE masa_siparisleri ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN;
ALTER TABLE masalar ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE masalar ADD COLUMN IF NOT EXISTS ad TEXT;
ALTER TABLE masalar ADD COLUMN IF NOT EXISTS kategori TEXT;
ALTER TABLE masalar ADD COLUMN IF NOT EXISTS kapasite BIGINT;
ALTER TABLE masalar ADD COLUMN IF NOT EXISTS durum TEXT;
ALTER TABLE masalar ADD COLUMN IF NOT EXISTS sira BIGINT;
ALTER TABLE masalar ADD COLUMN IF NOT EXISTS sube_id BIGINT;
ALTER TABLE masalar ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE masalar ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN;
ALTER TABLE musteri_puan ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE musteri_puan ADD COLUMN IF NOT EXISTS cari_id BIGINT;
ALTER TABLE musteri_puan ADD COLUMN IF NOT EXISTS toplam_puan DOUBLE PRECISION;
ALTER TABLE musteri_puan ADD COLUMN IF NOT EXISTS kullanilan DOUBLE PRECISION;
ALTER TABLE musteri_puan ADD COLUMN IF NOT EXISTS son_islem TIMESTAMPTZ;
ALTER TABLE musteri_puan ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE onay_talepleri ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE onay_talepleri ADD COLUMN IF NOT EXISTS tur TEXT;
ALTER TABLE onay_talepleri ADD COLUMN IF NOT EXISTS referans_turu TEXT;
ALTER TABLE onay_talepleri ADD COLUMN IF NOT EXISTS referans_id BIGINT;
ALTER TABLE onay_talepleri ADD COLUMN IF NOT EXISTS tutar DOUBLE PRECISION;
ALTER TABLE onay_talepleri ADD COLUMN IF NOT EXISTS esik_tutar DOUBLE PRECISION;
ALTER TABLE onay_talepleri ADD COLUMN IF NOT EXISTS aciklama TEXT;
ALTER TABLE onay_talepleri ADD COLUMN IF NOT EXISTS kullanici_id BIGINT;
ALTER TABLE onay_talepleri ADD COLUMN IF NOT EXISTS kullanici_adi TEXT;
ALTER TABLE onay_talepleri ADD COLUMN IF NOT EXISTS sube_id BIGINT;
ALTER TABLE onay_talepleri ADD COLUMN IF NOT EXISTS tarih TIMESTAMPTZ;
ALTER TABLE onay_talepleri ADD COLUMN IF NOT EXISTS goruldu BOOLEAN;
ALTER TABLE onay_talepleri ADD COLUMN IF NOT EXISTS goren_kullanici_id BIGINT;
ALTER TABLE onay_talepleri ADD COLUMN IF NOT EXISTS goruldu_tarihi TIMESTAMPTZ;
ALTER TABLE onay_talepleri ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE onay_talepleri ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN;
ALTER TABLE fis_seri ADD COLUMN IF NOT EXISTS sube_id BIGINT;
ALTER TABLE fis_seri ADD COLUMN IF NOT EXISTS fis_tipi TEXT;
ALTER TABLE fis_seri ADD COLUMN IF NOT EXISTS son_fis_no BIGINT;
ALTER TABLE fis_seri ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE personel ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE personel ADD COLUMN IF NOT EXISTS kullanici_id BIGINT;
ALTER TABLE personel ADD COLUMN IF NOT EXISTS ad_soyad TEXT;
ALTER TABLE personel ADD COLUMN IF NOT EXISTS tc_kimlik TEXT;
ALTER TABLE personel ADD COLUMN IF NOT EXISTS pozisyon TEXT;
ALTER TABLE personel ADD COLUMN IF NOT EXISTS departman TEXT;
ALTER TABLE personel ADD COLUMN IF NOT EXISTS telefon TEXT;
ALTER TABLE personel ADD COLUMN IF NOT EXISTS email TEXT;
ALTER TABLE personel ADD COLUMN IF NOT EXISTS maas DOUBLE PRECISION;
ALTER TABLE personel ADD COLUMN IF NOT EXISTS calisma_saati DOUBLE PRECISION;
ALTER TABLE personel ADD COLUMN IF NOT EXISTS ise_baslama TIMESTAMPTZ;
ALTER TABLE personel ADD COLUMN IF NOT EXISTS isten_cikis TIMESTAMPTZ;
ALTER TABLE personel ADD COLUMN IF NOT EXISTS aktif BOOLEAN;
ALTER TABLE personel ADD COLUMN IF NOT EXISTS notlar TEXT;
ALTER TABLE personel ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE personel ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN;
ALTER TABLE promosyon_aksiyon ADD COLUMN IF NOT EXISTS tanim_id BIGINT;
ALTER TABLE promosyon_aksiyon ADD COLUMN IF NOT EXISTS aksiyon_tipi TEXT;
ALTER TABLE promosyon_aksiyon ADD COLUMN IF NOT EXISTS aksiyon_degeri TEXT;
ALTER TABLE promosyon_aksiyon ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE promosyon_aksiyon ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE promosyon_kosul ADD COLUMN IF NOT EXISTS tanim_id BIGINT;
ALTER TABLE promosyon_kosul ADD COLUMN IF NOT EXISTS kosul_tipi TEXT;
ALTER TABLE promosyon_kosul ADD COLUMN IF NOT EXISTS kosul_degeri TEXT;
ALTER TABLE promosyon_kosul ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE promosyon_kosul ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE promosyon_tanim ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE promosyon_tanim ADD COLUMN IF NOT EXISTS ad TEXT;
ALTER TABLE promosyon_tanim ADD COLUMN IF NOT EXISTS aciklama TEXT;
ALTER TABLE promosyon_tanim ADD COLUMN IF NOT EXISTS tip TEXT;
ALTER TABLE promosyon_tanim ADD COLUMN IF NOT EXISTS baslangic TIMESTAMPTZ;
ALTER TABLE promosyon_tanim ADD COLUMN IF NOT EXISTS bitis TIMESTAMPTZ;
ALTER TABLE promosyon_tanim ADD COLUMN IF NOT EXISTS aktif BOOLEAN;
ALTER TABLE promosyon_tanim ADD COLUMN IF NOT EXISTS oncelik BIGINT;
ALTER TABLE promosyon_tanim ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ;
ALTER TABLE promosyon_tanim ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE promosyonlar ADD COLUMN IF NOT EXISTS urun_id BIGINT;
ALTER TABLE promosyonlar ADD COLUMN IF NOT EXISTS min_miktar DOUBLE PRECISION;
ALTER TABLE promosyonlar ADD COLUMN IF NOT EXISTS iskonto_oran DOUBLE PRECISION;
ALTER TABLE promosyonlar ADD COLUMN IF NOT EXISTS baslangic_tarihi TEXT;
ALTER TABLE promosyonlar ADD COLUMN IF NOT EXISTS bitis_tarihi TEXT;
ALTER TABLE promosyonlar ADD COLUMN IF NOT EXISTS aktif BOOLEAN;
ALTER TABLE promosyonlar ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE promosyonlar ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE promosyonlar ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
ALTER TABLE promosyonlar ADD COLUMN IF NOT EXISTS promosyon_adi TEXT;  -- ➕ yerel kolon adı; 'ad' farklı/eski isim, ikisi de korunuyor
ALTER TABLE promosyonlar ADD COLUMN IF NOT EXISTS iskonto_tutar DOUBLE PRECISION;  -- ➕ yerelde vardı, buluttan tamamen eksikti
ALTER TABLE puan_hareket ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE puan_hareket ADD COLUMN IF NOT EXISTS cari_id BIGINT;
ALTER TABLE puan_hareket ADD COLUMN IF NOT EXISTS islem_tipi TEXT;
ALTER TABLE puan_hareket ADD COLUMN IF NOT EXISTS puan DOUBLE PRECISION;
ALTER TABLE puan_hareket ADD COLUMN IF NOT EXISTS referans_id BIGINT;
ALTER TABLE puan_hareket ADD COLUMN IF NOT EXISTS tarih TIMESTAMPTZ;
ALTER TABLE puan_hareket ADD COLUMN IF NOT EXISTS aciklama TEXT;
ALTER TABLE puan_hareket ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE rol_yetkileri ADD COLUMN IF NOT EXISTS rol TEXT;
ALTER TABLE rol_yetkileri ADD COLUMN IF NOT EXISTS yetki_kodu TEXT;
ALTER TABLE rol_yetkileri ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE rol_yetkileri ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE roller_yetki ADD COLUMN IF NOT EXISTS kullanici_id BIGINT;
ALTER TABLE roller_yetki ADD COLUMN IF NOT EXISTS yetki_kodu TEXT;
ALTER TABLE roller_yetki ADD COLUMN IF NOT EXISTS created_at TEXT;
ALTER TABLE roller_yetki ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE roller_yetki ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE satis_kalem ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE satis_kalem ADD COLUMN IF NOT EXISTS satis_id BIGINT;
ALTER TABLE satis_kalem ADD COLUMN IF NOT EXISTS urun_id BIGINT;
ALTER TABLE satis_kalem ADD COLUMN IF NOT EXISTS urun_adi TEXT;
ALTER TABLE satis_kalem ADD COLUMN IF NOT EXISTS barkod TEXT;
ALTER TABLE satis_kalem ADD COLUMN IF NOT EXISTS miktar DOUBLE PRECISION;
ALTER TABLE satis_kalem ADD COLUMN IF NOT EXISTS birim_fiyat DOUBLE PRECISION;
ALTER TABLE satis_kalem ADD COLUMN IF NOT EXISTS iskonto_oran DOUBLE PRECISION;
ALTER TABLE satis_kalem ADD COLUMN IF NOT EXISTS iskonto_tutar DOUBLE PRECISION;
ALTER TABLE satis_kalem ADD COLUMN IF NOT EXISTS kdv_oran DOUBLE PRECISION;
ALTER TABLE satis_kalem ADD COLUMN IF NOT EXISTS kdv_tutar DOUBLE PRECISION;
ALTER TABLE satis_kalem ADD COLUMN IF NOT EXISTS net_fiyat DOUBLE PRECISION;
ALTER TABLE satis_kalem ADD COLUMN IF NOT EXISTS toplam_tutar DOUBLE PRECISION;
ALTER TABLE satis_kalem ADD COLUMN IF NOT EXISTS lot_id BIGINT;
ALTER TABLE satis_kalem ADD COLUMN IF NOT EXISTS seri_no TEXT;
ALTER TABLE satis_kalem ADD COLUMN IF NOT EXISTS alis_fiyat DOUBLE PRECISION;
ALTER TABLE satis_kalem ADD COLUMN IF NOT EXISTS alis_fiyat_kdv DOUBLE PRECISION;
ALTER TABLE satis_kalem ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE satis_kalem ADD COLUMN IF NOT EXISTS cihaz_id TEXT;
ALTER TABLE satislar ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE satislar ADD COLUMN IF NOT EXISTS fis_no TEXT;
ALTER TABLE satislar ADD COLUMN IF NOT EXISTS tarih TIMESTAMPTZ;
ALTER TABLE satislar ADD COLUMN IF NOT EXISTS cari_id BIGINT;
ALTER TABLE satislar ADD COLUMN IF NOT EXISTS toplam_tutar DOUBLE PRECISION;
ALTER TABLE satislar ADD COLUMN IF NOT EXISTS iskonto_tutar DOUBLE PRECISION;
ALTER TABLE satislar ADD COLUMN IF NOT EXISTS iskonto_oran DOUBLE PRECISION;
ALTER TABLE satislar ADD COLUMN IF NOT EXISTS kdv_tutar DOUBLE PRECISION;
ALTER TABLE satislar ADD COLUMN IF NOT EXISTS genel_toplam DOUBLE PRECISION;
ALTER TABLE satislar ADD COLUMN IF NOT EXISTS odenen_tutar DOUBLE PRECISION;
ALTER TABLE satislar ADD COLUMN IF NOT EXISTS odeme_yontemi TEXT;
ALTER TABLE satislar ADD COLUMN IF NOT EXISTS fis_tipi TEXT;
ALTER TABLE satislar ADD COLUMN IF NOT EXISTS aciklama TEXT;
ALTER TABLE satislar ADD COLUMN IF NOT EXISTS kargo_ucreti DOUBLE PRECISION;
ALTER TABLE satislar ADD COLUMN IF NOT EXISTS kasiyer_id BIGINT;
ALTER TABLE satislar ADD COLUMN IF NOT EXISTS kullanici_id BIGINT;
ALTER TABLE satislar ADD COLUMN IF NOT EXISTS vardiya_id BIGINT;
ALTER TABLE satislar ADD COLUMN IF NOT EXISTS sube_id BIGINT;
ALTER TABLE satislar ADD COLUMN IF NOT EXISTS iptal BOOLEAN;
ALTER TABLE satislar ADD COLUMN IF NOT EXISTS iptal_tarihi TIMESTAMPTZ;
ALTER TABLE satislar ADD COLUMN IF NOT EXISTS iptal_nedeni TEXT;
ALTER TABLE satislar ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE satislar ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN;
ALTER TABLE satislar ADD COLUMN IF NOT EXISTS efatura_uuid TEXT;
ALTER TABLE satislar ADD COLUMN IF NOT EXISTS efatura_durum TEXT;
ALTER TABLE satislar ADD COLUMN IF NOT EXISTS efatura_gonderim_tarihi TEXT;
ALTER TABLE satislar ADD COLUMN IF NOT EXISTS efatura_yanit TEXT;
ALTER TABLE satislar ADD COLUMN IF NOT EXISTS servis_ucreti DOUBLE PRECISION;
ALTER TABLE satislar ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
ALTER TABLE satislar ADD COLUMN IF NOT EXISTS cihaz_id TEXT;
ALTER TABLE stok_hareket ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE stok_hareket ADD COLUMN IF NOT EXISTS cihaz_id TEXT;
ALTER TABLE stok_hareket ADD COLUMN IF NOT EXISTS urun_id BIGINT;
ALTER TABLE stok_hareket ADD COLUMN IF NOT EXISTS hareket_turu TEXT;
ALTER TABLE stok_hareket ADD COLUMN IF NOT EXISTS miktar DOUBLE PRECISION;
ALTER TABLE stok_hareket ADD COLUMN IF NOT EXISTS onceki_stok DOUBLE PRECISION;
ALTER TABLE stok_hareket ADD COLUMN IF NOT EXISTS sonraki_stok DOUBLE PRECISION;
ALTER TABLE stok_hareket ADD COLUMN IF NOT EXISTS birim_maliyet DOUBLE PRECISION;
ALTER TABLE stok_hareket ADD COLUMN IF NOT EXISTS tarih TIMESTAMPTZ;
ALTER TABLE stok_hareket ADD COLUMN IF NOT EXISTS referans_id BIGINT;
ALTER TABLE stok_hareket ADD COLUMN IF NOT EXISTS referans_turu TEXT;
ALTER TABLE stok_hareket ADD COLUMN IF NOT EXISTS lot_id BIGINT;
ALTER TABLE stok_hareket ADD COLUMN IF NOT EXISTS aciklama TEXT;
ALTER TABLE stok_hareket ADD COLUMN IF NOT EXISTS kullanici_id BIGINT;
ALTER TABLE stok_hareket ADD COLUMN IF NOT EXISTS sube_id BIGINT;
ALTER TABLE stok_hareket ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE sube_urun ADD COLUMN IF NOT EXISTS urun_id BIGINT;
ALTER TABLE sube_urun ADD COLUMN IF NOT EXISTS sube_id BIGINT;
ALTER TABLE sube_urun ADD COLUMN IF NOT EXISTS stok DOUBLE PRECISION;
ALTER TABLE sube_urun ADD COLUMN IF NOT EXISTS rezerve_stok DOUBLE PRECISION;
ALTER TABLE sube_urun ADD COLUMN IF NOT EXISTS kritik_stok DOUBLE PRECISION;
ALTER TABLE sube_urun ADD COLUMN IF NOT EXISTS satis_fiyati DOUBLE PRECISION;
ALTER TABLE sube_urun ADD COLUMN IF NOT EXISTS raf_kodu TEXT;
ALTER TABLE sube_urun ADD COLUMN IF NOT EXISTS son_guncelleme TIMESTAMPTZ;
ALTER TABLE sube_urun ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE sube_urun ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE sube_urun ADD COLUMN IF NOT EXISTS alis_fiyati DOUBLE PRECISION;
ALTER TABLE sube_urun ADD COLUMN IF NOT EXISTS alis_fiyati DOUBLE PRECISION;  -- ➕ yerelde vardı, buluttan eksikti
ALTER TABLE subeler ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE subeler ADD COLUMN IF NOT EXISTS sube_kodu TEXT;
ALTER TABLE subeler ADD COLUMN IF NOT EXISTS sube_adi TEXT;
ALTER TABLE subeler ADD COLUMN IF NOT EXISTS adres TEXT;
ALTER TABLE subeler ADD COLUMN IF NOT EXISTS telefon TEXT;
ALTER TABLE subeler ADD COLUMN IF NOT EXISTS email TEXT;
ALTER TABLE subeler ADD COLUMN IF NOT EXISTS vergi_no TEXT;
ALTER TABLE subeler ADD COLUMN IF NOT EXISTS aktif BOOLEAN;
ALTER TABLE subeler ADD COLUMN IF NOT EXISTS created_at TEXT;
ALTER TABLE subeler ADD COLUMN IF NOT EXISTS updated_at TEXT;
ALTER TABLE subeler ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE subeler ADD COLUMN IF NOT EXISTS deleted BIGINT;
ALTER TABLE subeler ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN;
ALTER TABLE tedarikci_siparis_kalem ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE tedarikci_siparis_kalem ADD COLUMN IF NOT EXISTS siparis_id BIGINT;
ALTER TABLE tedarikci_siparis_kalem ADD COLUMN IF NOT EXISTS urun_id BIGINT;
ALTER TABLE tedarikci_siparis_kalem ADD COLUMN IF NOT EXISTS siparis_mik DOUBLE PRECISION;
ALTER TABLE tedarikci_siparis_kalem ADD COLUMN IF NOT EXISTS teslim_mik DOUBLE PRECISION;
ALTER TABLE tedarikci_siparis_kalem ADD COLUMN IF NOT EXISTS birim_fiyat DOUBLE PRECISION;
ALTER TABLE tedarikci_siparis_kalem ADD COLUMN IF NOT EXISTS kdv_oran DOUBLE PRECISION;
ALTER TABLE tedarikci_siparis_kalem ADD COLUMN IF NOT EXISTS toplam_tutar DOUBLE PRECISION;
ALTER TABLE tedarikci_siparis_kalem ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE tedarikci_siparisler ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE tedarikci_siparisler ADD COLUMN IF NOT EXISTS cari_id BIGINT;
ALTER TABLE tedarikci_siparisler ADD COLUMN IF NOT EXISTS siparis_no TEXT;
ALTER TABLE tedarikci_siparisler ADD COLUMN IF NOT EXISTS siparis_tarihi TIMESTAMPTZ;
ALTER TABLE tedarikci_siparisler ADD COLUMN IF NOT EXISTS teslim_tarihi TIMESTAMPTZ;
ALTER TABLE tedarikci_siparisler ADD COLUMN IF NOT EXISTS toplam_tutar DOUBLE PRECISION;
ALTER TABLE tedarikci_siparisler ADD COLUMN IF NOT EXISTS durum TEXT;
ALTER TABLE tedarikci_siparisler ADD COLUMN IF NOT EXISTS notlar TEXT;
ALTER TABLE tedarikci_siparisler ADD COLUMN IF NOT EXISTS olusturan_id BIGINT;
ALTER TABLE tedarikci_siparisler ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE tedarikci_siparisler ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN;
ALTER TABLE urun_fiyat_gruplari ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE urun_fiyat_gruplari ADD COLUMN IF NOT EXISTS urun_id BIGINT;
ALTER TABLE urun_fiyat_gruplari ADD COLUMN IF NOT EXISTS fiyat_grubu_id BIGINT;
ALTER TABLE urun_fiyat_gruplari ADD COLUMN IF NOT EXISTS fiyat DOUBLE PRECISION;
ALTER TABLE urun_fiyat_gruplari ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS kod TEXT;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS barkod TEXT;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS barkodlar TEXT;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS urun_adi TEXT;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS alternatif_urun_adi TEXT;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS birim_adi TEXT;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS alis_fiyat DOUBLE PRECISION;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS alis_fiyat_kdv_dahil DOUBLE PRECISION;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS satis_fiyati DOUBLE PRECISION;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS stok DOUBLE PRECISION;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS toplam_maliyet DOUBLE PRECISION;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS toplam_stok DOUBLE PRECISION;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS alis_kdv_oran DOUBLE PRECISION;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS kdv_oran TEXT;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS kategori_id BIGINT;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS ana_grup TEXT;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS alt_grup TEXT;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS aktif BOOLEAN;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS seri_no_takibi BOOLEAN;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS lot_takibi BOOLEAN;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS lot_no TEXT;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS son_kullanma_tarihi TIMESTAMPTZ;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS alan1 TEXT;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS alan2 TEXT;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS alan3 TEXT;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS alan4 TEXT;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS para_birimi TEXT;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS indirim_orani DOUBLE PRECISION;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS otomatik_indirim BOOLEAN;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS son_alim_indirim_oran DOUBLE PRECISION;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS minimum_stok DOUBLE PRECISION;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS maksimum_stok DOUBLE PRECISION;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS maksimum_satir_miktari DOUBLE PRECISION;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS renk TEXT;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS beden TEXT;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS sube TEXT;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS resim_yolu TEXT;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS resim_url TEXT;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS qr_menude BIGINT;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS uretici TEXT;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS marka TEXT;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS model TEXT;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS grup_sorumlusu TEXT;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS mensei TEXT;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS raf_numarasi TEXT;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS raf_omru BIGINT;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS plu_numarasi TEXT;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS puan_orani DOUBLE PRECISION;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS plu BIGINT;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS plu_kart_boyut BIGINT;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS plu_sira BIGINT;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS doviz_kodu TEXT;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS doviz_tutari DOUBLE PRECISION;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS muhasebe_kodu TEXT;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS muafiyet_kodu TEXT;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS resmi_bakiye DOUBLE PRECISION;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS barkod_olcu_birimi TEXT;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS en DOUBLE PRECISION;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS boy DOUBLE PRECISION;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS yukseklik DOUBLE PRECISION;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS agirlik DOUBLE PRECISION;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS eski_kodu TEXT;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS kart_tipi TEXT;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS seri_numarasi TEXT;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS fiyat_guncelleme_tarih TIMESTAMPTZ;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS fiyat_guncelleyen_kullanici TEXT;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS barkod_yazdirma_tarih TIMESTAMPTZ;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS barkod_yazdiran_kullanici TEXT;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS maliyet_guncelleme_tarih TIMESTAMPTZ;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS maliyet_guncelleyen_kullanici TEXT;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS guncelleme_tarihi TIMESTAMPTZ;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS kayit_tarihi TIMESTAMPTZ;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS guncelleyen_kullanici TEXT;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS kaydeden_kullanici TEXT;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS sync_status TEXT;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS kdv_dahil BIGINT;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS barkod_tipi TEXT;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS max_stok DOUBLE PRECISION;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS cihaz_id TEXT;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS zaman_fiyat_id BIGINT;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS indirimli_fiyat DOUBLE PRECISION;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS hacim DOUBLE PRECISION;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS evrak_kontrol_aktif BOOLEAN;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS lot_aciklama TEXT;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS eski_fiyat DOUBLE PRECISION;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS eski_fiyat_tarih TIMESTAMPTZ;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS promosyon_grup TEXT;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS promosyon_aktif BOOLEAN;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS recete_katsayi DOUBLE PRECISION;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS net_alis_fiyat DOUBLE PRECISION;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS toptan_fiyat DOUBLE PRECISION;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS koli_ici_miktar DOUBLE PRECISION;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS koli_birim_adi TEXT;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS satis_birimi_tipi TEXT;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS toptan_satista BIGINT;
ALTER TABLE urunler ADD COLUMN IF NOT EXISTS asgari_siparis_miktari DOUBLE PRECISION;
ALTER TABLE vardiyalar ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE vardiyalar ADD COLUMN IF NOT EXISTS kullanici_id BIGINT;
ALTER TABLE vardiyalar ADD COLUMN IF NOT EXISTS sube_id BIGINT;
ALTER TABLE vardiyalar ADD COLUMN IF NOT EXISTS acilis_tarihi TIMESTAMPTZ;
ALTER TABLE vardiyalar ADD COLUMN IF NOT EXISTS kapanis_tarihi TIMESTAMPTZ;
ALTER TABLE vardiyalar ADD COLUMN IF NOT EXISTS acilis_kasasi DOUBLE PRECISION;
ALTER TABLE vardiyalar ADD COLUMN IF NOT EXISTS kapanis_kasasi DOUBLE PRECISION;
ALTER TABLE vardiyalar ADD COLUMN IF NOT EXISTS baslangic_bakiye DOUBLE PRECISION;
ALTER TABLE vardiyalar ADD COLUMN IF NOT EXISTS bitis_bakiye DOUBLE PRECISION;
ALTER TABLE vardiyalar ADD COLUMN IF NOT EXISTS nakit_sayim DOUBLE PRECISION;
ALTER TABLE vardiyalar ADD COLUMN IF NOT EXISTS kart_toplam DOUBLE PRECISION;
ALTER TABLE vardiyalar ADD COLUMN IF NOT EXISTS fark DOUBLE PRECISION;
ALTER TABLE vardiyalar ADD COLUMN IF NOT EXISTS notlar TEXT;
ALTER TABLE vardiyalar ADD COLUMN IF NOT EXISTS durum TEXT;
ALTER TABLE vardiyalar ADD COLUMN IF NOT EXISTS onaylayan_kullanici_id BIGINT;
ALTER TABLE vardiyalar ADD COLUMN IF NOT EXISTS onaylanma_tarihi TIMESTAMPTZ;
ALTER TABLE vardiyalar ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE vardiyalar ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
ALTER TABLE zaman_fiyat ADD COLUMN IF NOT EXISTS urun_id BIGINT;
ALTER TABLE zaman_fiyat ADD COLUMN IF NOT EXISTS gun_listesi TEXT;
ALTER TABLE zaman_fiyat ADD COLUMN IF NOT EXISTS baslangic_saat TEXT;
ALTER TABLE zaman_fiyat ADD COLUMN IF NOT EXISTS bitis_saat TEXT;
ALTER TABLE zaman_fiyat ADD COLUMN IF NOT EXISTS fiyat_turu TEXT;
ALTER TABLE zaman_fiyat ADD COLUMN IF NOT EXISTS deger DOUBLE PRECISION;
ALTER TABLE zaman_fiyat ADD COLUMN IF NOT EXISTS aktif BOOLEAN;
ALTER TABLE zaman_fiyat ADD COLUMN IF NOT EXISTS aciklama TEXT;
ALTER TABLE zaman_fiyat ADD COLUMN IF NOT EXISTS olusturma TIMESTAMPTZ;
ALTER TABLE zaman_fiyat ADD COLUMN IF NOT EXISTS guncelleme TIMESTAMPTZ;
ALTER TABLE zaman_fiyat ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE zaman_fiyat ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;

-- Yıl Sonu Devir / Dönem Kapatma / Arşivleme (2026-09-16)
ALTER TABLE donemler ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE donemler ADD COLUMN IF NOT EXISTS donem_yili BIGINT;
ALTER TABLE donemler ADD COLUMN IF NOT EXISTS baslangic_tarihi TEXT;
ALTER TABLE donemler ADD COLUMN IF NOT EXISTS bitis_tarihi TEXT;
ALTER TABLE donemler ADD COLUMN IF NOT EXISTS durum TEXT;
ALTER TABLE donemler ADD COLUMN IF NOT EXISTS kapanis_tarihi TEXT;
ALTER TABLE donemler ADD COLUMN IF NOT EXISTS kapanisi_yapan_kullanici_id BIGINT;
ALTER TABLE donemler ADD COLUMN IF NOT EXISTS kapanis_cihazi TEXT;
ALTER TABLE donemler ADD COLUMN IF NOT EXISTS backup_durumu TEXT;
ALTER TABLE donemler ADD COLUMN IF NOT EXISTS arsiv_durumu TEXT;
ALTER TABLE donemler ADD COLUMN IF NOT EXISTS devir_durumu TEXT;
ALTER TABLE donemler ADD COLUMN IF NOT EXISTS created_at TEXT;
ALTER TABLE donemler ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE donem_sube_durumlari ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE donem_sube_durumlari ADD COLUMN IF NOT EXISTS donem_id BIGINT;
ALTER TABLE donem_sube_durumlari ADD COLUMN IF NOT EXISTS sube_id BIGINT;
ALTER TABLE donem_sube_durumlari ADD COLUMN IF NOT EXISTS durum TEXT;
ALTER TABLE donem_sube_durumlari ADD COLUMN IF NOT EXISTS kapanis_tarihi TEXT;
ALTER TABLE donem_sube_durumlari ADD COLUMN IF NOT EXISTS kapanisi_yapan_kullanici_id BIGINT;
ALTER TABLE donem_sube_durumlari ADD COLUMN IF NOT EXISTS kapanis_cihazi TEXT;
ALTER TABLE donem_sube_durumlari ADD COLUMN IF NOT EXISTS backup_durumu TEXT;
ALTER TABLE donem_sube_durumlari ADD COLUMN IF NOT EXISTS arsiv_durumu TEXT;
ALTER TABLE donem_sube_durumlari ADD COLUMN IF NOT EXISTS devir_durumu TEXT;
ALTER TABLE donem_sube_durumlari ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE devir_checkpoint ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE devir_checkpoint ADD COLUMN IF NOT EXISTS devir_id TEXT;
ALTER TABLE devir_checkpoint ADD COLUMN IF NOT EXISTS kaynak_donem_id BIGINT;
ALTER TABLE devir_checkpoint ADD COLUMN IF NOT EXISTS hedef_donem_id BIGINT;
ALTER TABLE devir_checkpoint ADD COLUMN IF NOT EXISTS sube_id BIGINT;
ALTER TABLE devir_checkpoint ADD COLUMN IF NOT EXISTS durum TEXT;
ALTER TABLE devir_checkpoint ADD COLUMN IF NOT EXISTS mevcut_faz BIGINT;
ALTER TABLE devir_checkpoint ADD COLUMN IF NOT EXISTS faz_ilerleme_json TEXT;
ALTER TABLE devir_checkpoint ADD COLUMN IF NOT EXISTS baslangic_zamani TEXT;
ALTER TABLE devir_checkpoint ADD COLUMN IF NOT EXISTS son_guncelleme TEXT;
ALTER TABLE devir_checkpoint ADD COLUMN IF NOT EXISTS tamamlanma_zamani TEXT;
ALTER TABLE devir_checkpoint ADD COLUMN IF NOT EXISTS hata_mesaji TEXT;
ALTER TABLE devir_checkpoint ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE donem_kilit ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE donem_kilit ADD COLUMN IF NOT EXISTS donem_id BIGINT;
ALTER TABLE donem_kilit ADD COLUMN IF NOT EXISTS sube_id BIGINT;
ALTER TABLE donem_kilit ADD COLUMN IF NOT EXISTS cihaz_id TEXT;
ALTER TABLE donem_kilit ADD COLUMN IF NOT EXISTS kilit_zamani TEXT;
ALTER TABLE donem_kilit ADD COLUMN IF NOT EXISTS son_yenileme TEXT;
ALTER TABLE donem_kilit ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE stok_kapanis_snapshot ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE stok_kapanis_snapshot ADD COLUMN IF NOT EXISTS devir_id TEXT;
ALTER TABLE stok_kapanis_snapshot ADD COLUMN IF NOT EXISTS donem_id BIGINT;
ALTER TABLE stok_kapanis_snapshot ADD COLUMN IF NOT EXISTS sube_id BIGINT;
ALTER TABLE stok_kapanis_snapshot ADD COLUMN IF NOT EXISTS urun_id BIGINT;
ALTER TABLE stok_kapanis_snapshot ADD COLUMN IF NOT EXISTS miktar DOUBLE PRECISION;
ALTER TABLE stok_kapanis_snapshot ADD COLUMN IF NOT EXISTS kaynak_hash TEXT;
ALTER TABLE stok_kapanis_snapshot ADD COLUMN IF NOT EXISTS olusturma_tarihi TEXT;
ALTER TABLE stok_kapanis_snapshot ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE cari_kapanis_snapshot ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE cari_kapanis_snapshot ADD COLUMN IF NOT EXISTS devir_id TEXT;
ALTER TABLE cari_kapanis_snapshot ADD COLUMN IF NOT EXISTS donem_id BIGINT;
ALTER TABLE cari_kapanis_snapshot ADD COLUMN IF NOT EXISTS cari_id BIGINT;
ALTER TABLE cari_kapanis_snapshot ADD COLUMN IF NOT EXISTS bakiye DOUBLE PRECISION;
ALTER TABLE cari_kapanis_snapshot ADD COLUMN IF NOT EXISTS kaynak_hash TEXT;
ALTER TABLE cari_kapanis_snapshot ADD COLUMN IF NOT EXISTS olusturma_tarihi TEXT;
ALTER TABLE cari_kapanis_snapshot ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE kasa_kapanis_snapshot ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE kasa_kapanis_snapshot ADD COLUMN IF NOT EXISTS devir_id TEXT;
ALTER TABLE kasa_kapanis_snapshot ADD COLUMN IF NOT EXISTS donem_id BIGINT;
ALTER TABLE kasa_kapanis_snapshot ADD COLUMN IF NOT EXISTS sube_id BIGINT;
ALTER TABLE kasa_kapanis_snapshot ADD COLUMN IF NOT EXISTS bakiye DOUBLE PRECISION;
ALTER TABLE kasa_kapanis_snapshot ADD COLUMN IF NOT EXISTS kaynak_hash TEXT;
ALTER TABLE kasa_kapanis_snapshot ADD COLUMN IF NOT EXISTS olusturma_tarihi TEXT;
ALTER TABLE kasa_kapanis_snapshot ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;
ALTER TABLE banka_kapanis_snapshot ADD COLUMN IF NOT EXISTS global_id TEXT;
ALTER TABLE banka_kapanis_snapshot ADD COLUMN IF NOT EXISTS devir_id TEXT;
ALTER TABLE banka_kapanis_snapshot ADD COLUMN IF NOT EXISTS donem_id BIGINT;
ALTER TABLE banka_kapanis_snapshot ADD COLUMN IF NOT EXISTS banka_hesap_id BIGINT;
ALTER TABLE banka_kapanis_snapshot ADD COLUMN IF NOT EXISTS bakiye DOUBLE PRECISION;
ALTER TABLE banka_kapanis_snapshot ADD COLUMN IF NOT EXISTS kaynak_hash TEXT;
ALTER TABLE banka_kapanis_snapshot ADD COLUMN IF NOT EXISTS olusturma_tarihi TEXT;
ALTER TABLE banka_kapanis_snapshot ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ;


-- ═══════════════════════════════════════════════════════════════════════
-- BÖLÜM 3 — TÜM FOREIGN KEY KISITLARINI KALDIR   (hata 23503 biter)
-- ═══════════════════════════════════════════════════════════════════════
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN (
    SELECT tc.table_name, tc.constraint_name
      FROM information_schema.table_constraints tc
     WHERE tc.table_schema = 'public'
       AND tc.constraint_type = 'FOREIGN KEY'
       AND tc.table_name IN (
         'adisyon_log',
         'audit_log',
         'ayarlar',
         'banka_hareketler',
         'banka_hesaplar',
         'banka_kapanis_snapshot',
         'bankalar',
         'bekleyen_siparis_kalem',
         'bekleyen_siparisler',
         'birimler',
         'borc_odemeler',
         'borclar',
         'cari',
         'cari_adres',
         'cari_hareket',
         'cari_kapanis_snapshot',
         'devir_checkpoint',
         'donem_kilit',
         'donem_sube_durumlari',
         'donemler',
         'fatura_detaylari',
         'faturalar',
         'fis_seri',
         'fiyat_gecmis',
         'fiyat_gruplari',
         'fiyat_kademeleri',
         'garson_cagri_log',
         'gider_kategoriler',
         'giderler',
         'iade',
         'iade_kalem',
         'irsaliye_kalem',
         'irsaliyeler',
         'kasa_hareketleri',
         'kasa_kapanis_snapshot',
         'kategoriler',
         'kredi_karti_hareket',
         'kredi_kartlari',
         'kullanicilar',
         'lot_seri',
         'markalar',
         'masa_hareket_log',
         'masa_rezervasyon',
         'masa_siparis_kalem',
         'masa_siparisleri',
         'masalar',
         'musteri_puan',
         'onay_talepleri',
         'personel',
         'promosyon_aksiyon',
         'promosyon_kosul',
         'promosyon_tanim',
         'promosyonlar',
         'puan_hareket',
         'rol_yetkileri',
         'roller_yetki',
         'satis_kalem',
         'satislar',
         'stok_hareket',
         'stok_kapanis_snapshot',
         'sube_urun',
         'subeler',
         'tedarikci_siparis_kalem',
         'tedarikci_siparisler',
         'urun_fiyat_gruplari',
         'urunler',
         'vardiyalar',
         'zaman_fiyat'
       )
  ) LOOP
    EXECUTE 'ALTER TABLE public.' || quote_ident(r.table_name) ||
            ' DROP CONSTRAINT ' || quote_ident(r.constraint_name);
  END LOOP;
END $$;


-- ═══════════════════════════════════════════════════════════════════════
-- BÖLÜM 4 — TÜM NOT NULL KISITLARINI KALDIR   (hata 23502 biter)
-- id sütunu hariç (o birincil anahtar).
-- ═══════════════════════════════════════════════════════════════════════
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN (
    SELECT c.table_name, c.column_name
      FROM information_schema.columns c
     WHERE c.table_schema = 'public'
       AND c.is_nullable = 'NO'
       AND c.column_name <> 'id'
       AND c.table_name IN (
         'adisyon_log',
         'audit_log',
         'ayarlar',
         'banka_hareketler',
         'banka_hesaplar',
         'banka_kapanis_snapshot',
         'bankalar',
         'bekleyen_siparis_kalem',
         'bekleyen_siparisler',
         'birimler',
         'borc_odemeler',
         'borclar',
         'cari',
         'cari_adres',
         'cari_hareket',
         'cari_kapanis_snapshot',
         'devir_checkpoint',
         'donem_kilit',
         'donem_sube_durumlari',
         'donemler',
         'fatura_detaylari',
         'faturalar',
         'fis_seri',
         'fiyat_gecmis',
         'fiyat_gruplari',
         'fiyat_kademeleri',
         'garson_cagri_log',
         'gider_kategoriler',
         'giderler',
         'iade',
         'iade_kalem',
         'irsaliye_kalem',
         'irsaliyeler',
         'kasa_hareketleri',
         'kasa_kapanis_snapshot',
         'kategoriler',
         'kredi_karti_hareket',
         'kredi_kartlari',
         'kullanicilar',
         'lot_seri',
         'markalar',
         'masa_hareket_log',
         'masa_rezervasyon',
         'masa_siparis_kalem',
         'masa_siparisleri',
         'masalar',
         'musteri_puan',
         'onay_talepleri',
         'personel',
         'promosyon_aksiyon',
         'promosyon_kosul',
         'promosyon_tanim',
         'promosyonlar',
         'puan_hareket',
         'rol_yetkileri',
         'roller_yetki',
         'satis_kalem',
         'satislar',
         'stok_hareket',
         'stok_kapanis_snapshot',
         'sube_urun',
         'subeler',
         'tedarikci_siparis_kalem',
         'tedarikci_siparisler',
         'urun_fiyat_gruplari',
         'urunler',
         'vardiyalar',
         'zaman_fiyat'
       )
  ) LOOP
    EXECUTE 'ALTER TABLE public.' || quote_ident(r.table_name) ||
            ' ALTER COLUMN ' || quote_ident(r.column_name) || ' DROP NOT NULL';
  END LOOP;
END $$;


-- ═══════════════════════════════════════════════════════════════════════
-- BÖLÜM 5 — TÜM DEFAULT TANIMLARINI KALDIR   (hata 42601 biter)
-- id sütunu hariç (IDENTITY'nin kendi mekanizması).
-- ═══════════════════════════════════════════════════════════════════════
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN (
    SELECT c.table_name, c.column_name
      FROM information_schema.columns c
     WHERE c.table_schema = 'public'
       AND c.column_default IS NOT NULL
       AND c.column_name <> 'id'
       AND c.table_name IN (
         'adisyon_log',
         'audit_log',
         'ayarlar',
         'banka_hareketler',
         'banka_hesaplar',
         'banka_kapanis_snapshot',
         'bankalar',
         'bekleyen_siparis_kalem',
         'bekleyen_siparisler',
         'birimler',
         'borc_odemeler',
         'borclar',
         'cari',
         'cari_adres',
         'cari_hareket',
         'cari_kapanis_snapshot',
         'devir_checkpoint',
         'donem_kilit',
         'donem_sube_durumlari',
         'donemler',
         'fatura_detaylari',
         'faturalar',
         'fis_seri',
         'fiyat_gecmis',
         'fiyat_gruplari',
         'fiyat_kademeleri',
         'garson_cagri_log',
         'gider_kategoriler',
         'giderler',
         'iade',
         'iade_kalem',
         'irsaliye_kalem',
         'irsaliyeler',
         'kasa_hareketleri',
         'kasa_kapanis_snapshot',
         'kategoriler',
         'kredi_karti_hareket',
         'kredi_kartlari',
         'kullanicilar',
         'lot_seri',
         'markalar',
         'masa_hareket_log',
         'masa_rezervasyon',
         'masa_siparis_kalem',
         'masa_siparisleri',
         'masalar',
         'musteri_puan',
         'onay_talepleri',
         'personel',
         'promosyon_aksiyon',
         'promosyon_kosul',
         'promosyon_tanim',
         'promosyonlar',
         'puan_hareket',
         'rol_yetkileri',
         'roller_yetki',
         'satis_kalem',
         'satislar',
         'stok_hareket',
         'stok_kapanis_snapshot',
         'sube_urun',
         'subeler',
         'tedarikci_siparis_kalem',
         'tedarikci_siparisler',
         'urun_fiyat_gruplari',
         'urunler',
         'vardiyalar',
         'zaman_fiyat'
       )
  ) LOOP
    EXECUTE 'ALTER TABLE public.' || quote_ident(r.table_name) ||
            ' ALTER COLUMN ' || quote_ident(r.column_name) || ' DROP DEFAULT';
  END LOOP;
END $$;


-- ═══════════════════════════════════════════════════════════════════════
-- BÖLÜM 6 — UPSERT ANAHTARLARI (UNIQUE)
-- on_conflict=<alan> ile upsert yapılabilmesi için ZORUNLU.
-- Zaten varsa hata vermez.
-- ═══════════════════════════════════════════════════════════════════════

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_adisyon_log_global_id') THEN
    ALTER TABLE adisyon_log ADD CONSTRAINT uq_adisyon_log_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_audit_log_global_id') THEN
    ALTER TABLE audit_log ADD CONSTRAINT uq_audit_log_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_ayarlar_anahtar') THEN
    ALTER TABLE ayarlar ADD CONSTRAINT uq_ayarlar_anahtar UNIQUE (anahtar);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_banka_hareketler_global_id') THEN
    ALTER TABLE banka_hareketler ADD CONSTRAINT uq_banka_hareketler_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_banka_hesaplar_global_id') THEN
    ALTER TABLE banka_hesaplar ADD CONSTRAINT uq_banka_hesaplar_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_banka_kapanis_snapshot_global_id') THEN
    ALTER TABLE banka_kapanis_snapshot ADD CONSTRAINT uq_banka_kapanis_snapshot_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_bankalar_global_id') THEN
    ALTER TABLE bankalar ADD CONSTRAINT uq_bankalar_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_bekleyen_siparis_kalem_global_id') THEN
    ALTER TABLE bekleyen_siparis_kalem ADD CONSTRAINT uq_bekleyen_siparis_kalem_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_bekleyen_siparisler_global_id') THEN
    ALTER TABLE bekleyen_siparisler ADD CONSTRAINT uq_bekleyen_siparisler_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_birimler_ad') THEN
    ALTER TABLE birimler ADD CONSTRAINT uq_birimler_ad UNIQUE (ad);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_borc_odemeler_global_id') THEN
    ALTER TABLE borc_odemeler ADD CONSTRAINT uq_borc_odemeler_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_borclar_global_id') THEN
    ALTER TABLE borclar ADD CONSTRAINT uq_borclar_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_cari_global_id') THEN
    ALTER TABLE cari ADD CONSTRAINT uq_cari_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_cari_adres_global_id') THEN
    ALTER TABLE cari_adres ADD CONSTRAINT uq_cari_adres_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_cari_hareket_global_id') THEN
    ALTER TABLE cari_hareket ADD CONSTRAINT uq_cari_hareket_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_cari_kapanis_snapshot_global_id') THEN
    ALTER TABLE cari_kapanis_snapshot ADD CONSTRAINT uq_cari_kapanis_snapshot_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_devir_checkpoint_global_id') THEN
    ALTER TABLE devir_checkpoint ADD CONSTRAINT uq_devir_checkpoint_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_donem_kilit_global_id') THEN
    ALTER TABLE donem_kilit ADD CONSTRAINT uq_donem_kilit_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_donem_sube_durumlari_global_id') THEN
    ALTER TABLE donem_sube_durumlari ADD CONSTRAINT uq_donem_sube_durumlari_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_donemler_global_id') THEN
    ALTER TABLE donemler ADD CONSTRAINT uq_donemler_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_fatura_detaylari_global_id') THEN
    ALTER TABLE fatura_detaylari ADD CONSTRAINT uq_fatura_detaylari_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_faturalar_global_id') THEN
    ALTER TABLE faturalar ADD CONSTRAINT uq_faturalar_global_id UNIQUE (global_id);
  END IF;
END $$;
-- fis_seri: global_id YOK, doğal anahtarı (sube_id, fis_tipi) çifti —
-- kod tarafı on_conflict=sube_id,fis_tipi gönderiyor (bkz. kolon_haritalama.dart).
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_fis_seri_sube_tip') THEN
    ALTER TABLE fis_seri ADD CONSTRAINT uq_fis_seri_sube_tip UNIQUE (sube_id, fis_tipi);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_fiyat_gecmis_global_id') THEN
    ALTER TABLE fiyat_gecmis ADD CONSTRAINT uq_fiyat_gecmis_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_fiyat_gruplari_global_id') THEN
    ALTER TABLE fiyat_gruplari ADD CONSTRAINT uq_fiyat_gruplari_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_fiyat_kademeleri_global_id') THEN
    ALTER TABLE fiyat_kademeleri ADD CONSTRAINT uq_fiyat_kademeleri_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_garson_cagri_log_global_id') THEN
    ALTER TABLE garson_cagri_log ADD CONSTRAINT uq_garson_cagri_log_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_gider_kategoriler_ad') THEN
    ALTER TABLE gider_kategoriler ADD CONSTRAINT uq_gider_kategoriler_ad UNIQUE (ad);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_giderler_global_id') THEN
    ALTER TABLE giderler ADD CONSTRAINT uq_giderler_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_iade_global_id') THEN
    ALTER TABLE iade ADD CONSTRAINT uq_iade_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_iade_kalem_global_id') THEN
    ALTER TABLE iade_kalem ADD CONSTRAINT uq_iade_kalem_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_irsaliye_kalem_global_id') THEN
    ALTER TABLE irsaliye_kalem ADD CONSTRAINT uq_irsaliye_kalem_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_irsaliyeler_global_id') THEN
    ALTER TABLE irsaliyeler ADD CONSTRAINT uq_irsaliyeler_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_kasa_hareketleri_global_id') THEN
    ALTER TABLE kasa_hareketleri ADD CONSTRAINT uq_kasa_hareketleri_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_kasa_kapanis_snapshot_global_id') THEN
    ALTER TABLE kasa_kapanis_snapshot ADD CONSTRAINT uq_kasa_kapanis_snapshot_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_kategoriler_ad') THEN
    ALTER TABLE kategoriler ADD CONSTRAINT uq_kategoriler_ad UNIQUE (ad);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_kredi_karti_hareket_global_id') THEN
    ALTER TABLE kredi_karti_hareket ADD CONSTRAINT uq_kredi_karti_hareket_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_kredi_kartlari_global_id') THEN
    ALTER TABLE kredi_kartlari ADD CONSTRAINT uq_kredi_kartlari_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_kullanicilar_kullanici_adi') THEN
    ALTER TABLE kullanicilar ADD CONSTRAINT uq_kullanicilar_kullanici_adi UNIQUE (kullanici_adi);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_lot_seri_global_id') THEN
    ALTER TABLE lot_seri ADD CONSTRAINT uq_lot_seri_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_markalar_ad') THEN
    ALTER TABLE markalar ADD CONSTRAINT uq_markalar_ad UNIQUE (ad);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_masa_hareket_log_global_id') THEN
    ALTER TABLE masa_hareket_log ADD CONSTRAINT uq_masa_hareket_log_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_masa_rezervasyon_global_id') THEN
    ALTER TABLE masa_rezervasyon ADD CONSTRAINT uq_masa_rezervasyon_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_masa_siparis_kalem_global_id') THEN
    ALTER TABLE masa_siparis_kalem ADD CONSTRAINT uq_masa_siparis_kalem_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_masa_siparisleri_global_id') THEN
    ALTER TABLE masa_siparisleri ADD CONSTRAINT uq_masa_siparisleri_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_masalar_global_id') THEN
    ALTER TABLE masalar ADD CONSTRAINT uq_masalar_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_musteri_puan_global_id') THEN
    ALTER TABLE musteri_puan ADD CONSTRAINT uq_musteri_puan_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_onay_talepleri_global_id') THEN
    ALTER TABLE onay_talepleri ADD CONSTRAINT uq_onay_talepleri_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_personel_global_id') THEN
    ALTER TABLE personel ADD CONSTRAINT uq_personel_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_promosyon_aksiyon_global_id') THEN
    ALTER TABLE promosyon_aksiyon ADD CONSTRAINT uq_promosyon_aksiyon_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_promosyon_kosul_global_id') THEN
    ALTER TABLE promosyon_kosul ADD CONSTRAINT uq_promosyon_kosul_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_promosyon_tanim_global_id') THEN
    ALTER TABLE promosyon_tanim ADD CONSTRAINT uq_promosyon_tanim_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_promosyonlar_global_id') THEN
    ALTER TABLE promosyonlar ADD CONSTRAINT uq_promosyonlar_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_puan_hareket_global_id') THEN
    ALTER TABLE puan_hareket ADD CONSTRAINT uq_puan_hareket_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_rol_yetkileri_global_id') THEN
    ALTER TABLE rol_yetkileri ADD CONSTRAINT uq_rol_yetkileri_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_roller_yetki_global_id') THEN
    ALTER TABLE roller_yetki ADD CONSTRAINT uq_roller_yetki_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_satis_kalem_global_id') THEN
    ALTER TABLE satis_kalem ADD CONSTRAINT uq_satis_kalem_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_satislar_global_id') THEN
    ALTER TABLE satislar ADD CONSTRAINT uq_satislar_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_stok_hareket_global_id') THEN
    ALTER TABLE stok_hareket ADD CONSTRAINT uq_stok_hareket_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_stok_kapanis_snapshot_global_id') THEN
    ALTER TABLE stok_kapanis_snapshot ADD CONSTRAINT uq_stok_kapanis_snapshot_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_sube_urun_global_id') THEN
    ALTER TABLE sube_urun ADD CONSTRAINT uq_sube_urun_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_subeler_sube_kodu') THEN
    ALTER TABLE subeler ADD CONSTRAINT uq_subeler_sube_kodu UNIQUE (sube_kodu);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_tedarikci_siparis_kalem_global_id') THEN
    ALTER TABLE tedarikci_siparis_kalem ADD CONSTRAINT uq_tedarikci_siparis_kalem_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_tedarikci_siparisler_global_id') THEN
    ALTER TABLE tedarikci_siparisler ADD CONSTRAINT uq_tedarikci_siparisler_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_urun_fiyat_gruplari_global_id') THEN
    ALTER TABLE urun_fiyat_gruplari ADD CONSTRAINT uq_urun_fiyat_gruplari_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_urunler_global_id') THEN
    ALTER TABLE urunler ADD CONSTRAINT uq_urunler_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_vardiyalar_global_id') THEN
    ALTER TABLE vardiyalar ADD CONSTRAINT uq_vardiyalar_global_id UNIQUE (global_id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_zaman_fiyat_global_id') THEN
    ALTER TABLE zaman_fiyat ADD CONSTRAINT uq_zaman_fiyat_global_id UNIQUE (global_id);
  END IF;
END $$;


-- ═══════════════════════════════════════════════════════════════════════
-- BÖLÜM 7 — İNDEKSLER
-- ═══════════════════════════════════════════════════════════════════════

CREATE INDEX IF NOT EXISTS idx_adisyon_log_last_updated ON adisyon_log(last_updated);
CREATE INDEX IF NOT EXISTS idx_adisyon_log_siparis_id ON adisyon_log(siparis_id);
CREATE INDEX IF NOT EXISTS idx_adisyon_log_yazdiran_kullanici_id ON adisyon_log(yazdiran_kullanici_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_last_updated ON audit_log(last_updated);
CREATE INDEX IF NOT EXISTS idx_audit_log_kayit_id ON audit_log(kayit_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_kullanici_id ON audit_log(kullanici_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_sube_id ON audit_log(sube_id);
CREATE INDEX IF NOT EXISTS idx_ayarlar_last_updated ON ayarlar(last_updated);
CREATE INDEX IF NOT EXISTS idx_banka_hareketler_last_updated ON banka_hareketler(last_updated);
CREATE INDEX IF NOT EXISTS idx_banka_hareketler_banka_hesap_id ON banka_hareketler(banka_hesap_id);
CREATE INDEX IF NOT EXISTS idx_banka_hareketler_kredi_karti_id ON banka_hareketler(kredi_karti_id);
CREATE INDEX IF NOT EXISTS idx_banka_hesaplar_last_updated ON banka_hesaplar(last_updated);
CREATE INDEX IF NOT EXISTS idx_banka_hesaplar_banka_id ON banka_hesaplar(banka_id);
CREATE INDEX IF NOT EXISTS idx_bankalar_last_updated ON bankalar(last_updated);
CREATE INDEX IF NOT EXISTS idx_bekleyen_siparis_kalem_last_updated ON bekleyen_siparis_kalem(last_updated);
CREATE INDEX IF NOT EXISTS idx_bekleyen_siparis_kalem_siparis_id ON bekleyen_siparis_kalem(siparis_id);
CREATE INDEX IF NOT EXISTS idx_bekleyen_siparis_kalem_urun_id ON bekleyen_siparis_kalem(urun_id);
CREATE INDEX IF NOT EXISTS idx_bekleyen_siparisler_last_updated ON bekleyen_siparisler(last_updated);
CREATE INDEX IF NOT EXISTS idx_bekleyen_siparisler_cari_id ON bekleyen_siparisler(cari_id);
CREATE INDEX IF NOT EXISTS idx_bekleyen_siparisler_sube_id ON bekleyen_siparisler(sube_id);
CREATE INDEX IF NOT EXISTS idx_bekleyen_siparisler_kullanici_id ON bekleyen_siparisler(kullanici_id);
CREATE INDEX IF NOT EXISTS idx_bekleyen_siparisler_satis_id ON bekleyen_siparisler(satis_id);
CREATE INDEX IF NOT EXISTS idx_birimler_last_updated ON birimler(last_updated);
CREATE INDEX IF NOT EXISTS idx_borc_odemeler_last_updated ON borc_odemeler(last_updated);
CREATE INDEX IF NOT EXISTS idx_borc_odemeler_borc_id ON borc_odemeler(borc_id);
CREATE INDEX IF NOT EXISTS idx_borc_odemeler_banka_hesap_id ON borc_odemeler(banka_hesap_id);
CREATE INDEX IF NOT EXISTS idx_borc_odemeler_kredi_karti_id ON borc_odemeler(kredi_karti_id);
CREATE INDEX IF NOT EXISTS idx_borclar_last_updated ON borclar(last_updated);
CREATE INDEX IF NOT EXISTS idx_cari_last_updated ON cari(last_updated);
CREATE INDEX IF NOT EXISTS idx_cari_sube_id ON cari(sube_id);
CREATE INDEX IF NOT EXISTS idx_cari_fiyat_grubu_id ON cari(fiyat_grubu_id);
CREATE INDEX IF NOT EXISTS idx_cari_adres_last_updated ON cari_adres(last_updated);
CREATE INDEX IF NOT EXISTS idx_cari_adres_cari_id ON cari_adres(cari_id);
CREATE INDEX IF NOT EXISTS idx_cari_hareket_last_updated ON cari_hareket(last_updated);
CREATE INDEX IF NOT EXISTS idx_cari_hareket_cari_id ON cari_hareket(cari_id);
CREATE INDEX IF NOT EXISTS idx_cari_hareket_fis_id ON cari_hareket(fis_id);
CREATE INDEX IF NOT EXISTS idx_fatura_detaylari_last_updated ON fatura_detaylari(last_updated);
CREATE INDEX IF NOT EXISTS idx_fatura_detaylari_fatura_id ON fatura_detaylari(fatura_id);
CREATE INDEX IF NOT EXISTS idx_fatura_detaylari_urun_id ON fatura_detaylari(urun_id);
CREATE INDEX IF NOT EXISTS idx_faturalar_last_updated ON faturalar(last_updated);
CREATE INDEX IF NOT EXISTS idx_faturalar_satis_id ON faturalar(satis_id);
CREATE INDEX IF NOT EXISTS idx_faturalar_iade_id ON faturalar(iade_id);
CREATE INDEX IF NOT EXISTS idx_faturalar_cari_id ON faturalar(cari_id);
CREATE INDEX IF NOT EXISTS idx_faturalar_sube_id ON faturalar(sube_id);
CREATE INDEX IF NOT EXISTS idx_fis_seri_last_updated ON fis_seri(last_updated);
CREATE INDEX IF NOT EXISTS idx_fiyat_gecmis_last_updated ON fiyat_gecmis(last_updated);
CREATE INDEX IF NOT EXISTS idx_fiyat_gecmis_urun_id ON fiyat_gecmis(urun_id);
CREATE INDEX IF NOT EXISTS idx_fiyat_gruplari_last_updated ON fiyat_gruplari(last_updated);
CREATE INDEX IF NOT EXISTS idx_fiyat_kademeleri_last_updated ON fiyat_kademeleri(last_updated);
CREATE INDEX IF NOT EXISTS idx_fiyat_kademeleri_urun_id ON fiyat_kademeleri(urun_id);
CREATE INDEX IF NOT EXISTS idx_fiyat_kademeleri_fiyat_grubu_id ON fiyat_kademeleri(fiyat_grubu_id);
CREATE INDEX IF NOT EXISTS idx_garson_cagri_log_last_updated ON garson_cagri_log(last_updated);
CREATE INDEX IF NOT EXISTS idx_garson_cagri_log_masa_id ON garson_cagri_log(masa_id);
CREATE INDEX IF NOT EXISTS idx_garson_cagri_log_yanitlayan_id ON garson_cagri_log(yanitlayan_id);
CREATE INDEX IF NOT EXISTS idx_gider_kategoriler_last_updated ON gider_kategoriler(last_updated);
CREATE INDEX IF NOT EXISTS idx_giderler_last_updated ON giderler(last_updated);
CREATE INDEX IF NOT EXISTS idx_giderler_kategori_id ON giderler(kategori_id);
CREATE INDEX IF NOT EXISTS idx_giderler_cari_id ON giderler(cari_id);
CREATE INDEX IF NOT EXISTS idx_giderler_kullanici_id ON giderler(kullanici_id);
CREATE INDEX IF NOT EXISTS idx_giderler_sube_id ON giderler(sube_id);
CREATE INDEX IF NOT EXISTS idx_iade_last_updated ON iade(last_updated);
CREATE INDEX IF NOT EXISTS idx_iade_satis_id ON iade(satis_id);
CREATE INDEX IF NOT EXISTS idx_iade_cari_id ON iade(cari_id);
CREATE INDEX IF NOT EXISTS idx_iade_kasiyer_id ON iade(kasiyer_id);
CREATE INDEX IF NOT EXISTS idx_iade_kalem_last_updated ON iade_kalem(last_updated);
CREATE INDEX IF NOT EXISTS idx_iade_kalem_iade_id ON iade_kalem(iade_id);
CREATE INDEX IF NOT EXISTS idx_iade_kalem_urun_id ON iade_kalem(urun_id);
CREATE INDEX IF NOT EXISTS idx_irsaliye_kalem_last_updated ON irsaliye_kalem(last_updated);
CREATE INDEX IF NOT EXISTS idx_irsaliye_kalem_irsaliye_id ON irsaliye_kalem(irsaliye_id);
CREATE INDEX IF NOT EXISTS idx_irsaliye_kalem_urun_id ON irsaliye_kalem(urun_id);
CREATE INDEX IF NOT EXISTS idx_irsaliyeler_last_updated ON irsaliyeler(last_updated);
CREATE INDEX IF NOT EXISTS idx_irsaliyeler_cari_id ON irsaliyeler(cari_id);
CREATE INDEX IF NOT EXISTS idx_irsaliyeler_kullanici_id ON irsaliyeler(kullanici_id);
CREATE INDEX IF NOT EXISTS idx_kasa_hareketleri_last_updated ON kasa_hareketleri(last_updated);
CREATE INDEX IF NOT EXISTS idx_kasa_hareketleri_referans_id ON kasa_hareketleri(referans_id);
CREATE INDEX IF NOT EXISTS idx_banka_hareketler_referans_id ON banka_hareketler(referans_id);
CREATE INDEX IF NOT EXISTS idx_kredi_karti_hareket_referans_id ON kredi_karti_hareket(referans_id);
CREATE INDEX IF NOT EXISTS idx_kasa_hareketleri_kullanici_id ON kasa_hareketleri(kullanici_id);
CREATE INDEX IF NOT EXISTS idx_kasa_hareketleri_sube_id ON kasa_hareketleri(sube_id);
CREATE INDEX IF NOT EXISTS idx_kategoriler_last_updated ON kategoriler(last_updated);
CREATE INDEX IF NOT EXISTS idx_kategoriler_ust_kategori_id ON kategoriler(ust_kategori_id);
CREATE INDEX IF NOT EXISTS idx_kredi_karti_hareket_last_updated ON kredi_karti_hareket(last_updated);
CREATE INDEX IF NOT EXISTS idx_kredi_karti_hareket_kredi_karti_id ON kredi_karti_hareket(kredi_karti_id);
CREATE INDEX IF NOT EXISTS idx_kredi_kartlari_last_updated ON kredi_kartlari(last_updated);
CREATE INDEX IF NOT EXISTS idx_kredi_kartlari_banka_id ON kredi_kartlari(banka_id);
CREATE INDEX IF NOT EXISTS idx_kullanicilar_last_updated ON kullanicilar(last_updated);
CREATE INDEX IF NOT EXISTS idx_kullanicilar_sube_id ON kullanicilar(sube_id);
CREATE INDEX IF NOT EXISTS idx_lot_seri_last_updated ON lot_seri(last_updated);
CREATE INDEX IF NOT EXISTS idx_lot_seri_urun_id ON lot_seri(urun_id);
CREATE INDEX IF NOT EXISTS idx_lot_seri_tedarikci_cari_id ON lot_seri(tedarikci_cari_id);
CREATE INDEX IF NOT EXISTS idx_markalar_last_updated ON markalar(last_updated);
CREATE INDEX IF NOT EXISTS idx_masa_hareket_log_last_updated ON masa_hareket_log(last_updated);
CREATE INDEX IF NOT EXISTS idx_masa_hareket_log_kaynak_masa_id ON masa_hareket_log(kaynak_masa_id);
CREATE INDEX IF NOT EXISTS idx_masa_hareket_log_hedef_masa_id ON masa_hareket_log(hedef_masa_id);
CREATE INDEX IF NOT EXISTS idx_masa_hareket_log_siparis_id ON masa_hareket_log(siparis_id);
CREATE INDEX IF NOT EXISTS idx_masa_hareket_log_yapan_kullanici_id ON masa_hareket_log(yapan_kullanici_id);
CREATE INDEX IF NOT EXISTS idx_masa_rezervasyon_last_updated ON masa_rezervasyon(last_updated);
CREATE INDEX IF NOT EXISTS idx_masa_rezervasyon_masa_id ON masa_rezervasyon(masa_id);
CREATE INDEX IF NOT EXISTS idx_masa_rezervasyon_kullanici_id ON masa_rezervasyon(kullanici_id);
CREATE INDEX IF NOT EXISTS idx_masa_siparis_kalem_last_updated ON masa_siparis_kalem(last_updated);
CREATE INDEX IF NOT EXISTS idx_masa_siparis_kalem_siparis_id ON masa_siparis_kalem(siparis_id);
CREATE INDEX IF NOT EXISTS idx_masa_siparis_kalem_urun_id ON masa_siparis_kalem(urun_id);
CREATE INDEX IF NOT EXISTS idx_masa_siparisleri_last_updated ON masa_siparisleri(last_updated);
CREATE INDEX IF NOT EXISTS idx_masa_siparisleri_masa_id ON masa_siparisleri(masa_id);
CREATE INDEX IF NOT EXISTS idx_masa_siparisleri_cari_id ON masa_siparisleri(cari_id);
CREATE INDEX IF NOT EXISTS idx_masa_siparisleri_kullanici_id ON masa_siparisleri(kullanici_id);
CREATE INDEX IF NOT EXISTS idx_masa_siparisleri_satis_id ON masa_siparisleri(satis_id);
CREATE INDEX IF NOT EXISTS idx_masa_siparisleri_garson_id ON masa_siparisleri(garson_id);
CREATE INDEX IF NOT EXISTS idx_masalar_last_updated ON masalar(last_updated);
CREATE INDEX IF NOT EXISTS idx_masalar_sube_id ON masalar(sube_id);
CREATE INDEX IF NOT EXISTS idx_musteri_puan_last_updated ON musteri_puan(last_updated);
CREATE INDEX IF NOT EXISTS idx_musteri_puan_cari_id ON musteri_puan(cari_id);
CREATE INDEX IF NOT EXISTS idx_onay_talepleri_last_updated ON onay_talepleri(last_updated);
CREATE INDEX IF NOT EXISTS idx_onay_talepleri_goruldu ON onay_talepleri(goruldu);
CREATE INDEX IF NOT EXISTS idx_personel_last_updated ON personel(last_updated);
CREATE INDEX IF NOT EXISTS idx_personel_kullanici_id ON personel(kullanici_id);
CREATE INDEX IF NOT EXISTS idx_promosyon_aksiyon_last_updated ON promosyon_aksiyon(last_updated);
CREATE INDEX IF NOT EXISTS idx_promosyon_aksiyon_tanim_id ON promosyon_aksiyon(tanim_id);
CREATE INDEX IF NOT EXISTS idx_promosyon_kosul_last_updated ON promosyon_kosul(last_updated);
CREATE INDEX IF NOT EXISTS idx_promosyon_kosul_tanim_id ON promosyon_kosul(tanim_id);
CREATE INDEX IF NOT EXISTS idx_promosyon_tanim_last_updated ON promosyon_tanim(last_updated);
CREATE INDEX IF NOT EXISTS idx_promosyonlar_last_updated ON promosyonlar(last_updated);
CREATE INDEX IF NOT EXISTS idx_promosyonlar_urun_id ON promosyonlar(urun_id);
CREATE INDEX IF NOT EXISTS idx_puan_hareket_last_updated ON puan_hareket(last_updated);
CREATE INDEX IF NOT EXISTS idx_puan_hareket_cari_id ON puan_hareket(cari_id);
CREATE INDEX IF NOT EXISTS idx_puan_hareket_referans_id ON puan_hareket(referans_id);
CREATE INDEX IF NOT EXISTS idx_rol_yetkileri_last_updated ON rol_yetkileri(last_updated);
CREATE INDEX IF NOT EXISTS idx_roller_yetki_last_updated ON roller_yetki(last_updated);
CREATE INDEX IF NOT EXISTS idx_roller_yetki_kullanici_id ON roller_yetki(kullanici_id);
CREATE INDEX IF NOT EXISTS idx_satis_kalem_last_updated ON satis_kalem(last_updated);
CREATE INDEX IF NOT EXISTS idx_satis_kalem_satis_id ON satis_kalem(satis_id);
CREATE INDEX IF NOT EXISTS idx_satis_kalem_urun_id ON satis_kalem(urun_id);
CREATE INDEX IF NOT EXISTS idx_satis_kalem_lot_id ON satis_kalem(lot_id);
CREATE INDEX IF NOT EXISTS idx_satislar_last_updated ON satislar(last_updated);
CREATE INDEX IF NOT EXISTS idx_satislar_cari_id ON satislar(cari_id);
CREATE INDEX IF NOT EXISTS idx_satislar_kasiyer_id ON satislar(kasiyer_id);
CREATE INDEX IF NOT EXISTS idx_satislar_kullanici_id ON satislar(kullanici_id);
CREATE INDEX IF NOT EXISTS idx_satislar_vardiya_id ON satislar(vardiya_id);
CREATE INDEX IF NOT EXISTS idx_satislar_sube_id ON satislar(sube_id);
CREATE INDEX IF NOT EXISTS idx_stok_hareket_last_updated ON stok_hareket(last_updated);
CREATE INDEX IF NOT EXISTS idx_stok_hareket_urun_id ON stok_hareket(urun_id);
CREATE INDEX IF NOT EXISTS idx_stok_hareket_referans_id ON stok_hareket(referans_id);
CREATE INDEX IF NOT EXISTS idx_stok_hareket_lot_id ON stok_hareket(lot_id);
CREATE INDEX IF NOT EXISTS idx_stok_hareket_kullanici_id ON stok_hareket(kullanici_id);
CREATE INDEX IF NOT EXISTS idx_stok_hareket_sube_id ON stok_hareket(sube_id);
CREATE INDEX IF NOT EXISTS idx_sube_urun_last_updated ON sube_urun(last_updated);
CREATE INDEX IF NOT EXISTS idx_sube_urun_urun_id ON sube_urun(urun_id);
CREATE INDEX IF NOT EXISTS idx_sube_urun_sube_id ON sube_urun(sube_id);
CREATE INDEX IF NOT EXISTS idx_subeler_last_updated ON subeler(last_updated);
CREATE INDEX IF NOT EXISTS idx_tedarikci_siparis_kalem_last_updated ON tedarikci_siparis_kalem(last_updated);
CREATE INDEX IF NOT EXISTS idx_tedarikci_siparis_kalem_siparis_id ON tedarikci_siparis_kalem(siparis_id);
CREATE INDEX IF NOT EXISTS idx_tedarikci_siparis_kalem_urun_id ON tedarikci_siparis_kalem(urun_id);
CREATE INDEX IF NOT EXISTS idx_tedarikci_siparisler_last_updated ON tedarikci_siparisler(last_updated);
CREATE INDEX IF NOT EXISTS idx_tedarikci_siparisler_cari_id ON tedarikci_siparisler(cari_id);
CREATE INDEX IF NOT EXISTS idx_tedarikci_siparisler_olusturan_id ON tedarikci_siparisler(olusturan_id);
CREATE INDEX IF NOT EXISTS idx_urun_fiyat_gruplari_last_updated ON urun_fiyat_gruplari(last_updated);
CREATE INDEX IF NOT EXISTS idx_urun_fiyat_gruplari_urun_id ON urun_fiyat_gruplari(urun_id);
CREATE INDEX IF NOT EXISTS idx_urun_fiyat_gruplari_fiyat_grubu_id ON urun_fiyat_gruplari(fiyat_grubu_id);
CREATE INDEX IF NOT EXISTS idx_urunler_last_updated ON urunler(last_updated);
CREATE INDEX IF NOT EXISTS idx_urunler_kategori_id ON urunler(kategori_id);
CREATE INDEX IF NOT EXISTS idx_urunler_zaman_fiyat_id ON urunler(zaman_fiyat_id);
CREATE INDEX IF NOT EXISTS idx_vardiyalar_last_updated ON vardiyalar(last_updated);
CREATE INDEX IF NOT EXISTS idx_vardiyalar_kullanici_id ON vardiyalar(kullanici_id);
CREATE INDEX IF NOT EXISTS idx_vardiyalar_sube_id ON vardiyalar(sube_id);
CREATE INDEX IF NOT EXISTS idx_zaman_fiyat_last_updated ON zaman_fiyat(last_updated);
CREATE INDEX IF NOT EXISTS idx_zaman_fiyat_urun_id ON zaman_fiyat(urun_id);

-- Yıl Sonu Devir / Dönem Kapatma / Arşivleme (2026-09-16)
CREATE INDEX IF NOT EXISTS idx_donemler_last_updated ON donemler(last_updated);
CREATE INDEX IF NOT EXISTS idx_donemler_yili ON donemler(donem_yili);
CREATE INDEX IF NOT EXISTS idx_donem_sube_durumlari_last_updated ON donem_sube_durumlari(last_updated);
CREATE INDEX IF NOT EXISTS idx_donem_sube_durumlari_donem ON donem_sube_durumlari(donem_id);
CREATE INDEX IF NOT EXISTS idx_devir_checkpoint_last_updated ON devir_checkpoint(last_updated);
CREATE INDEX IF NOT EXISTS idx_devir_checkpoint_durum ON devir_checkpoint(durum);
CREATE INDEX IF NOT EXISTS idx_donem_kilit_last_updated ON donem_kilit(last_updated);
CREATE INDEX IF NOT EXISTS idx_donem_kilit_donem ON donem_kilit(donem_id);
CREATE INDEX IF NOT EXISTS idx_stok_kapanis_snapshot_last_updated ON stok_kapanis_snapshot(last_updated);
CREATE INDEX IF NOT EXISTS idx_stok_kapanis_snapshot_donem ON stok_kapanis_snapshot(donem_id, sube_id);
CREATE INDEX IF NOT EXISTS idx_cari_kapanis_snapshot_last_updated ON cari_kapanis_snapshot(last_updated);
CREATE INDEX IF NOT EXISTS idx_cari_kapanis_snapshot_donem ON cari_kapanis_snapshot(donem_id);
CREATE INDEX IF NOT EXISTS idx_kasa_kapanis_snapshot_last_updated ON kasa_kapanis_snapshot(last_updated);
CREATE INDEX IF NOT EXISTS idx_kasa_kapanis_snapshot_donem ON kasa_kapanis_snapshot(donem_id);
CREATE INDEX IF NOT EXISTS idx_banka_kapanis_snapshot_last_updated ON banka_kapanis_snapshot(last_updated);
CREATE INDEX IF NOT EXISTS idx_banka_kapanis_snapshot_donem ON banka_kapanis_snapshot(donem_id);


-- ═══════════════════════════════════════════════════════════════════════
-- BÖLÜM 8 — ROW LEVEL SECURITY
-- ═══════════════════════════════════════════════════════════════════════

-- 🔴 SERTLEŞTİRME (2026-09-22): TÜM tablolarda "anon, authenticated
-- USING (true)" (herkese tam erişim) vardı — QR menü sayfasındaki
-- herkese açık anahtar (sb_publishable_...) bu sayede kullanicilar
-- (şifre hash dahil), kredi_kartlari, cari, satislar gibi TÜM
-- tablolara okuma+yazma+silme erişebiliyordu. Artık anon/authenticated
-- bu tablolara HİÇ erişemiyor — uygulamanın kendi (sb_secret_/
-- service_role) anahtarı RLS'i zaten atlıyor, bu yüzden hiçbir şey
-- kırılmıyor. urunler tablosu ayrı ele alınıyor (aşağıda) — anon
-- SADECE QR menüdeki ürünleri okuyabiliyor. Gerçek çalıştırılan SQL:
-- bkz. proje kökünde supabase_rls_sertlestirme.sql.

ALTER TABLE adisyon_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS adisyon_log_all ON adisyon_log;
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS audit_log_all ON audit_log;
ALTER TABLE ayarlar ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS ayarlar_all ON ayarlar;
ALTER TABLE banka_hareketler ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS banka_hareketler_all ON banka_hareketler;
ALTER TABLE banka_hesaplar ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS banka_hesaplar_all ON banka_hesaplar;
ALTER TABLE banka_kapanis_snapshot ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS banka_kapanis_snapshot_all ON banka_kapanis_snapshot;
ALTER TABLE bankalar ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS bankalar_all ON bankalar;
ALTER TABLE bekleyen_siparis_kalem ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS bekleyen_siparis_kalem_all ON bekleyen_siparis_kalem;
ALTER TABLE bekleyen_siparisler ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS bekleyen_siparisler_all ON bekleyen_siparisler;
ALTER TABLE birimler ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS birimler_all ON birimler;
ALTER TABLE borc_odemeler ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS borc_odemeler_all ON borc_odemeler;
ALTER TABLE borclar ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS borclar_all ON borclar;
ALTER TABLE cari ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS cari_all ON cari;
ALTER TABLE cari_adres ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS cari_adres_all ON cari_adres;
ALTER TABLE cari_hareket ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS cari_hareket_all ON cari_hareket;
ALTER TABLE cari_kapanis_snapshot ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS cari_kapanis_snapshot_all ON cari_kapanis_snapshot;
ALTER TABLE devir_checkpoint ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS devir_checkpoint_all ON devir_checkpoint;
ALTER TABLE donem_kilit ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS donem_kilit_all ON donem_kilit;
ALTER TABLE donem_sube_durumlari ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS donem_sube_durumlari_all ON donem_sube_durumlari;
ALTER TABLE donemler ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS donemler_all ON donemler;
ALTER TABLE fatura_detaylari ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS fatura_detaylari_all ON fatura_detaylari;
ALTER TABLE faturalar ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS faturalar_all ON faturalar;
ALTER TABLE fis_seri ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS fis_seri_all ON fis_seri;
ALTER TABLE fiyat_gecmis ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS fiyat_gecmis_all ON fiyat_gecmis;
ALTER TABLE fiyat_gruplari ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS fiyat_gruplari_all ON fiyat_gruplari;
ALTER TABLE fiyat_kademeleri ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS fiyat_kademeleri_all ON fiyat_kademeleri;
ALTER TABLE garson_cagri_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS garson_cagri_log_all ON garson_cagri_log;
ALTER TABLE gider_kategoriler ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS gider_kategoriler_all ON gider_kategoriler;
ALTER TABLE giderler ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS giderler_all ON giderler;
ALTER TABLE iade ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS iade_all ON iade;
ALTER TABLE iade_kalem ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS iade_kalem_all ON iade_kalem;
ALTER TABLE irsaliye_kalem ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS irsaliye_kalem_all ON irsaliye_kalem;
ALTER TABLE irsaliyeler ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS irsaliyeler_all ON irsaliyeler;
ALTER TABLE kasa_hareketleri ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS kasa_hareketleri_all ON kasa_hareketleri;
ALTER TABLE kasa_kapanis_snapshot ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS kasa_kapanis_snapshot_all ON kasa_kapanis_snapshot;
ALTER TABLE kategoriler ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS kategoriler_all ON kategoriler;
ALTER TABLE kredi_karti_hareket ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS kredi_karti_hareket_all ON kredi_karti_hareket;
ALTER TABLE kredi_kartlari ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS kredi_kartlari_all ON kredi_kartlari;
ALTER TABLE kullanicilar ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS kullanicilar_all ON kullanicilar;
ALTER TABLE lot_seri ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS lot_seri_all ON lot_seri;
ALTER TABLE markalar ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS markalar_all ON markalar;
ALTER TABLE masa_hareket_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS masa_hareket_log_all ON masa_hareket_log;
ALTER TABLE masa_rezervasyon ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS masa_rezervasyon_all ON masa_rezervasyon;
ALTER TABLE masa_siparis_kalem ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS masa_siparis_kalem_all ON masa_siparis_kalem;
ALTER TABLE masa_siparisleri ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS masa_siparisleri_all ON masa_siparisleri;
ALTER TABLE masalar ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS masalar_all ON masalar;
ALTER TABLE musteri_puan ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS musteri_puan_all ON musteri_puan;
ALTER TABLE onay_talepleri ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS onay_talepleri_all ON onay_talepleri;
ALTER TABLE personel ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS personel_all ON personel;
ALTER TABLE promosyon_aksiyon ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS promosyon_aksiyon_all ON promosyon_aksiyon;
ALTER TABLE promosyon_kosul ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS promosyon_kosul_all ON promosyon_kosul;
ALTER TABLE promosyon_tanim ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS promosyon_tanim_all ON promosyon_tanim;
ALTER TABLE promosyonlar ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS promosyonlar_all ON promosyonlar;
ALTER TABLE puan_hareket ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS puan_hareket_all ON puan_hareket;
ALTER TABLE rol_yetkileri ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS rol_yetkileri_all ON rol_yetkileri;
ALTER TABLE roller_yetki ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS roller_yetki_all ON roller_yetki;
ALTER TABLE satis_kalem ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS satis_kalem_all ON satis_kalem;
ALTER TABLE satislar ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS satislar_all ON satislar;
ALTER TABLE stok_hareket ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS stok_hareket_all ON stok_hareket;
ALTER TABLE stok_kapanis_snapshot ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS stok_kapanis_snapshot_all ON stok_kapanis_snapshot;
ALTER TABLE sube_urun ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS sube_urun_all ON sube_urun;
ALTER TABLE subeler ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS subeler_all ON subeler;
ALTER TABLE tedarikci_siparis_kalem ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tedarikci_siparis_kalem_all ON tedarikci_siparis_kalem;
ALTER TABLE tedarikci_siparisler ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tedarikci_siparisler_all ON tedarikci_siparisler;
ALTER TABLE urun_fiyat_gruplari ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS urun_fiyat_gruplari_all ON urun_fiyat_gruplari;
ALTER TABLE urunler ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS urunler_all ON urunler;
DROP POLICY IF EXISTS urunler_anon_qr_menu_okuyabilir ON urunler;
CREATE POLICY urunler_anon_qr_menu_okuyabilir ON urunler
  FOR SELECT TO anon
  USING (aktif = true AND is_deleted = false AND qr_menude = 1);
ALTER TABLE vardiyalar ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS vardiyalar_all ON vardiyalar;
ALTER TABLE zaman_fiyat ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS zaman_fiyat_all ON zaman_fiyat;


-- ═══════════════════════════════════════════════════════════════════════
-- BÖLÜM 9 — DOĞRULAMA
-- BUNU MUTLAKA ÇALIŞTIRIN.
-- Beklenen:  eksik_tablo=0 · fk_kisit=0 · not_null=0 · default_tanim=0
-- Dördü de 0 değilse bana o çıktıyı gönderin.
-- ═══════════════════════════════════════════════════════════════════════
WITH beklenen(tablo) AS (VALUES
    ('adisyon_log'),
    ('audit_log'),
    ('ayarlar'),
    ('banka_hareketler'),
    ('banka_hesaplar'),
    ('banka_kapanis_snapshot'),
    ('bankalar'),
    ('bekleyen_siparis_kalem'),
    ('bekleyen_siparisler'),
    ('birimler'),
    ('borc_odemeler'),
    ('borclar'),
    ('cari'),
    ('cari_adres'),
    ('cari_hareket'),
    ('cari_kapanis_snapshot'),
    ('devir_checkpoint'),
    ('donem_kilit'),
    ('donem_sube_durumlari'),
    ('donemler'),
    ('fatura_detaylari'),
    ('faturalar'),
    ('fis_seri'),
    ('fiyat_gecmis'),
    ('fiyat_gruplari'),
    ('fiyat_kademeleri'),
    ('garson_cagri_log'),
    ('gider_kategoriler'),
    ('giderler'),
    ('iade'),
    ('iade_kalem'),
    ('irsaliye_kalem'),
    ('irsaliyeler'),
    ('kasa_hareketleri'),
    ('kasa_kapanis_snapshot'),
    ('kategoriler'),
    ('kredi_karti_hareket'),
    ('kredi_kartlari'),
    ('kullanicilar'),
    ('lot_seri'),
    ('markalar'),
    ('masa_hareket_log'),
    ('masa_rezervasyon'),
    ('masa_siparis_kalem'),
    ('masa_siparisleri'),
    ('masalar'),
    ('musteri_puan'),
    ('onay_talepleri'),
    ('personel'),
    ('promosyon_aksiyon'),
    ('promosyon_kosul'),
    ('promosyon_tanim'),
    ('promosyonlar'),
    ('puan_hareket'),
    ('rol_yetkileri'),
    ('roller_yetki'),
    ('satis_kalem'),
    ('satislar'),
    ('stok_hareket'),
    ('stok_kapanis_snapshot'),
    ('sube_urun'),
    ('subeler'),
    ('tedarikci_siparis_kalem'),
    ('tedarikci_siparisler'),
    ('urun_fiyat_gruplari'),
    ('urunler'),
    ('vardiyalar'),
    ('zaman_fiyat')
)
SELECT
  (SELECT count(*) FROM beklenen)                                    AS beklenen_tablo,
  (SELECT count(*) FROM beklenen b
     WHERE to_regclass('public.'||b.tablo) IS NULL)                  AS eksik_tablo,
  (SELECT count(*) FROM information_schema.table_constraints tc
     JOIN beklenen b ON b.tablo = tc.table_name
    WHERE tc.table_schema='public' AND tc.constraint_type='FOREIGN KEY')
                                                                     AS fk_kisit,
  (SELECT count(*) FROM information_schema.columns c
     JOIN beklenen b ON b.tablo = c.table_name
    WHERE c.table_schema='public' AND c.is_nullable='NO'
      AND c.column_name <> 'id')                                     AS not_null,
  (SELECT count(*) FROM information_schema.columns c
     JOIN beklenen b ON b.tablo = c.table_name
    WHERE c.table_schema='public' AND c.column_default IS NOT NULL
      AND c.column_name <> 'id')                                     AS default_tanim;

-- ═══════════════════════════════════════════════════════════════════════
-- QR MENÜ / HERKESE AÇIK WEB SAYFASI TABLOLARI (qr_menu_sayfasi.html)
-- ═══════════════════════════════════════════════════════════════════════
-- [YENİ — 2026-09-14] Kullanıcı bulgusu: "html'den sipariş ver diyorum
-- vermiyor". Bu iki tablo (qr_siparisler, site_icerik) uygulamanın ana
-- senkron sistemine (yukarıdaki tüm tablolar) HİÇ dahil DEĞİL — bunlar
-- lokal SQLite'a hiç yansımaz, SADECE Supabase'de yaşar ve doğrudan
-- HTTP ile okunur/yazılır. ÖNCEDEN bu iki tablo bu referans dosyasında
-- HİÇ dokümante edilmemişti — bu yüzden "gerçekten doğru şemada mı,
-- RLS izinleri doğru mu" hiç doğrulanamıyordu. Aşağıdaki SQL'i Supabase
-- SQL Editor'de ÇALIŞTIRIP hem tabloların var olduğunu/doğru sütunlara
-- sahip olduğunu GARANTİ altına alın hem de (en olası "sipariş
-- vermiyor" nedeni) anon anahtarla INSERT izni verin.
--
-- ÖNEMLİ GÜVENLİK NOTU: qr_menu_sayfasi.html'e gömülü anahtar
-- (SUPABASE_ANON_KEY) HERKESE AÇIKTIR — sayfa kaynağını gören HERKES
-- görebilir. Bu yüzden bu iki tabloda RLS AÇIK tutulup SADECE gerekli
-- (aşağıdaki) dar izinler verilmeli; ASLA "tüm izinler" gibi geniş bir
-- policy eklenmemeli.

CREATE TABLE IF NOT EXISTS qr_siparisler (
  id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  masa_id      BIGINT NOT NULL,
  kalemler     JSONB NOT NULL,
  musteri_adi  TEXT,
  musteri_tel  TEXT,
  not_         TEXT,
  islendi      BOOLEAN NOT NULL DEFAULT false,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE qr_siparisler ENABLE ROW LEVEL SECURITY;
-- Müşteri (kimliksiz/anon) sipariş EKLEYEBİLMELİ — bu policy olmadan
-- (veya RLS açıkken hiç policy yoksa) HTML'den gelen POST /qr_siparisler
-- isteği 401/403 ile SESSİZCE reddedilir, tam olarak "sipariş
-- vermiyor" şikayetinin en olası nedeni budur.
DROP POLICY IF EXISTS qr_siparis_anon_ekleyebilir ON qr_siparisler;
CREATE POLICY qr_siparis_anon_ekleyebilir ON qr_siparisler
  FOR INSERT TO anon WITH CHECK (true);
-- Uygulamanın kendi (sb_secret_ / service_role) anahtarı RLS'i zaten
-- atlar — okuma/işaretleme (QrSiparisCekiciServisi) için ayrı bir
-- policy GEREKMEZ. Müşterinin BAŞKA siparişleri okuyabilmesi/
-- değiştirebilmesi İSTENMEDİĞİ için SELECT/UPDATE/DELETE için anon
-- policy'si BİLİNÇLİ OLARAK eklenmedi.

CREATE TABLE IF NOT EXISTS site_icerik (
  id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  anahtar      TEXT NOT NULL UNIQUE,
  deger        TEXT,
  last_updated TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE site_icerik ENABLE ROW LEVEL SECURITY;
-- Müşteri sadece OKUYABİLMELİ (işyeri fotoğrafları, hakkımızda metni
-- vb.) — yazma her zaman uygulamanın kendi (secret) anahtarıyla,
-- Ayarlar > Site İçeriği ekranından yapılır.
DROP POLICY IF EXISTS site_icerik_anon_okuyabilir ON site_icerik;
CREATE POLICY site_icerik_anon_okuyabilir ON site_icerik
  FOR SELECT TO anon USING (true);

-- ###########################################################################
-- BÖLÜM B — MERKEZİ FATURA SERİ/BLOK YÖNETİMİ
-- (kaynak: supabase_fatura_seri_bloklari.sql)
-- ###########################################################################

-- ═══════════════════════════════════════════════════════════════════════════
-- MERKEZİ FATURA SERİ/BLOK YÖNETİMİ — 2026-09-23
-- ═══════════════════════════════════════════════════════════════════════════
-- Bkz. proje kökünde CENTRAL_DOCUMENT_NUMBERING_DEEP_AUDIT.md (tam analiz).
--
-- NEDEN: Mevcut fatura numarası üretimi SADECE cihazın kendi yerel
-- verisine bakarak (SELECT MAX(fatura_no)+1) çalışıyordu — birden fazla
-- cihaz/terminal aynı anda aynı numarayı üretebilir, ikisi de GİB'e
-- gönderilirse bu resmi bir mükerrer/sıra hatası olur. Bu script,
-- numara ÜRETİMİNİ PostgreSQL'e taşıyor — burada atomik satır
-- kilidi/UPSERT ile İKİ terminal ASLA aynı numara aralığını alamaz
-- (Postgres'in kendi garantisi, uygulama kodu değil).
--
-- Bu script SADECE yeni tablo/fonksiyon ekler — MEVCUT hiçbir tabloya/
-- veriye dokunmaz, mevcut fatura numaralarını DEĞİŞTİRMEZ. Güvenle
-- çalıştırılabilir; uygulama kodu bunu kullanmaya başlayana kadar
-- hiçbir etkisi olmaz.
--
-- Supabase Dashboard'da: SQL Editor > New query > bu dosyanın TAMAMINI
-- yapıştırıp Run'a basın.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── 1) Terminaller — Şube'ye benzer, ADMİN tarafından bilinçli kaydedilen
--    bir kimlik (cihaz_id gibi kendiliğinden üretilmiş/doğrulanmamış bir
--    şeye DEĞİL, insan kararına dayanır — bkz. rapor §18) ─────────────────
CREATE TABLE IF NOT EXISTS terminaller (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  global_id      TEXT UNIQUE,
  terminal_kodu  TEXT NOT NULL UNIQUE,
  terminal_adi   TEXT,
  sube_id        BIGINT,
  aktif          BOOLEAN NOT NULL DEFAULT true,
  kayit_cihaz_id TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_updated   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── 2) Merkezi sayaç — blok tahsisinin ATOMİK kaynağı. Tek satır =
--    tek (belge_tipi, seri, yil) kombinasyonu. ────────────────────────────
CREATE TABLE IF NOT EXISTS fatura_seri_sayaclari (
  belge_tipi          TEXT NOT NULL DEFAULT 'FATURA',
  seri                TEXT NOT NULL,
  yil                 INT NOT NULL,
  son_tahsis_edilen   BIGINT NOT NULL DEFAULT 0,
  last_updated        TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (belge_tipi, seri, yil)
);

-- ── 3) Blok tahsis geçmişi — her terminale ne zaman hangi aralığın
--    verildiğinin kaydı (audit + mutabakat için). ─────────────────────────
CREATE TABLE IF NOT EXISTS fatura_seri_bloklari (
  id                 BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  global_id          TEXT UNIQUE,
  belge_tipi         TEXT NOT NULL DEFAULT 'FATURA',
  seri               TEXT NOT NULL,
  yil                INT NOT NULL,
  terminal_id        BIGINT REFERENCES terminaller(id),
  blok_baslangic     BIGINT NOT NULL,
  blok_bitis         BIGINT NOT NULL,
  son_kullanilan     BIGINT,
  durum              TEXT NOT NULL DEFAULT 'aktif',
  tahsis_zamani      TIMESTAMPTZ NOT NULL DEFAULT now(),
  aktivasyon_zamani  TIMESTAMPTZ,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_updated       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_fatura_seri_bloklari_terminal
  ON fatura_seri_bloklari(terminal_id);
CREATE INDEX IF NOT EXISTS idx_fatura_seri_bloklari_seri_yil
  ON fatura_seri_bloklari(belge_tipi, seri, yil);

-- ── 4) Mevcut faturalar tablosunda: bulutta fatura_no üzerinde HİÇ
--    UNIQUE kısıt yoktu (yerelde vardı) — artık bulutta da var. Önce
--    mevcut veride gerçek bir çakışma olmadığını doğrulayan bir kontrol,
--    SONRA kısıt. (Eğer çakışma varsa — ör. daha önce "-SYNC" ile
--    çözülmüş satırlar — kısıt eklenmeden önce görünür olsun diye
--    NOTICE ile uyarılır, script YİNE DE devam eder çünkü "-SYNC" ekli
--    satırlar zaten benzersizdir; gerçek bir çakışma varsa CREATE UNIQUE
--    INDEX aşağıda hata verip script'i durdurur — bu KASITLI, sessizce
--    geçmemesi gerekir.) ────────────────────────────────────────────────
DO $$
DECLARE
  v_cakisma_sayisi INT;
BEGIN
  SELECT COUNT(*) INTO v_cakisma_sayisi FROM (
    SELECT fatura_no FROM faturalar
    WHERE fatura_no IS NOT NULL
    GROUP BY fatura_no HAVING COUNT(*) > 1
  ) t;
  IF v_cakisma_sayisi > 0 THEN
    RAISE NOTICE 'UYARI: faturalar tablosunda % adet mükerrer fatura_no bulundu. UNIQUE kısıt eklenemeyecek — önce bu satırları elle inceleyip düzeltin (SELECT fatura_no, COUNT(*) FROM faturalar GROUP BY fatura_no HAVING COUNT(*)>1).', v_cakisma_sayisi;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS idx_faturalar_fatura_no_unique
  ON faturalar (fatura_no) WHERE fatura_no IS NOT NULL;

-- ── 5) Terminal/blok kolonları faturalar'a ekleniyor — mevcut fatura_no
--    formatı/metni DEĞİŞMİYOR, sadece hangi terminal/blok tarafından
--    üretildiğinin izi tutuluyor (audit + mutabakat için). ───────────────
ALTER TABLE faturalar ADD COLUMN IF NOT EXISTS terminal_id BIGINT;
ALTER TABLE faturalar ADD COLUMN IF NOT EXISTS blok_id BIGINT;

-- ── 6) Mevcut fatura_no'lardan sayaç TOHUMLANIR — "13 haneli sonek"
--    (4 haneli yıl + 9 haneli sıra) formatına uyan satırlar taranır,
--    her (seri,yıl) için GERÇEK maksimum bulunup sayaç oradan başlatılır.
--    Bu formata uymayan (ör. manuel serbest metinle girilmiş) satırlar
--    BİLEREK atlanır — onlar zaten yeni sistemin ürettiği bir numara
--    değil, sayacı yanlış yönlendirmemesi için dahil edilmez. ──────────
INSERT INTO fatura_seri_sayaclari (belge_tipi, seri, yil, son_tahsis_edilen)
SELECT
  'FATURA',
  substring(fatura_no from 1 for length(fatura_no) - 13) AS seri,
  substring(fatura_no from length(fatura_no) - 12 for 4)::int AS yil,
  MAX(substring(fatura_no from length(fatura_no) - 8 for 9)::bigint) AS son_tahsis_edilen
FROM faturalar
WHERE fatura_no IS NOT NULL
  AND length(fatura_no) >= 13
  AND fatura_no ~ '^.*[0-9]{13}$'
GROUP BY 2, 3
ON CONFLICT (belge_tipi, seri, yil) DO UPDATE
  SET son_tahsis_edilen = GREATEST(
    fatura_seri_sayaclari.son_tahsis_edilen,
    EXCLUDED.son_tahsis_edilen
  );

-- ── 7) Atomik blok tahsis fonksiyonu ──────────────────────────────────────
-- Aynı anda 2 terminal çağırsa bile Postgres'in kendi UPSERT satır kilidi
-- sayesinde ASLA aynı aralığı iki kez döndürmez. Yıl, SUNUCU saatinden
-- (now()) hesaplanır — çağıran cihazın saatine GÜVENİLMEZ (cihaz saati
-- yanlış ayarlıysa bile doğru yıl üretilir).
CREATE OR REPLACE FUNCTION fatura_blok_tahsis_et(
  p_terminal_id  BIGINT,
  p_seri         TEXT,
  p_blok_boyutu  INT DEFAULT 10
) RETURNS TABLE(blok_baslangic BIGINT, blok_bitis BIGINT, yil INT)
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql AS $$
#variable_conflict use_column
-- ↑ RETURNS TABLE'daki çıktı sütunları (blok_baslangic/blok_bitis/yil)
-- PL/pgSQL içinde değişken sayılır; tablo sütunlarıyla aynı isimde
-- oldukları için "column reference yil is ambiguous" hatası veriyordu
-- (2026-09-23 canlı testte yakalandı). Belirsizlikte tablo sütunu seçilir.
DECLARE
  v_yil INT := EXTRACT(YEAR FROM now())::INT;
  v_baslangic BIGINT;
BEGIN
  IF p_blok_boyutu IS NULL OR p_blok_boyutu <= 0 OR p_blok_boyutu > 1000 THEN
    RAISE EXCEPTION 'Geçersiz blok boyutu: %', p_blok_boyutu;
  END IF;

  -- Pasif (kaybolan/çalınan) terminale blok verilmez.
  IF p_terminal_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM terminaller t WHERE t.id = p_terminal_id AND t.aktif
  ) THEN
    RAISE EXCEPTION 'TERMINAL_PASIF: terminal % pasif veya kayıtlı değil', p_terminal_id;
  END IF;

  INSERT INTO fatura_seri_sayaclari (belge_tipi, seri, yil, son_tahsis_edilen, last_updated)
    VALUES ('FATURA', p_seri, v_yil, p_blok_boyutu, now())
    ON CONFLICT (belge_tipi, seri, yil)
    DO UPDATE SET
      son_tahsis_edilen = fatura_seri_sayaclari.son_tahsis_edilen + p_blok_boyutu,
      last_updated = now()
    RETURNING son_tahsis_edilen - p_blok_boyutu + 1 INTO v_baslangic;

  INSERT INTO fatura_seri_bloklari
    (belge_tipi, seri, yil, terminal_id, blok_baslangic, blok_bitis, durum, aktivasyon_zamani)
    VALUES
    ('FATURA', p_seri, v_yil, p_terminal_id, v_baslangic, v_baslangic + p_blok_boyutu - 1, 'aktif', now());

  RETURN QUERY SELECT v_baslangic, v_baslangic + p_blok_boyutu - 1, v_yil;
END;
$$;

-- ── 8) RLS — bu 3 tablo BİLEREK anon/authenticated'e HİÇ açılmıyor.
--    Uygulamanın kendi (sb_secret_/service_role) anahtarı zaten RLS'i
--    atlar; fatura_blok_tahsis_et() RPC'si SECURITY DEFINER olduğu
--    için RLS'ten BAĞIMSIZ çalışır — bu yüzden EXECUTE yetkisi de
--    aşağıda SADECE service_role'e bırakılıyor (aksi halde herkese açık
--    QR menü anahtarıyla numara aralıkları boşa harcatılabilirdi).
--    Tablolara DOĞRUDAN erişim de kapalı kalır. Aynı ilke: supabase_rls_sertlestirme
--    .sql'de diğer ~60 tablo için uygulanan desenin AYNISI — YENİ
--    eklenen tablolar da baştan bu desenle kurulmalı, sonradan
--    hatırlanmayı beklememeli. ────────────────────────────────────────
ALTER TABLE terminaller ENABLE ROW LEVEL SECURITY;
ALTER TABLE fatura_seri_sayaclari ENABLE ROW LEVEL SECURITY;
ALTER TABLE fatura_seri_bloklari ENABLE ROW LEVEL SECURITY;
-- (Kasıtlı olarak hiçbir CREATE POLICY yok — anon/authenticated'e sıfır
-- doğrudan erişim, sadece service_role ve SECURITY DEFINER RPC.)

REVOKE EXECUTE ON FUNCTION fatura_blok_tahsis_et(BIGINT, TEXT, INT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION fatura_blok_tahsis_et(BIGINT, TEXT, INT) FROM anon;
REVOKE EXECUTE ON FUNCTION fatura_blok_tahsis_et(BIGINT, TEXT, INT) FROM authenticated;
GRANT  EXECUTE ON FUNCTION fatura_blok_tahsis_et(BIGINT, TEXT, INT) TO service_role;

COMMIT;

-- ═══════════════════════════════════════════════════════════════════════════
-- DOĞRULAMA (script çalıştıktan sonra):
-- 1) SELECT * FROM fatura_seri_sayaclari;  — mevcut faturalarınızdaki gerçek
--    seri/yıllar ve doğru MAX+1'den başlayan sayaçları görmelisiniz.
-- 2) SELECT * FROM fatura_blok_tahsis_et(1, 'HLF', 10);  — (1 henüz gerçek
--    bir terminal id'si olmayabilir, test amaçlı; uygulama gerçek
--    terminal kaydını kendisi oluşturacak) — bir başlangıç/bitiş aralığı
--    dönmeli, fatura_seri_sayaclari'ndaki değer 10 artmalı.
-- ═══════════════════════════════════════════════════════════════════════════


-- ###########################################################################
-- BÖLÜM C — fatura_blok_tahsis_et() SON HÂLİ (yil-ambiguous yaması + pasif terminal kontrolü)
-- (kaynak: supabase_terminal_aktif_kontrolu.sql — supabase_fatura_blok_tahsis_fix.sql'in yerini alır)
-- ###########################################################################

-- ═══════════════════════════════════════════════════════════════════════════
-- YAMA — Pasif terminale fatura numara bloğu verilmesin — 2026-09-23
-- ═══════════════════════════════════════════════════════════════════════════
-- terminaller.aktif bayrağı hiçbir yerde kontrol edilmiyordu: kaybolan/
-- çalınan bir cihaz pasife alınsa bile numara bloğu almaya devam ederdi.
-- Artık fatura_blok_tahsis_et() pasif (ya da hiç kayıtlı olmayan) bir
-- terminal için 'TERMINAL_PASIF' hatası verir. Uygulama bunu yakalayıp
-- kullanıcıya açık bir mesaj gösterir.
--
-- Tablolara/veriye dokunmaz; yalnızca fonksiyonu yeniden tanımlar
-- (yetkiler — yalnızca service_role — korunur).
-- Supabase Dashboard > SQL Editor > New query > yapıştır > Run.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION fatura_blok_tahsis_et(
  p_terminal_id  BIGINT,
  p_seri         TEXT,
  p_blok_boyutu  INT DEFAULT 10
) RETURNS TABLE(blok_baslangic BIGINT, blok_bitis BIGINT, yil INT)
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql AS $$
#variable_conflict use_column
DECLARE
  v_yil INT := EXTRACT(YEAR FROM now())::INT;
  v_baslangic BIGINT;
BEGIN
  IF p_blok_boyutu IS NULL OR p_blok_boyutu <= 0 OR p_blok_boyutu > 1000 THEN
    RAISE EXCEPTION 'Geçersiz blok boyutu: %', p_blok_boyutu;
  END IF;

  IF p_terminal_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM terminaller t WHERE t.id = p_terminal_id AND t.aktif
  ) THEN
    RAISE EXCEPTION 'TERMINAL_PASIF: terminal % pasif veya kayıtlı değil', p_terminal_id;
  END IF;

  INSERT INTO fatura_seri_sayaclari (belge_tipi, seri, yil, son_tahsis_edilen, last_updated)
    VALUES ('FATURA', p_seri, v_yil, p_blok_boyutu, now())
    ON CONFLICT (belge_tipi, seri, yil)
    DO UPDATE SET
      son_tahsis_edilen = fatura_seri_sayaclari.son_tahsis_edilen + p_blok_boyutu,
      last_updated = now()
    RETURNING son_tahsis_edilen - p_blok_boyutu + 1 INTO v_baslangic;

  INSERT INTO fatura_seri_bloklari
    (belge_tipi, seri, yil, terminal_id, blok_baslangic, blok_bitis, durum, aktivasyon_zamani)
    VALUES
    ('FATURA', p_seri, v_yil, p_terminal_id, v_baslangic, v_baslangic + p_blok_boyutu - 1, 'aktif', now());

  RETURN QUERY SELECT v_baslangic, v_baslangic + p_blok_boyutu - 1, v_yil;
END;
$$;


-- ###########################################################################
-- BÖLÜM D — fatura_blok_tahsis_et() YETKİ KISITLAMA (yalnızca service_role)
-- (kaynak: supabase_fatura_blok_tahsis_yetki_kisitla.sql)
-- ###########################################################################

-- ═══════════════════════════════════════════════════════════════════════════
-- YAMA — fatura_blok_tahsis_et() herkese açık anahtarla çağrılabiliyordu
-- 2026-09-23
-- ═══════════════════════════════════════════════════════════════════════════
-- SORUN: Fonksiyon SECURITY DEFINER ve Postgres varsayılanı olarak EXECUTE
-- yetkisi PUBLIC'e açık. QR menü sayfasındaki publishable (anon) anahtarı
-- ele geçiren biri sürekli çağırarak fatura numarası aralıklarını boşa
-- harcatabilir (resmi numaralamada boşluk). Canlı testte doğrulandı.
--
-- Uygulama zaten sb_secret_ (service_role) anahtarıyla çalışıyor —
-- service_role yetkisi korunduğu için uygulama ETKİLENMEZ.
-- Supabase Dashboard > SQL Editor > New query > yapıştır > Run.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

REVOKE EXECUTE ON FUNCTION fatura_blok_tahsis_et(BIGINT, TEXT, INT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION fatura_blok_tahsis_et(BIGINT, TEXT, INT) FROM anon;
REVOKE EXECUTE ON FUNCTION fatura_blok_tahsis_et(BIGINT, TEXT, INT) FROM authenticated;
GRANT  EXECUTE ON FUNCTION fatura_blok_tahsis_et(BIGINT, TEXT, INT) TO service_role;


COMMIT;


-- ###########################################################################
-- BÖLÜM E — RLS SERTLEŞTİRME (herkese açık anahtarın erişimini kapatır)
-- (kaynak: supabase_rls_sertlestirme.sql)
-- ###########################################################################

-- ═══════════════════════════════════════════════════════════════════════════
-- SUPABASE RLS SERTLEŞTİRMESİ — 2026-09-22
-- ═══════════════════════════════════════════════════════════════════════════
-- NEDEN: Şu anda TÜM tablolarda "anon, authenticated USING (true)" politikası
-- var — yani QR menü sayfasındaki (qr_menu_sayfasi.html / _v2.html) herkese
-- açık anahtar (sb_publishable_...), kullanicilar (şifre hash dahil),
-- kredi_kartlari, cari, satislar, kasa_hareketleri gibi TÜM tablolara tam
-- okuma+yazma+silme erişimi veriyor. Bu anahtar sayfa kaynağında düz metin —
-- QR kodunu okutan HERKES tarayıcı geliştirici araçlarıyla görebilir.
--
-- UYGULAMANIN KENDİSİ etkilenmez: Ayarlar > Bulut Senkronizasyon'da
-- "sb_secret_" (service_role) anahtar kayıtlıysa, o anahtar RLS'i zaten
-- ATLAR (Supabase'in kendi kuralı) — aşağıdaki DROP'lar sadece anon/
-- authenticated rollerinin erişimini kapatır.
--
-- ⚠️ ÖN KOŞUL — BU SCRIPT'İ ÇALIŞTIRMADAN ÖNCE MUTLAKA KONTROL EDİN:
-- Uygulamada Ayarlar > Bulut Senkronizasyon ekranındaki kayıtlı anahtar
-- "sb_secret_" ile mi başlıyor? (Ekran zaten bunu "Secret anahtar
-- kaydedildi ✓ — tam yetkili senkron aktif" diye yeşil onaylıyor.)
--   - EVET ise → bu script'i güvenle çalıştırabilirsiniz.
--   - HAYIR ise (publishable/eyJ... anahtar kayıtlıysa) → ÖNCE Supabase
--     Dashboard > Project Settings > API Keys sayfasından "service_role"
--     (secret) anahtarı kopyalayıp o ekrana yapıştırıp kaydedin, SONRA bu
--     script'i çalıştırın. Aksi halde uygulamanızın kendi senkronu 401
--     hatası almaya başlar.
--
-- Supabase Dashboard'da: SQL Editor > New query > bu dosyanın TAMAMINI
-- yapıştırıp Run'a basın. Tamamı tek işlemde (transaction) uygulanır.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── 1) urunler: anon'a tam CRUD yerine SADECE okuma, SADECE QR menüdeki
--    ürünler (uygulama zaten bu filtreyle sorguluyor — RLS aynı kısıtı
--    sunucu tarafında da uygulasın, savunma derinliği) ──────────────────
DROP POLICY IF EXISTS urunler_all ON urunler;
DROP POLICY IF EXISTS urunler_anon_qr_menu_okuyabilir ON urunler;
CREATE POLICY urunler_anon_qr_menu_okuyabilir ON urunler
  FOR SELECT TO anon
  USING (aktif = true AND is_deleted = false AND qr_menude = 1);

-- ── 2) qr_siparisler / site_icerik: DOKUNULMUYOR — zaten doğru dar
--    kapsamlı politikaları var (INSERT-only / SELECT-only anon). ────────

-- ── 3) Geri kalan tüm tablolar: anon/authenticated'e HİÇBİR erişim
--    kalmasın — uygulamanın kendi secret anahtarı zaten RLS'i atlıyor. ──
DROP POLICY IF EXISTS adisyon_log_all ON adisyon_log;
DROP POLICY IF EXISTS audit_log_all ON audit_log;
DROP POLICY IF EXISTS ayarlar_all ON ayarlar;
DROP POLICY IF EXISTS banka_hareketler_all ON banka_hareketler;
DROP POLICY IF EXISTS banka_hesaplar_all ON banka_hesaplar;
DROP POLICY IF EXISTS banka_kapanis_snapshot_all ON banka_kapanis_snapshot;
DROP POLICY IF EXISTS bankalar_all ON bankalar;
DROP POLICY IF EXISTS bekleyen_siparis_kalem_all ON bekleyen_siparis_kalem;
DROP POLICY IF EXISTS bekleyen_siparisler_all ON bekleyen_siparisler;
DROP POLICY IF EXISTS birimler_all ON birimler;
DROP POLICY IF EXISTS borc_odemeler_all ON borc_odemeler;
DROP POLICY IF EXISTS borclar_all ON borclar;
DROP POLICY IF EXISTS cari_all ON cari;
DROP POLICY IF EXISTS cari_adres_all ON cari_adres;
DROP POLICY IF EXISTS cari_hareket_all ON cari_hareket;
DROP POLICY IF EXISTS cari_kapanis_snapshot_all ON cari_kapanis_snapshot;
DROP POLICY IF EXISTS devir_checkpoint_all ON devir_checkpoint;
DROP POLICY IF EXISTS donem_kilit_all ON donem_kilit;
DROP POLICY IF EXISTS donem_sube_durumlari_all ON donem_sube_durumlari;
DROP POLICY IF EXISTS donemler_all ON donemler;
DROP POLICY IF EXISTS fatura_detaylari_all ON fatura_detaylari;
DROP POLICY IF EXISTS faturalar_all ON faturalar;
DROP POLICY IF EXISTS fis_seri_all ON fis_seri;
DROP POLICY IF EXISTS fiyat_gecmis_all ON fiyat_gecmis;
DROP POLICY IF EXISTS fiyat_gruplari_all ON fiyat_gruplari;
DROP POLICY IF EXISTS fiyat_kademeleri_all ON fiyat_kademeleri;
DROP POLICY IF EXISTS garson_cagri_log_all ON garson_cagri_log;
DROP POLICY IF EXISTS gider_kategoriler_all ON gider_kategoriler;
DROP POLICY IF EXISTS giderler_all ON giderler;
DROP POLICY IF EXISTS iade_all ON iade;
DROP POLICY IF EXISTS iade_kalem_all ON iade_kalem;
DROP POLICY IF EXISTS irsaliye_kalem_all ON irsaliye_kalem;
DROP POLICY IF EXISTS irsaliyeler_all ON irsaliyeler;
DROP POLICY IF EXISTS kasa_hareketleri_all ON kasa_hareketleri;
DROP POLICY IF EXISTS kasa_kapanis_snapshot_all ON kasa_kapanis_snapshot;
DROP POLICY IF EXISTS kategoriler_all ON kategoriler;
DROP POLICY IF EXISTS kredi_karti_hareket_all ON kredi_karti_hareket;
DROP POLICY IF EXISTS kredi_kartlari_all ON kredi_kartlari;
DROP POLICY IF EXISTS kullanicilar_all ON kullanicilar;
DROP POLICY IF EXISTS lot_seri_all ON lot_seri;
DROP POLICY IF EXISTS markalar_all ON markalar;
DROP POLICY IF EXISTS masa_hareket_log_all ON masa_hareket_log;
DROP POLICY IF EXISTS masa_rezervasyon_all ON masa_rezervasyon;
DROP POLICY IF EXISTS masa_siparis_kalem_all ON masa_siparis_kalem;
DROP POLICY IF EXISTS masa_siparisleri_all ON masa_siparisleri;
DROP POLICY IF EXISTS masalar_all ON masalar;
DROP POLICY IF EXISTS musteri_puan_all ON musteri_puan;
DROP POLICY IF EXISTS onay_talepleri_all ON onay_talepleri;
DROP POLICY IF EXISTS personel_all ON personel;
DROP POLICY IF EXISTS promosyon_aksiyon_all ON promosyon_aksiyon;
DROP POLICY IF EXISTS promosyon_kosul_all ON promosyon_kosul;
DROP POLICY IF EXISTS promosyon_tanim_all ON promosyon_tanim;
DROP POLICY IF EXISTS promosyonlar_all ON promosyonlar;
DROP POLICY IF EXISTS puan_hareket_all ON puan_hareket;
DROP POLICY IF EXISTS rol_yetkileri_all ON rol_yetkileri;
DROP POLICY IF EXISTS roller_yetki_all ON roller_yetki;
DROP POLICY IF EXISTS satis_kalem_all ON satis_kalem;
DROP POLICY IF EXISTS satislar_all ON satislar;
DROP POLICY IF EXISTS stok_hareket_all ON stok_hareket;
DROP POLICY IF EXISTS stok_kapanis_snapshot_all ON stok_kapanis_snapshot;
DROP POLICY IF EXISTS sube_urun_all ON sube_urun;
DROP POLICY IF EXISTS subeler_all ON subeler;
DROP POLICY IF EXISTS tedarikci_siparis_kalem_all ON tedarikci_siparis_kalem;
DROP POLICY IF EXISTS tedarikci_siparisler_all ON tedarikci_siparisler;
DROP POLICY IF EXISTS urun_fiyat_gruplari_all ON urun_fiyat_gruplari;
DROP POLICY IF EXISTS vardiyalar_all ON vardiyalar;
DROP POLICY IF EXISTS zaman_fiyat_all ON zaman_fiyat;

COMMIT;

-- ═══════════════════════════════════════════════════════════════════════════
-- DOĞRULAMA (script çalıştıktan sonra):
-- 1) Uygulamada Ayarlar > Bulut Senkronizasyon > senkron hâlâ ✓ yeşil olmalı.
-- 2) Tarayıcıdan/curl'den anon anahtarla şu istek artık BOŞ ya da 401/403
--    dönmeli (önceden TÜM kullanıcıları dönüyordu):
--      GET {SUPABASE_URL}/rest/v1/kullanicilar?select=*
--      Header: apikey: sb_publishable_...  Authorization: Bearer sb_publishable_...
-- 3) QR menü sayfası (gerçek tarayıcıda) yine sorunsuz ürün listesi
--    gösterip sipariş verebilmeli.
-- ═══════════════════════════════════════════════════════════════════════════


-- ###########################################################################
-- BÖLÜM F — ARŞİV TABLOLARI + FONKSİYONLARI (yalnızca ekler, aktif tablolara dokunmaz)
-- (kaynak: supabase_arsiv_plani.sql)
-- ###########################################################################

-- ═══════════════════════════════════════════════════════════════════════
-- BARKOPRO — SUPABASE ARŞİV MİMARİSİ (ERP_DENETIM_KURALLARI.md, Madde 21 & 22)
-- Oluşturulma: 2026-09-20
--
-- AMAÇ: Yerel tarafta zaten üretim seviyesinde çalışan Yıl Sonu Devir /
-- Arşivleme sisteminin (bkz. lib/servisler/donem_arsiv_servisi.dart —
-- satislar, satis_kalem, stok_hareket, cari_hareket, kasa_hareketleri,
-- banka_hareketler'i arsiv/<YIL>/barkopro_<YIL>.db dosyasına kopyalayıp
-- Madde 19'a göre doğrulayan sistem) BULUT (Supabase/PostgreSQL)
-- tarafındaki bir benzerini kurmak: yüksek hacimli hareket tablolarını,
-- eski dönemlere ait satırları aktif tablolardan SİLMEDEN, salt-okunur
-- arşiv tablolarına ayırmak.
--
-- ───────────────────────────────────────────────────────────────────────
-- KARAR: "PARTITIONING" DEĞİL, "ARCHIVE TABLES" (Madde 21'in istediği
-- rapor — kod yazılmadan önce gerekçelendirilmesi istenen seçim)
-- ───────────────────────────────────────────────────────────────────────
-- 1. TUTARLILIK: Yerel taraf zaten "aktif DB küçük + ayrı, salt-okunur
--    arşiv dosyası" modelini kullanıyor (bkz. yukarıdaki dosya). Bulut
--    tarafında da AYNI zihinsel modeli (ayrı arşiv tablosu = yerel ayrı
--    arşiv dosyası) kurmak, native partitioning gibi yerelde hiçbir
--    karşılığı olmayan ikinci, farklı bir strateji öğrenmekten daha
--    güvenli ve tutarlı.
-- 2. RİSK: PostgreSQL'de declarative partitioning, ZATEN ÜRETİMDE DOLU
--    ve mobil istemcinin (anon/authenticated key ile) doğrudan INSERT/
--    UPSERT yaptığı bir tabloyu partitioned hale getirmek için tablo
--    DEĞİŞTİRİLEMEZ — yeni partitioned tablo oluşturup veriyi kopyalayıp
--    eski tabloyu RENAME/DROP ile değiştirmek gerekir (kesinti riski,
--    dikkatli bir "cutover" penceresi ister). Archive tables SADECE YENİ
--    TABLO EKLER — mevcut satislar/stok_hareket/cari_hareket/
--    kasa_hareketleri tablolarına ve üzerlerindeki sync akışına SIFIR
--    dokunuş, sıfır kesinti riski.
-- 3. GÜVENLİK: Madde 22'nin istediği "arşiv READ ONLY, normal kullanıcı
--    değiştiremez" kuralı, AYRI bir tabloda AYRI bir RLS politikasıyla
--    trivial biçimde ifade edilir. Tek bir partitioned tabloda RLS tüm
--    tabloya (ya da parça-bazlı ek karmaşıklığa) uygulanır — eski
--    parçalara yanlışlıkla yazma izni sızması ihtimali daha yüksektir.
-- 4. MİMARİ UYUM: Bu uygulamanın bulut istemcisi SADECE anon/authenticated
--    anahtar kullanıyor (Madde 16 — service_role hiçbir yerde yok, bkz.
--    lib/servisler/bulut/supabase_saglayici.dart). Partition attach/
--    detach gibi DBA işlemleri sunucu tarafı bir arka uç gerektirir; bu
--    projede yok. Archive tables + açıkça çağrılan SQL fonksiyonları,
--    yerelde zaten kurulu "aşamalı/checkpoint'li devir motoru" (Madde 17,
--    DonemArsivServisi) ile bire bir aynı çalışma şekline oturuyor: yerel
--    dönem kapanışı + yerel arşivleme + doğrulama TAMAMLANDIKTAN SONRA,
--    aynı cihaz/kullanıcı bu dosyadaki fonksiyonları açıkça çağırarak
--    bulut tarafını da arşivler.
--
-- SONUÇ: Archive Tables seçildi. Native partitioning şimdilik
-- uygulanmadı; ileride veri hacmi bunu zorunlu kılarsa (ör. tek tabloda
-- 50M+ satır) ayrı bir bakım penceresiyle yeniden değerlendirilebilir.
--
-- ───────────────────────────────────────────────────────────────────────
-- KAPSAM (yerel DonemArsivServisi._kurallar ile BİREBİR aynı 6 tablo)
-- ───────────────────────────────────────────────────────────────────────
-- satislar, satis_kalem (satislar'ın çocuğu), stok_hareket, cari_hareket,
-- kasa_hareketleri, banka_hareketler.
-- Kullanıcının istediği 4 tabloya (satislar, stok_hareket, cari_hareket,
-- kasa_hareketleri) EK olarak satis_kalem ve banka_hareketler de dahil
-- edildi — çünkü (a) satis_kalem'siz arşivlenmiş bir satis başlığı
-- raporlanamaz/faydasızdır, (b) yerel arşivleme zaten banka_hareketler'i
-- de kapsıyor; iki taraf arasında kapsam farkı bırakmak gelecekte
-- "yerelde arşivlendi ama bulutta arşivlenmedi" tutarsızlığına yol açar.
-- Master tablolar (urunler, cariler, subeler, kasalar, bankalar,
-- kullanicilar) Madde 7 gereği KOPYALANMIYOR — yerel karar burada da
-- aynen korunuyor.
--
-- ───────────────────────────────────────────────────────────────────────
-- KESİNLİKLE YAPILMAYAN (yerel karar burada da geçerli — bkz.
-- donem_arsiv_servisi.dart başlığı, kullanıcı onayı: "SADECE kopyalama,
-- silme yok")
-- ───────────────────────────────────────────────────────────────────────
-- ❌ Aktif tablolardan (satislar, stok_hareket, cari_hareket,
--    kasa_hareketleri, banka_hareketler, satis_kalem) satır SİLİNMİYOR.
--    Bu dosyanın sonunda, sadece ileride AYRI bir onayla açılmak üzere
--    YORUM SATIRI olarak bırakılmış bir "taşıma" iskeleti var — şu anda
--    ÇALIŞTIRILMAMALI.
-- ❌ Bu script hiçbir mevcut tabloyu, index'i, RLS politikasını veya
--    sync akışını DEĞİŞTİRMİYOR — sadece yeni tablo/index/politika/
--    fonksiyon EKLİYOR (additive-only).
--
-- ───────────────────────────────────────────────────────────────────────
-- SYNC_QUEUE UYUMLULUĞU (statik doğrulama — Madde 21 görevinin 2. adımı)
-- ───────────────────────────────────────────────────────────────────────
-- lib/servisler/bulut/sync_kuyruk_yazici.dart:SyncKuyrukYazici.ekleTxn()
-- her çağrıda `tablo` parametresini SABİT BİR STRING LİTERALİ olarak
-- alır (bkz. lib/depolar/satis_deposu.dart, stok_deposu.dart,
-- cari_deposu.dart, kasa_deposu.dart çağrı noktaları — 'satislar',
-- 'stok_hareket', 'cari_hareket', 'kasa_hareketleri'). Kuyruk hiçbir
-- yerde dinamik bir "tüm tablolar" listesi üzerinden ÇALIŞMIYOR; push
-- işlemi (BulutManager._isle → supabase_sync_servisi.dart) yalnızca
-- kuyruğa yazılmış olan bu sabit tablo adlarını Supabase'e gönderir.
-- Bu script'teki `*_arsiv` tabloları hiçbir kod yolunda `tablo:` argümanı
-- olarak GEÇMİYOR ve bu tablolara yazma SADECE aşağıdaki
-- `arsivle_*` fonksiyonları elle/açıkça çağrıldığında olur — sync
-- worker'ı bunları asla otomatik tetiklemez. Dolayısıyla:
--   • Arşiv tabloları eklemek sync_queue'nun davranışını DEĞİŞTİRMEZ.
--   • Sync push'u ile arşivleme fonksiyonu arasında çakışma/conflict
--     imkânı YOKTUR (ikisi de global_id UNIQUE + idempotent upsert
--     kullanır, ama tamamen ayrı tetikleyicilerle çalışır).
--   • Arşivleme dönem KAPANDIKTAN ve yerel devir/arşiv/doğrulama
--     TAMAMLANDIKTAN sonra çağrılmalıdır — o noktada ilgili dönem için
--     zaten hiçbir yeni satış/hareket üretilmiyor olması gerekir (Madde
--     4/5 — Yıl Sonu Kontrolü zaten "sync queue boş mu" kontrolünü
--     kapanıştan önce yapıyor), bu yüzden arşivleme sırasında hâlâ
--     bekleyen bir sync push'uyla yarışma riski pratikte yoktur.
-- ═══════════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════════
-- BÖLÜM 1 — ARŞİV TABLOLARI
-- Her tablo, ilgili aktif tablonun kolonlarını BİREBİR mirror eder + 2 ek
-- kolon: donem_id (hangi kapanmış döneme ait olduğu) ve arsivlenme_tarihi
-- (bu satırın arşive ne zaman yazıldığı — audit amaçlı).
-- ═══════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS satislar_arsiv (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  donem_id BIGINT NOT NULL REFERENCES donemler(id),
  global_id TEXT,
  fis_no TEXT,
  tarih TIMESTAMPTZ,
  cari_id BIGINT,
  toplam_tutar DOUBLE PRECISION,
  iskonto_tutar DOUBLE PRECISION,
  iskonto_oran DOUBLE PRECISION,
  kdv_tutar DOUBLE PRECISION,
  genel_toplam DOUBLE PRECISION,
  odenen_tutar DOUBLE PRECISION,
  odeme_yontemi TEXT,
  fis_tipi TEXT,
  aciklama TEXT,
  kargo_ucreti DOUBLE PRECISION,
  kasiyer_id BIGINT,
  kullanici_id BIGINT,
  vardiya_id BIGINT,
  sube_id BIGINT,
  iptal BOOLEAN,
  iptal_tarihi TIMESTAMPTZ,
  iptal_nedeni TEXT,
  last_updated TIMESTAMPTZ,
  is_deleted BOOLEAN,
  efatura_uuid TEXT,
  efatura_durum TEXT,
  efatura_gonderim_tarihi TEXT,
  efatura_yanit TEXT,
  servis_ucreti DOUBLE PRECISION,
  deleted_at TIMESTAMPTZ,
  cihaz_id TEXT,
  arsivlenme_tarihi TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- 🔴 DÜZELTME: PostgreSQL'de "ALTER TABLE ... ADD CONSTRAINT IF NOT
-- EXISTS" GEÇERLİ BİR SÖZDİZİMİ DEĞİL (sadece ADD COLUMN/CREATE INDEX
-- IF NOT EXISTS destekleniyor) — script'i ikinci kez çalıştırmak burada
-- syntax error verirdi. Eşdeğer, tekrar-çalıştırılabilir bir UNIQUE
-- INDEX kullanılıyor — ON CONFLICT (global_id) hedefi için de yeterli.
CREATE UNIQUE INDEX IF NOT EXISTS uq_satislar_arsiv_global_id ON satislar_arsiv (global_id);

CREATE TABLE IF NOT EXISTS satis_kalem_arsiv (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  donem_id BIGINT NOT NULL REFERENCES donemler(id),
  global_id TEXT,
  satis_id BIGINT,
  urun_id BIGINT,
  urun_adi TEXT,
  barkod TEXT,
  miktar DOUBLE PRECISION,
  birim_fiyat DOUBLE PRECISION,
  iskonto_oran DOUBLE PRECISION,
  iskonto_tutar DOUBLE PRECISION,
  kdv_oran DOUBLE PRECISION,
  kdv_tutar DOUBLE PRECISION,
  net_fiyat DOUBLE PRECISION,
  toplam_tutar DOUBLE PRECISION,
  lot_id BIGINT,
  seri_no TEXT,
  alis_fiyat DOUBLE PRECISION,
  alis_fiyat_kdv DOUBLE PRECISION,
  last_updated TIMESTAMPTZ,
  cihaz_id TEXT,
  arsivlenme_tarihi TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_satis_kalem_arsiv_global_id ON satis_kalem_arsiv (global_id);

CREATE TABLE IF NOT EXISTS stok_hareket_arsiv (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  donem_id BIGINT NOT NULL REFERENCES donemler(id),
  global_id TEXT,
  cihaz_id TEXT,
  urun_id BIGINT,
  hareket_turu TEXT,
  miktar DOUBLE PRECISION,
  onceki_stok DOUBLE PRECISION,
  sonraki_stok DOUBLE PRECISION,
  birim_maliyet DOUBLE PRECISION,
  tarih TIMESTAMPTZ,
  referans_id BIGINT,
  referans_turu TEXT,
  lot_id BIGINT,
  aciklama TEXT,
  kullanici_id BIGINT,
  sube_id BIGINT,
  last_updated TIMESTAMPTZ,
  arsivlenme_tarihi TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_stok_hareket_arsiv_global_id ON stok_hareket_arsiv (global_id);

CREATE TABLE IF NOT EXISTS cari_hareket_arsiv (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  donem_id BIGINT NOT NULL REFERENCES donemler(id),
  global_id TEXT,
  cari_id BIGINT,
  tarih TIMESTAMPTZ,
  fis_tipi TEXT,
  fis_id BIGINT,
  fis_no TEXT,
  aciklama TEXT,
  borc DOUBLE PRECISION,
  alacak DOUBLE PRECISION,
  bakiye DOUBLE PRECISION,
  odeme_turu TEXT,
  kullanici TEXT,
  last_updated TIMESTAMPTZ,
  is_deleted BOOLEAN,
  cihaz_id TEXT,
  arsivlenme_tarihi TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_cari_hareket_arsiv_global_id ON cari_hareket_arsiv (global_id);

CREATE TABLE IF NOT EXISTS kasa_hareketleri_arsiv (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  donem_id BIGINT NOT NULL REFERENCES donemler(id),
  global_id TEXT,
  hareket_tipi TEXT,
  tutar DOUBLE PRECISION,
  bakiye_sonrasi DOUBLE PRECISION,
  referans_id BIGINT,
  referans_turu TEXT,
  tarih TIMESTAMPTZ,
  aciklama TEXT,
  kullanici_id BIGINT,
  sube_id BIGINT,
  last_updated TIMESTAMPTZ,
  deleted_at TIMESTAMPTZ,
  odeme_yontemi TEXT,
  arsivlenme_tarihi TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_kasa_hareketleri_arsiv_global_id ON kasa_hareketleri_arsiv (global_id);

CREATE TABLE IF NOT EXISTS banka_hareketler_arsiv (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  donem_id BIGINT NOT NULL REFERENCES donemler(id),
  global_id TEXT,
  banka_hesap_id BIGINT,
  kredi_karti_id BIGINT,
  islem_tipi TEXT,
  tutar DOUBLE PRECISION,
  aciklama TEXT,
  tarih TIMESTAMPTZ,
  referans_no TEXT,
  karsi_hesap TEXT,
  onceki_bakiye DOUBLE PRECISION,
  sonraki_bakiye DOUBLE PRECISION,
  last_updated TEXT,
  is_deleted BOOLEAN,
  arsivlenme_tarihi TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_banka_hareketler_arsiv_global_id ON banka_hareketler_arsiv (global_id);


-- ═══════════════════════════════════════════════════════════════════════
-- BÖLÜM 2 — INDEXLER
-- Aktif tablolardaki mevcut indexlerin (bkz. "supabase tablolar önemli
-- buluttaki tablolar.txt" BÖLÜM 7) arşiv karşılıkları + donem_id.
-- ═══════════════════════════════════════════════════════════════════════

CREATE INDEX IF NOT EXISTS idx_satislar_arsiv_donem_id ON satislar_arsiv(donem_id);
CREATE INDEX IF NOT EXISTS idx_satislar_arsiv_cari_id ON satislar_arsiv(cari_id);
CREATE INDEX IF NOT EXISTS idx_satislar_arsiv_sube_id ON satislar_arsiv(sube_id);
CREATE INDEX IF NOT EXISTS idx_satislar_arsiv_tarih ON satislar_arsiv(tarih);
CREATE INDEX IF NOT EXISTS idx_satislar_arsiv_fis_no ON satislar_arsiv(fis_no);

CREATE INDEX IF NOT EXISTS idx_satis_kalem_arsiv_donem_id ON satis_kalem_arsiv(donem_id);
CREATE INDEX IF NOT EXISTS idx_satis_kalem_arsiv_satis_id ON satis_kalem_arsiv(satis_id);
CREATE INDEX IF NOT EXISTS idx_satis_kalem_arsiv_urun_id ON satis_kalem_arsiv(urun_id);

CREATE INDEX IF NOT EXISTS idx_stok_hareket_arsiv_donem_id ON stok_hareket_arsiv(donem_id);
CREATE INDEX IF NOT EXISTS idx_stok_hareket_arsiv_urun_id ON stok_hareket_arsiv(urun_id);
CREATE INDEX IF NOT EXISTS idx_stok_hareket_arsiv_sube_id ON stok_hareket_arsiv(sube_id);
CREATE INDEX IF NOT EXISTS idx_stok_hareket_arsiv_tarih ON stok_hareket_arsiv(tarih);

CREATE INDEX IF NOT EXISTS idx_cari_hareket_arsiv_donem_id ON cari_hareket_arsiv(donem_id);
CREATE INDEX IF NOT EXISTS idx_cari_hareket_arsiv_cari_id ON cari_hareket_arsiv(cari_id);
CREATE INDEX IF NOT EXISTS idx_cari_hareket_arsiv_fis_id ON cari_hareket_arsiv(fis_id);
CREATE INDEX IF NOT EXISTS idx_cari_hareket_arsiv_tarih ON cari_hareket_arsiv(tarih);

CREATE INDEX IF NOT EXISTS idx_kasa_hareketleri_arsiv_donem_id ON kasa_hareketleri_arsiv(donem_id);
CREATE INDEX IF NOT EXISTS idx_kasa_hareketleri_arsiv_sube_id ON kasa_hareketleri_arsiv(sube_id);
CREATE INDEX IF NOT EXISTS idx_kasa_hareketleri_arsiv_referans_id ON kasa_hareketleri_arsiv(referans_id);
CREATE INDEX IF NOT EXISTS idx_kasa_hareketleri_arsiv_tarih ON kasa_hareketleri_arsiv(tarih);

CREATE INDEX IF NOT EXISTS idx_banka_hareketler_arsiv_donem_id ON banka_hareketler_arsiv(donem_id);
CREATE INDEX IF NOT EXISTS idx_banka_hareketler_arsiv_banka_hesap_id ON banka_hareketler_arsiv(banka_hesap_id);
CREATE INDEX IF NOT EXISTS idx_banka_hareketler_arsiv_tarih ON banka_hareketler_arsiv(tarih);


-- ═══════════════════════════════════════════════════════════════════════
-- BÖLÜM 3 — ROW LEVEL SECURITY (Madde 22)
--
-- Bu uygulamanın bulut istemcisi (Flutter/anon+authenticated key) hiçbir
-- zaman service_role kullanmıyor (Madde 16). Mevcut aktif tablolarda RLS
-- "FOR ALL ... USING (true) WITH CHECK (true)" şeklinde (tüm CRUD
-- serbest — bkz. BÖLÜM 8, mevcut şema dosyası). Arşiv tabloları için
-- BİLİNÇLİ OLARAK DAHA SIKI bir politika kuruluyor:
--   • SELECT   → anon + authenticated: SERBEST (eski dönem raporları
--                okunabilmeli).
--   • INSERT   → SADECE authenticated (anonim/misafir cihaz arşivleme
--                yapamaz), WITH CHECK(true) — global_id UNIQUE kısıtı +
--                aşağıdaki arsivle_*() fonksiyonlarının ON CONFLICT DO
--                NOTHING kullanması sayesinde bu INSERT izni "idempotent
--                ekleme" ötesine geçemez: aynı satırı iki kez göndermek
--                veri çoğaltmaz, var olan bir arşiv satırını asla
--                değiştirmez.
--   • UPDATE / DELETE → HİÇBİR POLİTİKA YOK. PostgreSQL RLS'de bir
--                komut için politika tanımlanmamışsa o komut owner/
--                superuser DIŞINDAKİ HİÇBİR ROL için mümkün değildir.
--                Yani arşiv, tablo sahibi (Supabase SQL editöründen
--                elle, acil bir düzeltme için) DIŞINDA KİMSE TARAFINDAN
--                DEĞİŞTİRİLEMEZ/SİLİNEMEZ — Madde 22'nin istediği "salt
--                okunur" garantisi bu şekilde DB seviyesinde (UI'da
--                değil) sağlanıyor.
-- ═══════════════════════════════════════════════════════════════════════

DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'satislar_arsiv', 'satis_kalem_arsiv', 'stok_hareket_arsiv',
    'cari_hareket_arsiv', 'kasa_hareketleri_arsiv', 'banka_hareketler_arsiv'
  ]
  LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY;', t);

    EXECUTE format('DROP POLICY IF EXISTS %I ON %I;', t || '_select', t);
    EXECUTE format(
      'CREATE POLICY %I ON %I FOR SELECT TO anon, authenticated USING (true);',
      t || '_select', t);

    EXECUTE format('DROP POLICY IF EXISTS %I ON %I;', t || '_insert', t);
    EXECUTE format(
      'CREATE POLICY %I ON %I FOR INSERT TO authenticated WITH CHECK (true);',
      t || '_insert', t);
    -- UPDATE / DELETE: kasıtlı olarak politika oluşturulmuyor (yukarıdaki not).
  END LOOP;
END $$;


-- ═══════════════════════════════════════════════════════════════════════
-- BÖLÜM 4 — ARŞİVLEME FONKSİYONLARI
--
-- Her fonksiyon: dönem kapanış tarih aralığına düşen satırları ilgili
-- aktif tablodan SEÇER, arşiv tablosuna INSERT ... SELECT ile (tek
-- set-based sorgu — Postgres tarafında çalışır, milyonlarca satırda bile
-- istemci RAM'ine hiçbir veri çekilmez, Madde 24) YAZAR, ON CONFLICT
-- (global_id) DO NOTHING ile idempotent çalışır (Madde 28 — aynı devir
-- iki kez çalıştırılırsa veri çoğalmaz). AKTİF TABLODAN HİÇBİR SATIR
-- SİLİNMEZ (bkz. dosya başı).
--
-- Şube-bazlı tablolar (satislar, stok_hareket, kasa_hareketleri) için
-- p_sube_id ZORUNLU — yerel DonemArsivServisi ile aynı desen (Madde 29,
-- çoklu şube: devir şube bazında yapılmalı). Şirket geneli tablolar
-- (cari_hareket, banka_hareketler) için şube filtresi yoktur.
-- ═══════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION arsivle_satislar(p_donem_id BIGINT, p_sube_id BIGINT, p_baslangic TIMESTAMPTZ, p_bitis TIMESTAMPTZ)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE v_sayi BIGINT;
BEGIN
  INSERT INTO satislar_arsiv (
    donem_id, global_id, fis_no, tarih, cari_id, toplam_tutar, iskonto_tutar,
    iskonto_oran, kdv_tutar, genel_toplam, odenen_tutar, odeme_yontemi,
    fis_tipi, aciklama, kargo_ucreti, kasiyer_id, kullanici_id, vardiya_id,
    sube_id, iptal, iptal_tarihi, iptal_nedeni, last_updated, is_deleted,
    efatura_uuid, efatura_durum, efatura_gonderim_tarihi, efatura_yanit,
    servis_ucreti, deleted_at, cihaz_id
  )
  SELECT
    p_donem_id, global_id, fis_no, tarih, cari_id, toplam_tutar, iskonto_tutar,
    iskonto_oran, kdv_tutar, genel_toplam, odenen_tutar, odeme_yontemi,
    fis_tipi, aciklama, kargo_ucreti, kasiyer_id, kullanici_id, vardiya_id,
    sube_id, iptal, iptal_tarihi, iptal_nedeni, last_updated, is_deleted,
    efatura_uuid, efatura_durum, efatura_gonderim_tarihi, efatura_yanit,
    servis_ucreti, deleted_at, cihaz_id
  FROM satislar
  WHERE sube_id = p_sube_id AND tarih >= p_baslangic AND tarih <= p_bitis
  ON CONFLICT (global_id) DO NOTHING;
  GET DIAGNOSTICS v_sayi = ROW_COUNT;
  RETURN v_sayi;
END $$;

CREATE OR REPLACE FUNCTION arsivle_satis_kalem(p_donem_id BIGINT, p_sube_id BIGINT, p_baslangic TIMESTAMPTZ, p_bitis TIMESTAMPTZ)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE v_sayi BIGINT;
BEGIN
  -- satis_kalem'in kendi tarih/sube_id'si yok — satis_id JOIN'i üzerinden
  -- filtrelenir (yerel _satisKalemArsivle ile AYNI desen). Önkoşul:
  -- satislar bu dönem için ÖNCE arşivlenmiş olmalı (çağrı sırası önemli).
  INSERT INTO satis_kalem_arsiv (
    donem_id, global_id, satis_id, urun_id, urun_adi, barkod, miktar,
    birim_fiyat, iskonto_oran, iskonto_tutar, kdv_oran, kdv_tutar,
    net_fiyat, toplam_tutar, lot_id, seri_no, alis_fiyat, alis_fiyat_kdv,
    last_updated, cihaz_id
  )
  SELECT
    p_donem_id, sk.global_id, sk.satis_id, sk.urun_id, sk.urun_adi, sk.barkod,
    sk.miktar, sk.birim_fiyat, sk.iskonto_oran, sk.iskonto_tutar, sk.kdv_oran,
    sk.kdv_tutar, sk.net_fiyat, sk.toplam_tutar, sk.lot_id, sk.seri_no,
    sk.alis_fiyat, sk.alis_fiyat_kdv, sk.last_updated, sk.cihaz_id
  FROM satis_kalem sk
  WHERE sk.satis_id IN (
    SELECT id FROM satislar
    WHERE sube_id = p_sube_id AND tarih >= p_baslangic AND tarih <= p_bitis
  )
  ON CONFLICT (global_id) DO NOTHING;
  GET DIAGNOSTICS v_sayi = ROW_COUNT;
  RETURN v_sayi;
END $$;

CREATE OR REPLACE FUNCTION arsivle_stok_hareket(p_donem_id BIGINT, p_sube_id BIGINT, p_baslangic TIMESTAMPTZ, p_bitis TIMESTAMPTZ)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE v_sayi BIGINT;
BEGIN
  INSERT INTO stok_hareket_arsiv (
    donem_id, global_id, cihaz_id, urun_id, hareket_turu, miktar,
    onceki_stok, sonraki_stok, birim_maliyet, tarih, referans_id,
    referans_turu, lot_id, aciklama, kullanici_id, sube_id, last_updated
  )
  SELECT
    p_donem_id, global_id, cihaz_id, urun_id, hareket_turu, miktar,
    onceki_stok, sonraki_stok, birim_maliyet, tarih, referans_id,
    referans_turu, lot_id, aciklama, kullanici_id, sube_id, last_updated
  FROM stok_hareket
  WHERE sube_id = p_sube_id AND tarih >= p_baslangic AND tarih <= p_bitis
  ON CONFLICT (global_id) DO NOTHING;
  GET DIAGNOSTICS v_sayi = ROW_COUNT;
  RETURN v_sayi;
END $$;

CREATE OR REPLACE FUNCTION arsivle_kasa_hareketleri(p_donem_id BIGINT, p_sube_id BIGINT, p_baslangic TIMESTAMPTZ, p_bitis TIMESTAMPTZ)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE v_sayi BIGINT;
BEGIN
  INSERT INTO kasa_hareketleri_arsiv (
    donem_id, global_id, hareket_tipi, tutar, bakiye_sonrasi, referans_id,
    referans_turu, tarih, aciklama, kullanici_id, sube_id, last_updated,
    deleted_at, odeme_yontemi
  )
  SELECT
    p_donem_id, global_id, hareket_tipi, tutar, bakiye_sonrasi, referans_id,
    referans_turu, tarih, aciklama, kullanici_id, sube_id, last_updated,
    deleted_at, odeme_yontemi
  FROM kasa_hareketleri
  WHERE sube_id = p_sube_id AND tarih >= p_baslangic AND tarih <= p_bitis
  ON CONFLICT (global_id) DO NOTHING;
  GET DIAGNOSTICS v_sayi = ROW_COUNT;
  RETURN v_sayi;
END $$;

-- Şirket geneli (şube filtresiz) — bir dönem kapanışında sadece BİR KEZ
-- çağrılmalı (herhangi bir şube tarafından); birden fazla şube tarafından
-- tekrar çağrılsa bile ON CONFLICT DO NOTHING sayesinde veri çoğalmaz.
CREATE OR REPLACE FUNCTION arsivle_cari_hareket(p_donem_id BIGINT, p_baslangic TIMESTAMPTZ, p_bitis TIMESTAMPTZ)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE v_sayi BIGINT;
BEGIN
  INSERT INTO cari_hareket_arsiv (
    donem_id, global_id, cari_id, tarih, fis_tipi, fis_id, fis_no,
    aciklama, borc, alacak, bakiye, odeme_turu, kullanici, last_updated,
    is_deleted, cihaz_id
  )
  SELECT
    p_donem_id, global_id, cari_id, tarih, fis_tipi, fis_id, fis_no,
    aciklama, borc, alacak, bakiye, odeme_turu, kullanici, last_updated,
    is_deleted, cihaz_id
  FROM cari_hareket
  WHERE tarih >= p_baslangic AND tarih <= p_bitis
  ON CONFLICT (global_id) DO NOTHING;
  GET DIAGNOSTICS v_sayi = ROW_COUNT;
  RETURN v_sayi;
END $$;

CREATE OR REPLACE FUNCTION arsivle_banka_hareketleri(p_donem_id BIGINT, p_baslangic TIMESTAMPTZ, p_bitis TIMESTAMPTZ)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE v_sayi BIGINT;
BEGIN
  INSERT INTO banka_hareketler_arsiv (
    donem_id, global_id, banka_hesap_id, kredi_karti_id, islem_tipi, tutar,
    aciklama, tarih, referans_no, karsi_hesap, onceki_bakiye,
    sonraki_bakiye, last_updated, is_deleted
  )
  SELECT
    p_donem_id, global_id, banka_hesap_id, kredi_karti_id, islem_tipi, tutar,
    aciklama, tarih, referans_no, karsi_hesap, onceki_bakiye,
    sonraki_bakiye, last_updated, is_deleted
  FROM banka_hareketler
  WHERE tarih >= p_baslangic AND tarih <= p_bitis
  ON CONFLICT (global_id) DO NOTHING;
  GET DIAGNOSTICS v_sayi = ROW_COUNT;
  RETURN v_sayi;
END $$;


-- ═══════════════════════════════════════════════════════════════════════
-- BÖLÜM 5 — DOĞRULAMA (Madde 19)
-- Aktif/arşiv arasında satır sayısı VE toplam tutar karşılaştırması —
-- yerel DonemArsivTabloSonucu.dogrulandiMi ile AYNI mantık (tutar
-- toleransı: 0.01). Devir'in bulut kolunu "tamamlandı" işaretlemeden
-- önce bu fonksiyonun tüm satırlarında dogrulandi = true olmalı.
-- ═══════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION arsiv_dogrula(p_donem_id BIGINT, p_sube_id BIGINT, p_baslangic TIMESTAMPTZ, p_bitis TIMESTAMPTZ)
RETURNS TABLE(tablo TEXT, aktif_sayim BIGINT, arsiv_sayim BIGINT, aktif_toplam DOUBLE PRECISION, arsiv_toplam DOUBLE PRECISION, dogrulandi BOOLEAN)
LANGUAGE plpgsql AS $$
BEGIN
  RETURN QUERY
  SELECT 'satislar'::TEXT,
    (SELECT COUNT(*) FROM satislar WHERE sube_id = p_sube_id AND tarih >= p_baslangic AND tarih <= p_bitis),
    (SELECT COUNT(*) FROM satislar_arsiv WHERE donem_id = p_donem_id AND sube_id = p_sube_id),
    (SELECT COALESCE(SUM(genel_toplam),0) FROM satislar WHERE sube_id = p_sube_id AND tarih >= p_baslangic AND tarih <= p_bitis),
    (SELECT COALESCE(SUM(genel_toplam),0) FROM satislar_arsiv WHERE donem_id = p_donem_id AND sube_id = p_sube_id),
    NULL::BOOLEAN;

  RETURN QUERY
  SELECT 'stok_hareket'::TEXT,
    (SELECT COUNT(*) FROM stok_hareket WHERE sube_id = p_sube_id AND tarih >= p_baslangic AND tarih <= p_bitis),
    (SELECT COUNT(*) FROM stok_hareket_arsiv WHERE donem_id = p_donem_id AND sube_id = p_sube_id),
    (SELECT COALESCE(SUM(miktar),0) FROM stok_hareket WHERE sube_id = p_sube_id AND tarih >= p_baslangic AND tarih <= p_bitis),
    (SELECT COALESCE(SUM(miktar),0) FROM stok_hareket_arsiv WHERE donem_id = p_donem_id AND sube_id = p_sube_id),
    NULL::BOOLEAN;

  RETURN QUERY
  SELECT 'kasa_hareketleri'::TEXT,
    (SELECT COUNT(*) FROM kasa_hareketleri WHERE sube_id = p_sube_id AND tarih >= p_baslangic AND tarih <= p_bitis),
    (SELECT COUNT(*) FROM kasa_hareketleri_arsiv WHERE donem_id = p_donem_id AND sube_id = p_sube_id),
    (SELECT COALESCE(SUM(tutar),0) FROM kasa_hareketleri WHERE sube_id = p_sube_id AND tarih >= p_baslangic AND tarih <= p_bitis),
    (SELECT COALESCE(SUM(tutar),0) FROM kasa_hareketleri_arsiv WHERE donem_id = p_donem_id AND sube_id = p_sube_id),
    NULL::BOOLEAN;

  RETURN QUERY
  SELECT 'cari_hareket'::TEXT,
    (SELECT COUNT(*) FROM cari_hareket WHERE tarih >= p_baslangic AND tarih <= p_bitis),
    (SELECT COUNT(*) FROM cari_hareket_arsiv WHERE donem_id = p_donem_id),
    (SELECT COALESCE(SUM(borc),0) + COALESCE(SUM(alacak),0) FROM cari_hareket WHERE tarih >= p_baslangic AND tarih <= p_bitis),
    (SELECT COALESCE(SUM(borc),0) + COALESCE(SUM(alacak),0) FROM cari_hareket_arsiv WHERE donem_id = p_donem_id),
    NULL::BOOLEAN;

  RETURN QUERY
  SELECT 'banka_hareketler'::TEXT,
    (SELECT COUNT(*) FROM banka_hareketler WHERE tarih >= p_baslangic AND tarih <= p_bitis),
    (SELECT COUNT(*) FROM banka_hareketler_arsiv WHERE donem_id = p_donem_id),
    (SELECT COALESCE(SUM(tutar),0) FROM banka_hareketler WHERE tarih >= p_baslangic AND tarih <= p_bitis),
    (SELECT COALESCE(SUM(tutar),0) FROM banka_hareketler_arsiv WHERE donem_id = p_donem_id),
    NULL::BOOLEAN;

  RETURN QUERY
  SELECT 'satis_kalem'::TEXT,
    (SELECT COUNT(*) FROM satis_kalem WHERE satis_id IN (SELECT id FROM satislar WHERE sube_id = p_sube_id AND tarih >= p_baslangic AND tarih <= p_bitis)),
    (SELECT COUNT(*) FROM satis_kalem_arsiv WHERE donem_id = p_donem_id),
    (SELECT COALESCE(SUM(toplam_tutar),0) FROM satis_kalem WHERE satis_id IN (SELECT id FROM satislar WHERE sube_id = p_sube_id AND tarih >= p_baslangic AND tarih <= p_bitis)),
    (SELECT COALESCE(SUM(toplam_tutar),0) FROM satis_kalem_arsiv WHERE donem_id = p_donem_id),
    NULL::BOOLEAN;
END $$;

-- Kullanım: sonuç satırlarının HER BİRİNDE aktif_sayim = arsiv_sayim VE
-- abs(aktif_toplam - arsiv_toplam) < 0.01 olmalı. Örnek:
--   SELECT *, (aktif_sayim = arsiv_sayim AND abs(aktif_toplam - arsiv_toplam) < 0.01) AS dogrulandi
--   FROM arsiv_dogrula(<donem_id>, <sube_id>, '2026-01-01', '2026-12-31 23:59:59');


-- ═══════════════════════════════════════════════════════════════════════
-- BÖLÜM 6 — [ONAY BEKLİYOR — ŞU AN ÇALIŞTIRILMAMALI]
-- Aktif tablodan taşıma/silme (DB şişmesini gerçekten azaltan adım,
-- Madde 23). Yerel tarafta da AYNI kapsam dışı bırakma kararı var (bkz.
-- donem_arsiv_servisi.dart başlığı) — üretim finansal verisini etkiler,
-- ayrı ve açık bir kullanıcı onayı gerektirir. Sadece REFERANS/iskelet
-- olarak bırakıldı; arsiv_dogrula() o dönem için TÜM satırlarda
-- dogrulandi=true DÖNMEDEN bu ASLA çalıştırılmamalı.
-- ═══════════════════════════════════════════════════════════════════════

-- DELETE FROM satis_kalem WHERE satis_id IN (SELECT id FROM satislar WHERE sube_id = :p_sube_id AND tarih >= :p_baslangic AND tarih <= :p_bitis);
-- DELETE FROM satislar WHERE sube_id = :p_sube_id AND tarih >= :p_baslangic AND tarih <= :p_bitis;
-- DELETE FROM stok_hareket WHERE sube_id = :p_sube_id AND tarih >= :p_baslangic AND tarih <= :p_bitis;
-- DELETE FROM kasa_hareketleri WHERE sube_id = :p_sube_id AND tarih >= :p_baslangic AND tarih <= :p_bitis;
-- DELETE FROM cari_hareket WHERE tarih >= :p_baslangic AND tarih <= :p_bitis;
-- DELETE FROM banka_hareketler WHERE tarih >= :p_baslangic AND tarih <= :p_bitis;

-- ###########################################################################
-- BÖLÜM G — İŞLETME HESABIYLA GÜVENLİ GİRİŞ (Supabase Auth + izin listesi)
-- 2026-09-28 — bu bölüm TEK BAŞINA da çalıştırılabilir.
-- ###########################################################################
--
-- AMAÇ: cihazlarda tam yetkili gizli anahtar (sb_secret_ / service_role —
-- RLS'i tamamen atlar) kalmasın. Uygulama artık işletme hesabının
-- e-posta/şifresiyle giriş yapıp kısa ömürlü erişim anahtarı (JWT) kullanır.
-- Buluttaki veriye YALNIZCA aşağıdaki izin listesine eklenen hesaplar erişir.
--
-- ⚠️ ÇALIŞTIRMADAN ÖNCE (Supabase panelinde):
--   1) Authentication → Sign In / Providers → "Allow new users to sign up"
--      KAPATIN. (Herkese açık anahtar QR menü sayfasında görünür; kayıt açık
--      kalırsa herkes hesap açabilir. İzin listesi yine korur ama kapatın.)
--   2) Authentication → Users → "Add user" → e-posta + şifre, "Auto Confirm
--      User" işaretli. İşletme için bir hesap (isterseniz kasa başına bir).
--
-- SIRA GÜVENLİDİR: bu bölüm çalıştıktan sonra gizli anahtarla çalışan eski
-- cihazlar ÇALIŞMAYA DEVAM EDER (service_role kuralları atlar). Cihazları
-- tek tek herkese açık anahtar + işletme hesabına geçirin; HEPSİ geçince
-- Settings → API Keys'ten gizli anahtarı iptal edin (roll/revoke).
-- ###########################################################################

BEGIN;

-- ── G1. İzin listesi ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.bulut_yetkili_hesaplar (
  user_id    UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  aciklama   TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- Politika YOK: yalnız SQL Editor / service_role değiştirebilir. Uygulama
-- bu tabloya hiç erişmez; kontrol aşağıdaki SECURITY DEFINER fonksiyonla.
ALTER TABLE public.bulut_yetkili_hesaplar ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.bulut_yetkili_mi() RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $
  SELECT EXISTS (SELECT 1 FROM public.bulut_yetkili_hesaplar WHERE user_id = auth.uid());
$;
REVOKE ALL ON FUNCTION public.bulut_yetkili_mi() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.bulut_yetkili_mi() TO anon, authenticated;

-- ── G2. Eski geniş kuralları kaldır, her tabloya "yalnız izinli hesap" ────
-- Korunan (bilinçli) kurallar — QR menü sayfası (herkese açık anahtar):
--   urunler_anon_qr_menu_okuyabilir, qr_siparis_anon_ekleyebilir,
--   site_icerik_anon_okuyabilir.
-- Diğer TÜM kurallar kaldırılır — ör. Bölüm F'deki arşiv tablolarının
-- "anon, authenticated USING (true)" okuma kuralı, arşivlenmiş satış/kasa/
-- cari verisini herkese açık anahtara açıyordu.
DO $
DECLARE
  p RECORD;
  t RECORD;
BEGIN
  FOR p IN
    SELECT tablename, policyname FROM pg_policies
    WHERE schemaname = 'public'
      AND policyname NOT IN ('urunler_anon_qr_menu_okuyabilir',
                             'qr_siparis_anon_ekleyebilir',
                             'site_icerik_anon_okuyabilir')
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', p.policyname, p.tablename);
    RAISE NOTICE 'Kaldırılan kural: %.%', p.tablename, p.policyname;
  END LOOP;

  FOR t IN
    SELECT tablename FROM pg_tables
    WHERE schemaname = 'public' AND tablename <> 'bulut_yetkili_hesaplar'
  LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t.tablename);
    EXECUTE format(
      'CREATE POLICY isletme_hesabi_tam_erisim ON public.%I FOR ALL TO authenticated '
      'USING (public.bulut_yetkili_mi()) WITH CHECK (public.bulut_yetkili_mi())',
      t.tablename);
    EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON public.%I TO authenticated',
                   t.tablename);
  END LOOP;
END $;

GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO authenticated;

-- ── G3. Fatura numara bloğu fonksiyonu: yalnız izinli hesap ──────────────
-- (Bölüm C'deki gövdenin AYNISI + başta izin kontrolü. Bölüm D'de yalnız
-- service_role'e açılmıştı; artık uygulama işletme hesabıyla çağırıyor.)
CREATE OR REPLACE FUNCTION fatura_blok_tahsis_et(
  p_terminal_id  BIGINT,
  p_seri         TEXT,
  p_blok_boyutu  INT DEFAULT 10
) RETURNS TABLE(blok_baslangic BIGINT, blok_bitis BIGINT, yil INT)
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql AS $
#variable_conflict use_column
DECLARE
  v_yil INT := EXTRACT(YEAR FROM now())::INT;
  v_baslangic BIGINT;
BEGIN
  -- service_role (gizli anahtar, geçiş dönemi) veya izinli işletme hesabı.
  IF coalesce(auth.role(), '') <> 'service_role' AND NOT public.bulut_yetkili_mi() THEN
    RAISE EXCEPTION 'YETKISIZ: bu hesap buluta erişim iznine sahip değil';
  END IF;

  IF p_blok_boyutu IS NULL OR p_blok_boyutu <= 0 OR p_blok_boyutu > 1000 THEN
    RAISE EXCEPTION 'Geçersiz blok boyutu: %', p_blok_boyutu;
  END IF;

  IF p_terminal_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM terminaller t WHERE t.id = p_terminal_id AND t.aktif
  ) THEN
    RAISE EXCEPTION 'TERMINAL_PASIF: terminal % pasif veya kayıtlı değil', p_terminal_id;
  END IF;

  INSERT INTO fatura_seri_sayaclari (belge_tipi, seri, yil, son_tahsis_edilen, last_updated)
    VALUES ('FATURA', p_seri, v_yil, p_blok_boyutu, now())
    ON CONFLICT (belge_tipi, seri, yil)
    DO UPDATE SET
      son_tahsis_edilen = fatura_seri_sayaclari.son_tahsis_edilen + p_blok_boyutu,
      last_updated = now()
    RETURNING son_tahsis_edilen - p_blok_boyutu + 1 INTO v_baslangic;

  INSERT INTO fatura_seri_bloklari
    (belge_tipi, seri, yil, terminal_id, blok_baslangic, blok_bitis, durum, aktivasyon_zamani)
    VALUES
    ('FATURA', p_seri, v_yil, p_terminal_id, v_baslangic, v_baslangic + p_blok_boyutu - 1, 'aktif', now());

  RETURN QUERY SELECT v_baslangic, v_baslangic + p_blok_boyutu - 1, v_yil;
END;
$;
REVOKE EXECUTE ON FUNCTION fatura_blok_tahsis_et(BIGINT, TEXT, INT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION fatura_blok_tahsis_et(BIGINT, TEXT, INT) FROM anon;
GRANT  EXECUTE ON FUNCTION fatura_blok_tahsis_et(BIGINT, TEXT, INT) TO authenticated, service_role;

COMMIT;

-- ── G4. Dosya depolama (ürün resimleri, işyeri fotoğrafları, QR menü) ────
-- Okuma: bucket'lar "public" ise herkese açık adresle okunur (QR menü
-- sayfası bunu kullanır) — burada yalnız YAZMA/SİLME izinli hesaba verilir.
DROP POLICY IF EXISTS isletme_hesabi_depolama ON storage.objects;
CREATE POLICY isletme_hesabi_depolama ON storage.objects FOR ALL TO authenticated
  USING (bucket_id IN ('urun-resimleri', 'isyeri-fotograflari', 'menu')
         AND public.bulut_yetkili_mi())
  WITH CHECK (bucket_id IN ('urun-resimleri', 'isyeri-fotograflari', 'menu')
              AND public.bulut_yetkili_mi());
-- (G4 ayrı çalışır: "must be owner of table objects" hatası verirse yukarıdaki
--  G1–G3 yine uygulanmış olur; bu kuralı Storage → Policies ekranından ekleyin.)

-- ── G5. İşletme hesabını izin listesine ekleyin (e-postayı değiştirin) ────
-- Panelde "Add user" ile açtığınız HER hesap için:
--
--   INSERT INTO public.bulut_yetkili_hesaplar (user_id, aciklama)
--   SELECT id, 'Merkez kasa' FROM auth.users WHERE email = 'kasa@isletmeniz.com'
--   ON CONFLICT (user_id) DO NOTHING;
--
-- Bir hesabın erişimini kaldırmak (ör. çalınan tablet):
--   DELETE FROM public.bulut_yetkili_hesaplar
--   WHERE user_id = (SELECT id FROM auth.users WHERE email = '...');

-- ── G6. Doğrulama ─────────────────────────────────────────────────────────
-- (a) İzinli hesaplar:
--   SELECT u.email, y.aciklama FROM public.bulut_yetkili_hesaplar y
--   JOIN auth.users u ON u.id = y.user_id;
-- (b) RLS kapalı tablo kalmamalı (boş dönmeli):
--   SELECT tablename FROM pg_tables WHERE schemaname='public' AND NOT rowsecurity;
-- (c) Herkese açık anahtara açık kalan kurallar — yalnız 3 QR kuralı dönmeli:
--   SELECT tablename, policyname, roles FROM pg_policies
--   WHERE schemaname='public' AND 'anon' = ANY(roles);


-- ── H. Bulutta mevcut olup uygulamanın yerel şemasında bulunmayan sütunlar ─
-- Canlı bulut şemasıyla birebir aynı kalması için (hepsi NULL kabul eder;
-- uygulama bunları göndermez/okumaz, yalnız mevcut veri korunur).
ALTER TABLE promosyonlar ADD COLUMN IF NOT EXISTS ad TEXT;
ALTER TABLE promosyonlar ADD COLUMN IF NOT EXISTS created_at TEXT;
ALTER TABLE faturalar    ADD COLUMN IF NOT EXISTS efatura_uuid TEXT;
ALTER TABLE faturalar    ADD COLUMN IF NOT EXISTS efatura_durum TEXT;
ALTER TABLE faturalar    ADD COLUMN IF NOT EXISTS efatura_tipi TEXT;
ALTER TABLE personel     ADD COLUMN IF NOT EXISTS ise_baslama_tarihi TEXT;

-- ═══ DOSYA SONU ═══
