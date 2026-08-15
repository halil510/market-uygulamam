// lib/ekranlar/satis/widgets/kamera_paneli.dart
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
class SatisKameraPaneli extends StatefulWidget {
  final MobileScannerController controller;
  final bool flash;
  final void Function(String) onBarkod;
  final VoidCallback onKapat;
  final VoidCallback onFlashToggle;

  const SatisKameraPaneli({
    super.key,
    required this.controller,
    required this.flash,
    required this.onBarkod,
    required this.onKapat,
    required this.onFlashToggle,
  });

  @override
  State<SatisKameraPaneli> createState() => _SatisKameraPaneliState();
}

class _SatisKameraPaneliState extends State<SatisKameraPaneli>
    with SingleTickerProviderStateMixin {
  late final AnimationController _lazerCtrl;
  late final Animation<double>   _lazerAnim;

  @override
  void initState() {
    super.initState();
    _lazerCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _lazerAnim = CurvedAnimation(parent: _lazerCtrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() { _lazerCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final panelH = MediaQuery.of(context).size.height < 700 ? 200.0 : 260.0;
    return SizedBox(
      height: panelH,
      child: Stack(children: [
        // Kamera
        ClipRRect(
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
          child: MobileScanner(
            controller: widget.controller,
            onDetect: (capture) {
              final barkod = capture.barcodes.firstOrNull?.rawValue;
              if (barkod != null && barkod.isNotEmpty) widget.onBarkod(barkod);
            },
          ),
        ),
        // Üst gradient
        Positioned(top: 0, left: 0, right: 0,
          child: Container(height: panelH * 0.15,
            decoration: BoxDecoration(gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Colors.black.withAlpha(153), Colors.transparent])),
          ),
        ),
        // Alt gradient
        Positioned(bottom: 0, left: 0, right: 0,
          child: Container(height: panelH * 0.2,
            decoration: BoxDecoration(gradient: LinearGradient(
              begin: Alignment.bottomCenter, end: Alignment.topCenter,
              colors: [Colors.black.withAlpha(153), Colors.transparent])),
          ),
        ),
        // Tarama çerçevesi
        Center(child: Container(
          width: 240, height: 140,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white, width: 2),
            borderRadius: BorderRadius.circular(12)),
          child: const Stack(children: [
            Positioned(top: -1, left: -1, child: _Kose(Colors.greenAccent, true, true)),
            Positioned(top: -1, right: -1, child: _Kose(Colors.greenAccent, true, false)),
            Positioned(bottom: -1, left: -1, child: _Kose(Colors.greenAccent, false, true)),
            Positioned(bottom: -1, right: -1, child: _Kose(Colors.greenAccent, false, false)),
          ]),
        )),
        // Lazer animasyonu
        AnimatedBuilder(animation: _lazerAnim, builder: (_, __) {
          final top = panelH * 0.3 + (_lazerAnim.value * panelH * 0.35);
          return Positioned(top: top, left: 40, right: 40,
            child: Container(height: 2,
              decoration: BoxDecoration(
                color: Colors.red.shade400,
                boxShadow: const [BoxShadow(color: Color(0x80FF0000), blurRadius: 6)])));
        }),
        // Kontrol butonları
        Positioned(top: 8, right: 8,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _KontrolButon(
              widget.flash ? Icons.flash_on : Icons.flash_off,
              widget.onFlashToggle, Colors.black38),
            const SizedBox(width: 6),
            _KontrolButon(Icons.close, widget.onKapat,
                const Color(0xD9C62828)),
          ]),
        ),
        // Alt yazı
        Positioned(bottom: 8, left: 0, right: 0,
          child: Center(child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black54, borderRadius: BorderRadius.circular(12)),
            child: const Text('Barkodu çerçeve içine getirin',
                style: TextStyle(color: Colors.white70, fontSize: 11)),
          )),
        ),
      ]),
    );
  }
}

class _Kose extends StatelessWidget {
  final Color renk;
  final bool ust, sol;
  const _Kose(this.renk, this.ust, this.sol);
  @override
  Widget build(BuildContext context) {
    final k = BorderSide(color: renk, width: 3);
    const n = BorderSide.none;
    return Container(width: 20, height: 20,
      decoration: BoxDecoration(border: Border(
        top:    ust ? k : n, bottom: ust ? n : k,
        left:   sol ? k : n, right:  sol ? n : k,
      )));
  }
}

class _KontrolButon extends StatelessWidget {
  final IconData ikon;
  final VoidCallback onTap;
  final Color bg;
  const _KontrolButon(this.ikon, this.onTap, this.bg);
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: IconButton(
        icon: Icon(ikon, color: Colors.white, size: 20),
        onPressed: onTap, padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      ),
    );
  }
}
