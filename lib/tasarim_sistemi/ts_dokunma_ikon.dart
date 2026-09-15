// lib/tasarim_sistemi/ts_dokunma_ikon.dart
//
// Kullanıcı isteği: dokunulabilir ikonlara görsel geri bildirim —
// mevcut Material ripple'a EK olarak, basılı tutulduğu sürece kısa bir
// büzülme (scale) + renk koyulaşması animasyonu. onHighlightChanged
// InkWell'in kendi basılı/bırakıldı durumunu bildirdiği için ayrı bir
// GestureDetector'a gerek yok — jest arenası çakışması riski taşımaz.
import 'package:flutter/material.dart';

class TsDokunmaIkon extends StatefulWidget {
  final IconData ikon;
  final double boyut;
  final Color renk;
  final VoidCallback? onTap;
  final String? tooltip;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  const TsDokunmaIkon({
    super.key,
    required this.ikon,
    required this.onTap,
    this.boyut = 24,
    this.renk = Colors.white,
    this.tooltip,
    this.padding = const EdgeInsets.all(8),
    this.borderRadius = 24,
  });

  @override
  State<TsDokunmaIkon> createState() => _TsDokunmaIkonState();
}

class _TsDokunmaIkonState extends State<TsDokunmaIkon> {
  bool _basili = false;

  @override
  Widget build(BuildContext context) {
    final renk =
        _basili ? Color.lerp(widget.renk, Colors.black, 0.25)! : widget.renk;

    Widget child = AnimatedScale(
      scale: _basili ? 0.88 : 1.0,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: Icon(widget.ikon, size: widget.boyut, color: renk),
    );

    child = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        onHighlightChanged: widget.onTap == null
            ? null
            : (v) {
                if (mounted) setState(() => _basili = v);
              },
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: Padding(padding: widget.padding, child: child),
      ),
    );

    final tooltip = widget.tooltip;
    if (tooltip != null) {
      child = Tooltip(message: tooltip, child: child);
    }
    return child;
  }
}
