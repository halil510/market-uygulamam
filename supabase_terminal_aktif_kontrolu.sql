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
