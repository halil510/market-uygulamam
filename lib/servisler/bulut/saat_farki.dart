// lib/servisler/bulut/saat_farki.dart
//
// Cihaz saati ile sunucu saati arasındaki fark (çoklu cihaz analizi,
// 2026-11-08). Senkronda "hangi kayıt daha yeni" kararı kayıtların
// last_updated damgasıyla verilir; cihaz saati yanlışsa (ör. pil bitmiş,
// saat elle geri alınmış) eski değişiklik yeniyi ezebilir ya da yeni
// değişiklik "eski" sanılıp atlanabilir. Kullanıcı uyarılsın diye fark
// sunucunun HTTP `Date` başlığından ölçülür.
import 'dart:io' show HttpDate, HttpException;

class SaatFarki {
  SaatFarki._();

  /// Bu farkın üstü kullanıcıya gösterilir.
  static const esik = Duration(minutes: 5);

  /// Sunucu − cihaz farkı (pozitif: cihaz saati GERİDE). `Date` başlığı
  /// saniye hassasiyetindedir; cihaz anı olarak isteğin ortası alınır.
  /// Başlık yoksa/okunamazsa null.
  static Duration? hesapla(String? dateBasligi, DateTime istekBasi, DateTime istekSonu) {
    if (dateBasligi == null || dateBasligi.isEmpty) return null;
    final DateTime sunucu;
    try {
      sunucu = HttpDate.parse(dateBasligi);
    } on HttpException {
      return null;
    } on FormatException {
      return null;
    }
    final orta = istekBasi.add(istekSonu.difference(istekBasi) ~/ 2);
    return sunucu.difference(orta.toUtc());
  }

  static bool sapmaVar(Duration? fark) => fark != null && fark.abs() > esik;

  /// "Cihaz saati 12 dk geride" gibi.
  static String metin(Duration fark) {
    final dk = fark.inMinutes.abs();
    final sure = dk >= 120 ? '${(dk / 60).round()} saat' : '$dk dk';
    return 'Cihaz saati sunucudan $sure ${fark.isNegative ? 'ileride' : 'geride'}';
  }
}
