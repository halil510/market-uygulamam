-- ═══════════════════════════════════════════════════════════════════════════
-- YAMA — fatura_blok_tahsis_et() "column reference yil is ambiguous" hatası
-- 2026-09-23
-- ═══════════════════════════════════════════════════════════════════════════
-- supabase_fatura_seri_bloklari.sql daha önce çalıştırıldıysa SADECE bunu
-- çalıştırın (tablolara/veriye dokunmaz, yalnızca fonksiyonu yeniden tanımlar).
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

-- DOĞRULAMA (isteğe bağlı — sayacı 1 blok ilerletir, zararsız ama numara
-- aralığı "harcanır"; test etmek istemezseniz uygulamadan ilk faturayı kesin):
-- SELECT * FROM fatura_blok_tahsis_et(NULL, 'TEST', 1);
