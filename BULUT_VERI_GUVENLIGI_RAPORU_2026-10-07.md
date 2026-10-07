# Bulut Veri Güvenliği Raporu — Çok Cihazlı Senkron Denetimi

**Tarih:** 2026-10-07 · **Kapsam:** yerel SQLite (DB v81) ↔ Supabase (`supabase_tam_sema.sql`, `supabase_lww_koruma.sql`), kuyruk yazımı, gönderim (push), çekim (pull), çakışma çözümü, tüm ekranların tetiklediği servisler.
**Yöntem:** Kod satır satır okundu; şüpheli bulgular (a) geçici birim testiyle, (b) programatik liste/sıra karşılaştırmasıyla, (c) gerçek bulutta **salt-okuma** (yalnız GET) sorgularla doğrulandı.

> **Güncelleme 2026-10-08:** Tüm bulgular düzeltildi (Bulgu 6 bilinçli olarak hariç) — bkz. rapor sonundaki **Düzeltme durumu**.

---

## Yönetici Özeti

| # | Önem | Bulgu | Etki |
|---|---|---|---|
| 1 | **P0** | Çevrimdışı cihazın kayıtları diğer cihazlara **hiç inmeyebilir** (çekim filigranı istemci damgasına dayanıyor) | Satış/cari/stok hareketleri cihazlar arasında kalıcı eksik |
| 2 | **P0** | Her satış/stok hareketi ürünün **tüm satırını** yeni damgayla gönderiyor | Başka kasada yapılan fiyat/ad değişikliği sessizce geri alınır |
| 3 | **P0** | Stok sayımı ve toplu/döviz alış fiyatı güncellemesi **kimliksiz** kuyruğa giriyor (test ile kanıtlandı) | Bulutta gerçek ürün güncellenmez; kimliksiz hayalet ürün satırı eklenir |
| 4 | **P1** | Toplu gönderimde eksik sütunlar `null` ile dolduruluyor; tekli gönderimde `null` alanlar atılıyor | Kısmi satır diğer alanları siler; boşaltılan alan hiçbir yönde senkronlanmaz |
| 5 | **P1** | Kuyruk açlığı: ilk 500 satır backoff'tan önce seçiliyor; ebeveyni gelmeyen satır sonsuz bekletiliyor | Yeni kayıtların gönderimi tamamen durabilir |
| 6 | **P1** | Bulutta FK kısıtı yok (yalnız dönem tabloları) | Yanlış bağlantı/yetim satır sunucuda engellenmez |
| 7 | **P1** | Tam senkron sırası: `giderler` ebeveynlerinden (`banka_hesaplar`, `kredi_kartlari`) önce | Gider–hesap bağı boş/yanlış iner |
| 8 | **P1** | Sunucu LWW tetikleyicisi tam şemada yok, sonradan eklenen tablolara uygulanmıyor; LWW tüm satır bazlı | v81 tabloları korumasız; alan bazlı birleştirme yok |
| 9 | **P1** | FK bulut önbelleği ıskada ebeveyn tablonun **tamamını** indiriyor | Geçmiş büyüdükçe her satış turu yavaşlar (darboğaz) |
| 10 | P2 | Bulut yapılandırılmadan önce `BulutManager.upsert` yazımları kuyruğa alınmıyor | Ebeveyn hiç gitmez → çocuklar sonsuz bekler |
| 11 | P2 | Anlık (realtime) kısmi çekimde mutabakat yok | Stok/bakiye ekranları bir sonraki tam çekime kadar bayat |
| 12 | P2 | Çakışma çözümü: `gelenIleCoz` eski şemalı/bozuk kayıtta çöker ya da yazmadan "çözüldü" der | Sessiz çözümsüzlük |
| 13 | P2 | Çekimde `PRAGMA foreign_keys = OFF` + `REPLACE` | Yetim kabul; başka UNIQUE çakışmasında yerel satır yeni id ile yeniden yazılır |
| 14 | P3 | Gizli/latent riskler (aşağıda) | — |

**Sağlam bulunan alanlar** rapor sonunda ayrıca listelendi — mimarinin temeli (atomik kuyruk, UUID kimlik, FK dönüşümü + bekletme, türetilmiş değer mutabakatı, kasa bazlı numaralandırma) doğru.

> **Canlı bulut kontrolü (salt-okuma, 2026-10-07):** 19 ana tabloda `global_id IS NULL` satır sayısı **0** (urunler 4768, stok_hareket 4098, cari 117, satislar 33 …). Yani Bulgu 3 henüz bulutta iz bırakmamış — ilgili akışlar (stok sayımı onayı, toplu döviz güncelleme) bulut bağlıyken kullanılmamış. Kullanıldığı an tetiklenir.

---

## 1. [P0] Çevrimdışı cihazın kayıtları diğer cihazlara inmeyebilir

**Nerede**
- `lib/servisler/supabase_sync_servisi.dart` → `_sonSenkron()` (satır 127), `_senkronKaydet()` (176), `_enSonZaman()` (205): çekim filigranı = **çekilen bulut satırlarının en büyük `last_updated`'i**.
- Aynı dosya, `_buluttanAlCalistir()` satır 1245: `_genisPencereYapilanlar.add(tablo)` — 48 saatlik geniş pencere **uygulama süreci boyunca tablo başına yalnız bir kez**.
- Çekim sorgusu: `?last_updated=gt.<filigran>` (satır ~1250).
- `supabase_tam_sema.sql`: `last_updated`'i sunucu saatine çeken INSERT/UPDATE tetikleyicisi **yok** — damga istemciden gelir (`KolonHaritalama.cevir`, `kolon_haritalama.dart:342`).
- Otomatik akışta tam çekim (`sadeceDegisenler: false`) hiçbir yerden çağrılmıyor.

**Senaryo**
1. Kasa B gün boyu açık; diğer kasaların trafiğiyle filigranı ≈ "şimdi".
2. Kasa A 20 dk internetsiz satış yapar; satırlar kayıt anının damgasını taşır.
3. A bağlanınca satırlar buluta gider (damga 20 dk geride).
4. B'nin artımlı çekimi `last_updated > filigran` sorar → A'nın satırları **asla inmez**. B'nin `stokMutabakatYap`'ı eksik hareketle hesaplar; raporlar, cari ekstreler eksik.

**Öneri:** Bulutta her senkron tablosuna `sunucu_zamani TIMESTAMPTZ NOT NULL DEFAULT now()` + `BEFORE INSERT OR UPDATE` tetikleyicisi (`NEW.sunucu_zamani := now()`). Çekim filigranı bu sütuna geçsin; LWW `last_updated` ile kalsın. Geçiş süresince periyodik (ör. günde bir) tam çekim.

---

## 2. [P0] Stok hareketi ürünün tüm satırını gönderiyor → fiyat/ad değişikliği geri alınıyor

**Nerede**
- `lib/depolar/stok_deposu.dart` → `stokDusTxn()` (171): satır 197 `{'stok': sonraki, 'last_updated': now}`; satır 221-227 ürünün **tam satırını** kuyruğa yazar.
- Aynı desen `stokGir` yolunda: satır 413 / 439.
- `lib/depolar/satis_deposu.dart:848-853` (fiş düzenleme stok farkı).
- LWW tüm satıra uygulanır: `SyncLwwKoruma` + `supabase_lww_koruma.sql` (`NEW.last_updated < OLD.last_updated`).

**Senaryo**
1. 10:00 — Kasa B ürün fiyatını 20 → 25 yapar, buluta gönderir.
2. Kasa A çevrimdışı (25'i görmedi); 10:05'te o üründen satış yapar.
3. A bağlanınca ürünün **fiyatı 20 olan** tam satırı 10:05 damgasıyla gider; 10:05 > 10:00 → istemci ve sunucu LWW kabul eder.
4. Fiyat tüm kasalarda **sessizce 20'ye döner**. (Cari için aynı sorun YOK — `cari_deposu.dart:462` kuyruğa satır yazar ama hareket `cari.last_updated`'i ilerletmez; bkz. "Sağlam".)

**Öneri:** Stok değişiminde `urunler` satırını kuyruğa yazmayın — stok, `stok_hareket`'ten türetilen değerdir (cari bakiye gibi). Çekimde de `urunler.stok` korunmalı (`veritabani_supabase.dart:641`'deki `cari.bakiye` istisnasının aynısı) ve mutabakat sonrası türetilmiş stok ayrı, alan bazlı (PATCH) gönderilmeli.

---

## 3. [P0] Stok sayımı ve toplu/döviz alış fiyatı kimliksiz kuyruğa giriyor

**Nerede**
- `lib/depolar/stok_deposu.dart` → `stokDuzelt()` (465), satır 486-490: `veri: {'stok', 'last_updated', 'id'}` — `global_id` yok. Çağıranlar: `geciciSayimUygula` (Stok Sayım onayı, satır 622), `ai_eylem_motoru.dart:472` (asistan).
- `lib/depolar/urun_deposu.dart` → `alisFiyatiGuncelle()` (308), satır 333: `{alis_fiyat, alis_fiyat_kdv_dahil, last_updated, maliyet_guncelleme_tarih, id}` — `global_id` yok. Çağıran: Toplu Döviz Güncelleme.
- `SyncKuyrukYazici.ekleTxn` (`sync_kuyruk_yazici.dart`) eksik kimliği tamamlamaz (yalnız `BulutManager.upsert` tamamlar, `bulut_manager.dart:166-219`).
- Gönderimde `id` atılır (`kolon_haritalama.dart:13`) → payload'da eşleşme anahtarı kalmaz.

**Kanıt (geçici test, gerçek ürün `global_id='GERCEK-GID-123'`):**
```
stokDuzelt         | kuyruk.kayit_global_id=null | buluta giden={stok: 9.0, last_updated: …Z}
alisFiyatiGuncelle | kuyruk.kayit_global_id=null | buluta giden={alis_fiyat: 12.0, alis_fiyat_kdv_dahil: 14.16, …}
```
**Sonuç:** `on_conflict=global_id` eşleşmez; bulutta `global_id` NULL'a izin verildiği (UNIQUE birden çok NULL kabul eder, `urun_adi` zorunlu değil) için **adsız hayalet ürün satırı EKLENİR**, gerçek ürünün stoğu/maliyeti bulutta değişmez. Ek olarak `_kuyruktaBekliyorMu` (`veritabani_supabase.dart:323`) kimliksiz satırı göremediği için çekim, gönderilmemiş sayım sonucunu yerelde ezebilir.

**Öneri:** `ekleTxn` içinde `global_id` yoksa ve `id` varsa aynı txn'den okuyup ekleyin; kısmi haritalar yerine güncel tam satırı (Bulgu 2 kuralıyla) gönderin. Bulutta `global_id` için `NOT NULL` kısıtı (veri temizse) ikinci savunma hattı olur.

---

## 4. [P1] Null doldurma ve null atma — alan kaybı / boşaltmanın senkronlanmaması

**Nerede**
- `lib/servisler/bulut/supabase_saglayici.dart` → `topluUpsert()` satır 470-476: grup içindeki tüm anahtarların birleşimi alınır, eksik anahtarlara `putIfAbsent(anahtar, () => null)`.
- `lib/servisler/kolon_haritalama.dart:338` → `cevir()`: değeri `null` olan alan atılır.
- Çekim: `veritabani_supabase.dart:549, 637` → `temiz.removeWhere((_, v) => v == null)`.

**Etkiler**
- (a) Kısmi satır (Bulgu 3) aynı tablodaki tam satırlarla aynı gruba düşerse, gönderilmeyen tüm sütunları **NULL'a çevrilir**.
- (b) Yerelde bilerek boşaltılan alan (ör. giderde Banka → Nakit, `banka_hesap_id = null`; satıştan cari kaldırma; ürün barkodunu silme) tek başına gönderilirse sütun hiç gitmez → **bulut eski değeri tutar**. Aynı alan çekimde de atıldığı için ters yönde de boşalmaz. Boşaltma yalnızca grup birleşimi sayesinde "tesadüfen" gider.

**Öneri:** `cevir`'de null'u atmak yerine korumak (yalnız `deleted_at` gibi bilinçli istisnalar hariç) ve kısmi satırları yasaklamak; çekimde null'u uygulamak (master tablolarda LWW ile).

---

## 5. [P1] Kuyruk açlığı ve sonsuz bekletme

**Nerede:** `lib/servisler/bulut/bulut_manager.dart` → `_isle()`
- satır 607-613: `durum='beklemede' ORDER BY id LIMIT 500` **önce**, backoff süzgeci (`syncSatiriSimdiDenenebilirMi`, satır 623) **sonra** uygulanır.
- satır 493-496: ebeveyni bulutta olmayan satır "geçici" hata ile işaretlenir → asla `kalici_hata` olmaz, en fazla 30 dk aralıkla **sonsuza kadar** denenir.

**Senaryo:** Ebeveyn satır kalıcı hataya düşer (ör. NOT NULL/PGRST204) ya da hiç kuyruğa girmemiştir (Bulgu 10). Çocukları (stok_hareket, satis_kalem…) bekletilir. Bunlar ≥ 500 olunca kuyruğun başını kalıcı olarak işgal eder; arkadaki **yeni satışlar hiç okunmaz.** Toplu Excel/devir (ör. `stok_kapanis_snapshot` ürün başına satır, 4768 ürün) bu eşiği tek seferde aşar.

**Öneri:** Sorguda backoff'u SQL'e taşıyın (`son_deneme` + süre) ya da önce hiç denenmemiş satırları seçin; ebeveyni N denemedir gelmeyen çocuğu "ebeveyn eksik" durumuna alın ve ekranda gösterin.

---

## 6. [P1] Bulutta FK kısıtı yok — yanlış bağ/yetim satır sunucuda engellenmez

**Nerede:** `supabase_tam_sema.sql` — `REFERENCES` yalnız 8 yerde (dönem tabloları `donem_id`, `terminal_id`, auth). Satış–kalem, cari–hareket, gider–hesap gibi hiçbir iş ilişkisi sunucuda zorunlu değil.

**Not:** Bu yüzden istenen "foreign key constraint failed ile kuyruk kilitlenmesi" pratikte **yalnız dönem tablolarında** mümkün (`donemler` gönderilemezse çocuklar Bulgu 5'e düşer). Asıl risk patlama değil, **sessizlik**: koruma tamamen istemcideki `SupabaseSaglayici._fkDonustur()`'tedir; ebeveyn yerelde yoksa FK **NULL gönderilir** (`supabase_saglayici.dart:235`) — bulut bunu kabul eder.

**Öneri:** Yetim üretmeyen bir düzen oturduktan sonra (Bulgu 3/5 sonrası) kritik ilişkiler için `NOT VALID` FK ekleyip zamanla `VALIDATE`; sunucuda yetim satır raporu (Veri Sağlığı).

---

## 7. [P1] Tam senkron tablo sırası ihlali

**Nerede:** `lib/servisler/supabase_sync_sabitleri.dart` → `_tabloSirasi` (programatik kontrol, `fkHaritasi` + polimorfik hedefler):
```
giderler (#34)    → banka_hesaplar (#50): ebeveyn SONRA
giderler (#34)    → kredi_kartlari (#51): ebeveyn SONRA
stok_hareket (#37)→ cari_hareket (#38): ebeveyn SONRA (teorik)
```
Otomatik kuyruk yolu sırayı `KolonHaritalama.derinlik()` ile doğru hesaplar; ihlal **manuel/tam senkronu** (Buluta Gönder / Buluttan Al) etkiler: bankadan/kartla ödenen gider, hesap henüz yerelde yokken çekilir → FK eşlenemez.

**Öneri:** `_tabloSirasi`'nı da `derinlik()`'ten üretin (tek doğruluk kaynağı) ya da `bankalar, banka_hesaplar, kredi_kartlari` bloğunu `giderler`'den önceye alın; bu kontrolü kalıcı birim testi yapın.

---

## 8. [P1] LWW koruması: kapsam ve tanecik

- `supabase_lww_koruma.sql` **`supabase_tam_sema.sql`'de yok**; tetikleyiciyi yalnız çalıştırıldığı andaki tablolara bağlar (dinamik döngü). Sonradan eklenen tablolar (v81: `tedarikci_iadeler`, `tedarikci_iade_kalem`) script **yeniden çalıştırılmadıkça korumasız**.
- LWW **tüm satır** üzerinden; alan bazlı birleştirme yok. İki kasa aynı kaydın farklı alanlarını çevrimdışı düzenlerse geç gelen, diğerinin değişikliğini bütünüyle ezer. Master tablolarda (urunler, cari) çekim tarafı bunu `sync_cakismalar`'a kaydeder ama yine de uygular.
- `cevir()` `last_updated` boşsa "şimdi" basar (`kolon_haritalama.dart:342`) → eski bir görüntü en yeni gibi görünüp korumayı aşar.

**Öneri:** LWW tetikleyicisini tam şemaya ekleyin ve her şema güncellemesinde yeniden uygulayın (ya da `ALL TABLES` olay tetikleyicisi). Bulgu 2 düzeltilince en sık ezilme kaynağı kalkar.

---

## 9. [P1] Performans darboğazı — FK bulut önbelleği

**Nerede:** `supabase_saglayici.dart` → `_fkBulutCacheYukle()` (166): ebeveyn tablonun **tüm** `id, global_id` çiftlerini 1000'lik sayfalarla indirir; `_fkDonustur` ıskada (satır 240) her turda en az bir kez yeniden indirir. Aynı tur içinde az önce gönderilen satış önbellekte olmadığı için **her satış turu** `satislar` (ve polimorfik `stok_hareket`/`kasa_hareketleri` için `iade`, `tedarikci_siparisler`…) tablolarını baştan indirir. `_fkLokalCacheYukle` de yerel tabloyu tamamen okur.
**Etki:** Bugün 33 satışta hissedilmez; 50.000 satışta tur başına ~50+ istek. Ayrıca sıralamasız `offset` sayfalama (ORDER yok) eşzamanlı yazımda satır atlayabilir → gereksiz bekletme.

**Öneri:** Iskada yalnız eksik `global_id`'leri `in.(…)` ile sorgulayın (LWW kontrolündeki gibi 50'lik parçalar); gönderim yanıtını `return=representation` ile alıp yeni id'leri önbelleğe doğrudan yazın.

---

## 10-13. [P2] Diğer bulgular

**10. Yapılandırma öncesi kayıtlar** — `bulut_manager.dart:147` `if (_saglayici == null) return;`: bulut ayarı yokken `BulutManager.upsert` ile yazılan kayıtlar (ör. cari kartı, ürün düzenleme) **hiç kuyruğa girmez**; `SyncKuyrukYazici.ekleTxn` ile yazılanlar (hareketler) girer. Sonradan bağlanan cihazda çocuk var, ebeveyn yok → Bulgu 5. Öneri: ilk bağlantıda tablo başına "hiç gönderilmemiş satırları" otomatik kuyruğa alma (manuel "Buluta Gönder"in otomatik ilk-çalıştırması).

**11. Anlık çekimde mutabakat yok** — `supabase_sync_servisi.dart:1500` `if (sadeceTablolar != null) {}`: realtime kısmi çekim sonrası stok/bakiye yeniden hesaplanmaz; bir sonraki periyodik tam çekime kadar bayat görünür. Öneri: kısmi çekimde yalnız etkilenen kayıtlar için hedefli mutabakat.

**12. Çakışma çözümü** — `lib/depolar/sync_cakisma_deposu.dart` `gelenIleCoz()` (112-124): `gelen_kayit` JSON'u kayıt anındaki şemayla doğrudan `db.update` edilir; sonradan kaldırılan/eklenen sütunda "no such column" ile çöker. JSON bozuksa (`SyncCakismaModel.fromMap` güvenli çözer → null) veri yazılmadan "çözüldü" işaretlenir. `yerelIleCoz` doğru (damga + kuyruk). Öneri: güncel yerel sütunlarla kesişim al; null kayıtta çözümü reddet.

**13. Çekimde FK kapalı + REPLACE** — `veritabani_supabase.dart:522, 631` `PRAGMA foreign_keys = OFF`; `supaKayitlariEkle` `ConflictAlgorithm.replace`. `global_id` dışı bir UNIQUE çakışmasında (korunan alanlar: cari_kodu, fis_no, fatura_no, irsaliye_no, siparis_no, sube_kodu, ad, kod/barkod) SQLite yerel satırı silip **yeni yerel id** ile ekler → o satırın yerel çocuk FK'ları kopar. Bilinen alanlar `_cakismaKorumasiUygula` ile önlenmiş; bilinmeyen bir UNIQUE eklenirse risk açılır. Öneri: REPLACE yerine `global_id` ile UPDATE / INSERT ayrımı.

---

## 14. [P3] Gizli (latent) riskler

- `bulut_manager.dart` DELETE yolu filtre sütunu olarak `uniqueAlan` (ör. kategoriler → `ad`), değer olarak `global_id` kullanır → doğal anahtarlı tabloda `ad=eq.<uuid>` hiçbir satıra uymaz ama 200 döner, "başarılı" sayılır. **Bugün çağrılmıyor** (bu tablolar soft-delete'i upsert ile yapıyor); ileride eklenecek `sil()` çağrısı sessizce boşa gider.
- Terminal kaydı olmayan cihaz eski (kasasız) numara biçimine düşer (`veritabani_fis_seri.dart:74`) → iki kayıtsız cihaz aynı numarayı üretebilir (çekimde `-SYNC` ile ayrışır).
- `_kuyruktaBekliyorMu` / çakışma sezgisi `'+00:00'` damga son ekine dayanır (`veritabani_supabase.dart:395`) — damga biçimi değişirse sahte/kaçan çakışma.

---

## Sağlam bulunan alanlar (doğrulandı)

- **Atomik kuyruk:** iş verisi ve `sync_queue` satırı aynı transaction'da (`SyncKuyrukYazici.ekleTxn`); bekleyen eski kopya dedupe edilir; `idx_sync_tablo_gid (tablo_adi, kayit_global_id, durum)` indeksi var.
- **Kimlik:** `global_id` UUID v4 (çakışma olasılığı ihmal edilebilir); yerel `id` buluta asla gitmez, eşleşme `on_conflict=global_id`/doğal anahtar. Kuyruğa giren 41 tablonun hepsi `_unique` haritasında; eşleşmesi olmayan bulut tabloları (arşiv, terminaller, fatura seri) yalnız RPC ile yazılıyor.
- **FK dönüşümü:** yerel id → global_id → bulut id zinciri, polimorfik referanslar (kasa/stok/banka/kart hareketi, cari_hareket.fis_id) dahil; ebeveyn bulutta yoksa **bekletme** (yanlış bağlama yok).
- **Gönderim sırası (otomatik):** `KolonHaritalama.derinlik()` ile ebeveyn önce.
- **Türetilmiş değerler:** cari bakiye çekimde korunur (`:641`) + `bakiyeMutabakatYap`; stok `stok_hareket` delta toplamından (`stokMutabakatYap`) — tam çekimde çalışır.
- **İşlem verisi:** satış/hareket/fatura/irsaliye/iade tablolarında gerçek çakışmada otomatik ezme yok → `sync_cakismalar`.
- **Numaralandırma:** satış/iade/irsaliye/alım/TDI kasa (terminal) bazlı seri; fatura merkezi blok (`fatura_blok_tahsis_et` RPC, satır kilidi).
- **Hata dayanıklılığı:** kalıcı hatada grup ikiye bölünerek zehirli satır ayıklanır; bulut şema koruması (OpenAPI ile eksik sütun ayıklama); kalıcı hatalar açılışta otomatik yeniden denenir (20 sınır).
- **Liste tutarlılığı:** `_tabloSirasi` (69) = `_lastUpdatedVar` (69) = çekim `globalIdTablosu` (69); v81 tabloları tüm listelerde ve bulut şemasında.
- **Bulutta hayalet/kimliksiz satır yok** (canlı salt-okuma kontrolü).

---

## Düzeltme durumu (2026-10-08)

Tüm bulgular düzeltildi; her biri ayrı commit + birim testi. Tam test paketi ve `flutter analyze` temiz.

| # | Durum | Commit | Ne yapıldı |
|---|---|---|---|
| 1 | ✅ | 7fe5693b | Bulutta `sunucu_zamani` sütunu + tetikleyici (BÖLÜM H); çekim filigranı ona taşındı, ilk geçişte eski filigranın 48 saat gerisinden başlar; eski bulutta (sütun yoksa) `last_updated`'e düşer. |
| 2 | ✅ | d98c56f0 | Stok değişimleri `urunler.last_updated`'i ilerletmez; çekimde stok/bakiye uygulanmaz; LWW'de atlanan satırın yalnız türetilmiş alanı gönderilir. |
| 3 | ✅ | d98c56f0 | `ekleTxn` UPSERT'te `global_id`'yi transaction içinde tamamlar; stok sayımı/alış fiyatı tam satır yazar. |
| 4 | ✅ | c575f29f | `cevir` null'u korur (deleted_at hariç); toplu gönderim sütun kümesine göre gruplanır (null doldurma yok); çekimde null yalnız boş bırakılabilen, ilişki/türetilmiş olmayan sütunlara uygulanır. |
| 5 | ✅ | b9929483 | Yeni ve tekrar denenecek kuyruk satırları ayrı seçilir; backoff'taki satırlar yeni satışları bekletmez. |
| 6 | ⏸ Bilinçli | — | Bulut FK kısıtı **eklenmedi**: `supabase_tam_sema.sql` BÖLÜM 3 tüm FK'ları kasıtlı kaldırır (ebeveyn-çocuk aynı turda farklı cihazlardan gelebilir; sunucu kısıtı kuyruğu kilitlerdi). Koruma istemcide (FK dönüşümü + bekletme) kalır. |
| 7 | ✅ | 7fe5693b | `_tabloSirasi` düzeltildi; ebeveyn-önce kuralı kalıcı birim testinde. |
| 8 | ✅ | 7fe5693b | LWW tetikleyicisi tam şemaya alındı (BÖLÜM I), ayrı `supabase_lww_koruma.sql` kaldırıldı. Alan bazlı birleştirme kapsam dışı. |
| 9 | ✅ | 2bd3d1ea | FK dönüşümü yalnız gereken kimlikleri sorgular (yerelde `id IN`, bulutta `in.(…)` 50'lik parça); canlı bulutta salt-okuma ile doğrulandı. |
| 10 | ✅ | 3452dda8 | Sağlayıcı kurulmadan yapılan `upsert`/`sil` de kuyruğa yazılır. |
| 11 | ✅ | 113ec108 | Kısmi/anlık çekimde, değişen tablolardan beslenen mutabakat adımları çalışır. |
| 12 | ✅ | 4eb7fac9 | Çakışma çözümü yerel sütunlarla sınırlanır; gelen kayıt yoksa "çözüldü" denmez. |
| 13 | ✅ | 22c3a434 | Çekimde mevcut `global_id` yerinde güncellenir (yerel id korunur). Test ayrıca UNIQUE olmayan tabloda **çift kayıt** oluştuğunu gösterdi; o da kapandı. |
| 14 | ✅ (ilk madde) | ae4dc129 | Silme filtresinin sütunu ile değeri aynı alandan gelir. Diğer iki latent madde (kayıtsız terminal numarası, damga son eki) izlemede. |

**Kullanıcının yapması gereken:** `supabase_tam_sema.sql` dosyasını Supabase SQL Editor'de yeniden çalıştırın (BÖLÜM H: `sunucu_zamani`, BÖLÜM I: LWW tetikleyicisi). Ardından tüm kasalardaki uygulamaları yeniden başlatın (sütun yoksa uygulama o oturumda eski filigrana düşer).
