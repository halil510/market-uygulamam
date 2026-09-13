// lib/servisler/fiyat_simulasyon_servisi.dart
//
// FAZ 11 — Fiyat Simülasyonu (erp_roadmap madde 25, protokol madde 18).
// KESİNLİKLE salt önizleme: gerçek satis_fiyati'na HİÇBİR ŞEKİLDE
// yazmaz. Kullanıcı "bu ürünün fiyatını %X artırsam/azaltsam ne olur"
// sorusuna, mevcut satış hızı verisiyle (FAZ 8'deki
// UrunDeposu.satisHiziGetir yeniden kullanılıyor) yaklaşık bir cevap
// alır.
import '../depolar/urun_deposu.dart';

class FiyatSimulasyonuSonuc {
  final double eskiFiyat;
  final double yeniFiyat;
  final double eskiBirimKar;
  final double yeniBirimKar;
  /// Markup yüzdesi: (satış-alış)/alış*100 — UrunModel.karOrani ile AYNI
  /// konvansiyon (bu uygulamada "kâr oranı" hep markup, margin değil).
  final double eskiKarOrani;
  final double yeniKarOrani;
  /// Son 30 günün satış hızı sabit kalırsa aylık kâr farkı tahmini.
  /// Satış hızı verisi yoksa null.
  final double? aylikTahminiKarFarki;

  const FiyatSimulasyonuSonuc({
    required this.eskiFiyat,
    required this.yeniFiyat,
    required this.eskiBirimKar,
    required this.yeniBirimKar,
    required this.eskiKarOrani,
    required this.yeniKarOrani,
    required this.aylikTahminiKarFarki,
  });
}

/// Saf fonksiyon — DB'ye bağımlı değil, test edilebilir.
FiyatSimulasyonuSonuc fiyatSimulasyonuHesapla({
  required double alisFiyat,
  required double eskiFiyat,
  required double yeniFiyat,
  double? aylikSatilanMiktar,
}) {
  final eskiKar = eskiFiyat - alisFiyat;
  final yeniKar = yeniFiyat - alisFiyat;
  final eskiKarOrani = alisFiyat > 0 ? (eskiKar / alisFiyat) * 100 : 0.0;
  final yeniKarOrani = alisFiyat > 0 ? (yeniKar / alisFiyat) * 100 : 0.0;
  final aylikFark =
      aylikSatilanMiktar != null ? (yeniKar - eskiKar) * aylikSatilanMiktar : null;
  return FiyatSimulasyonuSonuc(
    eskiFiyat: eskiFiyat,
    yeniFiyat: yeniFiyat,
    eskiBirimKar: eskiKar,
    yeniBirimKar: yeniKar,
    eskiKarOrani: eskiKarOrani,
    yeniKarOrani: yeniKarOrani,
    aylikTahminiKarFarki: aylikFark,
  );
}

class FiyatSimulasyonuServisi {
  /// [urunId] için son 30 günün satış hızını alıp simülasyonu hesaplar.
  /// Satış geçmişi yoksa [FiyatSimulasyonuSonuc.aylikTahminiKarFarki] null
  /// döner (diğer alanlar yine hesaplanır).
  Future<FiyatSimulasyonuSonuc> hesapla({
    required int urunId,
    required double alisFiyat,
    required double eskiFiyat,
    required double yeniFiyat,
  }) async {
    final hiz = await UrunDeposu().satisHiziGetir([urunId], gunSayisi: 30);
    final aylikSatilan = hiz[urunId];
    return fiyatSimulasyonuHesapla(
      alisFiyat: alisFiyat,
      eskiFiyat: eskiFiyat,
      yeniFiyat: yeniFiyat,
      aylikSatilanMiktar: aylikSatilan,
    );
  }
}
