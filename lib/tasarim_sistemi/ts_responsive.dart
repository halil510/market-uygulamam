// lib/tasarim_sistemi/ts_responsive.dart
//
// TABLET / YATAY MOD DESTEĞİ — merkezi karar noktası
// ------------------------------------------------------------------
// Material Design'ın standart kırılma noktalarını kullanır (600dp).
// Bu sınıf sadece "ne zaman tablet/geniş ekran sayılır" kararını TEK
// yerden verir — her ekranın kendi eşik değeri icat etmesini önler.
//
// Telefon davranışı bu değişiklikle HİÇBİR ŞEKİLDE etkilenmez — sadece
// genişlik eşiğini geçen ekranlarda (tablet, katlanabilir telefon açık
// hali, masaüstü penceresi, yatay mod) ek düzen devreye girer.
import 'package:flutter/material.dart';

class TsResponsive {
  TsResponsive._();

  /// 600dp — Material Design'ın "compact" / "medium" ekran sınırı.
  static const double tabletEsigi = 600;

  /// 900dp — geniş tablet/masaüstü, 3+ kolonlu ızgaralar için.
  static const double genisEsigi = 900;

  static bool tabletMi(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= tabletEsigi;

  static bool genisMi(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= genisEsigi;

  /// Izgara görünümleri için ekran genişliğine göre kolon sayısı.
  /// Telefon: [telefon] (varsayılan çoğu yerde 2), tablet: [tablet],
  /// geniş tablet/masaüstü: [genis].
  static int izgaraKolonSayisi(
    BuildContext context, {
    int telefon = 2,
    int tablet = 3,
    int genis = 4,
  }) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= genisEsigi) return genis;
    if (w >= tabletEsigi) return tablet;
    return telefon;
  }

  /// Masaüstü: tüm uygulamanın en fazla bu genişliğe yayılması.
  static const double masaustuMaxGenislik = 1440;

  /// Uygulama kökü (MaterialApp.builder) için: çok geniş PC ekranlarında
  /// (tam ekran 1920px+ monitör) her şeyin monitör boyunca gerilmesini
  /// önler — içerik ortalanır, iki yan tema arka planıyla dolar. Telefon/
  /// tablette ([masaustuMaxGenislik] altı) hiçbir etkisi yoktur.
  static Widget uygulamaSarmalayici(BuildContext context, Widget? child) {
    final icerik = child ?? const SizedBox.shrink();
    final w = MediaQuery.sizeOf(context).width;
    if (w <= masaustuMaxGenislik) return icerik;
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: masaustuMaxGenislik),
          child: MediaQuery(
            // Alt widget'lar kendi genişlik kararlarını gerçek kullanılabilir
            // alana göre versin (ör. TsResponsive.genisMi).
            data: MediaQuery.of(context).copyWith(
                size: Size(masaustuMaxGenislik, MediaQuery.sizeOf(context).height)),
            child: icerik,
          ),
        ),
      ),
    );
  }

  /// Formlar/dialoglar için maksimum içerik genişliği. Telefon ekranında
  /// hiçbir etkisi yoktur (ekran zaten daha dar); tablette formun tüm
  /// genişliğe yayılıp "kocaman boş alanlar" oluşturmasını önler.
  static double formMaxGenislik(BuildContext context) =>
      tabletMi(context) ? 560 : double.infinity;

  /// Geniş ekranda formu ortalayıp [formMaxGenislik] ile sınırlayan sarmalayıcı.
  /// [maxGenislik] verilirse [formMaxGenislik] yerine o kullanılır (çok
  /// alanlı formlar için daha geniş). İçerik üste hizalanır.
  static Widget formSarmalayici({
    required BuildContext context,
    required Widget child,
    double? maxGenislik,
  }) {
    if (!tabletMi(context)) return child;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxGenislik ?? formMaxGenislik(context)),
        child: child,
      ),
    );
  }
}
