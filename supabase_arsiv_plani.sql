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
