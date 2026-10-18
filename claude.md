
# CLAUDE.md — BarkoPro Market/Perakende ERP

Bu dosya, Claude Code'un bu projede nasıl çalışacağını tanımlar. Her
oturum başında oku. Çelişki varsa önce bu dosya, sonra kod, sonra
yorumlar gelir. Yorumlardaki "önceden şu hata vardı" notları **kanonik
kural** sayılır — o hataları geri getirme.

---

## 0. Proje Özeti

- **Ürün:** BarkoPro — market/perakende için tam kapsamlı ERP (Flutter).
- **Platformlar:** Windows (kasa), Android (el terminali), tablet.
- **Veri:** Yerel SQLite (offline-first) + Supabase (Postgres) senkron.
- **Dil:** Türkçe domain terimleri (cari, kasa, fiş, irsaliye, vardiya…).
- **Durum:** Üretimde çalışan, 81 migration, ~250+ dosya. **Öncelik yeni
  özellik değil — var olanı sadeleştirmek, sağlamlaştırmak, tekrarı
  azaltmak.**

---

## 1. Komutlar (her işlemden önce/sonra)

```bash
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
