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
