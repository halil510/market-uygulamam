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
