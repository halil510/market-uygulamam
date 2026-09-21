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

    // 🔴🔴 MASTER ERP DEEP AUDIT — Madde 3 (Veritabanı Denetimi, 2026-09-16):
    // aşağıdaki indeksler "kritik hareket tabloları" taramasında eksik
    // bulundu — mevcut cihazlar için AYNI liste migrasyon_yonetici_
    // v36_v63.dart._v65denV66ya() içinde de tekrarlanır (bu dosyanın
    // kendi üstteki notundaki "sadece migrasyonda / sadece taze
    // kurulumda" kayması bir daha yaşanmasın diye iki yol da aynı anda
    // güncellendi).
    // ── KASA (en sık çalışan sorgu: her satış/iade/tahsilat bakiye
    //    hesabı için 'deleted_at IS NULL AND sube_id = ?' okuyor) ────────
    "CREATE INDEX IF NOT EXISTS idx_kasa_sube_silinmemis ON kasa_hareketleri(sube_id, deleted_at)",
    "CREATE INDEX IF NOT EXISTS idx_kasa_referans ON kasa_hareketleri(referans_id, referans_turu)",
    // ── STOK HAREKET (iade/irsaliye akışları referans_id+referans_turu
    //    ile ilgili satırı bulur) ─────────────────────────────────────
    "CREATE INDEX IF NOT EXISTS idx_stokh_referans ON stok_hareket(referans_id, referans_turu)",
    // ── CARİ HAREKET (iade düzenleme/silme fis_id+cari_id ile arar) ─────
    "CREATE INDEX IF NOT EXISTS idx_carih_fis ON cari_hareket(fis_id, cari_id)",
    // ── İADE KALEM / FATURA DETAY / İRSALİYE KALEM (her detay ekranı
    //    parent id'ye göre sorguluyordu, HİÇ indekslenmemişti) ──────────
    "CREATE INDEX IF NOT EXISTS idx_iade_kalem_iade ON iade_kalem(iade_id)",
    "CREATE INDEX IF NOT EXISTS idx_fatura_detay_fatura ON fatura_detaylari(fatura_id)",
    "CREATE INDEX IF NOT EXISTS idx_irsaliye_kalem_irsaliye ON irsaliye_kalem(irsaliye_id)",
    // ── TEDARİKÇİ SİPARİŞ (liste ekranı her sekme değişiminde 'durum'a
    //    göre filtreliyor, kalemler siparis_id ile sorgulanıyor) ────────
    "CREATE INDEX IF NOT EXISTS idx_tedsip_durum ON tedarikci_siparisler(durum)",
    "CREATE INDEX IF NOT EXISTS idx_tedsip_cari ON tedarikci_siparisler(cari_id)",
    "CREATE INDEX IF NOT EXISTS idx_tedsip_kalem_siparis ON tedarikci_siparis_kalem(siparis_id)",
    // ── VARDİYA (aktif/geçmiş vardiya sorgusu sube_id+kapanis_tarihi'ne
    //    göre filtreliyor) ───────────────────────────────────────────────
    "CREATE INDEX IF NOT EXISTS idx_vardiya_sube_kapanis ON vardiyalar(sube_id, kapanis_tarihi)",
    "CREATE INDEX IF NOT EXISTS idx_vardiya_kullanici ON vardiyalar(kullanici_id)",

    // 🔴🔴 MASTER ERP DEEP AUDIT — Madde 25/26 (Performans/Index Denetimi,
    // 2026-09-16): cari_hareket_ekrani.dart'ın ekstre sorgusu
    // ('WHERE cari_id=? AND is_deleted=0 ORDER BY tarih DESC') ayrı
    // idx_carih_cari(cari_id) ve idx_cari_hareket_deleted(is_deleted)
    // indekslerine sahipti ama İKİSİNİ BİRDEN + sıralamayı TEK geçişte
    // karşılayan bileşik bir indeks yoktu — yıllardır işlem gören bir
    // bayi/toptancı carisinde (binlerce hareket) bu sorgu index
    // birleştirme yerine kısmi tam taramaya düşebiliyordu.
    "CREATE INDEX IF NOT EXISTS idx_carih_cari_silinmemis_tarih ON cari_hareket(cari_id, is_deleted, tarih)",

    // 🔴 DEEP_AUDIT_REPORT FAZ 5 (Performans, 2026-09-21): FEFO satış
    // düşümü (StokDeposu.stokDusFefoTxn — 'WHERE urun_id=? AND aktif=1
    // AND miktar>0 ORDER BY son_kullanma_tarihi') lot takipli her ürün
    // satışında çalışan, ama hiç indekslenmemiş bir sorguydu — full scan.
    "CREATE INDEX IF NOT EXISTS idx_lot_seri_urun_aktif ON lot_seri(urun_id, aktif)",
  ];
}
