// lib/veri/database/semalar/index_semasi.dart
//
// 🔴 DERİN ANALİZ BULGUSU (kritik performans hatası):
//
// Bu 30 indeks, PROJEDE SADECE migrasyon_yonetici.dart içinde
// tanımlıydı. Yani:
//
//   • Mevcut cihazlar (DB'si v7 → v51 diye migrasyonlarla yükselmiş)
//     → indeksler YOL BOYUNCA oluştu, sorgular hızlı.
//
//   • YENİ KURULUM (yeni müşteri, yeni cihaz, uygulama silinip
//     tekrar kurulmuş) → Veritabani onCreate → TabloOlusturucu.olustur()
//     çalışır, migrasyonlar HİÇ ÇALIŞMAZ → bu 30 indeks HİÇ OLUŞMAZ.
//
// Sonuç: geliştirici kendi telefonunda hiçbir yavaşlık görmez, ama
// her yeni müşteride stok hareket / cari ekstre / ürün arama gibi
// ekranlar tam tablo taraması (full table scan) yapar. Kayıt sayısı
// arttıkça ekran açılışları saniyelerce sürer.
//
// Bu dosya o boşluğu kapatır. İçerik migrasyon_yonetici.dart'taki
// tanımlardan BİREBİR alınmıştır — hiçbir kolon/isim değiştirilmedi.
// "IF NOT EXISTS" olduğu için migrasyonla zaten oluşmuş cihazlarda
// tekrar çalışması zararsızdır.
import 'package:sqflite/sqflite.dart';

class IndexSemasi {
  /// TabloOlusturucu.olustur() içinde EN SON çağrılır — tüm tablolar
  /// oluştuktan sonra, çünkü indeks tablosuz oluşturulamaz.
  static Future<void> olustur(Database db) async {
    for (final sql in _indeksler) {
      // Tek bir indeks bir sebeple kurulamazsa (ör. o tablo o sürümde
      // henüz yoksa) TÜM kurulumun çökmesini istemiyoruz — indeks
      // eksikliği yavaşlatır ama uygulamayı bozmaz.
      try {
        await db.execute(sql);
      } catch (_) {
        // sessizce geç — kurulumu bloklamamalı
      }
    }
  }

  static const List<String> _indeksler = [
    // ── ÜRÜN (arama / listeleme / sync) ────────────────────────────────
    "CREATE INDEX IF NOT EXISTS idx_urunler_kod ON urunler(kod)",
    "CREATE INDEX IF NOT EXISTS idx_urunler_marka ON urunler(marka)",
    "CREATE INDEX IF NOT EXISTS idx_urunler_updated ON urunler(last_updated)",
    "CREATE INDEX IF NOT EXISTS idx_urunler_toptan_satista ON urunler(toptan_satista)",

    // ── STOK HAREKET (en çok büyüyen tablo — indekssiz felaket) ────────
    "CREATE INDEX IF NOT EXISTS idx_stokh_urun ON stok_hareket(urun_id)",
    "CREATE INDEX IF NOT EXISTS idx_stokh_tarih ON stok_hareket(tarih)",
    "CREATE INDEX IF NOT EXISTS idx_sube_urun_sube ON sube_urun(sube_id)",
    "CREATE INDEX IF NOT EXISTS idx_sube_urun_urun ON sube_urun(urun_id)",

    // ── CARİ HAREKET (ekstre ekranı) ───────────────────────────────────
    "CREATE INDEX IF NOT EXISTS idx_carih_cari ON cari_hareket(cari_id)",
    "CREATE INDEX IF NOT EXISTS idx_cari_hareket_deleted ON cari_hareket(is_deleted)",
    "CREATE INDEX IF NOT EXISTS idx_cari_hareket_global ON cari_hareket(global_id)",
    "CREATE INDEX IF NOT EXISTS idx_puan_hareket_global ON puan_hareket(global_id)",

    // ── FİNANS ─────────────────────────────────────────────────────────
    "CREATE INDEX IF NOT EXISTS idx_gider_tarih ON giderler(tarih)",
    "CREATE INDEX IF NOT EXISTS idx_fatura_cari ON faturalar(cari_id)",
    "CREATE INDEX IF NOT EXISTS idx_faturalar_iade ON faturalar(iade_id)",
    "CREATE INDEX IF NOT EXISTS idx_efatura_log ON efatura_log(fatura_id)",
    "CREATE INDEX IF NOT EXISTS idx_borc_son_odeme ON borclar(son_odeme_tarihi, odendi)",

    // ── İADE / İRSALİYE ────────────────────────────────────────────────
    "CREATE INDEX IF NOT EXISTS idx_iade_kalem_global ON iade_kalem(global_id)",
    "CREATE INDEX IF NOT EXISTS idx_irsaliye_kalem_global ON irsaliye_kalem(global_id)",

    // ── PROMOSYON ──────────────────────────────────────────────────────
    "CREATE INDEX IF NOT EXISTS idx_promo_urun ON promosyonlar(urun_id, aktif)",
    "CREATE INDEX IF NOT EXISTS idx_promosyon_kosul_global ON promosyon_kosul(global_id)",
    "CREATE INDEX IF NOT EXISTS idx_promosyon_aksiyon_global ON promosyon_aksiyon(global_id)",

    // ── MASA / RESTORAN ────────────────────────────────────────────────
    "CREATE INDEX IF NOT EXISTS idx_masa_siparis_durum_acilis ON masa_siparisleri(durum, acilis_zamani)",
    "CREATE INDEX IF NOT EXISTS idx_masa_siparis_kapanis ON masa_siparisleri(kapanis_zamani)",
    "CREATE INDEX IF NOT EXISTS idx_masa_kalem_durum ON masa_siparis_kalem(durum)",
    "CREATE INDEX IF NOT EXISTS idx_masa_hareket_global ON masa_hareket_log(global_id)",
    "CREATE INDEX IF NOT EXISTS idx_garson_cagri_global ON garson_cagri_log(global_id)",
    "CREATE INDEX IF NOT EXISTS idx_rezervasyon_durum_saat ON masa_rezervasyon(durum, saat)",

    // ── SİSTEM / SYNC ──────────────────────────────────────────────────
    "CREATE INDEX IF NOT EXISTS idx_sync_durum ON sync_queue(durum)",
    "CREATE INDEX IF NOT EXISTS idx_app_log_zaman ON app_log(zaman)",

    // ── HIZLI TUŞ / FAVORİ ÜRÜN (yeni ekran için) ──────────────────────
    // favori_urunler tablosu şemada vardı ama hiç indekslenmemişti;
    // hızlı satış ekranı her açılışta bu tabloyu sorguladığı için
    // kullanıcı bazlı erişim indekslendi.
    "CREATE INDEX IF NOT EXISTS idx_favori_kullanici ON favori_urunler(kullanici_id, sira)",
  ];
}
