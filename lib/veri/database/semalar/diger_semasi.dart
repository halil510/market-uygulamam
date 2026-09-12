// lib/veri/database/semalar/diger_semasi.dart
// OTOMATİK AYRIŞTIRILDI — tablo_olusturucu.dart içindeki _diger() bloğundan
// birebir taşındı. Amaç: 1097 satırlık tek dosya yerine modüler,
// domain bazlı şema dosyaları (Logo Yazılım tarzı katmanlı mimari).
//
// Personel ve diğer yardımcı tablolar
import 'package:sqflite/sqflite.dart';
import '../../../cekirdek/sabitler/db_sabitleri.dart';

class DigerSemasi {
  static Future<void> olustur(Database db) async {

    final indexler = [
      'CREATE INDEX IF NOT EXISTS idx_urunler_barkod       ON ${DbSabitler.urunler}(barkod)',
      'CREATE INDEX IF NOT EXISTS idx_urunler_stok         ON ${DbSabitler.urunler}(stok)',
      'CREATE INDEX IF NOT EXISTS idx_urunler_aktif        ON ${DbSabitler.urunler}(aktif, stok)',
      'CREATE INDEX IF NOT EXISTS idx_urunler_ana_grup     ON ${DbSabitler.urunler}(ana_grup)',
      'CREATE INDEX IF NOT EXISTS idx_urunler_kategori     ON ${DbSabitler.urunler}(kategori_id)',
      'CREATE INDEX IF NOT EXISTS idx_satislar_tarih       ON ${DbSabitler.satislar}(tarih)',
      'CREATE INDEX IF NOT EXISTS idx_satislar_kullanici   ON ${DbSabitler.satislar}(kullanici_id)',
      'CREATE INDEX IF NOT EXISTS idx_satislar_kasiyer     ON ${DbSabitler.satislar}(kasiyer_id)',
      'CREATE INDEX IF NOT EXISTS idx_satislar_iptal       ON ${DbSabitler.satislar}(iptal, tarih)',
      'CREATE INDEX IF NOT EXISTS idx_satislar_cari        ON ${DbSabitler.satislar}(cari_id)',
      'CREATE INDEX IF NOT EXISTS idx_satislar_fis_no      ON ${DbSabitler.satislar}(fis_no)',
      'CREATE INDEX IF NOT EXISTS idx_satislar_odeme       ON ${DbSabitler.satislar}(odeme_yontemi)',
      'CREATE INDEX IF NOT EXISTS idx_satislar_deleted     ON ${DbSabitler.satislar}(is_deleted, tarih)',
      'CREATE INDEX IF NOT EXISTS idx_satis_kalem_urun     ON ${DbSabitler.satisKalem}(urun_id)',
      'CREATE INDEX IF NOT EXISTS idx_satis_kalem_satis    ON ${DbSabitler.satisKalem}(satis_id)',
      'CREATE INDEX IF NOT EXISTS idx_stok_hareket_urun    ON stok_hareket(urun_id)',
      'CREATE INDEX IF NOT EXISTS idx_stok_hareket_tarih   ON stok_hareket(tarih)',
      'CREATE INDEX IF NOT EXISTS idx_stok_hareket_tur     ON stok_hareket(hareket_turu)',
      'CREATE INDEX IF NOT EXISTS idx_cari_unvan           ON ${DbSabitler.cari}(unvan)',
      'CREATE INDEX IF NOT EXISTS idx_cari_tip             ON ${DbSabitler.cari}(cari_tipi)',
      'CREATE INDEX IF NOT EXISTS idx_cari_kodu            ON ${DbSabitler.cari}(cari_kodu)',
      'CREATE INDEX IF NOT EXISTS idx_cari_hareket_cari    ON cari_hareket(cari_id)',
      'CREATE INDEX IF NOT EXISTS idx_cari_hareket_tarih   ON cari_hareket(tarih)',
      'CREATE INDEX IF NOT EXISTS idx_kasa_tarih           ON kasa_hareketleri(tarih)',
      'CREATE INDEX IF NOT EXISTS idx_kasa_tip             ON kasa_hareketleri(hareket_tipi)',
      'CREATE INDEX IF NOT EXISTS idx_giderler_tarih       ON giderler(tarih)',
      'CREATE INDEX IF NOT EXISTS idx_faturalar_tarih      ON faturalar(tarih)',
      'CREATE INDEX IF NOT EXISTS idx_faturalar_cari       ON faturalar(cari_id)',
      'CREATE INDEX IF NOT EXISTS idx_faturalar_efatura    ON faturalar(e_fatura_durum)',
      'CREATE INDEX IF NOT EXISTS idx_promosyon_urun       ON promosyonlar(urun_id)',
      'CREATE INDEX IF NOT EXISTS idx_promosyon_aktif      ON promosyonlar(aktif)',
      'CREATE INDEX IF NOT EXISTS idx_iade_cari            ON iade(cari_id)',
      'CREATE INDEX IF NOT EXISTS idx_iade_tarih           ON iade(tarih)',
      'CREATE INDEX IF NOT EXISTS idx_zaman_fiyat_urun     ON zaman_fiyat(urun_id, aktif)',
    ];

    for (final sql in indexler) {
      try { await db.execute(sql); } catch (e) { /* ignore */ }
    }

    await _triggerlar(db);
  
  }

  /// Ürün/fiyat/cari bakiye tetikleyicileri (orijinal dosyada _diger()'in
  /// hemen yanında ayrı bir static metottu; buraya birebir taşındı).
  //
  // 🔴🔴 KRİTİK SENKRON HATASI (derin analizde bulundu — protokol v54→v55
  // migration notuna bkz.): 'trg_urun_guncelle' HER UPDATE sonrası
  // last_updated/guncelleme_tarihi'ni datetime('now') (saat dilimsiz,
  // UTC) ile YENİDEN yazıyordu — uygulama kodunun (UrunDeposu.guncelle())
  // AYNI satırda zaten doğru (yerel saat) set ettiği değerin üzerine.
  // Dart'ın DateTime.tryParse()'ı saat dilimi işareti olmayan bir
  // string'i YEREL saat sayar; Türkiye (UTC+3) için bu, her ürün
  // güncellemesinin last_updated'ının GERÇEKTEN OLDUĞUNDAN ~3 SAAT ESKİ
  // görünmesine yol açıyordu — last-write-wins senkron çakışma çözümünü
  // bozan, sessiz ve sistemik bir hataydı. Uygulama kodu bu alanları
  // zaten her yazma yolunda doğru set ettiği için tetikleyici tamamen
  // kaldırıldı (yükseltilen kurulumlar için bkz. migrasyon_yonetici.dart
  // v54→v55 — aynı tetikleyiciyi ve eşdeğerini DROP eder).
  static Future<void> _triggerlar(Database db) async {
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_fiyat_gecmis
      AFTER UPDATE OF alis_fiyat, satis_fiyati ON ${DbSabitler.urunler}
      WHEN OLD.alis_fiyat != NEW.alis_fiyat OR OLD.satis_fiyati != NEW.satis_fiyati
      BEGIN
        INSERT INTO ${DbSabitler.fiyatGecmis}(
          urun_id, eski_alis, yeni_alis, eski_satis, yeni_satis
        ) VALUES (NEW.id, OLD.alis_fiyat, NEW.alis_fiyat, OLD.satis_fiyati, NEW.satis_fiyati);
      END
    ''');

    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_cari_hareket_bakiye
      AFTER INSERT ON ${DbSabitler.cariHareket}
      BEGIN
        UPDATE ${DbSabitler.cari}
        SET bakiye = (
          SELECT COALESCE(SUM(borc - alacak), 0) FROM ${DbSabitler.cariHareket}
          WHERE cari_id = NEW.cari_id
        )
        WHERE id = NEW.cari_id;
      END
    ''');
  }
}
