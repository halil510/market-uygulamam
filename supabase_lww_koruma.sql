-- ════════════════════════════════════════════════════════════════════════
-- MarketPlus — Sunucu tarafı "son yazan kazanır" koruması
-- ════════════════════════════════════════════════════════════════════════
-- SORUN: Uygulama, kuyruktaki satırı kuyruğa girdiği andaki görüntüsüyle
-- gönderir. Cihaz uzun süre çevrimdışı kaldıysa, eski görüntü buluttaki
-- daha yeni kaydın (başka cihazın düzenlemesi) üzerine yazılırdı.
--
-- ÇÖZÜM: Her tablonun UPDATE'inde gelen last_updated, mevcut kaydınkinden
-- KESİN olarak eskiyse güncelleme sessizce atlanır (RETURN NULL). Karar
-- veritabanında, satır kilidi altında verilir; iki cihaz aynı anda
-- gönderse bile yarış olmaz. İstemci de gönderim öncesi aynı kontrolü
-- yapar (SupabaseSaglayici.topluUpsert) — bu dosya kesin/atomik güvencedir.
--
-- DAVRANIŞ:
--   • Eşit ya da daha yeni last_updated  → güncelleme uygulanır.
--   • Daha eski last_updated             → satır olduğu gibi kalır.
--   • OLD/NEW last_updated NULL          → güncelleme uygulanır.
--   • INSERT ve DELETE etkilenmez.
--
-- KURULUM: Supabase → SQL Editor'de bir kez çalıştırın. Tekrar çalıştırmak
-- güvenlidir (idempotent). Geri almak için dosyanın sonundaki bloğu kullanın.
-- ════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.mp_lww_koruma()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF OLD.last_updated IS NOT NULL
     AND NEW.last_updated IS NOT NULL
     AND NEW.last_updated < OLD.last_updated THEN
    RETURN NULL;  -- eski görüntü: mevcut (daha yeni) kaydı koru
  END IF;
  RETURN NEW;
END;
$$;

-- last_updated sütunu TIMESTAMPTZ olan tüm public tablolara uygula.
DO $$
DECLARE
  t record;
BEGIN
  FOR t IN
    SELECT c.table_name
    FROM information_schema.columns c
    JOIN information_schema.tables tb
      ON tb.table_schema = c.table_schema
     AND tb.table_name   = c.table_name
     AND tb.table_type   = 'BASE TABLE'
    WHERE c.table_schema = 'public'
      AND c.column_name  = 'last_updated'
      AND c.data_type    = 'timestamp with time zone'
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS mp_lww_koruma_trg ON public.%I', t.table_name);
    -- WHEN koşulu: tetikleyici yalnız last_updated gerçekten geriye
    -- giderken çalışır; normal güncellemelere maliyeti sıfırdır.
    EXECUTE format(
      'CREATE TRIGGER mp_lww_koruma_trg BEFORE UPDATE ON public.%I '
      'FOR EACH ROW WHEN (NEW.last_updated < OLD.last_updated) '
      'EXECUTE FUNCTION public.mp_lww_koruma()', t.table_name);
  END LOOP;
END $$;

-- ── GERİ ALMA (gerekirse) ────────────────────────────────────────────────
-- DO $$ DECLARE t record; BEGIN
--   FOR t IN SELECT tgrelid::regclass AS tbl FROM pg_trigger
--            WHERE tgname = 'mp_lww_koruma_trg' LOOP
--     EXECUTE format('DROP TRIGGER mp_lww_koruma_trg ON %s', t.tbl);
--   END LOOP;
-- END $$;
-- DROP FUNCTION IF EXISTS public.mp_lww_koruma();
