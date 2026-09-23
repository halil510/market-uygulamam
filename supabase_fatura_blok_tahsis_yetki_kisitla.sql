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

-- Canlı testlerde oluşan test serisi kayıtlarını temizle (gerçek serilere
-- dokunmaz — yalnızca '__RLSTEST__' serisi).
DELETE FROM fatura_seri_bloklari  WHERE seri = '__RLSTEST__';
DELETE FROM fatura_seri_sayaclari WHERE seri = '__RLSTEST__';

COMMIT;
