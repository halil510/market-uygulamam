// lib/servisler/bulut/bulut_saglayici.dart
// ─────────────────────────────────────────────────────────────────────────────
// Profesyonel cloud provider arayüzü.
// Supabase, Firebase, AWS, custom REST — hangisi olursa olsun bu arayüzü impl. et.
// ─────────────────────────────────────────────────────────────────────────────

abstract class IBulutSaglayici {
  String get ad;           // 'Supabase', 'Firebase', 'AWS' vs.
  String get ikon;         // emoji veya asset yolu

  /// Bağlantı testi
  Future<BaglantiSonuc> baglantiTest();

  /// Tek kayıt upsert — varsa güncelle, yoksa ekle
  Future<void> upsert({
    required String tablo,
    required Map<String, dynamic> veri,
    required String uniqueAlan,
  });

  /// Toplu upsert
  Future<BulutSonuc> topluUpsert({
    required String tablo,
    required List<Map<String, dynamic>> veriler,
    required String uniqueAlan,
  });

  /// Kayıtları çek (son güncelleme sonrası)
  Future<List<Map<String, dynamic>>> cek({
    required String tablo,
    DateTime? sonGuncelleme,
    int limit = 1000,
  });

  /// Soft delete
  Future<void> sil({
    required String tablo,
    required String uniqueAlan,
    required String deger,
  });

  /// Ayarları kaydet
  Future<void> ayarlariKaydet(Map<String, String> ayarlar);
  Future<Map<String, String>> ayarlariYukle();
}

class BaglantiSonuc {
  final bool basarili;
  final String mesaj;
  final int? gecikmeMs;
  const BaglantiSonuc({required this.basarili, required this.mesaj, this.gecikmeMs});
}

// MASTER ERP DEEP AUDIT — Madde 5 sertleştirmesi: sunucudan dönen
// hataları "geçici" (yeniden denenmeye değer — ağ hatası, zaman aşımı,
// 5xx sunucu hatası) ve "kalıcı" (yeniden denemek SONUCU DEĞİŞTİRMEZ —
// 4xx: geçersiz veri/kimlik doğrulama/yetki) olarak ikiye ayırır. Standart
// HTTP semantiği kullanılır: 4xx istemci hatası (payload/kimlik bilgisi
// düzelmeden tekrar denemek aynı sonucu verir), 5xx/ağ hatası ise
// sunucunun/bağlantının GEÇİCİ bir sorunudur.
enum BulutHataTuru { gecici, kalici }

BulutHataTuru bulutHataTuruBelirle(int? statusKodu) {
  if (statusKodu != null && statusKodu >= 400 && statusKodu < 500) {
    return BulutHataTuru.kalici;
  }
  return BulutHataTuru.gecici;
}

/// Sağlayıcı implementasyonlarının HTTP durum koduyla birlikte fırlattığı
/// hata — [BulutManager] bunu yakalayıp [tur] üzerinden geçici/kalıcı
/// ayrımı yapar. Durum kodu yoksa (ör. SocketException/TimeoutException
/// gibi ham ağ istisnaları hiç bu tipe sarılmadan da geçebilir) geçici
/// sayılır — bkz. [bulutHataTuruBelirle].
class BulutIstekHatasi implements Exception {
  final int? statusKodu;
  final String mesaj;
  const BulutIstekHatasi(this.statusKodu, this.mesaj);
  BulutHataTuru get tur => bulutHataTuruBelirle(statusKodu);
  @override
  String toString() =>
      statusKodu != null ? '$mesaj (HTTP $statusKodu)' : mesaj;
}

class BulutSonuc {
  final int basarili;
  final int hata;
  final List<String> hataMesajlari;
  /// Bu çağrı sırasında karşılaşılan SON HTTP hata kodu (varsa) —
  /// [tur] bu alandan hesaplanır. Ağ/zaman aşımı hatalarında null kalır
  /// (BulutManager bunu geçici sayar).
  final int? sonStatusKodu;
  const BulutSonuc({
    this.basarili = 0,
    this.hata = 0,
    this.hataMesajlari = const [],
    this.sonStatusKodu,
  });
  bool get tamam => hata == 0;
  BulutHataTuru get tur => bulutHataTuruBelirle(sonStatusKodu);
}
