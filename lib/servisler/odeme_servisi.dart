// lib/servisler/odeme_servisi.dart
// Ödeme entegrasyonu için hazır altyapı (iyzico, PayTR vb.)
class OdemeServisi {
  static final OdemeServisi _instance = OdemeServisi._();
  factory OdemeServisi() => _instance;
  OdemeServisi._();

  // QR ödeme — gelecekte entegre edilecek
  Future<Map<String, dynamic>?> qrOdemeBaslat(double tutar) async {
    // QR kodu oluştur, ödeme kanalına gönder
    return null;
  }

  // NFC ödeme
  Future<bool> nfcOdeme(double tutar) async => false;

  // Nakit ödeme — para üstü hesapla
  Map<String, double> nakitOdemeHesapla(double toplamTutar, double verilenTutar) {
    final paraUstu = (verilenTutar - toplamTutar).clamp(0.0, double.infinity).toDouble();
    final kalan = (toplamTutar - verilenTutar).clamp(0.0, double.infinity).toDouble();
    return {'para_ustu': paraUstu, 'kalan': kalan};
  }
}


