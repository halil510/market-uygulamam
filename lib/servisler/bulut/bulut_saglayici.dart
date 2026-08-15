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

class BulutSonuc {
  final int basarili;
  final int hata;
  final List<String> hataMesajlari;
  const BulutSonuc({this.basarili=0, this.hata=0, this.hataMesajlari=const[]});
  bool get tamam => hata == 0;
}
