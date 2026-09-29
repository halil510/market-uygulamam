-- ═══════════════════════════════════════════════════════════════════════
-- BULUT VERİ TUTARLILIK KONTROLÜ (SALT OKUNUR — hiçbir şeyi değiştirmez)
-- Supabase > SQL Editor'de BÖLÜM BÖLÜM çalıştırın; her sorgu sorunlu kayıt
-- SAYISINI (ve ilk örnekleri) döndürür. 0 satır/0 sayı = sağlam.
-- Sonuçları (özellikle 0 olmayanları) bana yapıştırın; temizlik SQL'ini
-- ona göre hazırlarım. Yazma/silme içermez.
-- ═══════════════════════════════════════════════════════════════════════

-- ── 1. YETİM KAYITLAR (FK bütünlüğü) ───────────────────────────────────
SELECT 'satis_kalem → satislar yok' AS kontrol, COUNT(*) AS adet
FROM satis_kalem k WHERE NOT EXISTS (SELECT 1 FROM satislar s WHERE s.id = k.satis_id)
UNION ALL
SELECT 'satis_kalem → urunler yok', COUNT(*)
FROM satis_kalem k WHERE k.urun_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM urunler u WHERE u.id = k.urun_id)
UNION ALL
SELECT 'cari_hareket → cari yok', COUNT(*)
FROM cari_hareket h WHERE NOT EXISTS (SELECT 1 FROM cari c WHERE c.id = h.cari_id)
UNION ALL
SELECT 'stok_hareket → urunler yok', COUNT(*)
FROM stok_hareket h WHERE NOT EXISTS (SELECT 1 FROM urunler u WHERE u.id = h.urun_id)
UNION ALL
SELECT 'iade_kalem → iade yok', COUNT(*)
FROM iade_kalem k WHERE NOT EXISTS (SELECT 1 FROM iade i WHERE i.id = k.iade_id)
UNION ALL
SELECT 'iade → satislar yok', COUNT(*)
FROM iade i WHERE i.satis_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM satislar s WHERE s.id = i.satis_id)
UNION ALL
SELECT 'fatura_detaylari → faturalar yok', COUNT(*)
FROM fatura_detaylari d WHERE NOT EXISTS (SELECT 1 FROM faturalar f WHERE f.id = d.fatura_id)
UNION ALL
SELECT 'kasa (referans satis) → satislar yok', COUNT(*)
FROM kasa_hareketleri k WHERE k.referans_turu = 'satis'
  AND NOT EXISTS (SELECT 1 FROM satislar s WHERE s.id = k.referans_id);

-- ── 2. MÜKERRER global_id (aynı kayıt iki kez) ──────────────────────────
SELECT 'satislar' AS tablo, global_id, COUNT(*) FROM satislar WHERE global_id IS NOT NULL GROUP BY global_id HAVING COUNT(*) > 1
UNION ALL
SELECT 'satis_kalem', global_id, COUNT(*) FROM satis_kalem WHERE global_id IS NOT NULL GROUP BY global_id HAVING COUNT(*) > 1
UNION ALL
SELECT 'kasa_hareketleri', global_id, COUNT(*) FROM kasa_hareketleri WHERE global_id IS NOT NULL GROUP BY global_id HAVING COUNT(*) > 1
UNION ALL
SELECT 'cari_hareket', global_id, COUNT(*) FROM cari_hareket WHERE global_id IS NOT NULL GROUP BY global_id HAVING COUNT(*) > 1
UNION ALL
SELECT 'stok_hareket', global_id, COUNT(*) FROM stok_hareket WHERE global_id IS NOT NULL GROUP BY global_id HAVING COUNT(*) > 1;

-- ── 3. AYNI FİŞ NO İKİ SATIŞTA / -SYNC KOPYALARI ───────────────────────
SELECT fis_no, COUNT(*) AS adet FROM satislar
WHERE COALESCE(is_deleted, false) = false
GROUP BY fis_no HAVING COUNT(*) > 1 ORDER BY adet DESC LIMIT 50;

SELECT COUNT(*) AS sync_kopyasi_fis FROM satislar WHERE fis_no LIKE '%-SYNC%';

-- ── 4. TUTAR: SATIŞ BAŞLIĞI ↔ KALEM TOPLAMI ────────────────────────────
SELECT s.id, s.fis_no, s.genel_toplam,
       COALESCE(s.kargo_ucreti,0) + COALESCE(s.servis_ucreti,0) AS ek_ucret,
       SUM(k.toplam_tutar) AS kalem_toplami,
       ROUND((s.genel_toplam - COALESCE(s.kargo_ucreti,0) - COALESCE(s.servis_ucreti,0) - SUM(k.toplam_tutar))::numeric, 2) AS fark
FROM satislar s JOIN satis_kalem k ON k.satis_id = s.id
WHERE COALESCE(s.is_deleted,false) = false AND COALESCE(s.iptal,false) = false
GROUP BY s.id, s.fis_no, s.genel_toplam, s.kargo_ucreti, s.servis_ucreti
HAVING ABS(s.genel_toplam - COALESCE(s.kargo_ucreti,0) - COALESCE(s.servis_ucreti,0) - SUM(k.toplam_tutar)) > 0.10
ORDER BY ABS(s.genel_toplam - SUM(k.toplam_tutar)) DESC LIMIT 100;

-- Kalemi hiç olmayan (başlık var, kalem yok) satışlar:
SELECT s.id, s.fis_no, s.genel_toplam, s.tarih
FROM satislar s
WHERE COALESCE(s.is_deleted,false) = false AND COALESCE(s.iptal,false) = false
  AND NOT EXISTS (SELECT 1 FROM satis_kalem k WHERE k.satis_id = s.id)
ORDER BY s.tarih DESC LIMIT 100;

-- ── 5. TUTAR: SATIŞ ↔ KASA/CARİ KARŞILIĞI ───────────────────────────────
-- Nakit/Kart satışın kasa karşılığı olmayanlar:
SELECT s.id, s.fis_no, s.genel_toplam, s.odeme_yontemi, s.odenen_tutar
FROM satislar s
WHERE COALESCE(s.is_deleted,false) = false AND COALESCE(s.iptal,false) = false
  AND s.odeme_yontemi IN ('Nakit','Kart','Kredi Kartı')
  AND NOT EXISTS (SELECT 1 FROM kasa_hareketleri k
                  WHERE k.referans_id = s.id AND k.referans_turu = 'satis')
ORDER BY s.tarih DESC LIMIT 100;

-- Kasaya satış tutarından FAZLA yazılanlar (para üstü hatası — eski sürümden):
SELECT s.id, s.fis_no, s.genel_toplam, SUM(k.tutar) AS kasaya_yazilan,
       ROUND((SUM(k.tutar) - s.genel_toplam)::numeric, 2) AS fazla
FROM satislar s JOIN kasa_hareketleri k
  ON k.referans_id = s.id AND k.referans_turu = 'satis' AND k.hareket_tipi = 'Satış'
WHERE k.deleted_at IS NULL AND COALESCE(s.is_deleted,false) = false
GROUP BY s.id, s.fis_no, s.genel_toplam
HAVING SUM(k.tutar) - s.genel_toplam > 0.01
ORDER BY fazla DESC LIMIT 100;

-- ── 6. CARİ BAKİYE ↔ HAREKET TOPLAMI ────────────────────────────────────
SELECT c.id, c.bakiye AS kayitli_bakiye,
       COALESCE(SUM(h.borc - h.alacak), 0) AS hareketten,
       ROUND((c.bakiye - COALESCE(SUM(h.borc - h.alacak), 0))::numeric, 2) AS fark
FROM cari c LEFT JOIN cari_hareket h ON h.cari_id = c.id AND COALESCE(h.is_deleted,false) = false
GROUP BY c.id, c.bakiye
HAVING ABS(c.bakiye - COALESCE(SUM(h.borc - h.alacak), 0)) > 0.01
ORDER BY ABS(c.bakiye - COALESCE(SUM(h.borc - h.alacak), 0)) DESC LIMIT 100;

-- ── 7. ÜRÜN STOĞU ↔ STOK HAREKETİ ───────────────────────────────────────
SELECT u.id, u.stok AS kayitli_stok,
       COALESCE(SUM(h.sonraki_stok - h.onceki_stok), 0) AS hareketten,
       ROUND((u.stok - COALESCE(SUM(h.sonraki_stok - h.onceki_stok), 0))::numeric, 3) AS fark
FROM urunler u LEFT JOIN stok_hareket h ON h.urun_id = u.id
GROUP BY u.id, u.stok
HAVING ABS(u.stok - COALESCE(SUM(h.sonraki_stok - h.onceki_stok), 0)) > 0.001
ORDER BY ABS(u.stok - COALESCE(SUM(h.sonraki_stok - h.onceki_stok), 0)) DESC LIMIT 100;

-- ── 8. SİLİNMİŞ SATIŞA BAĞLI AKTİF HAREKETLER ───────────────────────────
SELECT 'kasa' AS tur, COUNT(*) FROM kasa_hareketleri k
JOIN satislar s ON s.id = k.referans_id AND k.referans_turu = 'satis'
WHERE COALESCE(s.is_deleted,false) = true AND k.deleted_at IS NULL AND k.hareket_tipi = 'Satış'
UNION ALL
SELECT 'cari', COUNT(*) FROM cari_hareket h
JOIN satislar s ON s.id = h.fis_id AND h.fis_tipi IN ('Satış','Toptan Satış','Toptan Satış (Sipariş)')
WHERE COALESCE(s.is_deleted,false) = true AND COALESCE(h.is_deleted,false) = false
  AND h.fis_tipi <> 'Satış İptali';

-- ═══════════════════════════════════════════════════════════════════════
-- ONARIM (İSTEĞE BAĞLI — YAZAR): "çift indirim" hatasıyla bozulan kalemler
-- Kök neden: kaydetme anında kalem toplamı birim_fiyat × (1 − iskonto_oran)
-- ile yeniden hesaplanıyordu (100 TL → 71,43 TL). Kod düzeltildi; eski
-- kayıtlar için önce ÖNİZLEME, sonra (isterseniz) UPDATE:
-- ═══════════════════════════════════════════════════════════════════════

-- ÖNİZLEME: yalnızca başlık toplamı = SUM(birim_fiyat × miktar) olan satışlar
WITH aday AS (
  SELECT s.id
  FROM satislar s JOIN satis_kalem k ON k.satis_id = s.id
  WHERE COALESCE(s.is_deleted,false) = false AND COALESCE(s.iptal,false) = false
  GROUP BY s.id, s.genel_toplam, s.kargo_ucreti, s.servis_ucreti
  HAVING ABS(s.genel_toplam - COALESCE(s.kargo_ucreti,0) - COALESCE(s.servis_ucreti,0) - SUM(k.toplam_tutar)) > 0.10
     AND ABS(s.genel_toplam - COALESCE(s.kargo_ucreti,0) - COALESCE(s.servis_ucreti,0) - SUM(k.birim_fiyat * k.miktar)) <= 0.10
)
SELECT k.id, k.satis_id, k.urun_adi, k.birim_fiyat, k.miktar, k.toplam_tutar AS eski_toplam,
       k.birim_fiyat * k.miktar AS yeni_toplam
FROM satis_kalem k WHERE k.satis_id IN (SELECT id FROM aday);

-- UYGULA (önizleme doğruysa; last_updated güncellenir ki cihazlar çeksin):
-- UPDATE satis_kalem k SET
--   net_fiyat     = k.birim_fiyat,
--   toplam_tutar  = k.birim_fiyat * k.miktar,
--   kdv_tutar     = CASE WHEN k.kdv_oran > 0 THEN (k.birim_fiyat * k.miktar) * k.kdv_oran / (100 + k.kdv_oran) ELSE 0 END,
--   iskonto_tutar = CASE WHEN k.iskonto_oran > 0 AND k.iskonto_oran < 100
--                        THEN (k.birim_fiyat / (1 - k.iskonto_oran/100) - k.birim_fiyat) * k.miktar ELSE 0 END,
--   last_updated  = now()
-- WHERE k.satis_id IN (SELECT id FROM aday);   -- yukarıdaki WITH aday ... ile birlikte çalıştırın
