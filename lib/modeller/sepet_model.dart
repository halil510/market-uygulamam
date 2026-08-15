// lib/modeller/sepet_model.dart
//
// KDV KONVANSİYONU:
//   satis_fiyati = KDV HARİÇ fiyat (net fiyat)
//   toplamTutar  = miktar × netFiyat  (KDV hariç)
//   kdvTutar     = toplamTutar × kdvOran%
//   kdvliToplamTutar = toplamTutar + kdvTutar  (KDV DAHİL)
//
// Eğer DB'deki satis_fiyati KDV dahilse kdvOran'ı 0 olarak geçirin
// veya kdvHaricFiyat = satisFiyati / (1 + kdvOran/100) kullanın.
import 'urun_model.dart';

class SepetKalem {
  final UrunModel urun;
  final double miktar;
  final double iskontoOran;
  final double birimFiyat;

  /// KDV hariç net birim fiyat (iskonto uygulanmış)
  double get netFiyat => birimFiyat * (1 - iskontoOran / 100);

  double get iskontoTutar => birimFiyat * miktar * (iskontoOran / 100);

  /// KDV hariç satır toplamı
  double get toplamTutar => netFiyat * miktar;

  double get kdvOran => double.tryParse(urun.kdvOran) ?? 18;

  /// Sadece KDV miktarı
  double get kdvTutar => toplamTutar * (kdvOran / 100);

  /// KDV dahil satır toplamı
  double get kdvliToplamTutar => toplamTutar + kdvTutar;

  SepetKalem({
    required this.urun,
    this.miktar = 1,
    this.iskontoOran = 0,
    double? birimFiyat,
  }) : birimFiyat = birimFiyat ?? urun.satisFiyati;

  /// Yeni nesne döndürür — immutable
  SepetKalem copyWith({
    double? miktar,
    double? iskontoOran,
    double? birimFiyat,
  }) => SepetKalem(
    urun:        urun,
    miktar:      miktar      ?? this.miktar,
    iskontoOran: iskontoOran ?? this.iskontoOran,
    birimFiyat:  birimFiyat  ?? this.birimFiyat,
  );
}
