// lib/modeller/sepet_model.dart
//
// KDV KONVANSİYONU (2026-09-16'da kullanıcı onayıyla doğrulandı):
//   satis_fiyati = KDV DAHİL fiyat (etikette yazan, müşterinin fiilen
//                  ödediği tutarın ta kendisi)
//   toplamTutar  = miktar × netFiyat  (KDV DAHİL, iskonto uygulanmış)
//   kdvTutar     = toplamTutar İÇİNDEN ayıklanan KDV payı (bölünerek —
//                  bkz. ParaUtils.kdvPayiCikar; ÇARPILARAK EKLENMEZ)
//   kdvliToplamTutar = toplamTutar (zaten KDV dahil olduğundan ayrıca
//                  KDV eklenmez — geriye dönük uyumluluk için tutulur)
//
// 🔴 DÜZELTME (Madde 21 — Para Hesaplamaları denetimi, 2026-09-16): bu
// dosya ÖNCEDEN "satis_fiyati KDV HARİÇ" yanlış varsayımıyla yazılmıştı
// ve kdvTutar'ı ÇARPARAK (KDV'yi üzerine ekleyerek) hesaplıyordu.
// Kullanıcıyla doğrulandı: satis_fiyati GERÇEKTE KDV DAHİL. Bu yanlış
// varsayım müşteriden tahsil edilen NİHAİ TUTARI etkilemiyordu (zaten
// KDV eklenmeden toplanıyordu, ki toplamTutar KDV dahil olduğu için bu
// doğruydu) — ama kaydedilen "KDV Tutarı" kırılımı (günlük rapor, fiş
// KDV satırı) olması gerekenden yüksek hesaplanıyordu. Aynı hatanın
// kopyaları toptan_satis_ekrani.dart ve bekleyen_siparis_deposu.dart'ta
// da vardı, hepsi bu turda düzeltildi (bkz. commit mesajı).
import 'urun_model.dart';
import '../cekirdek/utils/para_utils.dart';

class SepetKalem {
  final UrunModel urun;
  final double miktar;
  final double iskontoOran;
  final double birimFiyat;

  /// KDV dahil, iskonto uygulanmış birim fiyat
  double get netFiyat => birimFiyat * (1 - iskontoOran / 100);

  double get iskontoTutar => birimFiyat * miktar * (iskontoOran / 100);

  /// KDV dahil satır toplamı — müşteriden tahsil edilen tutarın ta kendisi
  double get toplamTutar => netFiyat * miktar;

  double get kdvOran => double.tryParse(urun.kdvOran) ?? 18;

  /// toplamTutar İÇİNDEKİ KDV payı (toplamTutar zaten KDV dahil)
  double get kdvTutar => ParaUtils.kdvPayiCikar(toplamTutar, kdvOran);

  /// Geriye dönük uyumluluk için tutulur — toplamTutar zaten KDV dahil
  /// olduğundan bu her zaman toplamTutar'a eşittir.
  double get kdvliToplamTutar => toplamTutar;

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
