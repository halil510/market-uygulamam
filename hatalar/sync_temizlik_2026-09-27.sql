-- ═══════════════════════════════════════════════════════════════════════════
-- SYNC ÇAKIŞMASI — BULUTTAKİ BOZUK KAYITLAR: TEŞHİS + BİR KERELİK TEMİZLİK
-- 2026-09-27
-- ═══════════════════════════════════════════════════════════════════════════
-- Kök neden (uygulamada düzeltildi): Hızlı Satış / Masa / Toptan / Bayi
-- Siparişi her satışı buluta İKİ KEZ gönderiyordu:
--   (a) doğru kopya: satış G1 kimliğiyle + kalemler doğru satis_id ile,
--   (b) hatalı kopya: satış YENİ bir G2 kimliğiyle (yerel kayıt da G2'ye
--       çevriliyordu) + kalemler satis_id=0 ve global_id BOŞ olarak.
-- Sonuç bulutta: aynı fiş no'lu 2 satış (biri kalemsiz) + hiçbir satışa bağlı
-- olmayan kimliksiz kalem satırları. Cihazlar "Buluttan Al" yapınca kalemsiz
-- kopya "…-SYNC" hayalet satış olarak iniyordu.
--
-- ADIM 1'i çalıştırıp sonuçlara bakın. ADIM 2 (temizlik) YEDEK ALARAK çalışır;
-- sayılar beklediğiniz gibiyse çalıştırın. Supabase > SQL Editor.
-- ═══════════════════════════════════════════════════════════════════════════


-- ── ADIM 1 — TEŞHİS (yalnızca okur) ─────────────────────────────────────────

-- 1a) Kimliksiz / hiçbir satışa bağlı olmayan kalemler (hatalı kopya b)
SELECT COUNT(*) AS kimliksiz_veya_yetim_kalem
  FROM satis_kalem
 WHERE global_id IS NULL OR satis_id IS NULL OR satis_id = 0;

-- 1b) Aynı fiş no'lu birden fazla satış (çift gönderim)
SELECT fis_no, COUNT(*) AS adet,
       array_agg(id ORDER BY id) AS bulut_idler,
       array_agg(genel_toplam ORDER BY id) AS tutarlar
  FROM satislar
 WHERE fis_no IS NOT NULL
 GROUP BY fis_no
HAVING COUNT(*) > 1
 ORDER BY fis_no;

-- 1c) Kalemi hiç olmayan satışlar
SELECT COUNT(*) AS kalemsiz_satis
  FROM satislar s
 WHERE NOT EXISTS (SELECT 1 FROM satis_kalem k WHERE k.satis_id = s.id);

-- 1d) Saat dilimi kayması: "gelecekte" duran last_updated (yerel saat UTC
--     gibi yazılmış — uygulamada düzeltildi, eski satırlar kendiliğinden
--     birkaç saat içinde geçmişte kalır; temizlik GEREKMEZ, sadece bilgi)
SELECT 'satislar' AS tablo, COUNT(*) AS gelecekte FROM satislar WHERE last_updated > now() + interval '5 minutes'
UNION ALL
SELECT 'satis_kalem', COUNT(*) FROM satis_kalem WHERE last_updated > now() + interval '5 minutes'
UNION ALL
SELECT 'cari_hareket', COUNT(*) FROM cari_hareket WHERE last_updated > now() + interval '5 minutes'
UNION ALL
SELECT 'stok_hareket', COUNT(*) FROM stok_hareket WHERE last_updated > now() + interval '5 minutes';

-- 1e) Temizlikte "kopya" sayılacak satışlar (ADIM 2b'nin önizlemesi):
--     aynı fiş no + aynı tutar, kendisinin kalemi YOK, eşinin kalemi VAR.
SELECT s.id, s.global_id, s.fis_no, s.genel_toplam, s.tarih
  FROM satislar s
 WHERE COALESCE(s.is_deleted, false) = false
   AND NOT EXISTS (SELECT 1 FROM satis_kalem k WHERE k.satis_id = s.id)
   AND EXISTS (
         SELECT 1 FROM satislar e
          WHERE e.fis_no = s.fis_no AND e.id <> s.id
            AND ABS(COALESCE(e.genel_toplam,0) - COALESCE(s.genel_toplam,0)) < 0.01
            AND EXISTS (SELECT 1 FROM satis_kalem k2 WHERE k2.satis_id = e.id))
 ORDER BY s.fis_no;


-- ── ADIM 2 — TEMİZLİK (yedek alır, tek işlemde) ────────────────────────────
-- Önce ADIM 1 sonuçlarını kontrol edin. Hepsi tek transaction: bir hata
-- olursa hiçbir şey değişmez.

BEGIN;

-- 2a) Kimliksiz/yetim kalemleri yedekle ve sil (bunlar hiçbir satışa bağlı
--     değil; doğru kopyaları zaten kendi satışlarının altında duruyor)
CREATE TABLE IF NOT EXISTS yedek_20260927_satis_kalem AS
  SELECT * FROM satis_kalem WHERE false;
INSERT INTO yedek_20260927_satis_kalem
  SELECT * FROM satis_kalem
   WHERE global_id IS NULL OR satis_id IS NULL OR satis_id = 0;
DELETE FROM satis_kalem
 WHERE global_id IS NULL OR satis_id IS NULL OR satis_id = 0;

-- 2b) Kalemsiz çift satış kopyalarını yedekle ve SOFT-DELETE et
--     (is_deleted=true — cihazlar bir sonraki "Buluttan Al"da kendi
--     yerel "-SYNC" kopyalarını otomatik silinmiş işaretler). Kalıcı
--     silme YAPILMAZ.
CREATE TABLE IF NOT EXISTS yedek_20260927_satislar AS
  SELECT * FROM satislar WHERE false;
WITH kopya AS (
  SELECT s.id
    FROM satislar s
   WHERE COALESCE(s.is_deleted, false) = false
     AND NOT EXISTS (SELECT 1 FROM satis_kalem k WHERE k.satis_id = s.id)
     AND EXISTS (
           SELECT 1 FROM satislar e
            WHERE e.fis_no = s.fis_no AND e.id <> s.id
              AND ABS(COALESCE(e.genel_toplam,0) - COALESCE(s.genel_toplam,0)) < 0.01
              AND EXISTS (SELECT 1 FROM satis_kalem k2 WHERE k2.satis_id = e.id))
)
INSERT INTO yedek_20260927_satislar SELECT * FROM satislar WHERE id IN (SELECT id FROM kopya);

UPDATE satislar
   SET is_deleted = true, last_updated = now()
 WHERE id IN (SELECT id FROM yedek_20260927_satislar);

COMMIT;

-- Geri almak gerekirse (yedekten):
--   INSERT INTO satis_kalem OVERRIDING SYSTEM VALUE SELECT * FROM yedek_20260927_satis_kalem;
--   UPDATE satislar SET is_deleted = false, last_updated = now()
--    WHERE id IN (SELECT id FROM yedek_20260927_satislar);
