# BARKOPRO / MARKETPLUS — DEEP AUDIT REPORT
**Tarih:** 2026-09-20 · **Kapsam:** ERP_DENETIM_KURALLARI.md.txt'nin BAŞINDAKİ prompt (madde 1-33, "MASTER DEEP ERP AUDIT + MODERNIZATION + UX/UI DISCOVERY") · **Yöntem:** 8 paralel derin-analiz turu (Satış/POS, Stok/Ürün, Finans/Cari/Kasa/Banka, Sync/Offline/DB Şema/Arşiv, Güvenlik/Yetki/Kod Kalitesi, UX/UI/Tasarım, Test/Performans/AI/Backup, Proje Envanteri/Mimari) — gerçek kod okunarak, zincir takip edilerek. **KOD DEĞİŞİKLİĞİ YAPILMADI.**

Bu rapor, önceki oturumlarda kullanıcı tarafından işaret edilen maddelerin ("Madde X") tek tek denetiminden FARKLI: bu tur, hiçbir madde verilmeden projenin kendi kendine keşfedilmesini istedi. Aşağıdaki bulguların büyük kısmı bu yüzden YENİ — önceki 60+ commit'lik denetim turlarında hiç raporlanmamış.

---

## 1. EXECUTIVE SUMMARY

**1. Projenin mevcut mimari seviyesi:** Olgun, çok-fazlı geliştirilmiş bir offline-first ERP/POS. SQLite→Supabase sync, transaction atomikliği, cari/stok/kasa mutabakat motorları, yıl sonu devir sistemi, 30+ ekranlık roadmap'in tamamı gerçekten mevcut. Ancak bu olgunluk EŞİT DAĞILMAMIŞ: en çok işletilen akışlar (hızlı satış, alış, transfer) sertleştirilmiş; ikincil akışlar (masa satışı, iade, bekleyen sipariş, ürün yönetimi/Excel/sayım) aynı sertleştirmeyi almamış — sistemik bir "eşit olmayan olgunluk" deseni var.

**2. En kritik 10 problem** (bkz. bölüm 3, Technical Debt için P0/P1 listesi) — özet: (1) 3 satış akışında (masa/iade/bekleyen-sipariş) şube stok payı güncellenmiyor, (2) conflict resolution transaction-data/master-data ayrımı yapmıyor, (3) restore sonrası bütünlük kontrolü yok, (4) `/vardiya /arama /bildirimler` route guard'sız, (5) reauth mekanizması 9 hassas işlemden sadece 2'sinde, (6) sync_queue release build'de sessizce hata yutuyor, (7) çok şubeli kasa mutabakat düzeltmesi şubeleri karıştırıyor, (8) Onay Merkezi/Vardiya Geçmişi filtresiz sınırsız büyüyor, (9) ürün yönetimi (Excel/sayım/fiyat) sync ile business-data aynı transaction'da değil, (10) yıl sonu arşiv hâlâ sadece kopyalama — aktif tablolardan silme yok.

**3. En kritik veri riski:** Şube stok payı senkronizasyonundaki 3 kopukluk (masa/iade/bekleyen-sipariş) — çok şubeli kurulumlarda zamanla birikimli sapma üretir, fark edilmesi zor.

**4. En kritik finans riski:** Çok şubeli kasa mutabakat düzeltmesinin (`hareketSil`/`bakiyeMutabakatYap`) şube ayrımını gözetmemesi — "düzelt" aksiyonu aslında veriyi bozabilir.

**5. En kritik sync riski:** LWW (last-write-wins) conflict resolution TÜM tablolara (transaction-data dahil) aynı şekilde uygulanıyor — madde 7'nin "transaction kayıtları immutable olmalı" kuralı kodda karşılığı yok.

**6. En kritik security riski:** `/vardiya`, `/arama`, `/bildirimler` route'ları hiçbir yetki koduna bağlı değil — deep-link ile kasa bakiyesi/müşteri listesi/satış toplamları yetkisiz görülebilir.

**7. En büyük UX problemi:** Onay Merkezi ve Vardiya Geçmişi ekranları filtre/sayfalama olmadan TÜM geçmişi tek sorguda çekiyor — yıllar içinde kullanışsız ve yavaş hale gelecek.

**8. En büyük performans problemi:** Excel import/export ana thread'de (ANR riski, 100.000+ kayıtta); `lot_seri` üzerinde index yok (FEFO sorgusu full-scan).

**9. En büyük mimari borç:** 27 ekran (%17) Riverpod→Service→Repository zincirini atlayıp doğrudan `Veritabani()` çağırıyor; ayrıca "hardening" refactor'ünün ürün yönetimi tarafına hiç yayılmamış olması.

**10. Modern ERP'ye ulaşmak için ana yol haritası:** bkz. bölüm 5 (Roadmap).

---

## 2. ERP GAP ANALYSIS

| MODÜL | MEVCUT | EKSİK | RİSK | ÖNERİ |
|---|---|---|---|---|
| Satış (Hızlı/Toptan/Masa) | 3 akış, karma ödeme, promosyon, FEFO | Masa+Bekleyen Sipariş şube-stok payı güncellemiyor | HIGH (çok şube) | `subeStokPayiUygula` çağrısını 3 akışa da ekle |
| İade (fiş/hızlı/manuel) | Merkezi `IadeIslemServisi`, lot-farkındalı (fişten) | Hiçbiri şube-stok payı güncellemiyor | HIGH | Aynı |
| Stok/Ürün yönetimi | Source-of-truth doğru (stok_hareket) | Excel/sayım/fiyat güncelleme sync ile aynı txn'de değil | HIGH | 4 metodu txn+SyncKuyrukYazici deseniyle sarmalayın |
| Cari/Kasa/Banka | Mutabakat motorları sağlam (tek şube) | Çok şubeli kasa düzeltme şube karıştırıyor; banka özeti is_deleted filtresiz | P1/P2 | Şube filtresi ekle |
| Sync/Offline | sync_queue kalıcı, atomik, backoff, idempotent (UNIQUE global_id) | Conflict resolution transaction/master ayrımı yok; release'de hata yutma | HIGH | Bkz. bölüm 3 |
| Yıl Sonu/Arşiv | Checkpoint tabanlı devir motoru, snapshot | Aktif tablolardan silme yok (sadece kopyalama); çoklu cihaz kilidi yok | MEDIUM | Kullanıcı kararı gerekli (mimari) |
| Güvenlik/Yetki | Route+widget guard çoğu ekranda, audit log sistematik | 3 route guard'sız; reauth 2/9; Ayarlar tek kod | HIGH | Bkz. bölüm 3 |
| Backup/Restore | Güvenli restore mekaniği (rollback, eski yedek temizleme) | Restore sonrası bütünlük/veri sağlığı kontrolü yok | HIGH | integrity_check + otomatik VeriSagligiServisi |
| Test | 87 dosya, gerçek şemaya karşı (mock değil) | Migration/upgrade testi yok; route-guard testi yok | MEDIUM | 2 yeni test sınıfı |
| Performans | Index kapsamı genel güçlü | Excel ana thread; lot_seri index yok | MEDIUM | compute()/Isolate + index |
| UX/UI | Design System (Ts*) olgun, çoğu ekranda benimsenmiş | Onay Merkezi/Vardiya listesi filtresiz; dashboard/vardiya grid tutarsız; 53 dosyada dark-mode'a duyarsız renk | MEDIUM | Bkz. bölüm 4 |
| Mimari | Riverpod→Service→Repository çoğu yerde | 27 ekran (%17) doğrudan DB erişimi | LOW (davranışsal değil) | Kademeli refactor |
| AI | Kesin salt-okunur doğrulandı | — | — | Sağlam |

---

## 3. TECHNICAL DEBT (öncelik sıralı)

### P0/P1 — Kritik (veri bütünlüğü / güvenlik / finansal doğruluk)
1. **[HIGH] Şube stok payı 3 akışta güncellenmiyor** — `lib/servisler/masa_odeme_servisi.dart`, `lib/servisler/iade_islem_servisi.dart` (5 fonksiyon), `lib/depolar/bekleyen_siparis_deposu.dart:265`. Çözüm: `subeStokPayiUygula` çağrısı eklemek (satis_tamamlama_servisi'ndeki desen). Migration yok, test gerekir.
2. **[HIGH] Çok şubeli kasa mutabakat düzeltmesi şube karıştırıyor** — `lib/depolar/kasa_deposu.dart:349-460` (`hareketSil`, `bakiyeMutabakatYap`, `bakiyeUyumsuzlukSayisi`). Çözüm: `_sonBakiyeTxn`'deki `sube_id` filtre desenini bu 3 fonksiyona da uygulamak.
3. **[HIGH] Ürün yönetimi sync-atomikliği eksik** — `lib/depolar/urun_deposu.dart` (`topluEkleGuncelle`, `guncelle`, `alisFiyatiGuncelle`), `lib/depolar/stok_deposu.dart` (`stokDuzelt`/Sayım Onayı). Çözüm: `db.transaction` + `SyncKuyrukYazici.ekleTxn` deseni.
4. **[HIGH] Conflict resolution'da master/transaction-data ayrımı yok** — `lib/veri/database/veritabani.dart:699-758` (`supaKayitlariGuncelle`). Tüm tablolar aynı LWW ile ezilir. Karar gerektirir — mimari değişiklik, kullanıcı onayı şart.
5. **[HIGH] Restore sonrası bütünlük/veri sağlığı kontrolü yok** — `lib/servisler/yedekleme_servisi.dart:96-198`. Çözüm: `PRAGMA integrity_check` + otomatik `VeriSagligiServisi` tetiklemesi.
6. **[HIGH] `/vardiya`, `/arama`, `/bildirimler` route guard'sız** — `lib/uygulama/router/uygulama_router.dart:286-359`. Çözüm: `_routeYetkiler` haritasına ekleme (küçük, düşük riskli).
7. **[HIGH] Reauth kapsamı 9 hassas işlemden 2'sinde** — `lib/widgetlar/ortak/yonetici_sifre_dialogu.dart`. Sadece cari/borç silmede kullanılıyor; kullanıcı silme, yedek geri yükleme, veritabanı temizleme kapsam dışı.
8. **[MEDIUM-HIGH] sync_queue release build'de hatayı sessizce yutuyor** — `lib/servisler/bulut/bulut_manager.dart:175-191` (`_kuyrukaYaz`, `kDebugMode` guard'lı catch). Çözüm: `LogServisi().hata()` ekleme.
9. **[HIGH] Onay Merkezi filtresiz sınırsız büyüyor** — `lib/servisler/onay_merkezi_servisi.dart:122-127` + `onay_merkezi_ekrani.dart:35`. Çözüm: varsayılan `sadeceGorulmemis:true` + tarih/LIMIT.

### P2 — Önemli
10. Banka özet `is_deleted` filtresi eksik (`banka_hareket_deposu.dart:187-206`).
11. Ayarlar alt-ekranları (yedek/sync/audit-log/GİB/log) tek 'ayarlar' koduna bağlı — granüler yetki yok.
12. Excel import/export ana thread'de (ANR riski 100.000+ kayıtta) — `excel_servisi.dart`.
13. `lot_seri(urun_id,aktif)` index yok — FEFO sorgusu full-scan.
14. Vardiya Geçmişi filtresiz büyüyor; Dashboard/Vardiya KPI grid'leri tablet'te tutarsız (bir kısmı `TsResponsive`, bir kısmı sabit `crossAxisCount:2`).
15. 53 dosyada `Colors.x.shade50` hard-code — koyu temada tutarsız görünüm.
16. `sube_urun` tablosunda FK yok (birleşik PK var).
17. Yıl sonu arşivleme sadece kopyalama — aktif tablolardan silme yok (aktif DB büyümeye devam eder). **Kullanıcı kararı gerekiyor** (mimari, geri dönüşü zor).
18. Devir motorunda çoklu cihaz kilidi yok.
19. Migration/upgrade testi ve route-guard coverage testi yok.
20. `stokDusTxn` clamp'inde `miktar` alanı düzeltilmiyor (nadir kenar durum, negatif stok engellenmiş sistemlerde).

### P3 — Kod kalitesi / kozmetik
21. `stok_fifo` tablosu tanımlı ama tamamen kullanılmayan ölü tablo.
22. RLS politikaları hiç kaynak kontrolünde değil (sadece canlı Supabase panelinde).
23. God-class adayları: `dashboard_ekrani.dart` (1663 satır), `borc_dashboard_ekrani.dart` (1370), `fatura_detay_ekrani.dart` (1323), `cari_detay_paneli.dart` (1315), `urun_liste_ekrani.dart` (1204).
24. 27 ekranda (%17) doğrudan `Veritabani()`/`db.rawQuery` erişimi — Riverpod→Service→Repository atlanıyor.
25. Design System'de `TsDialog`/`TsBottomSheet`/`TsChart` bileşenleri yok — dialog radius/padding elle tekrarlanıyor.
26. Devir doğrulaması checksum değil COUNT+SUM (pratikte yeterli, kriptografik değil).

---

## 4. UX/UI GAP ANALYSIS (öne çıkanlar)

| Ekran | Mevcut | Problem | Modern Tasarım | Öncelik |
|---|---|---|---|---|
| Onay Merkezi | Tüm kayıtları tek sorguda çeker | Filtre/sayfalama yok, yıllar içinde şişer | Varsayılan "görülmemiş", tarih aralığı + LIMIT | P1 |
| Vardiya (Geçmiş sekmesi) | Filtresiz tam liste | Aynı büyüme riski | Ay/tarih filtresi + sayfalama | P2 |
| Dashboard + Vardiya KPI grid'leri | Kısmen `TsResponsive` | Tablet'te bir kısmı sabit 2 sütun kalıyor | Tüm KPI grid'lerini `TsResponsive.izgaraKolonSayisi`'ye taşı | P2 |
| 53 ekran (durum bandı/uyarı) | `Colors.x.shade50` hard-code | Dark mode'da tutarsız/parlak kutu | `TsRenk.zemin()`'e geçiş | P2 |
| Design System | Ts* bileşenleri olgun ve benimsenmiş | Dialog/BottomSheet/Chart resmi bileşen değil | `TsDialog`, ince `TsChart` sarmalayıcı ekle | P3 |
| Vardiya liste satırları | `Text` overflow tanımsız | 360px'te taşma riski | `Expanded`+`ellipsis` | P3 |

**Onay Merkezi ve Veri Sağlığı ekranları** loading/empty/error state kullanımında referans kalitede — iyi örnek olarak not edildi.

**Dashboard sorgusu (Madde 9):** KPI seti kapsamlı (ciro/kâr/marj/alacak-borç), ama saatlik satış grafiği, kasiyer/şube karşılaştırması hâlâ yok — "yönetici hangi saatte/kimde" sorusuna cevap veremiyor.

---

## 5. MODERN ERP ROADMAP

**FAZ 1 — Kritik veri/güvenlik (P0/P1, hızlı ve düşük riskli):**
- Şube stok payı 3 akışa ekleme, kasa mutabakat şube filtresi, route guard 3 eksik, sync_queue log ekleme, Onay Merkezi filtre — hepsi migration'sız, izole, test edilebilir.

**FAZ 2 — Finansal bütünlük:**
- Ürün yönetimi sync-atomikliği, banka özet filtresi, reauth kapsamını genişletme.

**FAZ 3 — Sync/Conflict mimarisi (kullanıcı kararı gerekli):**
- Transaction-data/master-data conflict resolution ayrımı — büyük mimari karar, önce plan sunulmalı.

**FAZ 4 — Devir/Arşiv (kullanıcı kararı gerekli):**
- Aktif tablolardan arşivlenmiş kayıtların çıkarılması (geri dönüşü zor) + çoklu cihaz kilidi.

**FAZ 5 — Performans:**
- Excel işlemlerini Isolate'e taşıma, `lot_seri` index'i.

**FAZ 6 — UX/UI:**
- Onay Merkezi/Vardiya filtreleme+sayfalama, grid tutarlılığı, dark-mode renk geçişi, TsDialog/TsChart.

**FAZ 7 — Modern ERP özellikleri (yeni, roadmap'te olmayan):**
1. Kritik stok/SKT için OS-seviyesi push bildirimi (paket zaten kurulu, tetikleyici yok) — P2
2. Ayarlar alt-ekranlarına granüler yetki kodu (yedek/sync/audit-log/GİB ayrı) — P1 (güvenlik)
3. Personel Performans/Satış Karnesi (kasiyer bazlı) — P2
4. Bekleyen/tamamlanmayan fiş analizi ("sepet terk") — P3
5. Tedarikçiye ödeme vade takibi/uyarısı — P2
6. Mimari katman temizliği (27 ekranın DB erişimini repository'ye taşıma) — P3, kademeli

---

## 6. SON KONTROL (Madde 32 self-check)

- **Kendim yeni problem keşfettim mi, yoksa sadece söyleneni mi aradım?** Evet — bu turun bulgularının ezici çoğunluğu (şube-stok payı 3 akış, çok şubeli kasa mutabakatı, route guard boşlukları, Onay Merkezi büyümesi, ürün yönetimi sync-atomikliği, restore sonrası kontrol eksikliği) önceki 60+ commit'lik hiçbir oturumda raporlanmamıştı.
- **Finansal veri kaybı mümkün mü?** Doğrudan para kaybı riski düşük (mutabakat motorları hâlâ devrede) ama **çok şubeli kurulumlarda** kasa/stok raporlarının sessizce sapması mümkün — bu, "veri kaybı" değil "veri sapması" riski, fark edilmesi zor olduğu için ayrıca ciddi.
- **Sync güvenilir mi?** Temel mekanik (kalıcı kuyruk, atomiklik, idempotency, backoff) sağlam. Conflict resolution'daki transaction/master ayrımının eksikliği teorik bir risk — nadir senaryoda (aynı satır iki cihazdan güncellenirse) veri kaybı üretebilir.
- **Yıl sonu devir gerçekten güvenli mi?** Snapshot/checkpoint/doğrulama sağlam ama arşivin "sadece kopyalama" olması nedeniyle asıl hedeflerden biri (aktif DB'yi küçültme) karşılanmıyor — güvenli ama eksik.
- **DB yıllar içinde kontrolsüz büyür mü?** Evet, yukarıdaki nedenle.
- **10 kat veri olduğunda uygulama çalışır mı?** Genel index kapsamı iyi; Excel ve Onay Merkezi/Vardiya listesi gibi noktalarda hayır.
- **Bir sistem yöneticisi backup'a güvenebilir mi?** Şu an HAYIR net değil — restore mekanizması güvenli ama "sonrasında her şey doğru mu" sorusuna otomatik cevap vermiyor.
- **Bu gerçekten modern bir ERP mi, yoksa büyümüş bir CRUD mu?** Modern ERP'ye çok yakın — mutabakat motorları, onay akışları, AI analiz derinliği, tasarım sistemi hepsi "büyümüş CRUD" seviyesinin üstünde. Kalan boşluklar nokta-atışı (belirli akışlarda sertleştirme eksikliği), sistemik bir zayıflık değil.

---

## 7. PUANLAMA (10 üzerinden)

| Alan | Puan | Not |
|---|---|---|
| Security | 6.5 | Auth/audit sağlam, route-guard boşlukları + reauth kapsamı dar |
| Architecture | 7 | Katmanlar net ama %17 ekranda ihlal |
| Database | 7.5 | Index/constraint güçlü, birkaç tablo FK/index eksik |
| Sync | 6.5 | Mekanik sağlam, conflict-resolution kavramsal eksik |
| POS | 7.5 | Zengin akış, şube-stok payı 3 kopukluk |
| Stock | 7.5 | Source-of-truth doğru, ürün yönetimi tarafı eski desen |
| Cari | 8 | Mutabakat/360/risk merkezi olgun |
| Finance | 7 | Genel sağlam, çok şubeli kasa mutabakatı hatası |
| ERP (kapsam) | 8.5 | Roadmap'in ezici çoğunluğu gerçekten mevcut |
| UX | 7 | Design system olgun, 2 ekranda ölçeklenmezlik |
| Testing | 6.5 | Gerçek şemaya karşı test var, migration/guard testi yok |
| Performance | 7 | Index iyi, Excel/lot_seri istisna |
| **GENEL** | **7.3 / 10** | Production-yakın, nokta-atışı sertleştirme gerekiyor |

---

*Bu rapor kod değiştirmeden hazırlanmıştır (Madde 30 kuralı). Uygulamaya geçiş için önce FAZ 1'in onaylanması bekleniyor.*
