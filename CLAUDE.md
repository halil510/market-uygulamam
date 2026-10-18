flutter pub get
flutter analyze           # 0 error / 0 yeni warning hedef
flutter test              # tüm testler yeşil olmalı
dart format --set-exit-if-changed .
flutter build windows --release   # Windows hedefi için
Kural: Değişiklikten sonra flutter analyze + flutter test
çalıştırmadan işi "bitti" sayma. Analyze'da yeni warning/error çıkarsa
ayrı commit'te temizle. Testin kırıldığı bir refactor'ı "sonra düzeltirim"
diye bırakma.

2. Mimari Katmanlar (bu sıraya uy)
text
UI (ekranlar/, widgetlar/)       → sadece çağırır
   ↓
Servis (servisler/)              → iş kuralları, transaction orkestrasyonu
   ↓
Depo/Repository (depolar/)       → SQL, CRUD, veri erişimi
   ↓
Veritabani (veri/database/)      → şema, migration, fisNoUret
Katman ihlali kabul edilmez:

Ekran Veritabani().db'ye doğrudan erişemez → depoya taşı.

Ekran SQL yazamaz → depoya taşı.

Servis BuildContext alamaz → sonuç döner, ekran gösterir.

Model DB'ye bağımlı olmaz → fromMap/toMap yeter.

Yeni özellik sırası: model → depo → servis → ekran → route → test.

3. Değişmez Kurallar (ASLA ihlal etme)
3.1 Para ve KDV
Tüm parasal tutarlar ParaUtils.yuvarla ile kuruşa yuvarlanır.
Yeni bir çarpma/bölme sonucu mutlaka yuvarla'dan geçir.

Satış fiyatı KDV DAHİL saklanır (kanonik kural,
sepet_model.dart baş yorumu). KDV tutarı ParaUtils.kdvPayiCikar
(bölerek) hesaplanır — kdvHesapla (çarparak) yalnızca KDV HARİÇ
taban fiyattan KDV üretmek içindir, karıştırma.

double.tryParse kullanma. Kullanıcı girdisi →
ParaUtils.sayiCoz (virgül/nokta, binlik, para simgesi temizler).

Yeni parasal alanlar int kuruş veya Decimal tercih et (yeni kod
kuralı; eski alanları refactor ederken topluca değiştir).

3.2 Transaction ve senkron
Çoklu tablo yazan her yeni akış tek db.transaction içinde.

Senkron kuyruğu aynı transaction içinde
SyncKuyrukYazici.ekleTxn ile yazılır.

BulutManager().upsert transaction içinde çağrılmaz (rollback
olursa buluta hayalet kayıt gider). Commit sonrası, okunan taze
satırla çağır.

Yeni tablo eklerken _tabloSirasi, _globalIdVar, _lastUpdatedVar,
_uniqueAlan, _softDeleteKolonu haritalarının hepsine ekle
(supabase_sync_sabitleri.dart). Eksik bırakırsan delta senkron
çalışmaz, kimliksiz kayıt buluta gider.

_softDeleteKolonu doğru sütunu göstermeli: is_deleted /
deleted_at / aktif — üçü farklı semantik.

3.3 Silme
Hard delete yasak (istisna: urun_fiyat_gruplari,
fiyat_kademeleri gibi türev kayıtlar — bunlar belgelenmiş).

Silme ters kayıt üretir: is_deleted=1 + audit + gerekirse
kasa/banka/cari/stok ters hareketi (bkz. SatisDeposu.sil,
AlimIslemServisi.sil, CariDeposu.hareketIptalEt).

İkinci kez silme çağrılırsa hiçbir ters kayıt üretilmez
(idempotent) — if (is_deleted == 1) return; guard zorunlu.

3.4 Tarih
tarih sütunları yerel saatle DateTime.now().toIso8601String()
yazılır. SQLite datetime('now') UTC döner — karşılaştırırken
'localtime' değiştiricisi kullan veya Dart tarafında karşılaştır.

last_updated her yazma yolunda set edilir.

3.5 Şube
Kasa, satış, gider, stok hareketi, vardiya → sube_id zorunlu;
boşsa AktifSubeServisi().subeId ile doldur.

Cari, banka hareketi şirket geneli — sube_id yok.

Rapor/listelerde "Tüm Şubeler" modu açıkça kurgulanmalı
(subeId == null ise filtre eklenmez).

3.6 Global ID
Global eşleşen her satırda global_id (UUID v4) dolu olmalı.
Yerel id cihaza özeldir, senkron anahtarı değildir.

update öncesi global_id boşsa üret (bkz.
BankaHesapDeposu.guncelle).

4. Kod Tekrarı Avı — Nereye Bak
Aşağıdaki desenler bu kod tabanında tarihsel olarak çoğaltılmıştır.
Bulduğun her kopyayı tek kaynağa çek, kopyayı sil, çağrı yerlerini
güncelle. Her taşımada davranış birebir aynı kalır — testlerin
yeşil kalması kanıt.

4.1 Bulut bildirim üçlemesi
text
db.query('X', where: 'id = ?', ...);
BulutManager().upsert('X', Map<String, dynamic>.from(row));
50+ yerde tekrar. Her depoya ortak yardımcı:

dart
Future<void> bildir(String tablo, int id) async {
  final db = await _d;
  final s = await db.query(tablo, where: 'id = ?', whereArgs: [id], limit: 1);
  if (s.isNotEmpty) BulutManager().upsert(tablo, Map<String, dynamic>.from(s.first));
}
4.2 Bakiye yeniden hesaplama
text
UPDATE cari SET bakiye = ROUND((SELECT SUM(borc) - SUM(alacak)
  FROM cari_hareket WHERE cari_id = ? AND is_deleted = 0), 2) WHERE id = ?
CariDeposu.hareketEkleTxn, hareketIptalEt, bakiyeYenidenHesapla,
bakiyeGuncelle, SatisDeposu.sil, IadeIslemServisi (3 yerde),
AlimIslemServisi — tek metoda çek:
CariDeposu._bakiyeTazeleTxn. Aynı desen kasa (bakiye_sonrasi),
banka (sonraki_bakiye), kredi kartı (kullanilan_limit) için de var
— her biri kendi deposunda tek fonksiyon.

4.3 "Giriş mi çıkış mı" sınıflandırması
KasaHareketModel.girisTipleri merkezi kaynak. Ama şu SQL CASE
listeleri ayrı ayrı yazılı ve zamanla senkronsuz kaldı:

kasa_deposu.dart — gunlukOzet, aralikOzet

vardiya_deposu.dart — hareket tipi eşlemeleri

rapor_deposu.dart — KDV/ödeme yöntemi grupları

Tek enum veya sabit set yap, SQL'e parametre olarak geçir veya Dart
tarafında süz.

4.4 Fatura/makbuz/iade PDF üretimi
fatura_detay_pdf_ext.dart — A4 + 80mm

yazdirma_servisi_belgeler.dart — termal (ESC/POS)

iade_fis_yazdirma.dart — iade fişi

gunluk_rapor_ekrani.dart — günlük PDF

Ortak metinler (firma bilgisi, "Yalnız … TL", KDV satırı, imza) 4
dosyada tekrar. PdfSablonlari ortak sınıfına topla. Toplam
hesaplarında tek formül (genelToplam = vergilerHaric + toplamKdv)
kalsın; "Ara Toplam" hem brüt hem net anlamda kullanılmasın (bu zaten
bir kez bug olmuş).

4.5 Satış fiyatı hesaplama
UrunFiyatHesaplayici.hesapla (promosyon/indirim)

FiyatHesaplamaServisi.kuralUygula (toptan/bayi)

Sepet provider (Hızlı Satış)

MasaDeposu.kalemEkle (masa)

Hızlı Satış ve Masa aynı UrunFiyatHesaplayici'yi kullanmalı. Bu
deseni asla ikinci bir yere kopyalama; toptan fiyat kuralını da
aynı servise taşı (şu an iki ayrı yer).

4.6 Rapor tarih karşılaştırma
datetime(tarih) BETWEEN datetime(?) AND datetime(?) deseni 40+ yerde.
Bazı yerde localtime, bazı yerde değil (bu tam olarak bir zamanlar
"gece 00:00–03:00 arası satışlar kayboluyor" bug'ı olmuş). Tarih
karşılaştırmalarını TarihUtils üzerinden tek biçime indir:
TarihUtils.betweenWhere('tarih', bas, bit) gibi.

4.7 Seçim diyalogları
hizli_satis, iade_ekrani, alim_ekrani, toptan_satis,
bayi_siparis_al — hepsinde cari/ürün seçim dialogu kopya.
widgetlar/ortak/ altında cariSecDialog ve urunAraWidget yap.

4.8 Para formatlama
ParaUtils.formatla var ama hâlâ elle '${x.toStringAsFixed(2)} ₺'
formatlayan yerler var (fatura_detay_ekrani, iade_ekrani,
banka_detay_ekrani). Hepsini ParaUtils.formatla'ya geçir.

4.9 Fiyat/marj hesabı
Ürün detay, cari liste, toptan satış, rapor — 4 ayrı yerde (satis - alis) / alis * 100 formülü. ParaUtils.karOrani var; çağırmayan
yerleri ona geçir. KDV'li marj ayrı fonksiyon olsun.

5. Bu Kod Tabanına Özgü Hata Desenleri (Avla)
Aşağıdaki hatalar birden fazla kez düzeltilmiş; yeni kodda tekrar
etme, var olan kodda hâlâ varsa düzelt.

5.1 "Çift ters kayıt" hatası
Sil/iptal fonksiyonunun başında if (is_deleted == 1) return; guard'ı
zorunlu. Aksi halde kasa/cari/stok ikinci kez ters çevrilir.

5.2 copyWith alan kaybı
UrunModel.copyWith bir zamanlar 11 alanı sıfırlıyordu. Aynı hata
KrediKartiModel, CariModel'de de olmuş. Yeni alan eklerken
copyWith parametresine eklemek yetmez — gövdedeki UrunModel(...)
çağrısına da ekle. Her modelde bu kontrolü yap.

5.3 "Bakiye alanı doğrudan yazma"
Cari bakiye, kasa bakiye, banka bakiye, kart limit — hepsi
hareketlerden türetilir. db.update('cari', {'bakiye': x}) gibi
doğrudan yazma yasak. Tek istisna: mutabakat fonksiyonları
(bakiyeMutabakatYap, bakiyeYenidenHesapla).

5.4 MAX(id) + 1 numara üretimi
Fatura no, cari kodu, fiş no — hep MAX+1 veya COUNT+1 ile
üretilmiş, silme/senkron sonrası çakışma üretir. Yeni numara üretimi:

Fatura → FaturaSeriBlokServisi (merkezi blok)

Fiş/cari/iade/irsaliye → BelgeNoServisi().uret(tip)

Elle MAX+1 yazma.

5.5 UTC vs local karışıklığı
DateTime.now().toIso8601String() yerel, SQLite datetime('now')
UTC. Karşılaştırmalarda 'localtime' veya Dart tarafında çevir.

5.6 Çift-await yarışı
if (_islemAktif) return; _islemAktif = true; — bu iki await
arasında değil, ilk await'ten ÖNCE olmalı. Bu hata her ekranda
tekrar tekrar düzeltilmiş (hızlı satış, iade, toplu işlem, ödeme…).
Yeni async handler yazarken guard'ı en üste koy.

5.7 Sessiz hata yutma
dart
catch (e) { if (kDebugMode) debugPrint('...'); }
Production'da hatayı görünmez yapar. Yeni kodda:

İş kuralı hatası → throw Exception('kullanıcıya gösterilecek mesaj').

Beklenmedik hata → LogServisi().hata(...) + üst katmana rethrow.

Sadece kozmetik (resim yüklenemedi) sessizce geçebilir; log yine de
yazılmalı.

catch (_) {} beyaz liste dışında yasak.

5.8 WidgetRef parametre olarak geçirme
SyncMiniButon(ref: ref) gibi desenler Riverpod anti-pattern. Widget
ConsumerWidget/ConsumerStatefulWidget olsun, ref'i kendi içinde
alsın.

5.9 showDialog(...).whenComplete(...)
Diyalog kapandıktan sonra controller'ı hemen dispose etme, 600 ms bekle
(dialogSonrasiBirak yardımcı zaten var). Her dialog'da kullan.

5.10 BuildContext await sonrası
await sonrası context.mounted / mounted kontrolü zorunlu. Bu
kural her ekranda hâlâ ihlal ediliyor — yeni kodda ihmal etme.

5.11 DropdownButtonFormField initialValue yenileme
Liste provider'ı yenilendiğinde eski nesne referansı kaybolur, dropdown
"exactly one item" hatasıyla çöker. Seçili değeri ID ile eşle
(bankalar.where((b) => b.id == secili?.id).firstOrNull).

6. Refactor Sırası (öncelik)
Bir maddeyi bitirmeden sonrakine geçme.

Faz A — Güvenlik ve veri bütünlüğü (1. öncelik)
double.tryParse ile para parse eden tüm yerleri tara, ParaUtils.sayiCoz'a geçir.

Tüm MAX(id)+1 numara üretimlerini BelgeNoServisi / FaturaSeriBlokServisi'ne geçir.

Tüm sil/iptal fonksiyonlarına if (is_deleted == 1) return; guard'ı ekle.

Bakiye/stok/limit alanlarına doğrudan yazma var mı tara; hareket tabanlı yeniden hesaplamaya çevir.

catch (_) {} ve sessiz debugPrint catch'lerini LogServisi + rethrow'a çevir (kozmetik olanları belgele).

Tüm async handler'larda _islemAktif guard'ının ilk await'ten önce set edildiğini doğrula.

Faz B — Kod tekrarı (2. öncelik)
Bölüm 4'teki 9 desenin her birini tek kaynağa çek. Davranış değişmesin.

Ortak cari/ürün seçim diyaloğu → widgetlar/ortak/.

Ortak PDF parçaları → PdfSablonlari.

Fiyat hesaplama tek yol → FiyatHesaplamaServisi (masa + hızlı satış + toptan).

Kâr/marj hesabı tek yol → ParaUtils.karOrani.

Bakiye yenileme tek metot → her depoda _bakiyeTazeleTxn.

Faz C — Mimari temizlik (3. öncelik)
Veritabani().db doğrudan kullanan ekranları tara (grep -r "Veritabani().db" lib/ekranlar/ lib/widgetlar/), depoya taşı.

God-class'ları böl: 1500 satır üstü her dosya için servis/repo çıkar.

WidgetRef parametreli widget'ları Consumer'a çevir.

Naming: _depo sonekini her yerde standartlaştır, Servisi/Deposu ayrımını netleştir.

SQL şablonlarını lib/veri/database/sql_sablonlari.dart altında topla (tekrar eden sorgular).

Faz D — Performans (4. öncelik)
Tüm liste sorgularına LIMIT ekle (yoksa).

ListView(children: ...) → ListView.builder (büyük listelerde).

Tarih filtreleri için eksik index'leri ekle.

N+1 sorguları toplu sorguya çevir (MasaDeposu._kalemleriTopluGetir desenini kopyala).

7. Test ve Doğrulama
Var olan testleri kırma. Davranış değişikliği gerekiyorsa önce
testi kasıtlı güncelle, commit mesajında neden belirt.

Yeni saf fonksiyon yazınca mutlaka test yaz
(ParaUtils.sayiCoz, TarihUtils.secimAraligiKirp,
cariHareketleriniGrupla gibi).

Bug düzeltiyorsan regresyon testi ekle — hata mesajını/senaryoyu
testin adına yansıt.

DB transaction testleri için sqflite_common_ffi kullan (projede var).

Her refactor PR'ı flutter test yeşil olmalı.

8. Yapılmayacaklar (yasak listesi)
❌ Veritabani().db'yi ekran/UI katmanında açma.

❌ Yeni BulutManager().upsert çağrısını transaction içine koyma.

❌ Yeni catch (_) {} (beyaz liste dışı) ekleme.

❌ Yeni MAX(id)+1 numara üretimi yazma.

❌ cari.bakiye, banka_hesaplar.bakiye, kredi_kartlari.kullanilan_limit alanına hareket dışı doğrudan yazma.

❌ copyWith'e parametre ekleyip gövdeye aktarmayı unutma.

❌ double.tryParse ile para parse etme.

❌ Rota prefix çakışması olan yeni yetki kodu eklerken _routeYetkiler'e yazmayı unutma.

❌ Yeni tablo eklerken supabase_sync_sabitleri.dart'ın 5 haritasını atlama.

❌ debugPrint ile production'da hata "gösterme" — LogServisi kullan.

❌ await sonrası mounted/context.mounted kontrolsüz context kullanma.

❌ WidgetRef'i widget parametresi olarak geçirme.

9. Çıktı Formatı (commit ve PR)
Her commit tek bir konuya odaklanır.

Commit mesajı:

text
faz-X: <kısa başlık>

- Ne: <bir cümle>
- Neden: <hangi hata / hangi tekrar / hangi risk>
- Dosyalar: <virgülle>
- Test: <yeni test adı veya "mevcut testler geçti">
- Regresyon riski: <yok / şu>
PR açıklaması:

text
## Özet
## Davranış değişti mi? (evet/hayır, evetse neden)
## Etkilenen dosyalar
## Test durumu: `flutter test` ✅ / ❌
## Analyze: `flutter analyze` ✅ / ❌
## Manuel doğrulama adımları
Refactor PR'larında davranış değişmez kural: "davranış değişmedi,
sadece X taşındı" cümlesi PR'da açıkça yazılmalı.

10. Bilinen "Dokunma" Alanlar
Şu dosyaların iç mantığı tarihsel olarak çok kırılgan; refactor
ederken tek tek, test eşliğinde ilerle:

lib/veri/database/veritabani_supabase.dart — çakışma koruması
(5 tablo tipi, idempotency, "gerçek çakışma mı" sezgileri)

lib/servisler/supabase_sync_servisi.dart + supabase_sync_sabitleri.dart

lib/servisler/fatura_seri/* — merkezi numara blok tahsisi

lib/servisler/gib_servisi.dart + gib_ubl_olusturucu.dart — ETTN
deterministik, GİB şeması

lib/servisler/donem_devir_servisi.dart + donem_arsiv_servisi.dart
— 10 fazlı resumable state machine

lib/servisler/iade_islem_servisi*.dart — ters kayıt zinciri

Bu dosyalarda değişiklikten önce:

Mevcut testleri çalıştır.

Tek bir faz/fonksiyon seç, sadece onu değiştir.

Değişiklik sonrası tüm testleri tekrar çalıştır.

11. Hızlı Referans — Yardımcılar
Yeni kod yazarken önce "bu var mı?" diye bak, varsa tekrar yazma:

İhtiyaç	Kullanılacak
Para format	ParaUtils.formatla
Metin → sayı	ParaUtils.sayiCoz
Kuruş yuvarlama	ParaUtils.yuvarla
KDV payı çıkar	ParaUtils.kdvPayiCikar
Kâr oranı	ParaUtils.karOrani
Tarih format	TarihUtils.tarihFormatla
Fiş no üret	BelgeNoServisi().uret(tip)
Fatura no üret	FaturaSeriBlokServisi (txn içinde)
Sync kuyruğu yaz	SyncKuyrukYazici.ekleTxn
Audit log	AuditLogServisi().kaydet
Hata log	LogServisi().hata (yakala + rethrow)
Dialog sonrası bırak	dialogSonrasiBirak
Excel güvenliği	excelIcinGuvenliMetin
VKN/TCKN doğrula	VergiNoDogrulayici
Kullanıcıya hata metni	kullaniciyaHataMetni
Aktif şube	AktifSubeServisi().subeId
Tekrar görününce yenile	TekrarGorununceYenile mixin


# GÖREV: Test Güvenilirliği — Kademe 1 & 2

Proje kökünde çalış. Bu görev CLAUDE.md'nin TÜM kurallarına %100 uyar — hiçbir 
kuralı ihlal etme. Her commit öncesi `flutter analyze` (0 error, 0 yeni warning) 
ve `flutter test` (tam yeşil) zorunlu. CLAUDE.md §1: "Değişiklikten sonra analyze 
+ test çalıştırmadan işi 'bitti' sayma."

---

## ÖNKOŞUL KONTROLÜ (işe başlamadan yap)

1. `git status` temiz mi? Değilse **dur**, kullanıcıya sor.
2. Yeni dal aç: `git checkout -b test-refactor-kademe1`
3. Başlangıç durumunu doğrula:
   - `flutter analyze` → 0 error, 0 yeni warning
   - `flutter test` → tam yeşil
4. Bu üç komut da yeşil değilse **dur**, rapor et, işe başlama.

---

## GEREKÇE (neden bu iş CLAUDE.md'deki faz A/B/C/D'den ÖNCE yapılmalı)

CLAUDE.md §4.2 ve §4.5 kod tekrarını azaltmayı istiyor. Ama şu an bu tekrarın 
testleri de kopya olarak yazılmış durumda (bkz. aşağıdaki dosya listesi). 
Testler önce gerçek üretim fonksiyonlarına bağlanmazsa, Faz B refactor'ı 
sırasında **üretim davranışı sessizce değişir ve testler hâlâ yeşil kalır**. 
Yani bu görev, CLAUDE.md'nin faz B/C'sinin **önkoşuludur**.

---

## KADEME 1 — Kopya Testleri Gerçek Fonksiyonlara Bağla

### Problem
Aşağıdaki test dosyalarında üretim mantığı SQL/metot olarak kopyalanmış 
("BİREBİR AYNI" yorumlarıyla işaretli). Üretim kodu bozulsa bile testler 
yeşil kalır → hiçbir regresyonu yakalayamıyorlar.

### Dosya Tablosu

| # | Test dosyası | Kopya helper | Bağlanacak gerçek fonksiyon |
|---|---|---|---|
| 1 | `test/depolar/satis_sil_cari_ters_kayit_test.dart` | `_satisSilSimulasyonu` | `SatisDeposu().sil(id)` |
| 2 | `test/servisler/alim_sil_test.dart` | `_alimSilSimulasyonu` | `AlimIslemServisi().sil(id)` |
| 3 | `test/servisler/iade_olustur_cift_iade_fix_test.dart` | `_iadeCariYaz` | `IadeIslemServisi().topluIadeKaydet(...)` |
| 4 | `test/servisler/iade_cari_gercek_etki_test.dart` | `_iadeCariYaz`, `kasaYazIadeGirisi` | `IadeIslemServisi()` gerçek metotları |
| 5 | `test/servisler/iade_sil_test.dart` | `_gecmisFisIadeSilSimulasyonu` | `IadeIslemServisi().gecmisFisIadeSil(...)` |
| 6 | `test/servisler/borc_odeme_islem_servisi_test.dart` | `_nakitOdemeSimule` | `BorcOdemeIslemServisi().odemeYap(...)` |
| 7 | `test/servisler/satis_tamamlama_servisi_test.dart` | `_satisiSimuleEt` | `SatisTamamlamaServisi().tamamla(...)` |
| 8 | `test/servisler/virman_servisi_test.dart` | `_virmanYap` | `VirmanServisi().virmanYap(...)` |
| 9 | `test/servisler/gider_banka_kredi_gercek_etki_test.dart` | `_bankaUzlastir`, `_krediUzlastir` | `GiderDeposu().guncelle/sil` |
| 10 | `test/servisler/cari_hareket_iptal_banka_kk_test.dart` | `_hareketIptalEt` | `CariDeposu().hareketIptalEt(...)` |
| 11 | `test/ekranlar/alim_para_hareketi_test.dart` | `_alimiSimuleEt` | `AlimIslemServisi().alimKaydet(...)` |
| 12 | `test/ekranlar/tedarikci_siparis_test.dart` | `_siparisOlustur`, `_siparisiTeslimAl` | İlgili servis/depo gerçek metotları |
| 13 | `test/ekranlar/iade_lot_dagitim_test.dart` | `_iadeDagilimiHesapla` | `IadeIslemServisi` içinde `@visibleForTesting` sarmalayıcı |
| 14 | `test/depolar/veri_sagligi_mutabakat_test.dart` | `_cariBakiyeMutabakatYap`, `_kasaBakiyeMutabakatYap`, `_bankaBakiyeMutabakatYap` | `CariDeposu/KasaDeposu/BankaHesapDeposu.bakiyeMutabakatYap()` |
| 15 | `test/depolar/sube_urun_deposu_test.dart` | `SubeUrunDeposuTest.transferEt` | `SubeUrunDeposu().transferEt(...)` |
| 16 | `test/ekranlar/cari_excel_ice_disa_aktarim_test.dart` | `satiriIsle`, `_cariTuruCoz`, `_cariBaslikSatiriBul` | `ExcelServisi` gerçek metotları |

### Her Dosya İçin Adımlar

1. **Önce gerçek üretim metodunu aç, oku.** Zaten `Veritabani.testVeritabani` 
   seam'i kullanılıyor — bu desen projede yerleşik (bkz. mevcut `uruns`/`cari` 
   depo testleri).
2. **Test edilebilirlik kontrolü:**
   - Metot `Veritabani()` singleton'ı kullanıyorsa → testte `Veritabani.testVeritabani = db;` 
     zaten kurulu olduğu için doğrudan çağrılabilir.
   - Metot **private** ise → `@visibleForTesting` public sarmalayıcı ekle. 
     CLAUDE.md §10 dikkat: `iade_islem_servisi*.dart` "dokunma" listesinde. 
     **Bu dosyada SADECE `@visibleForTesting` sarmalayıcı ekle; iç mantığa 
     DOKUNMA.** Sarmalayıcı adı: `fisKalemIadeTestIcin` gibi açık olsun.
3. **Kopyayı test dosyasından sil.** Yerine gerçek metodu çağır.
4. **Assertion'ları DEĞİŞTİRME.** Sadece çağrılan fonksiyon değişecek. Davranış 
   aynı kalacak (test yeşil → kanıt).
5. **Dosya bazında commit at** (16 commit). Her commit tek dosyaya odaklı — 
   CLAUDE.md §9.
6. **Her commit sonrası:** `flutter test test/<dosya>` → yeşil doğrula.

### CLAUDE.md Uyum Notları

- **§3.2:** `SyncKuyrukYazici.ekleTxn` transaction içinde çağrılıyor. Test bunu 
  doğrulamıyorsa assertion **ekle** (regresyon önleyici).
- **§3.3:** Silme idempotency (`if (is_deleted == 1) return;`) testlerinde 
  doğrulanmalı. Kopya helper'ların birçoğu bu guard'ı atlamış olabilir — 
  gerçek metoda bağlanınca doğrulanacak.
- **§5.4:** `MAX(id)+1` numara üretimi testlerinde varsa → gerçek `BelgeNoServisi` 
  yolunu doğrula.
- **§11:** Yardımcı fonksiyonları kendin yazma, tablodakileri kullan.

### Kademe 1 Kabul Kriterleri
- 16 dosyada `_simuleEt`, `Simulasyonu`, `_Yaz`, `Test.transferEt` gibi kopya 
  helper isimleri **kalmamış**
- `grep -rn "BİREBİR AYNI" test/` çıktısı **%80+ azalmış**
- `flutter test` hâlâ **tam yeşil**
- `flutter analyze` 0 yeni warning/error
- Her commit tek dosya odaklı, commit mesajı CLAUDE.md §9 formatında

---

## KADEME 2 — Test Edilmemiş Hayati Akışlar İçin Yeni Testler

Her yeni dosyayı ayrı commit'te gönder. Dosya adından sonra `(YENİ)` yaz.

### 2.1 `test/servisler/auth_servisi_giris_test.dart` (YENİ)

`AuthServisi.girisYap` — şu an SADECE `hashle` test edilmiş; giriş akışı hiç test 
edilmemiş. Kırılırsa **uygulama açılamaz**.

Senaryolar:
- Doğru kullanıcı + doğru şifre → `kullanici != null`
- Yanlış şifre → `false`, `GirisDenemeSayaci` artar
- Olmayan kullanıcı → `false`, sayaç artar (bilgi sızdırma yok)
- `aktif = 0` kullanıcı → `false`
- 3 yanlış sonrası kilit → `GirisDenemeSayaci` devreye girer, kilit süresi içinde 
  doğru şifre bile reddedilir
- Başarılı giriş sonrası sayaç `temizle()` çağrıldı mı
- Tuzsuz eski hash'li kullanıcı hâlâ girebiliyor (geriye dönük uyumluluk — 
  CLAUDE.md §3.6 ruhu)
- Tuzlu yeni kullanıcı doğru şifreyle girer, yanlış şifreyle reddedilir

Kurulum: `SharedPreferences.setMockInitialValues({})` + `TestVeritabani.olustur()`.

### 2.2 `test/servisler/yedekleme_servisi_uctan_uca_test.dart` (YENİ)

`YedeklemeServisi.yedekleGeriYukle` — şu an `yedekGunuGeldiMi` ve 
`butunlukKontrolEt` var ama **gerçek yedekle → sil → geri yükle** akışı yok. 
Kurtarma yolu test edilmemiş.

Senaryolar:
- `TestVeritabani.olustur()` + 3 ürün ekle
- `yedekAl()` → dosya oluşur, boyut > 0
- Yeni ürün ekle (4. ürün)
- `yedektenGeriYukle(dosya)` → 4. ürün yok, 3 ürün var
- Bozuk dosya ver → `throwsException`, mevcut veriye dokunulmamış
- Aynı yedek iki kez restore → idempotent
- `cekimFiligranlariniSifirla()` çağrıldı mı (bkz. `acilis_koruma_test.dart`)

Geçici dizin: `Directory.systemTemp.createTempSync()`. `path_provider` 
kanalını mock'la veya `veritabani_dosya_servisi_test.dart`'taki deseni kopyala.

### 2.3 `test/widget/fatura_pdf_icerik_test.dart` (YENİ)

`fatura_detay_pdf_ext.dart` gerçek PDF üretiyor mu, içeriği tutarlı mı?

Senaryolar:
- 2 satırlı örnek fatura → `Uint8List` PDF döner
- PDF iç tutarlılığı: `fatura.toplamAraToplam + fatura.toplamKdv == fatura.genelToplam` 
  (CLAUDE.md §4.4 uyarınca bu formül kutsaldır — daha önce bug olmuş)
- PDF byte'larında firma adı geçiyor mu (basit `contains` araması)
- PDF byte'larında `genelToplam` değeri geçiyor mu
- İndirimli kalem varsa: `iskontoTutari > 0` ve toplamlar hâlâ tutuyor

**Not:** PDF metin ayrıştırma gerçekten zorsa, en azından byte düzeyinde `contains` 
ile smoke doğrulaması yeterli — "hiç yoktan iyidir" prensibi. Tam metin 
çıkarımı için ek paket eklemeyin.

### 2.4 `test/widget/yazdirma_servisi_escpos_test.dart` (YENİ)

`YazdirmaServisi` fiş/etiket ESC/POS çıktısı:

Senaryolar:
- Boş sepet → fiş basılmaz (byte dizisi boş veya sadece init)
- Örnek fiş → byte dizisinde `0x1B, 0x40` (ESC @ başlat) var
- Byte dizisinde `0x1D, 0x56` (GS V kes) var
- Türkçe karakter (ş, ğ, ı) doğru kodlanmış (CP857/CP1254 — mevcut 
  `temizleYaziciMetni` sonrası byte'a dönüşüm)
- Uzun fiş (>20 satır) → sonda kes komutu
- Tutar formatı `ParaUtils.formatla` çıktısıyla uyumlu

Eğer `YazdirmaServisi` byte'a çevirmiyorsa (sadece metin üretiyorsa), en azından:
- Üretilen metin boyutu > 0
- İçinde tarih, tutar, firma adı var
- `temizleYaziciMetni` uygulanmış mı (Türkçe → Latin-1)

### 2.5 `test/servisler/masa_odeme_uclu_karma_test.dart` (YENİ)

`MasaOdemeServisi.odemeYap` **üçlü karma** (şu an ikili kombinasyonlar test 
edilmiş, üçlü yok):

Senaryolar:
- 100 TL sipariş = 40 Nakit + 30 Kart + 30 Cari
- Kasa hareketleri: +40 Nakit +30 Kart (2 satır, `referans_turu='satis'`)
- Cari: +30 borç hareketi (`borc=30, alacak=0`, `fis_tipi='SatДұЕҹ'`)
- Satış kaydı: `genel_toplam=100`, `odeme_yontemi='Karma'`
- Masa: `durum='bos'`
- Sipariş: `durum='odendi'`
- Aynı sipariş ikinci kez ödenmeye çalışılırsa → hata (idempotent guard, §3.3)
- Toplamlar tutuyor: `40+30+30 == 100`, kasa+cari = satış (mutabakat)

### Kademe 2 Kabul Kriterleri
- 5 yeni test dosyası, hepsi geçiyor
- `flutter test` toplam süresi **< %30 artmış** (300 saniyeyi aşmasın)
- Her yeni dosya ayrı commit
- `flutter analyze` 0 yeni warning

---

## KISITLAR — CLAUDE.md'DEN AKTARIM

Bu görev sırasında **her satırda** bunlara uy:

### §2 Mimari
- UI → Servis → Depo → Veritabani. Test yazarken bile katmanı koru.
- Ekran testi depoyu doğrudan çağıramaz → servisi çağıracak.

### §3.1 Para/KDV
- Test içinde para hesaplaması yazma → `ParaUtils.*` kullan.
- `double.tryParse` yok.
- `ParaUtils.kdvPayiCikar` (içinden) vs `kdvHesapla` (üstüne) karıştırma.

### §3.2 Transaction & Sync
- Test kurulumunda çok tablo yazıyorsan tek `db.transaction`.
- `SyncKuyrukYazici.ekleTxn` transaction içinde çağrılmalı — testin 
  bunu doğrulaması bekleniyor.
- `BulutManager().upsert` transaction DIŞINDA — test bunu da doğrulasın.

### §3.3 Silme
- Silme idempotency (`if (is_deleted == 1) return;`) testlerde **açıkça** 
  doğrulanmalı (var olan testlerde eksik olabilir — Kademe 1 sırasında ekle).

### §3.4 Tarih
- Test kurulumunda `DateTime.now().toIso8601String()` (yerel).
- SQL karşılaştırmalarında `datetime('now', 'localtime')`.

### §3.5 Şube
- Kasa/satış/gider/stok satırlarında `sube_id` dolu olmalı — testte 
  `AktifSubeServisi` veya seed şube.

### §3.6 Global ID
- Testle eklenen her senkron satırda `global_id` dolu olmalı.

### §10 "Dokunma" Dosyaları — EKSTRA DİKKAT

Bu dosyalarda **SADECE** `@visibleForTesting` sarmalayıcı ekle, **iç mantığa 
dokunma**, her değişiklik öncesi/sonrası `flutter test`:

- `lib/veri/database/veritabani_supabase.dart`
- `lib/servisler/supabase_sync_servisi.dart` + `supabase_sync_sabitleri.dart`
- `lib/servisler/fatura_seri/*`
- `lib/servisler/gib_servisi.dart` + `gib_ubl_olusturucu.dart`
- `lib/servisler/donem_devir_servisi.dart` + `donem_arsiv_servisi.dart`
- **`lib/servisler/iade_islem_servisi*.dart`** ← Kademe 1 #3, #4, #5, #13 buradan

Bu dosyalara dokunduğunda commit mesajında **açıkça belirt**: 
`"iade_islem_servisi.dart: sadece @visibleForTesting sarmalayıcı eklendi, iç mantık DEĞİŞMEDİ."`

### §11 Yardımcı Referans
Yeni test yazarken "bu var mı?" diye tabloya bak:

| İhtiyaç | Kullan |
|---|---|
| Para format | `ParaUtils.formatla` |
| Metin → sayı | `ParaUtils.sayiCoz` |
| Kuruş yuvarlama | `ParaUtils.yuvarla` |
| KDV payı çıkar | `ParaUtils.kdvPayiCikar` |
| Fiş no üret | `BelgeNoServisi().uret(tip)` |
| Sync kuyruğu | `SyncKuyrukYazici.ekleTxn` |
| Aktif şube | `AktifSubeServisi().subeId` |
| Dialog sonrası | `dialogSonrasiBirak` |

---

## YASAKLAR (CLAUDE.md §8 + bu görev özelinde)

- ❌ Hiçbir **assertion silme** — sadece çağrıları gerçek fonksiyona çevir.
- ❌ Hiçbir **üretim mantığını değiştirme** — sadece test edilebilirlik için 
  `@visibleForTesting` sarmalayıcı.
- ❌ **`Veritabani().db`** ekran testlerinde doğrudan kullanma.
- ❌ **`BulutManager().upsert`** transaction içinde.
- ❌ Yeni `catch (_) {}`.
- ❌ `MAX(id)+1` numara üretimi (testte bile).
- ❌ `cari.bakiye` / `banka_hesaplar.bakiye` / `kredi_kartlari.kullanilan_limit` 
  alanına hareket dışı doğrudan yazma.
- ❌ `double.tryParse`.
- ❌ `copyWith` gövdesine parametre aktarmayı unutma (test fixture'larında da).
- ❌ `await` sonrası `mounted`/`context.mounted` kontrolü olmadan context kullanımı.
- ❌ Commit başına birden fazla dosya (Kademe 1'de tek dosya = tek commit).
- ❌ Testleri toplu commit et (16 commit Kademe 1, 5 commit Kademe 2 — toplam **21 commit**).
- ❌ Yeşil olmayan testle commit atma.

---

## COMMIT FORMATI (CLAUDE.md §9)

Kademe 1 için:
```
faz-test-1: <dosya_adı> kopyasını gerçek fonksiyona bağladı

- Ne: <kısa açıklama>
- Neden: test kopyası üretim kodunu korumuyordu
- Dosyalar: test/<dosya>.dart [, lib/<üretim>.dart — sadece sarmalayıcıysa]
- Test: mevcut testler geçti (davranış değişmedi)
- Regresyon riski: yok (yalnızca test kodu değişti)
```

Kademe 2 için:
```
faz-test-2: <yeni dosya> eklendi

- Ne: <senaryo>
- Neden: <hangi akış test edilmemişti>
- Dosyalar: test/<yeni>.dart
- Test: 8 senaryo (hepsi geçti)
- Regresyon riski: yok (yalnızca test eklemesi)
```

---

## MANUEL DOĞRULAMA (kendini kontrol et)

Her commit öncesi:
1. `flutter test test/<dosya>` → yeşil
2. `flutter analyze` → 0 yeni warning

Her 5 commit'te bir (tam koşu):
3. `flutter test` → tam yeşil, **süre < 300 sn**
4. `git log --oneline -5` → format doğru

Bittiğinde:
5. `flutter test --coverage` → `coverage/lcov.info` üret
6. `git diff main --stat` → beklenen dosya sayısı (16 test + ~2 üretim sarmalayıcı + 5 yeni test)

---

## RAPOR (son commit sonrası yaz)

```
## Kademe 1 Tamamlandı ✅

Değiştirilen test dosyaları: 16
Üretim dosyası dokunuşu: N (hepsi @visibleForTesting, açıklamalı)
Assertion değişikliği: 0 (davranış aynı)
Kalan "BİREBİR AYNI" grep sonucu: N (hedef: <10)

## Kademe 2 Tamamlandı ✅

Yeni test dosyaları: 5
Senaryo sayısı: ~40
Coverage önce/sonra: X% → Y%

## Test Durumu
- flutter test: ✅ (N test, M saniye)
- flutter analyze: ✅ (0 error, 0 yeni warning)
- dart format --set-exit-if-changed .: ✅

## Commit Sayısı
21 (16 Kademe 1 + 5 Kademe 2)

## Kalan Riskler (bu görevle KAPANMADI)
- integration_test/ klasörü hâlâ yok (GİB, Supabase gerçek entegrasyon)
- Yıllık performans benchmark yok
- Karanlık mod tüm ekranlarda taranmadı
- [kullanıcı doldursun]

## Sonraki Öneri
Faz B (CLAUDE.md §4 kod tekrarı) — Kademe 1 sayesinde testler artık 
gerçek üretim kodunu koruyor, güvenli refactor yapılabilir.
```

---

## EN KRİTİK KURAL

**"Davranış değişmedi, sadece X taşındı"** cümlesi her Kademe 1 commit'inde 
PR açıklamasında açıkça yazılmalı (CLAUDE.md §9 son paragrafı).

Kademe 1'de **sıfır davranış değişikliği** olmalı. Test kırmızıya dönerse:
- Kopya helper'ın gerçek koddan **farklı** davrandığı ortaya çıkmıştır → 
  bu bir bug'dır, `git stash` ile geri al, kullanıcıya raporla, **düzeltme**.

Kademe 2'de yeni test kırmızıya dönerse:
- Ya test yanlış yazılmış → düzelt
- Ya da gerçekten üretim bug'ı → commit mesajında `fix:` etiketiyle üretim 
  düzeltmesi de ekle, ayrı commit.

---

## BAŞLA

1. `git checkout -b test-refactor-kademe1`
2. `flutter analyze && flutter test` → yeşil doğrula
3. Kademe 1 dosya #1 ile başla
4. Her commit sonrası bu prompt'a geri dön, kabul kriterlerini kontrol et