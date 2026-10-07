// lib/ekranlar/satis/iade/cari_iade_kurali.dart
//
// Manuel iadede seçili cariye göre iadenin TÜRÜ ve bu türün kuralları
// (fiyat, stok yönü, açıklama). Ekrandan ayrıldı (2026-10-07 refactor):
// arayüzden bağımsız, saf iş kuralı — tek başına test edilebilir.
import '../../../modeller/cari_model.dart';
import '../../../modeller/urun_model.dart';
import '../../../servisler/fiyat_hesaplama_servisi.dart';
import '../../../servisler/iade_islem_servisi.dart';

enum CariIadeTuru {
  /// Müşteri (veya cari seçilmemiş): satış fiyatı, serbest iskonto, stok artar.
  musteri,

  /// Saf tedarikçi: son alış maliyeti (KDV dahil), stok AZALIR, borcumuz düşer.
  tedarikci,

  /// Bayi/Toptan müşterisi: bayi fiyatı, stok artar, bayinin borcu düşer.
  bayi;

  /// Seçili cariden iade türü. "Hem Müşteri Hem Tedarikçi" bu ekranda müşteri
  /// sayılır (bkz. cariSafTedarikciMi) — tedarikçiye iade yalnız saf tedarikçide.
  static CariIadeTuru belirle(CariModel? cari) {
    if (cari?.id == null) return musteri;
    if (cariSafTedarikciMi(cari!.cariTipi)) return tedarikci;
    if (cariBayiMi(cari)) return bayi;
    return musteri;
  }

  /// İade stoğu azaltır mı (tedarikçiye mal gider)?
  bool get stokAzalir => this == tedarikci;

  /// Fiyat bir iş kuralıyla mı belirlenir (formda kilitli, iskonto yok)?
  bool get fiyatKuralli => this != musteri;

  /// Formda fiyatın neden kilitli olduğunu anlatan metin (müşteride null).
  String? fiyatAciklamasi(CariModel? cari) => switch (this) {
        musteri => null,
        tedarikci => 'Tedarikçiye iade: fiyat ürünün son alış maliyetidir (KDV dahil). '
            'Stok azalır, tutar ${cari?.unvan ?? ''} carisine olan borcumuzdan düşülür.',
        bayi => 'Bayi iadesi: fiyat bu bayiye özel toptan fiyatıdır. Stok artar, '
            'tutar ${cari?.unvan ?? ''} bayisinin borcundan düşülür.',
      };

  /// Formda gösterilecek iade birim fiyatı. Tedarikçi/bayide asıl tutar
  /// kayıtta serviste AYNI kuralla yeniden hesaplanır (bu yalnız önizleme).
  Future<double> onizlemeFiyati(UrunModel urun,
          {CariModel? cari, required double miktar}) async =>
      switch (this) {
        musteri => urun.satisFiyat,
        tedarikci => tedarikciIadeBirimMaliyeti(
            alisFiyat: urun.alisFiyat,
            alisKdvOran: urun.alisKdvOran,
            alisFiyatKdvDahil: urun.alisFiyatKdvDahil),
        bayi => (await FiyatHesaplamaServisi().hesapla(urun: urun, cari: cari, miktar: miktar))
            .birimFiyat,
      };
}
