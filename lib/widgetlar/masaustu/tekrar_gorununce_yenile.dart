// lib/widgetlar/masaustu/tekrar_gorununce_yenile.dart
//
// Listeleme ekranının üstü başka bir sayfayla örtülüp sonra tekrar
// görünür olduğunda verisini yenilemesi için.
//
// Neden: Windows'ta menü sayfaları üst üste açılır (push). Ürünler listesi
// alttayken Hızlı Satış'ta satış yapılıp Geri'ye basılınca liste satıştan
// ÖNCEKİ stoğu gösteriyordu (2026-10-07 canlı testi: Deterjan DB'de 49,
// ekranda 50). Opak bir sayfanın altında kalan ekran Flutter tarafından
// TickerMode=false ile işaretlenir (bkz. ekran_ustte.dart); false → true
// geçişi "ekran tekrar öne geldi" demektir.
import 'package:flutter/widgets.dart';

mixin TekrarGorununceYenile<T extends StatefulWidget> on State<T> {
  bool? _sonGorunur;

  /// Ekran örtüldükten sonra tekrar görünür olunca çağrılır (ilk açılışta değil).
  void tekrarGorununce();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final gorunur = TickerMode.valuesOf(context).enabled;
    if (_sonGorunur == false && gorunur) {
      // Build sırasında sağlayıcı durumunu değiştirmemek için kare sonrasına.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) tekrarGorununce();
      });
    }
    _sonGorunur = gorunur;
  }
}
