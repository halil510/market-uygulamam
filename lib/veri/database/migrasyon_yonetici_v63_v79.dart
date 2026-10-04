// lib/veri/database/migrasyon_yonetici_v63_v79.dart
// migrasyon_yonetici.dart'ın parçası — v63→v79 arası migrasyonlar. Önceden
// migrasyon_yonetici_v36_v63.dart içindeydi; fonksiyonlar BİREBİR aynı,
// çalışma sırası migrasyon_yonetici.dart içindeki sürüm kontrollerine bağlı
// (dosya sırasına değil), bu yüzden taşıma sırayı etkilemez.
part of 'migrasyon_yonetici.dart';

// v63'ten v64'e — fis_seri (fiş/irsaliye/sipariş numara sayacı) artık
// buluta senkronize oluyor.
//
// 🔴 Derin analizde bulundu: fis_seri tablosu senkron sisteminin
// TAMAMEN DIŞINDAYDı (global_id/last_updated hiç yoktu, ne push ne pull
// yolunda hiç göründü) — aynı şubede birden fazla POS cihazı kullanılan
// kurulumlarda her cihaz kendi lokal sayacını tutuyordu, biri diğerinin
// ürettiği numaralardan habersizdi. son_fis_no bir SAYAÇ olduğu için bu
// tabloyu projenin standart global_id tabanlı, "son güncelleme kazanır"
// senkron yoluna sokmak YANLIŞ olur: iki cihaz aynı şubede farklı
// zamanlarda senkron olursa, geç senkron olan cihazın DAHA KÜÇÜK yerel
// sayacı, buluttaki DAHA BÜYÜK sayacın üzerine yazıp aynı numaraların
// tekrar üretilmesine yol açabilirdi. last_updated eklendi (yalnızca
// push zamanlaması için); asıl güvenlik MAX-birleştirme'de —
// bkz. veritabani.dart.fisNoUret() ve _fisSeriBulutlaUyumla().
Future<void> _v63denV64e(Database db) async {
  await _calistir(db, 'ALTER TABLE fis_seri ADD COLUMN last_updated TEXT');
}

// ==================== v64 -> v65 ====================
// MASTER ERP DEEP AUDIT — Madde 5 (Senkronizasyon) sertleştirmesi:
// 'sync_queue' tablosu ÖNCEDEN de kuruluyordu (bkz. sync_semasi.dart) ama
// hiçbir kod ona yazmıyordu — gerçek kuyruk BulutManager._kuyruk adlı
// RAM-only bir listeydi, uygulama çökerse henüz gönderilmemiş kayıtlar
// kalıcı olarak kayboluyordu. BulutManager artık bu tabloyu tek kaynak
// olarak kullanıyor; 'hata_mesaji' son başarısız deneme mesajını
// görünür kılmak için eklendi (taze kurulumlar zaten sync_semasi.dart
// üzerinden bu kolonla geliyor — bu migrasyon SADECE mevcut cihazlar
// içindir).
Future<void> _v64denV65e(Database db) async {
  await _calistir(db, 'ALTER TABLE sync_queue ADD COLUMN hata_mesaji TEXT');
}

// ==================== v65 -> v66 ====================
// MASTER ERP DEEP AUDIT — Madde 3 (Veritabanı Denetimi): "kritik hareket
// tabloları" (satış/stok/cari/kasa/iade/fatura/tedarik/vardiya) PRIMARY
// KEY/global_id/UNIQUE/last_updated/is_deleted/deleted_at/sube_id
// açısından tarandı — bu alanların hepsi zaten mevcuttu. Bulunan GERÇEK
// eksikler INDEX tarafındaydı: bu tablolardaki en sık çalışan sorgu
// kalıpları (kasa bakiye hesabı, iade/fatura/irsaliye detay ekranları,
// tedarikçi sipariş listesi, vardiya aktif/geçmiş sorgusu) hiç
// indekslenmemiş sütunlarda filtreleme yapıyordu — veri büyüdükçe tam
// tablo taraması (full table scan) kaçınılmazdı. Liste, taze kurulum
// tarafının (IndexSemasi._indeksler) BİREBİR aynısıdır — bkz. o
// dosyadaki "Madde 3" notu.
//
// 🔴 BİLİNÇLİ OLARAK YAPILMAYAN: yeni FOREIGN KEY eklenmedi. İki sebep:
// (1) SQLite ALTER TABLE'ın kendisi mevcut bir tabloya FK constraint
// eklemeyi DESTEKLEMEZ (tablo yeniden oluşturulup veri kopyalanmadan
// mümkün değil — "mevcut verileri bozmadan güvenli" ilkesiyle çelişir).
// (2) Bu kod tabanında (bkz. SatisDeposu.satisEkleTxn'deki cari_id/
// sube_id/kasiyer_id doğrulama notu) FK ihlalleri ÇOK ŞUBELİ/ÇOK
// CİHAZLI SENKRONDA gerçek production hatalarına yol açtığı için
// KASITLI OLARAK stok_hareket/kasa_hareketleri gibi tablolarda hareket
// satırlarının referans kolonlarına hiç FK konulmamış — bir cihazda
// henüz senkronlanmamış bir kullanıcı/şube/lot'a referans veren bir
// hareket, FK varsa INSERT anında patlar. Yeni FK eklemek bu bilinçli
// tasarımı bozar ve aynı hata sınıfını yeniden üretir.
Future<void> _v65denV66ya(Database db) async {
  const indeksler = [
    'CREATE INDEX IF NOT EXISTS idx_kasa_sube_silinmemis ON kasa_hareketleri(sube_id, deleted_at)',
    'CREATE INDEX IF NOT EXISTS idx_kasa_referans ON kasa_hareketleri(referans_id, referans_turu)',
    'CREATE INDEX IF NOT EXISTS idx_stokh_referans ON stok_hareket(referans_id, referans_turu)',
    'CREATE INDEX IF NOT EXISTS idx_carih_fis ON cari_hareket(fis_id, cari_id)',
    'CREATE INDEX IF NOT EXISTS idx_iade_kalem_iade ON iade_kalem(iade_id)',
    'CREATE INDEX IF NOT EXISTS idx_fatura_detay_fatura ON fatura_detaylari(fatura_id)',
    'CREATE INDEX IF NOT EXISTS idx_irsaliye_kalem_irsaliye ON irsaliye_kalem(irsaliye_id)',
    'CREATE INDEX IF NOT EXISTS idx_tedsip_durum ON tedarikci_siparisler(durum)',
    'CREATE INDEX IF NOT EXISTS idx_tedsip_cari ON tedarikci_siparisler(cari_id)',
    'CREATE INDEX IF NOT EXISTS idx_tedsip_kalem_siparis ON tedarikci_siparis_kalem(siparis_id)',
    'CREATE INDEX IF NOT EXISTS idx_vardiya_sube_kapanis ON vardiyalar(sube_id, kapanis_tarihi)',
    'CREATE INDEX IF NOT EXISTS idx_vardiya_kullanici ON vardiyalar(kullanici_id)',
  ];
  for (final sql in indeksler) {
    await _calistir(db, sql);
  }

  // 'vardiyalar' tablosunda deleted_at/is_deleted hiç yoktu — Madde 3
  // kontrol listesinin istediği soft-delete alanı tamamlandı. Şu an
  // hiçbir kod bir vardiyayı silmiyor (audit amaçlı kalıcı kayıt) — bu
  // sütun ileride bir "yanlışlıkla açılan vardiyayı iptal et" özelliği
  // için hazırlık, nullable olduğu için mevcut hiçbir sorguyu etkilemez.
  await _calistir(db, 'ALTER TABLE vardiyalar ADD COLUMN deleted_at DATETIME');
}

// ==================== v66 -> v67 ====================
// MASTER ERP DEEP AUDIT — Madde 25/26 (Performans / Database Index
// Audit): cari_hareket_ekrani.dart (cari ekstre ekranı) doğrudan
// Veritabani().db üzerinden 'SELECT * FROM cari_hareket WHERE cari_id=?
// AND is_deleted=0 ORDER BY tarih DESC' çalıştırıyordu — HİÇ LIMIT yoktu
// ve mevcut ayrı cari_id/is_deleted indeksleri bu bileşik sorguyu tek
// geçişte karşılamıyordu. Ekran artık CariDeposu.hareketleriniGetir()
// (mevcut, sınırlı/parametrik repository metodu) üzerinden güvenli bir
// tavanla (5000) çağırıyor; bu bileşik indeks o sorguyu (ve aynı deseni
// kullanan her yeri) hızlandırır.
Future<void> _v66danV67ye(Database db) async {
  await _calistir(db,
      'CREATE INDEX IF NOT EXISTS idx_carih_cari_silinmemis_tarih ON cari_hareket(cari_id, is_deleted, tarih)');
}

// ==================== v67 -> v68 ====================
// YIL SONU DEVİR / DÖNEM KAPATMA / ARŞİVLEME SİSTEMİ — FAZ 1 (2026-09-16,
// kullanıcı onaylı mimari plan raporu). Mevcut kurulumlar için 7 yeni
// tablo — tanımlar donem_semasi.dart (fresh install) ile BİREBİR aynı,
// tek doğruluk kaynağı orası; buradaki SQL'ler o dosyadan kopyalanmıştır.
// Devir motoru mantığı (DevirYoneticiServisi) İLERİKİ bir fazda gelecek —
// bu migrasyon SADECE şemayı hazırlar.
Future<void> _v67denV68e(Database db) async {
  await _calistir(db, '''
    CREATE TABLE IF NOT EXISTS donemler (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      global_id TEXT UNIQUE,
      donem_yili INTEGER NOT NULL UNIQUE,
      baslangic_tarihi TEXT NOT NULL,
      bitis_tarihi TEXT NOT NULL,
      durum TEXT NOT NULL DEFAULT 'OPEN',
      kapanis_tarihi TEXT,
      kapanisi_yapan_kullanici_id INTEGER,
      kapanis_cihazi TEXT,
      backup_durumu TEXT NOT NULL DEFAULT 'bekliyor',
      arsiv_durumu TEXT NOT NULL DEFAULT 'bekliyor',
      devir_durumu TEXT NOT NULL DEFAULT 'bekliyor',
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      last_updated TEXT
    )
  ''');
  await _calistir(db,
      'CREATE INDEX IF NOT EXISTS idx_donem_yili ON donemler(donem_yili)');
  await _calistir(db,
      'CREATE INDEX IF NOT EXISTS idx_donem_durum ON donemler(durum)');

  await _calistir(db, '''
    CREATE TABLE IF NOT EXISTS donem_sube_durumlari (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      global_id TEXT UNIQUE,
      donem_id INTEGER NOT NULL,
      sube_id INTEGER NOT NULL,
      durum TEXT NOT NULL DEFAULT 'OPEN',
      kapanis_tarihi TEXT,
      kapanisi_yapan_kullanici_id INTEGER,
      kapanis_cihazi TEXT,
      backup_durumu TEXT NOT NULL DEFAULT 'bekliyor',
      arsiv_durumu TEXT NOT NULL DEFAULT 'bekliyor',
      devir_durumu TEXT NOT NULL DEFAULT 'bekliyor',
      last_updated TEXT,
      UNIQUE(donem_id, sube_id)
    )
  ''');
  await _calistir(db,
      'CREATE INDEX IF NOT EXISTS idx_donemsube_donem ON donem_sube_durumlari(donem_id)');

  await _calistir(db, '''
    CREATE TABLE IF NOT EXISTS devir_checkpoint (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      global_id TEXT UNIQUE,
      devir_id TEXT NOT NULL UNIQUE,
      kaynak_donem_id INTEGER NOT NULL,
      hedef_donem_id INTEGER NOT NULL,
      sube_id INTEGER NOT NULL DEFAULT 0,
      durum TEXT NOT NULL DEFAULT 'INIT',
      mevcut_faz INTEGER NOT NULL DEFAULT 0,
      faz_ilerleme_json TEXT,
      baslangic_zamani TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      son_guncelleme TEXT,
      tamamlanma_zamani TEXT,
      hata_mesaji TEXT,
      last_updated TEXT,
      UNIQUE(kaynak_donem_id, hedef_donem_id, sube_id)
    )
  ''');
  await _calistir(db,
      'CREATE INDEX IF NOT EXISTS idx_devir_durum ON devir_checkpoint(durum)');

  await _calistir(db, '''
    CREATE TABLE IF NOT EXISTS stok_kapanis_snapshot (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      global_id TEXT UNIQUE,
      devir_id TEXT NOT NULL,
      donem_id INTEGER NOT NULL,
      sube_id INTEGER NOT NULL,
      urun_id INTEGER NOT NULL,
      miktar REAL NOT NULL,
      kaynak_hash TEXT,
      olusturma_tarihi TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      last_updated TEXT,
      UNIQUE(donem_id, sube_id, urun_id)
    )
  ''');
  await _calistir(db,
      'CREATE INDEX IF NOT EXISTS idx_stoksnap_donem ON stok_kapanis_snapshot(donem_id, sube_id)');

  await _calistir(db, '''
    CREATE TABLE IF NOT EXISTS cari_kapanis_snapshot (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      global_id TEXT UNIQUE,
      devir_id TEXT NOT NULL,
      donem_id INTEGER NOT NULL,
      cari_id INTEGER NOT NULL,
      bakiye REAL NOT NULL,
      kaynak_hash TEXT,
      olusturma_tarihi TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      last_updated TEXT,
      UNIQUE(donem_id, cari_id)
    )
  ''');
  await _calistir(db,
      'CREATE INDEX IF NOT EXISTS idx_carisnap_donem ON cari_kapanis_snapshot(donem_id)');

  await _calistir(db, '''
    CREATE TABLE IF NOT EXISTS kasa_kapanis_snapshot (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      global_id TEXT UNIQUE,
      devir_id TEXT NOT NULL,
      donem_id INTEGER NOT NULL,
      sube_id INTEGER NOT NULL,
      bakiye REAL NOT NULL,
      kaynak_hash TEXT,
      olusturma_tarihi TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      last_updated TEXT,
      UNIQUE(donem_id, sube_id)
    )
  ''');
  await _calistir(db,
      'CREATE INDEX IF NOT EXISTS idx_kasasnap_donem ON kasa_kapanis_snapshot(donem_id)');

  await _calistir(db, '''
    CREATE TABLE IF NOT EXISTS banka_kapanis_snapshot (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      global_id TEXT UNIQUE,
      devir_id TEXT NOT NULL,
      donem_id INTEGER NOT NULL,
      banka_hesap_id INTEGER NOT NULL,
      bakiye REAL NOT NULL,
      kaynak_hash TEXT,
      olusturma_tarihi TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      last_updated TEXT,
      UNIQUE(donem_id, banka_hesap_id)
    )
  ''');
  await _calistir(db,
      'CREATE INDEX IF NOT EXISTS idx_bankasnap_donem ON banka_kapanis_snapshot(donem_id)');
}

// Madde 12 denetimi (2026-09-16, kullanıcı onaylı UX: "Anında PIN
// onayı") — Kasa Kapanış'ta "Müdür Onayı" alanı. Vardiyayı kapatan
// kişi Müdür/Admin değilse, kapanış anında bir yöneticinin kimlik
// bilgileriyle (KullaniciDeposu.girisKontrol) onayladığı kullanıcı
// burada kaydedilir — Müdür/Admin kendi vardiyasını kapatırken bu
// adım atlanır (zaten yetkili).
Future<void> _v68denV69a(Database db) async {
  await _calistir(
      db, 'ALTER TABLE vardiyalar ADD COLUMN onaylayan_kullanici_id INTEGER');
  await _calistir(
      db, 'ALTER TABLE vardiyalar ADD COLUMN onaylanma_tarihi TEXT');
}

// v69'dan v70'e — Yıl Sonu Devir çoklu cihaz kilidi (2026-09-21,
// kullanıcı onayı, FAZ 4). Tanım donem_semasi.dart (fresh install) ile
// BİREBİR aynı, tek doğruluk kaynağı orası.
Future<void> _v69danV70e(Database db) async {
  await _calistir(db, '''
    CREATE TABLE IF NOT EXISTS donem_kilit (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      global_id TEXT UNIQUE,
      donem_id INTEGER NOT NULL,
      sube_id INTEGER NOT NULL DEFAULT 0,
      cihaz_id TEXT NOT NULL,
      kilit_zamani TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      son_yenileme TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      last_updated TEXT,
      UNIQUE(donem_id, sube_id)
    )
  ''');
  await _calistir(db,
      'CREATE INDEX IF NOT EXISTS idx_donemkilit_donem ON donem_kilit(donem_id)');
}

// v70'den v71'e — DEEP_AUDIT_REPORT FAZ 5 (Performans, 2026-09-21):
// FEFO satış düşümü lot_seri'de hiç indekslenmemiş bir sorgu
// çalıştırıyordu (bkz. index_semasi.dart'taki aynı gerekçe — o dosya
// sadece TAZE kurulumları kapsar, mevcut cihazlar için bu migrasyon
// gerekli).
Future<void> _v70denV71e(Database db) async {
  await _calistir(db,
      'CREATE INDEX IF NOT EXISTS idx_lot_seri_urun_aktif ON lot_seri(urun_id, aktif)');
}

// v71'den v72'ye — DEEP_AUDIT (kendi-keşif turu, 2026-09-21): cari
// hareket iptali ÖNCEDEN sadece kasa (nakit) tarafını bulup tersine
// çevirebiliyordu — banka_hareketler/kredi_karti_hareket'te bunu
// mümkün kılacak referans_id/referans_turu kolonu hiç yoktu (bilinçli,
// dokümante edilmiş bir sınırlamaydı — bkz. CariDeposu.hareketIptalEt
// eski yorumu). Artık ekleniyor.
Future<void> _v71denV72ye(Database db) async {
  await _calistir(
      db, 'ALTER TABLE banka_hareketler ADD COLUMN referans_id INTEGER');
  await _calistir(
      db, 'ALTER TABLE banka_hareketler ADD COLUMN referans_turu TEXT');
  await _calistir(
      db, 'ALTER TABLE kredi_karti_hareket ADD COLUMN referans_id INTEGER');
  await _calistir(
      db, 'ALTER TABLE kredi_karti_hareket ADD COLUMN referans_turu TEXT');
  await _calistir(db,
      'CREATE INDEX IF NOT EXISTS idx_banka_hareket_referans ON banka_hareketler(referans_turu, referans_id)');
  await _calistir(db,
      'CREATE INDEX IF NOT EXISTS idx_kk_hareket_referans ON kredi_karti_hareket(referans_turu, referans_id)');
}

// v72'den v73'e — kullanıcı bulgusu (2026-09-21, ekran görüntüleri):
// Veritabani._cakismaKorumasiUygula() bir 'satislar' fis_no çakışmasını
// '<fis_no>-SYNC<kısaId>' diye yeniden adlandırıp AYRI bir satır olarak
// eklediğinde (bkz. o fonksiyonun yorumu — TİPİK TETİKLEYİCİ: "Veritabanını
// Temizle" sonrası bulut hâlâ eski veriyi barındırıyorsa), bu satır Satış
// Listesi'nde VE Gün Sonu Raporu'nda sıradan, tam değerli bir satış gibi
// görünüp toplamları şişiriyordu — kullanıcı ekran görüntüsünde ₺90'lık
// TEK satışın Gün Sonu'nda ₺180 Cari Satış olarak göründüğünü bildirdi.
// Bu sütun, böyle bir satırı normal listelerden AYIRT ETMEK için eklendi
// — veri KAYBEDİLMİYOR (satır hâlâ DB'de, cari/stok/kasa etkisi hâlâ
// geçerli), sadece "incelenmeli" olarak işaretlenip Satış Listesi/Gün
// Sonu'ndan varsayılan olarak gizleniyor; kullanıcı Sync Çakışmaları
// ekranından gerçek/kopya olduğuna karar verebiliyor.
Future<void> _v72denV73e(Database db) async {
  await _calistir(db,
      'ALTER TABLE satislar ADD COLUMN sync_cakisma_kopyasi INTEGER NOT NULL DEFAULT 0');
}

// v73'ten v74'e — kullanıcı bulgusu ("tam ERP oldu mu, başka hata var
// mı" sorusuna cevaben yapılan denetim, 2026-09-22): 'sube_urun' (şube
// bazlı stok payı) tablosunda hiç FOREIGN KEY yoktu — composite PK
// (urun_id, sube_id) dışında hiçbir bütünlük garantisi yoktu, bir ürün
// veya şube hard-delete edilse (ya da bozuk bir senkron satırı gelse)
// yetim satırlar sessizce birikebilirdi. SQLite mevcut bir tabloya
// ALTER TABLE ile FK ekleyemediğinden standart "yeniden oluştur" deseni
// kullanılıyor: yeniden adlandır → FK'lı yeni tabloyu oluştur → SADECE
// hem ürünü hem şubesi hâlâ var olan satırları kopyala (var olan yetim
// satırlar — varsa — sessizce ATLANIR, veri kaybı riski taşıyan bir
// silme değil, zaten anlamsız satırların yeni şemaya taşınmaması) →
// eskiyi sil → indeksleri yeniden kur. Taze kurulumlar için aynı FK'lar
// StokSemasi.olustur()'a da eklendi (bkz. o dosyanın aynı satırı).
Future<void> _v73denV74e(Database db) async {
  await _calistir(db, 'ALTER TABLE sube_urun RENAME TO sube_urun_eski_v73');
  await _calistir(db, '''
    CREATE TABLE IF NOT EXISTS sube_urun (
      global_id TEXT,
      urun_id INTEGER NOT NULL, sube_id INTEGER NOT NULL,
      stok REAL NOT NULL DEFAULT 0, rezerve_stok REAL NOT NULL DEFAULT 0,
      kritik_stok REAL DEFAULT 0, satis_fiyati REAL, alis_fiyati REAL,
      raf_kodu TEXT, son_guncelleme DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      last_updated DATETIME,
      PRIMARY KEY (urun_id, sube_id),
      FOREIGN KEY(urun_id) REFERENCES urunler(id) ON DELETE CASCADE,
      FOREIGN KEY(sube_id) REFERENCES subeler(id) ON DELETE CASCADE
    )
  ''');
  await _calistir(db, '''
    INSERT INTO sube_urun (global_id, urun_id, sube_id, stok, rezerve_stok,
        kritik_stok, satis_fiyati, alis_fiyati, raf_kodu, son_guncelleme, last_updated)
    SELECT o.global_id, o.urun_id, o.sube_id, o.stok, o.rezerve_stok,
        o.kritik_stok, o.satis_fiyati, o.alis_fiyati, o.raf_kodu,
        o.son_guncelleme, o.last_updated
    FROM sube_urun_eski_v73 o
    WHERE EXISTS (SELECT 1 FROM urunler u WHERE u.id = o.urun_id)
      AND EXISTS (SELECT 1 FROM subeler s WHERE s.id = o.sube_id)
  ''');
  await _calistir(db, 'DROP TABLE sube_urun_eski_v73');
  await _calistir(db,
      'CREATE INDEX IF NOT EXISTS idx_sube_urun_urun ON sube_urun(urun_id)');
  await _calistir(db,
      'CREATE INDEX IF NOT EXISTS idx_sube_urun_sube ON sube_urun(sube_id)');
}

// v74'ten v75'e — kullanıcı bulgusu ("tam ERP oldu mu, başka hata var
// mı" denetimi, 2026-09-22): 'stok_fifo' tablosu şemada VARDI (v1'den
// beri) ama HİÇBİR depo/servis/ekran onu hiç okumuyor/yazmıyordu —
// tamamen ölü, kullanılmayan bir FIFO maliyet takibi denemesiydi. Gerçek
// lot/parti takibi zaten ayrı, aktif çalışan 'lot_seri' (FEFO) tablosu
// üzerinden yapılıyor. Boş/ölü bir tablo veri kaybı riski taşımaz —
// güvenle kaldırılıyor.
Future<void> _v74denV75e(Database db) async {
  await _calistir(db, 'DROP TABLE IF EXISTS stok_fifo');
}

// v75'ten v76'ya — kullanıcı bulgusu ("tam ERP" denetimi, paralel fork
// taraması, 2026-09-22): Banka/Kredi Kartı ödeme yöntemiyle girilen
// GİDERLER hiçbir gerçek banka/kredi kartı hareketi oluşturmuyordu —
// sadece 'giderler' tablosuna düşüyor, şirketin gerçek banka bakiyesi/
// kart limit kullanımı hiç etkilenmiyordu (Virman/İade'de daha önce
// bulunan AYNI hata sınıfı). GiderDeposu artık bu iki sütunu kullanarak
// CariTahsilatOdemeServisi'ndeki AYNI desenle gerçek hareket yazıyor.
Future<void> _v75denV76ya(Database db) async {
  await _calistir(db, 'ALTER TABLE giderler ADD COLUMN banka_hesap_id INTEGER');
  await _calistir(db, 'ALTER TABLE giderler ADD COLUMN kredi_karti_id INTEGER');
}

// v76'dan v77'ye — KRİTİK kök neden düzeltmesi (kullanıcı bulgusu, "tam
// ERP" denetimi devamı, 2026-09-22): PuanServisi.puanEkle()'deki
// 'INSERT ... ON CONFLICT(cari_id) DO UPDATE' cümlesi, musteri_puan.
// cari_id üzerinde HİÇBİR UNIQUE/PRIMARY KEY kısıtı OLMADIĞI için HER
// ZAMAN "ON CONFLICT clause does not match any PRIMARY KEY or UNIQUE
// constraint" SQL hatasıyla patlıyordu. Bu hata satis_tamamlama_servisi.
// dart'ta BOŞ bir try/catch(_){} ile sessizce yutuluyordu — yani satış
// sonrası müşteri sadakat puanı kazandırma özelliği muhtemelen HİÇ
// ÇALIŞMAMIŞTI, her müşterinin puan bakiyesi her zaman 0 görünüyordu ve
// kimse fark etmedi çünkü hata hiçbir yere düşmüyordu (o catch bloğu da
// bu turda LogServisi'ne loglayacak şekilde düzeltildi).
//
// Önce (varsa — tablo muhtemelen boştu ama savunmacı davranılıyor) aynı
// cari_id'ye ait birden fazla satır Dart tarafında TEK satıra
// birleştiriliyor, SONRA cari_id üzerinde bir UNIQUE INDEX kuruluyor —
// SQLite'ta ON CONFLICT hedefi bir UNIQUE INDEX'i de kabul eder, tabloyu
// yeniden oluşturmaya gerek yok.
Future<void> _v76denV77ye(Database db) async {
  // Savunmacı: 'musteri_puan' teorik olarak yoksa (ör. çok eski/kısmi
  // bir şema durumu) sessizce atla — CREATE UNIQUE INDEX zaten
  // _calistir() içinde 'no such table' durumunu güvenle yutuyor, ama
  // buradaki SELECT/DELETE/UPDATE adımları _calistir() KULLANMIYOR.
  final tabloVarMi = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='musteri_puan'");
  if (tabloVarMi.isEmpty) return;

  final satirlar = await db.query('musteri_puan', orderBy: 'id ASC');
  final gruplu = <int, List<Map<String, dynamic>>>{};
  for (final s in satirlar) {
    final cariId = s['cari_id'] as int?;
    if (cariId == null) continue;
    (gruplu[cariId] ??= []).add(s);
  }
  for (final entry in gruplu.entries) {
    if (entry.value.length <= 1) continue;
    double toplam = 0, kullanilan = 0;
    String? sonIslem;
    for (final s in entry.value) {
      toplam += (s['toplam_puan'] as num?)?.toDouble() ?? 0;
      kullanilan += (s['kullanilan'] as num?)?.toDouble() ?? 0;
      final si = s['son_islem'] as String?;
      if (si != null && (sonIslem == null || si.compareTo(sonIslem) > 0)) sonIslem = si;
    }
    final korunacakId = entry.value.first['id'] as int;
    await db.update(
        'musteri_puan',
        {
          'toplam_puan': toplam,
          'kullanilan': kullanilan,
          if (sonIslem != null) 'son_islem': sonIslem,
        },
        where: 'id = ?',
        whereArgs: [korunacakId]);
    for (final s in entry.value.skip(1)) {
      await db.delete('musteri_puan', where: 'id = ?', whereArgs: [s['id']]);
    }
  }
  await _calistir(db,
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_musteri_puan_cari_unique ON musteri_puan(cari_id)');
}

// v77'den v78'e — MERKEZİ FATURA SERİ/BLOK YÖNETİMİ (kullanıcının
// ERP_DENETIM_KURALLARI.md.txt spesifikasyonu, derin denetim sonucu —
// bkz. proje kökünde CENTRAL_DOCUMENT_NUMBERING_DEEP_AUDIT.md).
//
// Fatura numarası ÖNCEDEN sadece cihazın kendi yerel verisine bakarak
// (SELECT MAX+1) üretiliyordu — birden fazla cihaz/terminal aynı anda
// aynı numarayı üretebilirdi. Artık numara ÜRETİMİ Supabase'deki
// fatura_blok_tahsis_et() RPC'sine (bkz. supabase_fatura_seri_bloklari
// .sql) taşınıyor — burada Postgres'in kendi atomik satır kilidi iki
// terminalin ASLA aynı aralığı almamasını garanti ediyor. Bu iki yerel
// tablo, tahsis edilen bloğun OFFLINE tüketimi için (cihaz internetsiz
// kalsa bile önceden alınmış bloktan numara üretebilsin diye).
//
// yerel_terminal: TEK satır (id=1) — bu cihazın hangi bulut Terminal
// kaydına karşılık geldiği. NULL ise cihaz henüz bir Terminal olarak
// kayıtlı değildir (TerminalServisi ilk kullanımda otomatik kaydeder).
//
// yerel_fatura_blok: bu cihaza tahsis edilmiş blok(lar) — offline
// tüketim için "sıradaki" imleç yerelde SQLite transaction'ı İÇİNDE
// (fatura INSERT'iyle AYNI transaction'da) atomik olarak ilerletilir.
Future<void> _v77denV78e(Database db) async {
  await _calistir(db, '''
    CREATE TABLE IF NOT EXISTS yerel_terminal (
      id             INTEGER PRIMARY KEY CHECK (id = 1),
      terminal_id    INTEGER,
      terminal_kodu  TEXT,
      sube_id        INTEGER,
      kayit_tarihi   TEXT
    )
  ''');
  await _calistir(db, '''
    CREATE TABLE IF NOT EXISTS yerel_fatura_blok (
      id              INTEGER PRIMARY KEY AUTOINCREMENT,
      seri            TEXT NOT NULL,
      yil             INTEGER NOT NULL,
      blok_baslangic  INTEGER NOT NULL,
      blok_bitis      INTEGER NOT NULL,
      siradaki        INTEGER NOT NULL,
      durum           TEXT NOT NULL DEFAULT 'aktif',
      tahsis_zamani   TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    )
  ''');
  await _calistir(db,
      'CREATE INDEX IF NOT EXISTS idx_yerel_fatura_blok_durum ON yerel_fatura_blok(durum, seri, yil)');
  await _calistir(db, 'ALTER TABLE faturalar ADD COLUMN terminal_id INTEGER');
  await _calistir(db, 'ALTER TABLE faturalar ADD COLUMN blok_id INTEGER');
}

// v78'den v79'a — migrasyon tam yükseltme testi bulgusu (2026-09-29):
// eski sürümden yükseltilen cihazlarda yeni kurulumda OLMAYAN 4 trigger
// çalışmaya devam ediyordu ve fiyat trigger'ının gövdesi farklıydı:
//  • trg_urun_fiyat_gecmis — trg_fiyat_gecmis ile AYNI işi yapıyordu, her
//    fiyat değişikliği fiyat_gecmis'e İKİ KEZ yazılıyordu.
//  • trg_kredi_karti_limit(_upd) — kalan_limit'i hesaplıyordu; kod
//    (KrediKartiDeposu) bunu zaten açıkça yazıyor.
//  • trg_soft_delete_satis — satislar.deleted_at'i UTC dolduruyordu; hiçbir
//    kod okumuyor, yeni kurulumda yok.
// Kanonik kaynak yeni kurulum şeması (semalar/diger_semasi.dart). Önceki
// çift yazımın bıraktığı kopya fiyat_gecmis satırları da temizlenir
// (aynı ürün/değerler/zaman — değiştireni boş olan ikiz silinir).
Future<void> _v78denV79a(Database db) async {
  for (final t in [
    'trg_urun_fiyat_gecmis',
    'trg_kredi_karti_limit',
    'trg_kredi_karti_limit_upd',
    'trg_soft_delete_satis',
    'trg_fiyat_gecmis',
  ]) {
    await _calistir(db, 'DROP TRIGGER IF EXISTS $t');
  }
  await _calistir(db, '''
    CREATE TRIGGER IF NOT EXISTS trg_fiyat_gecmis
    AFTER UPDATE OF alis_fiyat, satis_fiyati ON urunler
    WHEN OLD.alis_fiyat != NEW.alis_fiyat OR OLD.satis_fiyati != NEW.satis_fiyati
    BEGIN
      INSERT INTO fiyat_gecmis(
        urun_id, eski_alis, yeni_alis, eski_satis, yeni_satis, degistiren
      ) VALUES (NEW.id, OLD.alis_fiyat, NEW.alis_fiyat, OLD.satis_fiyati, NEW.satis_fiyati,
        NEW.fiyat_guncelleyen_kullanici);
    END
  ''');
  await _calistir(db, '''
    DELETE FROM fiyat_gecmis WHERE degistiren IS NULL AND EXISTS (
      SELECT 1 FROM fiyat_gecmis f2
      WHERE f2.id != fiyat_gecmis.id AND f2.urun_id = fiyat_gecmis.urun_id
        AND f2.tarih = fiyat_gecmis.tarih
        AND f2.eski_alis IS fiyat_gecmis.eski_alis AND f2.yeni_alis IS fiyat_gecmis.yeni_alis
        AND f2.eski_satis IS fiyat_gecmis.eski_satis AND f2.yeni_satis IS fiyat_gecmis.yeni_satis
        AND (f2.degistiren IS NOT NULL OR f2.id < fiyat_gecmis.id))
  ''');
}
