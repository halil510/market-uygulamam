# Supabase RLS ile Bayi Veri İzolasyonu — Rehber

**Durum:** Bu dosya kod tabanının parçası değil, sadece Supabase panelinde
(SQL Editor) kendi başına uygulaman için hazırlanmış bir rehber. **Bu ortamda
gerçek bir Supabase projesine karşı test EDİLEMEDİ** — önce test/yedek bir
bayi hesabıyla dene, üretim verisiyle doğrudan denemeden önce.

## Sorunun tam olarak ne olduğu

Uygulama Supabase'e `supabase_sync_servisi.dart` üzerinden ham HTTP (REST)
istekleriyle bağlanıyor — `Ayarlar → Bulut Sync` ekranına girdiğin URL + key
her istekte hem `apikey` hem `Authorization: Bearer` başlığı olarak
gönderiliyor. **Bütün cihazlar (personel VE bayi) aynı key'i kullanıyor** —
Postgres/PostgREST tarafında "bu isteği kim yapıyor" bilgisi yok, hepsi aynı
rol (muhtemelen `anon`) olarak görünüyor. Bu yüzden:

- Bir bayi hesabı ilk kurulumda "Buluttan Al" çalıştırdığında, key aynı
  olduğu için RLS (satır güvenliği) olsa bile bugünkü haliyle hiçbir şey
  filtrelenmiyor — kasa, banka, diğer müşteriler, diğer bayiler, ürün alış
  fiyatları dahil HER ŞEY iniyor. Uygulama bunları ekranda göstermiyor ama
  cihazın yerel veritabanında duruyor.

## Çözüm: bayi'ye özel, kısıtlı bir "key" (JWT) + RLS

Supabase'de `apikey`/`Authorization` alanına, projenin JWT secret'ı ile
imzalanmış **herhangi bir** JWT verilebilir — sadece "anon" ya da
"service_role" olmak zorunda değil. Yani:

1. Yeni, kısıtlı bir Postgres rolü oluşturuyoruz (`bayi_rol`).
2. Bu role SADECE bayinin ihtiyaç duyduğu tablolara, SADECE gerekli
   sütunlara, SADECE kendi kayıtlarına erişim veriyoruz.
3. Her bayi için, içinde o bayinin `cari_id`'si gömülü, `bayi_rol`
   claim'ini taşıyan AYRI bir JWT üretiyoruz.
4. O JWT'yi, o bayinin cihazındaki `Ayarlar → Bulut Sync → Key` alanına
   yapıştırıyoruz (personelin key'i DEĞİŞMİYOR, aynı kalıyor).

Personel cihazlarındaki mevcut key'e hiç dokunulmuyor — bu değişiklik
sadece YENİ, isteğe bağlı bir ikinci erişim yolu ekliyor.

## Adım 1 — Supabase SQL Editor'de rolü ve izinleri oluştur

```sql
-- 1) Kısıtlı rol
create role bayi_rol nologin;
grant usage on schema public to bayi_rol;

-- 2) Bayinin ihtiyaç duyduğu, GÜVENLİ tablolar — tam okuma izni
--    (fiyat hesaplama + katalog için gerekli, hassas veri içermiyor)
grant select on
  subeler, kategoriler, birimler, markalar,
  fiyat_gruplari, urun_fiyat_gruplari, fiyat_kademeleri
to bayi_rol;

-- 3) urunler — TÜM sütunlar değil, sadece bayinin görmesi gereken
--    sütunlar. Kendi tablonuzdaki gerçek sütun adlarını
--    "supabase tablolar önemli buluttaki tablolar.txt" dosyasından
--    doğrulayıp gerekirse bu listeyi güncelleyin — ALIŞ FİYATI ve
--    TEDARİKÇİ İSKONTOSU sütunlarını KESİNLİKLE bu listeye eklemeyin.
grant select (
  id, global_id, urun_adi, barkod, barkodlar, satis_fiyati, kdv_oran,
  birim_adi, ana_grup, alt_grup, marka, resim_yolu, stok, aktif,
  is_deleted, last_updated
) on urunler to bayi_rol;

-- 4) cari, bekleyen_siparisler(+kalem), faturalar(+detay) — SADECE
--    KENDİ KAYITLARI. current_setting ile JWT'deki özel claim okunuyor.
alter table cari enable row level security;
create policy bayi_kendi_carisi on cari
  for select to bayi_rol
  using (id = (current_setting('request.jwt.claims', true)::json->>'bayi_cari_id')::bigint);

alter table bekleyen_siparisler enable row level security;
create policy bayi_kendi_siparisi on bekleyen_siparisler
  for select to bayi_rol
  using (cari_id = (current_setting('request.jwt.claims', true)::json->>'bayi_cari_id')::bigint);

alter table bekleyen_siparis_kalem enable row level security;
create policy bayi_kendi_siparis_kalemi on bekleyen_siparis_kalem
  for select to bayi_rol
  using (
    siparis_id in (
      select id from bekleyen_siparisler
      where cari_id = (current_setting('request.jwt.claims', true)::json->>'bayi_cari_id')::bigint
    )
  );

alter table faturalar enable row level security;
create policy bayi_kendi_faturasi on faturalar
  for select to bayi_rol
  using (cari_id = (current_setting('request.jwt.claims', true)::json->>'bayi_cari_id')::bigint);

alter table fatura_detaylari enable row level security;
create policy bayi_kendi_fatura_detayi on fatura_detaylari
  for select to bayi_rol
  using (
    fatura_id in (
      select id from faturalar
      where cari_id = (current_setting('request.jwt.claims', true)::json->>'bayi_cari_id')::bigint
    )
  );

-- 🔴 ÖNEMLİ: RLS'i açtığınız (enable row level security) tablolarda,
-- personel/admin'in kullandığı MEVCUT rolün (muhtemelen 'anon' veya
-- 'service_role') bu tablolara erişimi KESİLMEMELİ. 'service_role' RLS'i
-- zaten tamamen atlar (dokunmanıza gerek yok). Eğer personel de 'anon'
-- rolüyle bağlanıyorsa, 'anon' için de "her şeyi göster" policy'si
-- eklemeniz gerekir, yoksa personel ekranları da bu 4 tabloda BOŞ veri
-- görmeye başlar:
create policy personel_hepsini_gorur_cari on cari
  for all to anon using (true) with check (true);
create policy personel_hepsini_gorur_siparis on bekleyen_siparisler
  for all to anon using (true) with check (true);
create policy personel_hepsini_gorur_siparis_kalem on bekleyen_siparis_kalem
  for all to anon using (true) with check (true);
create policy personel_hepsini_gorur_fatura on faturalar
  for all to anon using (true) with check (true);
create policy personel_hepsini_gorur_fatura_detay on fatura_detaylari
  for all to anon using (true) with check (true);

-- 5) Geri kalan HER ŞEY (kasa_hareketleri, banka_*, kredi_kartlari,
--    borclar, giderler, personel, vardiyalar, audit_log, onay_talepleri,
--    satislar, iade, irsaliyeler, stok_hareket, cari_hareket, lot_seri,
--    sube_urun, kullanicilar, promosyon*, tedarikci_siparis*, masa*,
--    puan_hareket, musteri_puan, roller_yetki, rol_yetkileri, ayarlar...)
--    hiçbir şey grant EDİLMEDİĞİ için bayi_rol zaten göremiyor — ekstra
--    bir REVOKE gerekmiyor, Postgres'te varsayılan "izin yok".
```

## Adım 2 — Her bayi için özel bir JWT üret

**Secret'ınızı hiçbir online araca (jwt.io dahil) YAPIŞTIRMAYIN** — bunun
yerine kendi bilgisayarınızda, internete gitmeyen küçük bir script kullanın.
JWT secret'ı Supabase panelinde **Project Settings → API → JWT Settings →
JWT Secret** altında.

Python ile (`pip install pyjwt` yeterli):

```python
import jwt, datetime

JWT_SECRET = "PROJENIZIN_JWT_SECRET'I"   # Supabase panelinden, kimseyle paylaşmayın
BAYI_CARI_ID = 42                         # bu bayinin cari.id'si

payload = {
    "role": "bayi_rol",
    "bayi_cari_id": str(BAYI_CARI_ID),
    "iss": "supabase",
    # İsteğe bağlı: süresiz olsun istemiyorsanız "exp" ekleyin.
}
token = jwt.encode(payload, JWT_SECRET, algorithm="HS256")
print(token)
```

Çıkan token'ı, o bayinin cihazında **Ayarlar → Bulut Sync → Key** alanına
(URL aynı kalacak) yapıştırın.

## Adım 3 — Test

1. Bayinin cihazında (ya da bir test cihazında bu token'la) **Buluttan Al**'ı
   çalıştırın.
2. Yerel veritabanını açıp (ör. bir DB tarayıcıyla) `kasa_hareketleri`,
   `borclar`, `satislar` gibi tabloların **boş** geldiğini, `cari`
   tablosunda **sadece o bayinin kendi satırının** indiğini doğrulayın.
3. Personel cihazında normal senkronun hâlâ eskisi gibi TAM çalıştığını
   doğrulayın (Adım 1'deki `anon` policy'leri bunun için var).

## Bilinmeyen/doğrulanamayan nokta

Supabase'in gateway katmanı bazı kurulumlarda `apikey` başlığının projenin
bilinen `anon`/`service_role` anahtarlarından biriyle birebir eşleşmesini
isteyebilir (özel rol claim'i taşıyan bir JWT'yi bu seviyede reddedebilir).
Bu, projenizin Supabase sürümüne/planına göre değişebilir ve bu ortamdan
doğrulanamadı. Adım 3'teki testte 401/403 alırsanız, bu senaryo demektir —
o durumda alternatif olarak Supabase Destek'e "custom role claim JWT with
apikey header" konusunu sorabilir, ya da bir Edge Function/proxy üzerinden
key'i `service_role` ile sunucu tarafında değiştirip filtrelemeniz gerekir
(bu ikincisi ayrı, daha büyük bir iş).
