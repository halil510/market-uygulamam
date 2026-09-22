# CENTRAL DOCUMENT NUMBERING DEEP AUDIT

**Tarih:** 2026-09-23
**Kapsam:** `ERP_DENETIM_KURALLARI.md.txt`'de tanımlanan görev — fatura (ve
genişletilebilir şekilde diğer resmi belge) numaralandırma sistemini
çoklu cihaz/kasa/şube, offline, senkron, GİB, yıl geçişi, devir/arşiv,
RLS, backup/restore, audit ve performans açılarından denetleme.
**Yöntem:** 4 paralel derin araştırma ajanı (read-only, gerçek kod
üzerinden, dosya:satır referanslı) + bu sentez. **HİÇBİR KOD
DEĞİŞTİRİLMEDİ** — doküman kuralına göre bu SADECE analiz raporu.

---

## 1. Mevcut Mimari

Fatura numaralandırmasına dokunan tüm dosyalar:

| Dosya | Rol |
|---|---|
| `lib/servisler/faturalandirma_servisi.dart` | `sonrakiFaturaNo()` (otomatik yol üretici), `faturaOlustur()` (orkestrasyon) |
| `lib/depolar/fatura_deposu.dart` | `siradakiFaturaNoUret()` (manuel yol üretici + çakışma-retry kaynağı), `ekle()` (insert + 1 kez retry) |
| `lib/ekranlar/fatura/fatura_ekle_ekrani.dart` | Manuel fatura ekranı — numarayı **serbest metin** olarak düzenlenebilir gösterir |
| `lib/ekranlar/ayarlar/fatura_ayar_ekrani.dart` | Ön ek/başlangıç no ayarı (SharedPreferences) — bugün eklenen "farklı cihaza farklı ön ek" uyarısı burada |
| `lib/veri/database/veritabani.dart:450-537` | `_cakismaKorumasiUygula()` — senkron anı çakışma-sonrası yeniden adlandırma |
| `lib/veri/database/semalar/finans_semasi.dart` | Yerel şema: `fatura_no TEXT UNIQUE` |
| `supabase tablolar önemli buluttaki tablolar.txt` | Bulut şeması: `fatura_no TEXT` — **UNIQUE YOK** |
| `lib/servisler/gib_servisi.dart`, `gib/gib_ubl_olusturucu.dart` | ETTN üretimi — mimari olarak fatura_no'dan AYRI (doğru) |

**Şubeler:** Gerçek ve olgun bir sistem. `subeler` tablosu (id,
global_id, sube_kodu UNIQUE, sube_adi, ...), tam CRUD ekranı
(`sube_ekrani.dart`), ve **uygulama genelinde zaten çalışan** bir aktif
şube seçici: `lib/servisler/aktif_sube_servisi.dart` — rol bazlı
kilitleme (normal personel kendi şubesine kilitli, admin/müdür
değiştirebilir/"Tüm Şubeler" görebilir), SharedPreferences'ta kalıcı.

**"Kasa" — kritik terminoloji uyarısı:** Kodda `kasa_id` kolonu,
`KasaModel` ya da bir `kasalar` ana tablosu **YOK**. "Kasa" bu
kod tabanında sadece **kasa çekmecesi/vardiya** anlamında kullanılıyor
(`kasa_hareketleri`, `vardiyalar`). Yeni tasarımdaki "numaralandırma
silosu" (SAP'teki number-range object) kavramı için **"Kasa" kelimesi
KULLANILMAMALI** — mevcut anlamla çakışır. Bu raporda bunun yerine
**"Terminal"** terimi kullanılacak.

**Cihaz kimliği — VAR, ama numaralandırmada hiç kullanılmıyor:**
`SupabaseSyncServisi.cihazId()` (`supabase_sync_servisi.dart:453-461`)
kurulumda bir kez üretilip SharedPreferences'ta (`mp_cihaz_id`)
saklanan gerçek bir kimlik — `urunler`, `satislar`, `cari`,
`fatura_detaylari` gibi birçok tabloda `cihaz_id` kolonunda kullanılıyor,
dönem kilidi (yıl sonu devir çoklu-cihaz kilidi) ve audit_log'da
kullanılıyor. **Ama** `faturalandirma_servisi.dart`/`fatura_deposu.dart`
bunu HİÇ okumuyor. Önemli sınır: bu kimlik **istemci tarafından
kendiliğinden üretiliyor, sunucu tarafında hiç doğrulanmıyor**, ve
SharedPreferences'ta olduğu için **uygulama verisi silinirse/cihaz
değişirse kalıcı değil**.

**`sube_id` — şemada var, asla doldurulmuyor:** `faturalar.sube_id`
kolonu (FK `subeler`e), `FaturaModel.subeId` alanı hepsi var ve doğru
bağlı — ama hem otomatik (`faturalandirma_servisi.dart:200-227`) hem
manuel (`fatura_ekle_ekrani.dart:296-317`) fatura oluşturma noktalarının
İKİSİ DE bu alanı hiç set etmiyor. Her faturanın `sube_id`'si bugün
sessizce NULL. **P1 — "alan var ama ölü" bulgusu.**

---

## 2. Mevcut Fatura Numarası Üretim Akışı

**Otomatik yol (satış/iade → fatura):**
1. `faturalandirma_servisi.dart:198` — `sonrakiFaturaNo(tarih)` çağrılır: SharedPreferences'tan ön ek/başlangıç okur, yerel `SELECT fatura_no FROM faturalar WHERE fatura_no LIKE '$onek$yil%' ORDER BY fatura_no DESC LIMIT 1` çalıştırır, +1 hesaplar, **döner — hiçbir kilit/rezervasyon YOK**.
2. `fatura_deposu.dart:79-93` — asıl `INSERT`, **AYRI, kendi transaction'ında**, adım 1'den SONRA ve ayrı.
3. **TOCTOU boşluğu doğrulandı:** adım 1'in SELECT'i ile adım 2'nin INSERT'i arasında başka bir yazma girebilir. Tek koruma: yerel `UNIQUE` kısıtı + **tam olarak 1 kez** retry (`for (deneme=0; deneme<2; deneme++)`).
4. Bulut gönderimi (`BulutManager().upsert`) fire-and-forget, transaction dışında.

**Manuel yol (Fatura Ekle ekranı):** Aynı MAX+1 kaynağından
öneri numara üretir ama kullanıcı **serbestçe düzenleyebiliyor**
(format/uzunluk kontrolü yok). Çakışma olursa DB sessizce farklı bir
numara üretip kaydediyor, ekran bunu SONRADAN fark edip uyarı veriyor —
yani kullanıcının GİRDİĞİ numara sessizce değişebiliyor.

**Sonuç:** Her iki yolda da "sırayı oku" ve "kaydet" **atomik bir
birim DEĞİL**, iki ayrı adım.

---

## 3. Mevcut Seri Sistemi

Sadece 2 ayar var: `fatura_no_onek`, `fatura_baslangic_no` — **ikisi de
SADECE cihaz-yerel SharedPreferences'ta**, hiçbir DB tablosunda değil,
**hiç buluta senkronize edilmiyor**. Blok/aralık/rezervasyon kavramı
kodda **hiç yok** (repo genelinde doğrulandı — sıfır sonuç).

---

## 4. ID ve Numara Kavramlarının Ayrımı

| Kavram | Durum |
|---|---|
| `global_id` (UUID) | Doğru ayrılmış, sync/dedup kimliği |
| `fatura_no` | Tek bir TEXT string içinde seri+yıl+sıra hepsi birleşik — **yapısal ayrım yok**, sadece substring ile geri ayrıştırılıyor (kırılgan) |
| ETTN | Doğru ayrılmış (deterministic UUIDv5) |
| `cihaz_id` | Var ama kendiliğinden/doğrulanmamış, numaralandırmada kullanılmıyor |
| `kasa_id` (silo anlamında) | **YOK** |
| `sube_id` | Şemada var, FK doğru, ama fatura oluşturmada hiç set edilmiyor |

**P0/P1 bulgu (dokümanın kendi kuralına göre):** `fatura_no` tek
başına hem görüntü metni hem benzersizlik anahtarı hem de "bir sonraki
numarayı hesaplama" kaynağı — üç görevi birden üstleniyor. Ayrıca
manuel ekranda serbest metin girilebildiği için, formatı bozan TEK bir
manuel giriş (`int.tryParse` başarısız olur) üretici fonksiyonun "gerçek
maksimumu" unutup `baslangic` değerine geri dönmesine ve **önceden
kullanılmış bir aralığı yeniden üretmesine** yol açabilir.

---

## 5. Şube/Kasa/Cihaz Mimarisi

- **Şube:** olgun, yeniden kullanılabilir (bkz. §1).
- **Cihaz:** gerçek bir ID var ama kalıcı değil (SharedPreferences,
  uygulama verisi silinince/cihaz değişince kaybolur) ve sunucu
  tarafında doğrulanmıyor — numaralandırma için **doğrudan** güvenilir
  bir temel değil, ama başlangıç noktası olabilir.
- **Terminal (yeni kavram):** hiç yok, sıfırdan tasarlanmalı — ve
  admin tarafından KAYITLI (Şube gibi), kendiliğinden üretilmiş
  `cihaz_id`'den DAHA GÜVENİLİR bir kimlik olmalı (aşağıda §18).

---

## 6. Audit Eksikleri

Numara üretimi, çakışma, retry, ya da manuel-numara-sessizce-değişti
olaylarının **HİÇBİRİ** `audit_log`'a düşmüyor — sadece geçici bir UI
toast'ı olarak görünüp kayboluyor.

---

## 7. Backup/Restore ile Etkileşim

`faturalar` tablosu tam yedeğin içinde (güvenli — aynı cihaza restore
edilirse sorun yok, sayaç her zaman canlı MAX-scan). **Ama** ön
ek/başlangıç no ayarları SharedPreferences'ta olduğu için **yedeğin
DIŞINDA** — farklı/yeni bir cihaza restore edilirse ön ek sessizce
varsayılana ("FTR") döner ve eski seriyle **paralel, farkında olunmayan
ikinci bir seri** başlar (DB bunu çakışma saymaz, çünkü ön ek farklı).

---

## 8. Devir/Arşiv ile Etkileşim

**İyi haber:** `faturalar`/`fatura_detaylari` devir/arşiv sisteminin
**tamamen dışında** — kod yorumunda "bilerek dahil edilmedi" yazıyor.
Yani MAX-scan hiçbir zaman arşivlenmiş/silinmiş veri yüzünden yanlış
sonuç vermiyor, **numara tekrar kullanım riski yok.**
Yan bulgu (kapsam dışı ama not edilmeli): `faturalar.satis_id`'de FK
kısıtı yok — devir, ilişkili `satislar` satırını sildiğinde
`faturalar.satis_id` sessizce "hayalet" bir referansa dönüşebiliyor
(ayrı bir düzeltme konusu, bu raporun kapsamı dışında).

---

## 9-13. Offline / Concurrency / Supabase / Sync Riskleri (özet)

- **Offline kuyruk sağlam:** hiçbir satır kaybolmuyor, çökme sonrası
  hayatta kalıyor, birikmiş yüzlerce kayıt birkaç dakikada senkronize
  oluyor.
- **Aynı cihaz içi ek risk doğrulandı:** arka planda çalışan bir
  "pull" (buluttan indirme) ile ön plandaki `faturaOlustur()` aynı
  bağlantı üzerinde iç içe geçebiliyor; büyük bir toplu indirme + o
  anda yerel fatura kaydı çakışırsa, tek seferlik retry bütçesi
  tükenip kullanıcıya "numara çakışması çözülemedi" hatası çıkabilir.
- **Supabase kimlik modeli sınırlaması (kritik mimari kısıt):** Uygulama
  Supabase'e HER ZAMAN tek, paylaşılan bir statik anahtarla bağlanıyor
  — gerçek Supabase Auth/JWT yok. Yani Postgres tarafında "bu isteği
  hangi cihaz/şube gönderdi" diye GÜVENİLİR bir şekilde ayırt etmenin
  **hiçbir yolu yok**. `sb_secret_` (service_role) anahtar kullanılıyorsa
  (önerilen/beklenen durum) RLS zaten tamamen atlanıyor.
- **Senkron çakışma yeniden adlandırması buluta artık gönderiliyor**
  (bugün düzeltildi) — sonsuz döngü riski YOK, doğrulandı (deterministic/idempotent).
  Ama bu yeniden adlandırma, faturanın GİB'e ZATEN gönderilmiş olup
  olmadığını hiç kontrol etmiyor — GİB'e gönderilmiş bir fatura kaybeden
  tarafta olursa, yerel numara değişir ama GİB'deki resmi belge/XML
  eski numarayı taşımaya devam eder — **yerel/resmi numara uyuşmazlığı**,
  hiçbir yerde işaretlenmiyor/gözden geçirme kuyruğuna düşmüyor.

## 14. GİB/e-Belge Riskleri

Yukarıdaki "yerel/resmi numara uyuşmazlığı" bu bölümün ana bulgusu.
Ayrıca: bu senaryo için (fatura_no'su sonradan değişen ama GİB'e zaten
gönderilmiş bir belge) **hiçbir düzeltme/inceleme ekranı yok** — mevcut
"Sync Çakışmaları" ekranı sadece `satislar` ve genel LWW alan
çakışmalarını gösteriyor, `faturalar`'ı hiç kapsamıyor.

## 15. Yıl Değişimi Riskleri

Yıl belirleme **tamamen cihaz saatine güveniyor**, hiçbir doğrulama
yok. Yanlış ayarlı bir cihaz saati → yanlış yıl önekli, hukuken
sorunlu bir fatura numarası üretebilir; DB bunu da çakışma saymaz
(farklı yıl öneki = farklı seri).

## 16. Security/RLS Riskleri (gelecekteki blok tablosu için)

**Dürüst değerlendirme:** Bugünkü kimlik doğrulama modeliyle, "bir
cihaz başka bir şubenin bloğunu çalamaz" garantisi **Postgres seviyesinde
sağlanamaz** — bunun için gerçek cihaz/şube bazlı kimlik doğrulama
(Supabase Auth, JWT) eklenmesi ÖN KOŞULdur. Bugün sadece "onur sistemi"
(uygulama kodu seviyesinde) bir izolasyon mümkün — güvenlik açısından
bugünkü senkron katmanının geri kalanıyla aynı güven seviyesinde.

## 17. Performans Riskleri

Bu tek bir market/mağaza — muhtemelen günde onlarca/yüz civarı fatura
(tüm satışlar değil, sadece cari/VKN'li faturalandırılan satışlar).
Bu ölçekte, **fatura başına bir Supabase RPC çağrısı bile performans
sorunu yaratmaz** — yine de küçük bloklar (5-10 numaralık) önerilir:
hem ağ çağrısı sıklığını daha da azaltır hem de bir cihaz kalıcı olarak
çevrimdışı kalırsa oluşacak "boşluk" küçük ve GİB'e açıklanabilir kalır.

---

# 18. Önerilen Hedef Mimari

```
                        SUPABASE / POSTGRESQL
                                 │
                    fatura_seri_bloklari (merkezi sayaç)
                    fatura_blok_tahsis_et() [RPC, SECURITY DEFINER,
                                              satır kilidi/atomik UPDATE]
                                 │
              ┌──────────────────┼──────────────────┐
              │                  │                   │
         TERMINAL 1          TERMINAL 2          TERMINAL 3
     (admin kayıtlı kimlik, Şube gibi bir tablo — cihaz_id DEĞİL)
              │                  │                   │
       Yerel blok önbelleği  Yerel blok önbelleği  Yerel blok önbelleği
       (ör. 10 numara)        (ör. 10 numara)       (ör. 10 numara)
              │                  │                   │
              └──────────────────┼──────────────────┘
                                 │
                             SQLITE (yerel, offline)
                                 │
                     %80 uyarı / %95 kritik / %100 → yeni blok iste
                                 │
                          SYNC / RECONCILE
```

**Neden "Terminal" ayrı bir tablo, `cihaz_id` değil:** `cihaz_id`
kendiliğinden üretilir, sunucuda doğrulanmaz, uygulama verisi
silinince/cihaz değişince kaybolur. Numaralandırma gibi hukuken kritik
bir kimlik için bunun yerine **admin tarafından bilinçli olarak
kaydedilen** bir varlık gerekir — tıpkı Şube gibi. Yeni cihaz kurulduğunda
"Bu cihazı bir Terminal olarak kaydet" tek seferlik adımı, kimlik
kararını insana bırakır (otomatik/tahmin edilebilir değil).

**Neden bu, bugünkü "MAX+1" hatasını kökten çözüyor:** Sayaç artık
Postgres'te, satır kilidi/atomik `UPDATE ... RETURNING` ile korunuyor
— birden fazla terminal AYNI ANDA blok istese bile Postgres bunları
sıraya koyar, iki terminal asla aynı numarayı alamaz. Bu, dokümanın
29. maddesindeki "ASLA SELECT MAX ile concurrency güvenliği kurma"
kuralının doğrudan çözümü.

**Bugünkü RLS/kimlik sınırlaması ne anlama geliyor (dürüstçe):** Bu
mimari **çakışma/mükerrer numara hatasını** tamamen çözer (bu, asıl
"büyük ceza" riski). Ama "kötü niyetli/bozuk bir cihaz başka bir şubenin
bloğunu talep edemez" garantisini VERMEZ — bunun için ayrı, daha büyük
bir proje (gerçek Supabase Auth) gerekir. Tek işletme/tek admin
senaryosunda bu ikincil risk kabul edilebilir düzeydedir.

---

## 19. Database Şeması (taslak)

```sql
-- Yeni: numaralandırma terminali (Şube'ye benzer, admin kaydı)
CREATE TABLE terminaller (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  global_id TEXT UNIQUE,
  terminal_kodu TEXT NOT NULL UNIQUE,   -- ör. "KASA-1", "OFIS-PC"
  terminal_adi TEXT,
  sube_id BIGINT REFERENCES subeler(id),
  aktif BOOLEAN DEFAULT true,
  kayit_cihaz_id TEXT,                  -- bilgi amaçlı, güven kaynağı DEĞİL
  created_at TIMESTAMPTZ DEFAULT now(),
  last_updated TIMESTAMPTZ DEFAULT now()
);

-- Yeni: merkezi seri sayaç + blok tahsis geçmişi
CREATE TABLE fatura_seri_bloklari (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  global_id TEXT UNIQUE,
  belge_tipi TEXT NOT NULL DEFAULT 'FATURA',  -- ileride e-İrsaliye vb. için
  seri TEXT NOT NULL,                   -- ör. "HLF"
  yil INT NOT NULL,
  terminal_id BIGINT REFERENCES terminaller(id),
  blok_baslangic BIGINT NOT NULL,
  blok_bitis BIGINT NOT NULL,
  son_kullanilan BIGINT,                -- terminal tarafından raporlanır (bilgi amaçlı)
  durum TEXT NOT NULL DEFAULT 'aktif',  -- aktif | tukendi | terkedilmis | iptal
  tahsis_zamani TIMESTAMPTZ DEFAULT now(),
  aktivasyon_zamani TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now(),
  last_updated TIMESTAMPTZ DEFAULT now()
);

-- Merkezi sayaç (blok tahsisinin atomik kaynağı)
CREATE TABLE fatura_seri_sayaclari (
  belge_tipi TEXT NOT NULL DEFAULT 'FATURA',
  seri TEXT NOT NULL,
  yil INT NOT NULL,
  son_tahsis_edilen BIGINT NOT NULL DEFAULT 0,
  PRIMARY KEY (belge_tipi, seri, yil)
);

CREATE UNIQUE INDEX idx_fatura_blok_no_cakisma
  ON fatura_seri_bloklari (belge_tipi, seri, yil, blok_baslangic);
```

**`faturalar` tablosunda (mevcut) önerilen ek/yapısal kolonlar
(geriye dönük UYUMLU — fatura_no metni DEĞİŞMEZ):**
```sql
ALTER TABLE faturalar ADD COLUMN IF NOT EXISTS terminal_id BIGINT;
ALTER TABLE faturalar ADD COLUMN IF NOT EXISTS blok_id BIGINT;
-- sube_id zaten var — sadece artık gerçekten dolduruluyor.
-- fatura_no formatı DEĞİŞMEZ, sadece kaynağı artık merkezi blok.
CREATE UNIQUE INDEX IF NOT EXISTS idx_faturalar_fatura_no_bulut
  ON faturalar (fatura_no);  -- BULUTTA da artık UNIQUE (bugün yoktu)
```

---

## 20. RPC / Transaction Tasarımı

```sql
CREATE OR REPLACE FUNCTION fatura_blok_tahsis_et(
  p_terminal_id BIGINT,
  p_seri TEXT,
  p_blok_boyutu INT DEFAULT 10
) RETURNS TABLE(blok_baslangic BIGINT, blok_bitis BIGINT)
SECURITY DEFINER
LANGUAGE plpgsql AS $$
DECLARE
  v_yil INT := EXTRACT(YEAR FROM now())::INT;  -- 🔴 SUNUCU yılı kullanılır,
                                                 -- cihaz saatine GÜVENİLMEZ
                                                 -- (§15'teki bulgunun çözümü)
  v_baslangic BIGINT;
BEGIN
  INSERT INTO fatura_seri_sayaclari (belge_tipi, seri, yil, son_tahsis_edilen)
    VALUES ('FATURA', p_seri, v_yil, p_blok_boyutu)
    ON CONFLICT (belge_tipi, seri, yil)
    DO UPDATE SET son_tahsis_edilen =
      fatura_seri_sayaclari.son_tahsis_edilen + p_blok_boyutu
    RETURNING son_tahsis_edilen - p_blok_boyutu + 1 INTO v_baslangic;
    -- ↑ Atomik: PostgreSQL'in kendi satır kilidi (UPSERT), ayrı bir
    -- SELECT+UPDATE adımı YOK — iki terminal aynı anda çağırsa bile
    -- Postgres bunları sıraya koyar, ASLA aynı aralığı vermez.

  INSERT INTO fatura_seri_bloklari
    (belge_tipi, seri, yil, terminal_id, blok_baslangic, blok_bitis,
     durum, aktivasyon_zamani)
    VALUES ('FATURA', p_seri, v_yil, p_terminal_id,
            v_baslangic, v_baslangic + p_blok_boyutu - 1,
            'aktif', now());

  RETURN QUERY SELECT v_baslangic, v_baslangic + p_blok_boyutu - 1;
END;
$$;
```

---

## 21. Offline Block Allocation Tasarımı

1. Terminal ilk kez kaydolduğunda (ya da mevcut bloğu bittiğinde,
   çevrimiçiyken) `fatura_blok_tahsis_et()` çağrılır, dönen aralık
   yerel SQLite'a (`fatura_seri_bloklari` yerel kopyası + "sıradaki
   numara" imleci) yazılır.
2. Fatura oluşturulurken: yerel imleçten SIRADAKI numara ATOMİK olarak
   (aynı SQLite transaction içinde INSERT ile birlikte) tüketilir —
   ağ gerektirmez, offline çalışır.
3. Kalan numara %20'nin altına düşünce (arka planda, engellemeden):
   internet varsa yeni blok proaktif olarak istenir.
4. Blok tamamen biterse VE internet yoksa: fatura oluşturma
   **engellenir**, açık hata gösterilir ("Numara bloğu tükendi,
   internete bağlanıp yeni blok alın") — **kesinlikle** eski
   yerel-MAX+1'e sessizce geri dönülmez (dokümanın 29. madde kuralı).
5. Terkedilmiş blok senaryosu (§11 — cihaz arızası): bir bloğun
   kullanılmayan kalanı, terminal "yeniden kaydedilirse"/manuel olarak
   `terkedilmis` işaretlenir — asla başka bir terminale otomatik
   verilmez (boşluk kalır, bu GİB açısından kabul edilebilir/açıklanabilir).

---

## 22. Audit Tasarımı

`audit_log`'a (mevcut, genel tabloya) ya da yeni `fatura_seri_audit`'e:
`BLOCK_ALLOCATED`, `BLOCK_ACTIVATED`, `BLOCK_EXHAUSTED`,
`BLOCK_ABANDONED`, `TERMINAL_REGISTERED`, `TERMINAL_REVOKED`,
`SERIES_CREATED/CHANGED/DISABLED`. **Tek tek numara tüketimi
loglanmaz** (hacim/performans — zaten `faturalar` satırının kendisi
kanıt), sadece blok seviyesi olaylar.

## 23. Reconciliation Tasarımı

"Seri Mutabakatı" ekranı (Ayarlar altında, admin-only): her (seri,yıl)
için "toplam tahsis edilen" vs "faturalar tablosunda gerçekten
kullanılan MAX" vs "her terminalin kendi bildirdiği son numara"
karşılaştırması — tutarsızlık varsa görsel uyarı.

## 24. Migration Planı

| Faz | İçerik | Risk |
|---|---|---|
| 1 | Yeni tablolar+RPC eklenir (Supabase) — mevcut sisteme DOKUNULMAZ | Sıfır |
| 2 | Mevcut `faturalar`'daki her (seri,yıl) için gerçek MAX taranıp `fatura_seri_sayaclari` o değerden başlatılır — **hiçbir mevcut numara değişmez** | Düşük |
| 3 | Şu anki (1) cihaz "Terminal-1" olarak admin ekranından kaydedilir, Merkez şubeye bağlanır | Düşük |
| 4 | Yeni fatura oluşturma kodu, `sonrakiFaturaNo()`/`siradakiFaturaNoUret()` yerine yerel-blok-veya-RPC yolunu kullanır (feature flag ile, geri alınabilir) | Orta — test gerektirir |
| 5 | Eski üretici fonksiyonlar sadece "acil durum" yorumlu, kod içinde bırakılır (silinmez) | Sıfır |
| 6 | Audit + Mutabakat ekranları eklenir | Düşük |
| 7 | (Kullanıcı isterse, AYRI proje) Gerçek Supabase Auth eklenerek RLS'in blok tablosunu da koruması sağlanır | Büyük, ayrı karar |

**Mevcut fatura numaraları KESİNLİKLE değiştirilmez** — migration sadece
sayacı "kaldığı yerden devam" ettirir.

## 25. Test Planı

- **Unit:** blok tüketim matematiği, %80/90/95/100 eşik hesabı, seri format ayrıştırma.
- **Integration:** RPC'ye gerçek Supabase'e karşı 50-100 paralel çağrı → hepsi benzersiz, çakışmasız aralık almalı.
- **Concurrency:** 10 simüle terminal × 100 paralel numara talebi → 1000 benzersiz numara.
- **Offline:** interneti kes → bloktan offline üret → tekrar bağlan → senkronize et, tutarlılığı doğrula.
- **Failure injection:** RPC çağrısı ortasında ağ kopması, blok alındıktan hemen sonra uygulama kill, SQLite transaction rollback.
- **Recovery:** uygulama yeniden açıldığında doğru blok/imleç durumuna dönmeli.

## 26. P0 / P1 / P2 / P3 Önceliklendirme

| # | Bulgu | Öncelik |
|---|---|---|
| Çoklu cihaz/terminal numara çakışma riski (kök neden) | **P0** |
| `sube_id` faturalarda hiç doldurulmuyor | P1 |
| Manuel ekranda serbest metin numara girişi format koruması yok | P1 |
| GİB'e gönderilmiş fatura ile senkron-sonrası yerel numara uyuşmazlığı hiç işaretlenmiyor | P1 |
| Ön ek/başlangıç ayarı yedekte/senkronda yok (farklı cihaza restore riski) | P1 |
| Cihaz saatine güvenerek yıl belirleme | P1 (RPC'de sunucu-yılıyla çözülür) |
| Numara üretimi hiç audit edilmiyor | P2 |
| Gerçek per-device kimlik doğrulama yok (RLS blok tablosunu koruyamaz) | P2 (ayrı, büyük proje) |
| `faturalar.satis_id`'de FK yok (devir sonrası hayalet referans) | P3 (bu raporun kapsamı dışı, ayrı not) |

---

# SONUÇ

**ÖNCE ŞU MİMARİ KARARLAR GEREKLİ** — aşağıdaki 3 soruya karar
vermeden implementasyona geçmiyorum:

1. **Şu an bu yatırım gerekli mi?** Tek cihazla çalışıyorsunuz, risk şu
   an pratikte sıfır. Bu mimari (yeni tablolar+RPC+Terminal
   kaydı+migration+testler) gerçek bir mühendislik yatırımı. İkinci
   cihazı/şubeyi eklemeden önce mi yapalım, yoksa o zaman mı?
2. **"Terminal" kaydı ne kadar sade olsun?** Yukarıdaki tasarım admin'in
   her yeni cihazı bir kere elle "Terminal" olarak kaydetmesini
   istiyor (Şube ekler gibi). Bunu kabul ediyor musunuz, yoksa daha
   basit (ama daha az güvenilir) bir otomatik-cihaz-kimliği yaklaşımı
   mı tercih edersiniz?
3. **Gerçek kimlik doğrulama (Supabase Auth) ayrı bir proje olarak ele alınsın mı?**
   §16/26'da açıklandığı gibi, bu mimari çakışma hatasını TAMAMEN
   çözer ama "bir terminal başka bir şubenin bloğunu talep edemez"
   güvenliğini vermez — bunun için ayrı, büyük bir iş (gerçek
   Auth) gerekir. Şimdilik bunu kabul edilebilir bulup ertelemek mi,
   yoksa şimdi mi ele alalım?
