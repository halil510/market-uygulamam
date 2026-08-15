# MarketPlus - Veri Transfer & Senkronizasyon Mimarisi

## SENARYO 1: Cihaz ↔ Cihaz (WiFi LAN - Çevrimdışı)

### Mevcut Durum (ÇALIŞIYOR)
- `SyncServisi` → HTTP sunucu (port 8080) başlatılır
- `SyncEkrani` → IP gir → ping → tablo seç → çek/gönder
- Conflict: global_id > barkod/cari_kodu > fis_no sırasıyla
- PRAGMA foreign_keys = OFF sırasında import

### Nasıl Kullanılır
1. Cihaz A: Sync → Sunucu Başlat → IP göster (192.168.1.x:8080)
2. Cihaz B: Sync → Bağlan → IP gir → Tablo seç → Çek/Gönder
3. Otomatik conflict: last_updated kazanır

### Genişletme İmkânı
- QR ile IP paylaşımı (eklenebilir)
- Otomatik keşif (mDNS/Bonjour - dart:io ile)
- Seçici alan sync (sadece stok, sadece fiyat)

---

## SENARYO 2: Bilgisayar (PC) Sync

### A) USB/ADB (En Kolay, Ücretsiz)
```
flutter run → adb ile PC'ye bağla
adb forward tcp:8080 tcp:8080
PC tarayıcısından http://localhost:8080/api/ping
```

### B) Windows/Mac Masaüstü Uygulaması
```
flutter build windows → PC'de çalışır
Aynı MarketPlus → Sunucu başlat
Telefon bağlanır
```

### C) REST API + PC Web Paneli (Gelişmiş)
- PC'de küçük Python/Node sunucu
- MarketPlus API endpoint'lerini çağırır
- Excel/ERP entegrasyonu

---

## SENARYO 3: Online Bulut Sync

### A) Firebase (En Hızlı)
- cloud_firestore paketi
- Realtime sync
- Ücretli (Firestore free tier: 50K okuma/gün)

### B) Supabase (PostgreSQL, Açık Kaynak)
- supabase_flutter paketi
- Free tier: 500MB DB
- Row Level Security

### C) Kendi Sunucu (En Esnek)
- VPS: DigitalOcean/Hetzner ~5$/ay
- Backend: FastAPI (Python) veya Node.js
- MarketPlus → HTTP POST/GET

### D) PocketBase (Tavsiye Edilen)
- Tek binary, kendi sunucu
- Flutter SDK var
- SQLite tabanlı, kolay kurulum
- Ücretsiz self-hosted

### Sync Stratejisi
1. Her kayıt global_id (UUID) taşır (MEVCUT)
2. last_updated timestamp ile çakışma çözümü (MEVCUT)
3. Offline queue: sync_queue tablosu (MEVCUT)
4. Online'a gelince queue flush

---

## ETİKET TASARIM GENİŞLETME

### Mevcut
- EtiketBoyut: küçük/orta/büyük
- ESC/POS komutları
- Barkod/QR seçimi
- Fiyat/ad toggle

### Eklenebilir
- Şablon kaydetme (5-10 custom şablon)
- Logo/görsel ekleme (image paketi ile)
- Özel alanlar (üretim tarihi, SKT, lot no)
- A4 PDF etiket sayfası (printing ile)
- 4x6cm kargo etiketi
- Seri baskı (lot/SKT'ye göre değişken)

### Fiş Tasarım Genişletme
- HTML template → PDF (pdf paketi ile MEVCUT)
- Dinamik bölümler (drag-drop - gelişmiş)
- Şablon kaydetme
- Çoklu dil desteği
