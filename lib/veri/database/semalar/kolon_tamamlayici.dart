// lib/veri/database/semalar/kolon_tamamlayici.dart
//
// 🔴 DERİN ANALİZ BULGUSU — SENKRON SÜTUN KAYMASI
//
// `supabase_sync_servisi.dart` içindeki `_lastUpdatedVar` kümesi, hangi
// tabloların `last_updated` sütununa sahip olduğunu BİLDİRİR. Bu küme 8
// tabloda gerçekle uyuşmuyordu:
//
//   fiyat_gecmis, irsaliye_kalem, promosyon_aksiyon, promosyon_kosul,
//   rol_yetkileri, zaman_fiyat
//        → sütun HİÇBİR YERDE yok (ne CREATE'te ne migrasyonda)
//   garson_cagri_log, masa_hareket_log
//        → migrasyonla geliyor ama TAZE KURULUMDA yok
//
// SONUÇ (düzeltilmeden önce):
//   • GÖNDERİRKEN: kod `m['last_updated'] ??= now` ile sütunu payload'a
//     ekliyor → bulut kabul ediyor (bulutta sütun var).
//   • ÇEKERKEN: bulut satırı `last_updated` içeriyor, yerel tabloda o
//     sütun yok → SQLite "no such column: last_updated" → o tablonun
//     TÜM partisi düşüyor. Hata log'a yazılıyor ama sonuç kartı büyük
//     ölçüde yeşil görünüyor, kullanıcı fark etmiyor.
//   • Ayrıca yerelde saklanamadığı için her gönderimde değer yeniden
//     "now" oluyor → diğer cihazlar bu 8 tabloyu HER senkronda baştan
//     indiriyor (delta hiç ilerlemiyor).
//
// Bu dosya sütunları tamamlar. İki yerden çağrılır:
//   1) TabloOlusturucu.olustur()  → taze kurulum
//   2) MigrasyonYonetici v51→v52  → mevcut cihazlar
// Böylece iki yol da aynı noktada buluşur (indeks sorununda olduğu gibi
// "sadece migrasyonda var" durumu bir daha oluşmaz).
//
// NOT: `buluttanAl()` içine ayrıca genel bir sütun filtresi eklendi —
// bu dosya sorunu KAYNAĞINDA çözer, filtre ise gelecekteki her
// bulut/yerel kaymasına karşı kalıcı sigortadır. İkisi birlikte gerekir.
import 'package:sqflite/sqflite.dart';

class KolonTamamlayici {
  /// Idempotent: sütun zaten varsa SQLite hata verir, sessizce geçilir.
  static Future<void> tamamla(DatabaseExecutor db) async {
    for (final sql in _sutunlar) {
      try {
        await db.execute(sql);
      } catch (_) {
        // "duplicate column name" — zaten var, sorun değil.
        // Başka bir hata olsa bile kurulumu/migrasyonu bloklamamalı.
      }
    }
  }

  static const List<String> _sutunlar = [
    // ── Senkron delta anahtarı: bu 8 tabloda eksikti ──────────────────
    // Tip DATETIME: projedeki diğer last_updated sütunlarıyla aynı.
    // DEFAULT konulmadı — uygulama zaman damgasını kendisi yazıyor
    // (bulut şemasındaki not da bunu söylüyor: "DEFAULT now() kaldırıldı,
    //  uygulama zaten tüm zaman damgalarını kendisi gönderiyor").
    'ALTER TABLE fiyat_gecmis      ADD COLUMN last_updated DATETIME',
    'ALTER TABLE irsaliye_kalem    ADD COLUMN last_updated DATETIME',
    'ALTER TABLE promosyon_aksiyon ADD COLUMN last_updated DATETIME',
    'ALTER TABLE promosyon_kosul   ADD COLUMN last_updated DATETIME',
    'ALTER TABLE rol_yetkileri     ADD COLUMN last_updated DATETIME',
    'ALTER TABLE zaman_fiyat       ADD COLUMN last_updated DATETIME',
    'ALTER TABLE garson_cagri_log  ADD COLUMN last_updated DATETIME',
    'ALTER TABLE masa_hareket_log  ADD COLUMN last_updated DATETIME',

    // ── promosyon_tanim: bulut şemasında last_updated var, yerelde yok.
    // Senkron listesinde olduğu için eklendi.
    'ALTER TABLE promosyon_tanim   ADD COLUMN last_updated DATETIME',
  ];

  /// Delta senkronun tarayacağı sütunlar için indeks.
  /// (Bunlar olmadan her "Hızlı Gönder" tam tablo taraması yapar.)
  static Future<void> indeksle(DatabaseExecutor db) async {
    const idx = [
      'CREATE INDEX IF NOT EXISTS idx_fiyat_gecmis_lu      ON fiyat_gecmis(last_updated)',
      'CREATE INDEX IF NOT EXISTS idx_irsaliye_kalem_lu    ON irsaliye_kalem(last_updated)',
      'CREATE INDEX IF NOT EXISTS idx_promosyon_aksiyon_lu ON promosyon_aksiyon(last_updated)',
      'CREATE INDEX IF NOT EXISTS idx_promosyon_kosul_lu   ON promosyon_kosul(last_updated)',
      'CREATE INDEX IF NOT EXISTS idx_rol_yetkileri_lu     ON rol_yetkileri(last_updated)',
      'CREATE INDEX IF NOT EXISTS idx_zaman_fiyat_lu       ON zaman_fiyat(last_updated)',
      'CREATE INDEX IF NOT EXISTS idx_garson_cagri_log_lu  ON garson_cagri_log(last_updated)',
      'CREATE INDEX IF NOT EXISTS idx_masa_hareket_log_lu  ON masa_hareket_log(last_updated)',
      'CREATE INDEX IF NOT EXISTS idx_promosyon_tanim_lu   ON promosyon_tanim(last_updated)',
    ];
    for (final s in idx) {
      try {
        await db.execute(s);
      } catch (_) {
        // sütun yoksa indeks de kurulamaz — sessizce geç
      }
    }
  }
}
