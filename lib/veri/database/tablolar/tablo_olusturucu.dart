// lib/veri/database/tablolar/tablo_olusturucu.dart
//
// TEK GİRİŞ NOKTASI — Veritabanı ilk kurulumunda çağrılır.
//
// Önceden bu dosya 1097 satırlık tek bir blok halindeydi. Artık her
// modül kendi şema dosyasında (lib/veri/database/semalar/) yaşıyor ve
// burada sadece sırayla çağrılıyor. Yeni bir modül eklerken:
//   1) lib/veri/database/semalar/ altına yeni bir *_semasi.dart oluştur
//   2) DbSabitler'a tablo adlarını ekle
//   3) aşağıdaki listeye tek satır ekle
//
// SQL içerikleri mevcut (üretimde çalışan) şemadan birebir taşınmıştır;
// hiçbir kolon/ilişki değiştirilmeden sadece dosya bazında ayrıştırılmıştır.
// (Eski tek-parça hali: tablo_olusturucu_ESKI_YEDEK.dart.bak)
import 'package:sqflite/sqflite.dart';

import '../semalar/temel_semasi.dart';
import '../semalar/urun_semasi.dart';
import '../semalar/cari_semasi.dart';
import '../semalar/satis_semasi.dart';
import '../semalar/stok_semasi.dart';
import '../semalar/iade_semasi.dart';
import '../semalar/promosyon_semasi.dart';
import '../semalar/tedarik_semasi.dart';
import '../semalar/finans_semasi.dart';
import '../semalar/sistem_semasi.dart';
import '../semalar/sync_semasi.dart';
import '../semalar/diger_semasi.dart';
import '../semalar/masa_semasi.dart';
import '../semalar/borc_semasi.dart';
import '../semalar/banka_borc_semasi.dart';
import '../semalar/doviz_semasi.dart';
import '../semalar/toptan_siparis_semasi.dart';
import '../semalar/index_semasi.dart';
import '../semalar/kolon_tamamlayici.dart';

class TabloOlusturucu {
  /// Sıralama önemlidir: FOREIGN KEY bağımlılığı olan tablolar,
  /// referans verdikleri tablodan SONRA oluşturulur.
  static Future<void> olustur(Database db) async {
    await TemelSemasi.olustur(db); // 1. şube, kullanıcı, kategori, birim, marka
    await UrunSemasi.olustur(db); // 2. ürün kartı + fiyat geçmişi + lot/seri
    await CariSemasi.olustur(db); // 3. cari, cari adres/hareket, müşteri puan
    await SatisSemasi.olustur(db); // 4. satış fişi + kalemleri
    await StokSemasi.olustur(db); // 5. stok hareketleri, sayım, şube-ürün
    await IadeSemasi.olustur(db); // 6. iade + irsaliye
    await PromosyonSemasi.olustur(db); // 7. promosyon tanım/koşul/aksiyon
    await TedarikSemasi.olustur(db); // 8. tedarikçi siparişleri
    await FinansSemasi.olustur(db); // 9. gider, kasa, vardiya, fatura
    await SistemSemasi.olustur(db); // 10. bildirim, yazıcı, ayarlar, roller
    await SyncSemasi.olustur(db); // 11. bulut senkron kuyruğu
    await DigerSemasi.olustur(db); // 12. personel ve yardımcı tablolar
    await MasaSemasi.olustur(db); // 13. masa/restoran modülü
    await BorcSemasi.olustur(db); // 14. borç takip
    await BankaBorcSemasi.olustur(db); // 15. banka, kredi kartı, borç ödeme
    await DovizSemasi.olustur(db); // 16. çoklu para birimi / döviz kurları
    await ToptanSiparisSemasi.olustur(db); // 17. bayilerden bekleyen sipariş alma

    // 17. Audit log + bildirim merkezi (kullanıcı isteği: "kim ne
    // yaptı ne zaman" + "stok azaldı, borç günü geldi" bildirimleri).
    // NOT: Bu, mevcut kurulumlar için migrasyon (_v35denV36e) ile de
    // ekleniyor — burada YENİ kurulumlar için tekrarlanıyor çünkü
    // fresh install migrasyon adımlarını çalıştırmıyor, doğrudan en
    // güncel şemayla başlıyor.
    await db.execute("""
      CREATE TABLE IF NOT EXISTS audit_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        global_id TEXT UNIQUE,
        tablo_adi TEXT NOT NULL,
        kayit_id TEXT,
        islem_turu TEXT NOT NULL,
        ozet TEXT,
        kullanici_id INTEGER,
        kullanici_adi TEXT,
        cihaz_id TEXT,
        sube_id INTEGER,
        tarih DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        last_updated DATETIME
      )
    """);
    await db.execute("CREATE INDEX IF NOT EXISTS idx_audit_log_tarih ON audit_log(tarih DESC)");
    await db.execute("CREATE INDEX IF NOT EXISTS idx_audit_log_tablo ON audit_log(tablo_adi)");
    await db.execute("""
      CREATE TABLE IF NOT EXISTS bildirim_okundu (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        bildirim_anahtari TEXT UNIQUE NOT NULL,
        okundu_tarihi DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    """);

    // 18. Toptan satış / bayi fiyatlandırma sistemi (kullanıcı isteği:
    // "Ülker gibi firmaların kullandığı profesyonel sistem").
    await db.execute("""
      CREATE TABLE IF NOT EXISTS fiyat_gruplari (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        global_id TEXT UNIQUE,
        ad TEXT NOT NULL,
        aciklama TEXT,
        varsayilan_iskonto_orani REAL NOT NULL DEFAULT 0,
        aktif INTEGER NOT NULL DEFAULT 1,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        last_updated DATETIME
      )
    """);
    await db.execute("""
      CREATE TABLE IF NOT EXISTS urun_fiyat_gruplari (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        global_id TEXT UNIQUE,
        urun_id INTEGER NOT NULL,
        fiyat_grubu_id INTEGER NOT NULL,
        fiyat REAL NOT NULL,
        last_updated DATETIME,
        UNIQUE(urun_id, fiyat_grubu_id)
      )
    """);
    await db.execute("CREATE INDEX IF NOT EXISTS idx_ufg_urun ON urun_fiyat_gruplari(urun_id)");
    await db.execute("""
      CREATE TABLE IF NOT EXISTS fiyat_kademeleri (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        global_id TEXT UNIQUE,
        urun_id INTEGER NOT NULL,
        fiyat_grubu_id INTEGER,
        min_miktar REAL NOT NULL,
        birim TEXT NOT NULL DEFAULT 'adet',
        fiyat REAL NOT NULL,
        last_updated DATETIME
      )
    """);
    await db.execute("CREATE INDEX IF NOT EXISTS idx_fk_urun ON fiyat_kademeleri(urun_id)");
    // urunler/cari şemaları (yukarıda UrunSemasi/CariSemasi ile
    // oluşturuldu) bu yeni sütunları içermiyor — burada ekleniyor.
    for (final sql in [
      "ALTER TABLE urunler ADD COLUMN toptan_fiyat REAL NOT NULL DEFAULT 0",
      "ALTER TABLE urunler ADD COLUMN koli_ici_miktar REAL NOT NULL DEFAULT 0",
      "ALTER TABLE urunler ADD COLUMN koli_birim_adi TEXT NOT NULL DEFAULT 'Koli'",
      "ALTER TABLE urunler ADD COLUMN satis_birimi_tipi TEXT NOT NULL DEFAULT 'adet'",
      "ALTER TABLE urunler ADD COLUMN toptan_satista INTEGER NOT NULL DEFAULT 0",
      "ALTER TABLE cari ADD COLUMN fiyat_grubu_id INTEGER",
      "ALTER TABLE cari ADD COLUMN musteri_tipi TEXT NOT NULL DEFAULT 'Perakende'",
    ]) {
      try { await db.execute(sql); } catch (_) { /* kolon zaten varsa atla — taze kurulum ile yükseltme aynı kodu paylaşıyor */ }
    }

    // 🔴🔴 DÜZELTME (derin analizde bulundu): Burada ÖNCEDEN bir
    // "CREATE TABLE IF NOT EXISTS adisyon_log" bloğu vardı — ama bu
    // dosya, çağrı sırasında banka_borc_semasi.dart'TAN SONRA çalışıyor
    // ve O dosya adisyon_log'u ZATEN oluşturuyordu (last_updated
    // OLMADAN). "IF NOT EXISTS" yüzünden buradaki blok HİÇBİR ZAMAN
    // etkili olmadı — ÖLÜ KOD'du. Gerçek düzeltme artık doğru yerde:
    // banka_borc_semasi.dart'ın kendi adisyon_log tanımına last_updated
    // eklendi. Bu global_id indeksi (banka_borc_semasi.dart'ta yoktu)
    // hâlâ faydalı olduğu için korunuyor.
    await db.execute("CREATE INDEX IF NOT EXISTS idx_adisyon_log_global ON adisyon_log(global_id)");

    await db.execute("""
      CREATE TABLE IF NOT EXISTS garson_cagri_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        global_id TEXT,
        masa_id INTEGER NOT NULL,
        masa_adi TEXT,
        cagri_zamani DATETIME DEFAULT CURRENT_TIMESTAMP,
        yanit_zamani DATETIME,
        yanitlayan_id INTEGER,
        durum TEXT DEFAULT 'beklemede',
        last_updated DATETIME,
        FOREIGN KEY(masa_id) REFERENCES masalar(id)
      )
    """);
    await db.execute("CREATE INDEX IF NOT EXISTS idx_garson_cagri_durum ON garson_cagri_log(durum)");

    await db.execute("""
      CREATE TABLE IF NOT EXISTS masa_hareket_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        global_id TEXT,
        kaynak_masa_id INTEGER,
        hedef_masa_id INTEGER,
        islem_tipi TEXT NOT NULL,
        siparis_id INTEGER,
        yapan_kullanici_id INTEGER,
        islem_zamani DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        last_updated DATETIME,
        FOREIGN KEY(kaynak_masa_id) REFERENCES masalar(id),
        FOREIGN KEY(hedef_masa_id) REFERENCES masalar(id)
      )
    """);

    // 🔴 KRİTİK (derin analiz bulgusu): 30 indeks SADECE migrasyon
    // zincirinde tanımlıydı — taze kurulumlarda hiç oluşmuyordu.
    // EN SON çağrılır çünkü tüm tabloların var olması gerekir.
    await IndexSemasi.olustur(db);

    // 🔴 SENKRON KRİTİK: 9 tabloda `last_updated` sütunu eksikti —
    // bulut senkronu bu tablolarda "no such column" ile düşüyordu.
    // Taze kurulum ile migrasyon yolunun aynı noktada buluşması için
    // her iki yerden de çağrılır.
    await KolonTamamlayici.tamamla(db);
    await KolonTamamlayici.indeksle(db);
  }
}
