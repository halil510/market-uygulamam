// lib/uygulama/masaustu/masaustu_olcek.dart
//
// Windows: büyük ekranlarda (24" all-in-one, 1080p/1440p/4K monitör) arayüz
// küçük kalıyordu — uygulama pencereyi kaplıyor ama yazılar/butonlar sanki
// 1366x768 ekran içindeymiş gibi küçük çiziliyordu. Bu sarmalayıcı, pencere
// 1366x768 tasarım ölçüsünden büyükse tüm arayüzü orantılı büyütür; alt
// widget'lar MediaQuery'den "büyütülmüş" (daha küçük) mantıksal boyutu görür,
// böylece mevcut genişlik eşikleri (ör. 1100px tablo görünümü) doğru çalışır.
// Mobilde ve küçük pencerede hiçbir etkisi yoktur (ölçek 1.0).
import 'package:flutter/material.dart';

class MasaustuOlcek extends StatelessWidget {
  final Widget child;
  const MasaustuOlcek({super.key, required this.child});

  static const double _tasarimGenislik = 1366;
  static const double _tasarimYukseklik = 768;
  static const double _enFazla = 1.8;

  /// [pencere] mantıksal boyutuna göre arayüz ölçeği (1.0 ≤ ölçek ≤ 1.8).
  static double hesapla(Size pencere) {
    final o = pencere.width / _tasarimGenislik < pencere.height / _tasarimYukseklik
        ? pencere.width / _tasarimGenislik
        : pencere.height / _tasarimYukseklik;
    if (o <= 1.05) return 1.0; // küçük farklar için bulanıklık/kayma yaratma
    return o > _enFazla ? _enFazla : o;
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final olcek = hesapla(mq.size);
    if (olcek == 1.0) return child;
    final w = mq.size.width / olcek;
    final h = mq.size.height / olcek;
    return SizedBox(
      width: mq.size.width,
      height: mq.size.height,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: w,
          maxWidth: w,
          minHeight: h,
          maxHeight: h,
          child: Transform.scale(
            scale: olcek,
            alignment: Alignment.topLeft,
            child: MediaQuery(
              data: mq.copyWith(size: Size(w, h)),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
