// lib/servisler/urun_fiyat_hesaplayici.dart
// Bir ürünün, verilen miktar için uygulanacak otomatik birim fiyatı.
// Hızlı Satış sepeti (Sepet) ve masa siparişi (MasaDeposu) AYNI kuralı
// kullanır — önceden kural sepet provider'ının içindeydi, masa satışı ürünün
// ham liste fiyatını yazıyordu (promosyon/indirim uygulanmıyordu).
import '../modeller/promosyon_model.dart';
import '../modeller/urun_model.dart';

class UrunFiyatHesaplayici {
  UrunFiyatHesaplayici._();

  /// Öncelik: (1) geçerli ve miktar eşiği sağlanan promosyonlardan EN YÜKSEK
  /// indirim oranlısı, (2) üründe kayıtlı indirimli fiyat, (3) ürün indirim
  /// oranı, (4) liste fiyatı.
  static double hesapla(
      UrunModel urun, double miktar, List<PromosyonModel>? promosyonlar) {
    final bazFiyat = urun.satisFiyati;

    if (promosyonlar != null && promosyonlar.isNotEmpty) {
      PromosyonModel? best;
      for (final p in promosyonlar) {
        if (p.gecerli && miktar >= p.minMiktar) {
          if (best == null || p.iskontoOran > best.iskontoOran) best = p;
        }
      }
      if (best != null) return bazFiyat * (1 - best.iskontoOran / 100);
    }

    if (urun.indirimliFiyatKayitli > 0 && urun.indirimliFiyatKayitli < bazFiyat) {
      return urun.indirimliFiyatKayitli;
    }
    if (urun.indirimOrani > 0) {
      return bazFiyat * (1 - urun.indirimOrani / 100);
    }
    return bazFiyat;
  }
}
