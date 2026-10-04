# Elle Test Listesi (Windows kasa PC + telefon)

Her madde: **Yap → Beklenen**. Sorun çıkarsa ekran görüntüsü + tam hata metni gönder.
Veriler deneme verisi olduğu sürece yıkıcı testler serbest.

## A. Hızlı Satış
1. Bir ürün okut, arama kutusuna `*5` yaz, Enter → ürünün miktarı mevcut miktar + 5 olur; kutu temizlenir, odak kutuda kalır.
2. Aynı ürün için art arda `*3`, `*2` → her seferinde eklenir (2 → 5 → 7 …).
3. Sepet boşken `*3` Enter → "Sepet boş" uyarısı.
4. `*0`, `*abc`, `*-2`, `*100000` → "Geçersiz miktar" uyarısı, sepet değişmez.
5. Kg'lı ürün okut, `*0,5` Enter → 0,5 kg eklenir.
6. İki farklı ürün okut, `*2` → yalnız EN ÜSTTEKİ (son okutulan) ürün değişir.
7. Ürünün fiyatına elle indirim uygula, sonra `*2` → indirimli fiyat korunur.
8. Normal barkod okutma, ürün adı arama, F1 (Nakit bitir) ve F12 hâlâ çalışıyor.

## B. Excel İçe/Dışa Aktarma
9. Ürün Excel'ini dışa aktar, aynı dosyayı içe aktar → "güncellenen" sayısı doğru, hata yok.
10. Excel'de bir fiyatı `1,234.50` ve bir başkasını `1.234,50` olarak yaz → ikisi de 1234,50 okunur.
11. KDV sütununa `%18`, `18,0` ve yüzde biçimli hücre (0,18) gir → hepsi 18 olur.
12. "Eski Fiyat Tarih" sütununa `31.12.2025` yaz → tarih okunur.
13. Cari, İade, Promosyon, Günsonu, Stok Sayım Excel'lerini bir kez dışa + içe aktar (bölünmüş dosyalar: hepsi eskisi gibi çalışmalı).

## C. Raporlar
14. Ürün Raporu → Satış sekmesi: bilinen bir günün toplamını Satış Raporu / Gün Sonu ile karşılaştır (ciro aynı, iade farkı hariç).
15. Eski (aylar öncesi) bir satış içeren aralıkta Kâr değeri makul mü (maliyet 0 görünmemeli).
16. Alım sekmesi: kısmi teslim alınan siparişte tutar = teslim edilen miktar × birim fiyat.
17. Arama kutusuna `biskrem`, `cikolata`, büyük harfli `BİSKREM` yaz (Ürün Raporu + Stok Raporu) → aynı ürün bulunur.
18. Şube seçiliyken Ürün Raporu yalnız o şubenin satışını gösterir.

## D. Yazdırma (bölünmüş dosya — mutlaka bir kez dene)
19. Satış fişi yazdır (nakit).
20. Cari tahsilat makbuzu yazdır.
21. Fatura yazdır.
22. Test fişi yazdır.
23. Raf etiketi yazdır (ZPL ve/veya ESC/POS) + kasa çekmecesi aç.

## E. İade (bölünmüş dosya)
24. Fiş kalemi iade et (nakit) → stok artar, kasa düşer.
25. Cari ödeme yöntemiyle iade → cari bakiye azalır.
26. Oturumdaki bir iadeyi sil, bir iadeyi düzenle.
27. Geçmiş fiş iadesini sil → kasa/stok/cari geri döner.

## F. Senkron (bölünmüş sabit tablolar)
28. Ayarlar → Bulut: "Buluta Gönder" → hata yok.
29. İkinci cihazda "Buluttan Al" → ürün/cari/satış sayıları eşit.
30. Aynı kaydı iki cihazda düzenleme → Sync Çakışmaları ekranında sahte çakışma çıkmıyor.

## G. Windows Masaüstü Görünümü
31. 24" ekranda pencere tam ekran açılır; arayüz ölçeği (büyütme) okunaklı, taşma yok.
32. Banka, Borç ve Ürün Kayıt ekranları: F-tuşları, Tab sırası, iki sütunlu ürün formu.
33. Hızlı Satış ödeme pencerelerini yalnızca klavyeyle kullan (Tab/Enter/Esc).

## H. Güvenlik (senin tarafında)
34. Supabase service anahtarını yenile (sohbete yapıştırılmıştı).
35. İşletme hesabı SQL adımlarının sonucunu kontrol et (giriş çalışıyor mu).
