-- ═══════════════════════════════════════════════════════════════════════
-- CARİ MÜKERRER TEMİZLİĞİ (29.09.2026)
-- Bulutta 127 cari + hareketleri ikinci kez oluşmuş (15:07 UTC civarı,
-- yeni global_id + 'CARIO-n' kodlarıyla). ÖNCE 1-3'ü çalıştırıp sonuca
-- bakın; 4 (soft-delete) yalnızca sonuç doğruysa çalıştırılmalıdır.
-- Silme YAPILMAZ: is_deleted=true işaretlenir (geri alınabilir).
-- ═══════════════════════════════════════════════════════════════════════

-- 1) Aday mükerrer cariler: aynı unvanın SONRADAN (15:00-15:30 UTC) oluşan kopyası
--    (daha eski bir aynı-unvanlı kayıt varsa).
CREATE TEMP TABLE IF NOT EXISTS _mukerrer_cari AS
SELECT c.id, c.unvan, c.cari_kodu, c.bakiye, c.last_updated
FROM cari c
WHERE c.last_updated >= '2026-09-29T15:00:00Z' AND c.last_updated < '2026-09-29T15:30:00Z'
  AND COALESCE(c.is_deleted, false) = false
  AND EXISTS (SELECT 1 FROM cari o
              WHERE o.id < c.id
                AND UPPER(TRIM(o.unvan)) = UPPER(TRIM(c.unvan))
                AND o.last_updated < '2026-09-29T15:00:00Z');

-- 2) Kaç kayıt? (127 bekleniyor) ve örnekler
SELECT COUNT(*) AS aday_cari FROM _mukerrer_cari;
SELECT * FROM _mukerrer_cari ORDER BY id LIMIT 10;

-- 3) Bu carilere bağlı hareketler (kopyalarına ait olduğundan emin olun)
SELECT COUNT(*) AS aday_hareket
FROM cari_hareket h JOIN _mukerrer_cari m ON m.id = h.cari_id
WHERE COALESCE(h.is_deleted, false) = false;

-- 4) UYGULA (yalnızca 2-3 doğruysa; yorum satırlarını açın):
-- UPDATE cari_hareket h SET is_deleted = true, last_updated = now()
--   FROM _mukerrer_cari m WHERE h.cari_id = m.id;
-- UPDATE cari c SET is_deleted = true, last_updated = now()
--   FROM _mukerrer_cari m WHERE c.id = m.id;

-- 5) Sonra doğrulama: kalan aktif cari sayısı 130 civarı olmalı
-- SELECT COUNT(*) FROM cari WHERE COALESCE(is_deleted,false) = false;
