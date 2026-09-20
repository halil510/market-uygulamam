// lib/widgetlar/ortak/tap_scale.dart
//
// Dokununca hafifçe küçülen, bırakınca geri büyüyen kart sarmalayıcısı —
// dashboard kartlarına "dokunma hissi" kazandırır. Önceden dashboard_
// ekrani.dart'ta private (_TapScale) tanımlıydı; dashboard'un istatistik
// sayfası ayrı bir widget'a taşınırken (mimari denetim: 1663 satırlık
// tek dosya) ikisi arasında paylaşılması gerektiği için ortak bir
// dosyaya çıkarıldı. DAVRANIŞ DEĞİŞMEDİ — saf bir taşıma.
import 'package:flutter/material.dart';

class TapScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const TapScale({super.key, required this.child, this.onTap});

  @override
  State<TapScale> createState() => _TapScaleState();
}

class _TapScaleState extends State<TapScale> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown:
          widget.onTap == null ? null : (_) => setState(() => _scale = 0.94),
      onTapUp:
          widget.onTap == null ? null : (_) => setState(() => _scale = 1.0),
      onTapCancel:
          widget.onTap == null ? null : () => setState(() => _scale = 1.0),
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
