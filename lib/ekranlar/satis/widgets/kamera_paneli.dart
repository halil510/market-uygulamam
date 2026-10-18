// lib/ekranlar/satis/widgets/kamera_paneli.dart
//
// Hızlı satış kamera paneli — mobile_scanner 7.4.2
//
// ÖZELLİKLER
//  • scanWindow: yalnız çerçevenin içi taranır, çerçeve dışı karartılır
//    (hedef çerçevesi ile gerçek tarama alanı birebir aynı dikdörtgendir)
//  • Çift okuma koruması: aynı barkod çerçevede durdukça TEKRAR iletilmez;
//    barkod çerçeveden çıkıp yeniden girince (>= ayniBarkodBosluk) yeni
//    okuma sayılır → kasiyer aynı ürünü art arda okutabilir, ama elini
//    çerçevede beklettiğinde ürün 2 kez eklenmez
//  • Zoom: − / + butonları ve iki parmakla kıstırma
//    (mobile_scanner setZoomScale 0.0–1.0 aralığını bekler)
//  • Işık: ikon, kameranın GERÇEK torch durumunu gösterir
//  • İzin / kamera hatası ekranı: "Ayarları Aç", "Tekrar Dene", "Kapat"
//  • Okuma geri bildirimi: çerçeve yeşile döner, okunan kod gösterilir
//
// Controller'ı üst widget oluşturur → BarkodServisi.tarayiciOlustur()
// (format kısıtlaması + çözünürlük ayarları tek yerde).
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart'
    show openAppSettings;
import '../../../tasarim_sistemi/ts_token.dart';

class SatisKameraPaneli extends StatefulWidget {
  final MobileScannerController controller;
  final bool flash;
  final void Function(String) onBarkod;
  final VoidCallback onKapat;
  final VoidCallback onFlashToggle;

  /// Aynı barkodun "çerçeveden çıktı" sayılması için gereken boşluk.
  /// Barkod bu süreden kısa aralıklarla görünmeye devam ediyorsa tekrar
  /// okuma sayılmaz.
  final Duration ayniBarkodBosluk;

  const SatisKameraPaneli({
    super.key,
    required this.controller,
    required this.flash,
    required this.onBarkod,
    required this.onKapat,
    required this.onFlashToggle,
    this.ayniBarkodBosluk = const Duration(milliseconds: 500),
  });

  @override
  State<SatisKameraPaneli> createState() => _SatisKameraPaneliState();
}

class _SatisKameraPaneliState extends State<SatisKameraPaneli>
    with SingleTickerProviderStateMixin {
  static const double _zoomAdimi = 0.15;

  late final AnimationController _lazerCtrl;
  late final Animation<double> _lazerAnim;

  // Zoom (0.0 = 1x, 1.0 = cihazın azami yakınlaştırması)
  double _zoom = 0.0;
  double _zoomBaslangic = 0.0;
  bool _calisiyordu = false;

  // Çift okuma koruması
  String? _sonBarkod;
  DateTime? _sonGorulme;

  // Geri bildirim
  bool _basari = false;
  String? _sonOkunan;
  Timer? _basariTimer;
  Timer? _okunanTimer;

  @override
  void initState() {
    super.initState();
    _lazerCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _lazerAnim = CurvedAnimation(parent: _lazerCtrl, curve: Curves.easeInOut);
    _calisiyordu = widget.controller.value.isRunning;
    widget.controller.addListener(_kontrolDegisti);
  }

  @override
  void didUpdateWidget(covariant SatisKameraPaneli eski) {
    super.didUpdateWidget(eski);
    if (eski.controller != widget.controller) {
      eski.controller.removeListener(_kontrolDegisti);
      widget.controller.addListener(_kontrolDegisti);
      _calisiyordu = widget.controller.value.isRunning;
      _zoom = 0.0;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_kontrolDegisti);
    _basariTimer?.cancel();
    _okunanTimer?.cancel();
    _lazerCtrl.dispose();
    super.dispose();
  }

  /// Kamera yeniden başlayınca (diyalog / arka plan dönüşü) zoom'un platforma
  /// göre korunup korunmayacağı belli değil (Android'de kamera yeniden
  /// bağlanınca sıfırlanır). Göstergeyle donanım ayrışmasın diye son zoom
  /// değeri kameraya TEKRAR uygulanır. Kamera çalışmıyorsa setZoomScale
  /// zaten etkisizdir; hata yutulur.
  void _kontrolDegisti() {
    final calisiyor = widget.controller.value.isRunning;
    if (calisiyor && !_calisiyordu && _zoom > 0.0 && mounted) {
      unawaited(widget.controller
          .setZoomScale(_zoom)
          .then<void>((_) {}, onError: (_) {}));
    }
    _calisiyordu = calisiyor;
  }

  // ── Okuma ────────────────────────────────────────────────────────────

  void _algilandi(BarcodeCapture capture) {
    // Panel kapanırken gelen son kare setState'i dispose sonrası çağırmasın.
    if (!mounted) return;
    String? secilen;
    for (final b in capture.barcodes) {
      final raw = b.rawValue?.trim();
      if (raw != null && raw.isNotEmpty) {
        secilen = raw;
        break;
      }
    }
    if (secilen == null) return;

    final simdi = DateTime.now();
    final halaCercevede = _sonBarkod == secilen &&
        _sonGorulme != null &&
        simdi.difference(_sonGorulme!) < widget.ayniBarkodBosluk;
    _sonBarkod = secilen;
    _sonGorulme = simdi; // bastırılan karelerde de güncellenir
    if (halaCercevede) return;

    _geriBildirimVer(secilen);
    widget.onBarkod(secilen);
  }

  void _geriBildirimVer(String barkod) {
    _basariTimer?.cancel();
    _okunanTimer?.cancel();
    setState(() {
      _basari = true;
      _sonOkunan = barkod;
    });
    _basariTimer = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _basari = false);
    });
    _okunanTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _sonOkunan = null);
    });
  }

  // ── Zoom ─────────────────────────────────────────────────────────────

  Future<void> _zoomAyarla(double yeni) async {
    final z = yeni.clamp(0.0, 1.0).toDouble();
    if ((z - _zoom).abs() < 0.001) return;
    setState(() => _zoom = z);
    try {
      await widget.controller.setZoomScale(z);
    } catch (_) {
      // Kamera henüz hazır değil / cihaz zoom desteklemiyor → yoksay
    }
  }

  Future<void> _yenidenDene() async {
    try {
      await widget.controller.start();
    } catch (_) {}
  }

  // ── Arayüz ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final panelH = MediaQuery.of(context).size.height < 700 ? 200.0 : 260.0;
    return SizedBox(
      height: panelH,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
        child: LayoutBuilder(builder: (context, c) {
          // %72: sol üstteki zoom butonlarıyla çerçeve köşesi çakışmasın
          final genislik = (c.maxWidth * 0.72).clamp(0.0, 420.0).toDouble();
          final yukseklik = c.maxHeight * 0.52;
          // Tarama alanı = hedef çerçevesi (aynı dikdörtgen)
          final scanRect = Rect.fromCenter(
            center: Offset(c.maxWidth / 2, c.maxHeight * 0.47),
            width: genislik,
            height: yukseklik,
          );
          final cerceveRenk = _basari ? Colors.greenAccent : Colors.white70;

          return Stack(children: [
            // Kamera (+ iki parmakla zoom)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onScaleStart: (_) => _zoomBaslangic = _zoom,
                onScaleUpdate: (d) {
                  if (d.pointerCount < 2) return;
                  _zoomAyarla(_zoomBaslangic + (d.scale - 1.0) * 0.5);
                },
                child: MobileScanner(
                  controller: widget.controller,
                  scanWindow: scanRect,
                  onDetect: _algilandi,
                  errorBuilder: (context, error) => _hataGorunumu(error),
                ),
              ),
            ),
            // Çerçeve dışını karart
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _KarartmaBoyaci(scanRect)),
              ),
            ),
            // Üst gradient
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Container(
                  height: panelH * 0.15,
                  decoration: BoxDecoration(
                      gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                        Colors.black.withAlpha(153),
                        Colors.transparent
                      ])),
                ),
              ),
            ),
            // Alt gradient
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Container(
                  height: panelH * 0.2,
                  decoration: BoxDecoration(
                      gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                        Colors.black.withAlpha(153),
                        Colors.transparent
                      ])),
                ),
              ),
            ),
            // Hedef çerçevesi
            Positioned.fromRect(
              rect: scanRect,
              child: IgnorePointer(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    color: _basari
                        ? Colors.greenAccent.withAlpha(46)
                        : Colors.transparent,
                    border: Border.all(
                        color: cerceveRenk, width: _basari ? 3 : 1.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Stack(children: [
                    Positioned(
                        top: 0,
                        left: 0,
                        child: _Kose(Colors.greenAccent, true, true)),
                    Positioned(
                        top: 0,
                        right: 0,
                        child: _Kose(Colors.greenAccent, true, false)),
                    Positioned(
                        bottom: 0,
                        left: 0,
                        child: _Kose(Colors.greenAccent, false, true)),
                    Positioned(
                        bottom: 0,
                        right: 0,
                        child: _Kose(Colors.greenAccent, false, false)),
                  ]),
                ),
              ),
            ),
            // Lazer çizgisi (çerçevenin içinde gezer)
            if (!_basari)
              AnimatedBuilder(
                  animation: _lazerAnim,
                  builder: (_, _) {
                    final top = scanRect.top +
                        8 +
                        _lazerAnim.value * (scanRect.height - 16);
                    return Positioned(
                      top: top,
                      left: scanRect.left + 10,
                      width: scanRect.width - 20,
                      child: IgnorePointer(
                        child: Container(
                          height: 2,
                          decoration: const BoxDecoration(
                              color: TsRenk.hata,
                              boxShadow: [
                                BoxShadow(
                                    color: Color(0x80FF0000), blurRadius: 6)
                              ]),
                        ),
                      ),
                    );
                  }),
            // Zoom kontrolleri (sol üst)
            Positioned(
              top: 8,
              left: 8,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _KontrolButon(
                  Icons.zoom_in,
                  _zoom < 1.0 ? () => _zoomAyarla(_zoom + _zoomAdimi) : null,
                  Colors.black38,
                  tooltip: 'Yakınlaştır',
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text('%${(_zoom * 100).round()}',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 10)),
                ),
                _KontrolButon(
                  Icons.zoom_out,
                  _zoom > 0.0 ? () => _zoomAyarla(_zoom - _zoomAdimi) : null,
                  Colors.black38,
                  tooltip: 'Uzaklaştır',
                ),
              ]),
            ),
            // Işık + kapat (sağ üst)
            Positioned(
              top: 8,
              right: 8,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                ValueListenableBuilder<MobileScannerState>(
                  valueListenable: widget.controller,
                  builder: (_, durum, _) {
                    final acik = durum.torchState == TorchState.on ||
                        (durum.torchState == TorchState.unavailable &&
                            widget.flash);
                    return _KontrolButon(
                      acik ? Icons.flash_on : Icons.flash_off,
                      widget.onFlashToggle,
                      acik ? const Color(0xB3FFA000) : Colors.black38,
                      tooltip: 'Işık',
                    );
                  },
                ),
                const SizedBox(width: 6),
                _KontrolButon(Icons.close, widget.onKapat,
                    const Color(0xD9C62828),
                    tooltip: 'Kapat'),
              ]),
            ),
            // Alt bilgi: son okunan kod veya ipucu
            Positioned(
              bottom: 8,
              left: 12,
              right: 12,
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                        color: _sonOkunan != null
                            ? const Color(0xCC1B5E20)
                            : Colors.black54,
                        borderRadius: BorderRadius.circular(12)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (_sonOkunan != null) ...[
                        const Icon(Icons.check_circle,
                            color: Colors.greenAccent, size: 14),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: Text(
                          _sonOkunan ?? 'Barkodu çerçeve içine getirin',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: _sonOkunan != null
                                  ? Colors.white
                                  : Colors.white70,
                              fontSize: 11,
                              fontWeight: _sonOkunan != null
                                  ? FontWeight.w600
                                  : FontWeight.normal),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ]);
        }),
      ),
    );
  }

  Widget _hataGorunumu(MobileScannerException error) {
    final izinYok = error.errorCode == MobileScannerErrorCode.permissionDenied;
    final mesaj = izinYok
        ? 'Kamera izni verilmedi. Barkod okutmak için izin vermelisiniz.'
        : 'Kamera başlatılamadı (${error.errorCode.name}).';
    return ColoredBox(
      color: Colors.black87,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.no_photography_outlined,
                color: Colors.white54, size: 36),
            const SizedBox(height: 8),
            Text(mesaj,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              alignment: WrapAlignment.center,
              children: [
                if (izinYok)
                  FilledButton.tonal(
                    onPressed: () => openAppSettings(),
                    child: const Text('Ayarları Aç'),
                  ),
                OutlinedButton(
                  onPressed: _yenidenDene,
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70),
                  child: const Text('Tekrar Dene'),
                ),
                TextButton(
                  onPressed: widget.onKapat,
                  style:
                      TextButton.styleFrom(foregroundColor: Colors.white54),
                  child: const Text('Kapat'),
                ),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}

/// Tarama çerçevesi dışını karartır (çerçeve içi şeffaf kalır).
class _KarartmaBoyaci extends CustomPainter {
  final Rect pencere;
  const _KarartmaBoyaci(this.pencere);

  @override
  void paint(Canvas canvas, Size size) {
    final yol = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(pencere, const Radius.circular(12)));
    canvas.drawPath(yol, Paint()..color = const Color(0x73000000));
  }

  @override
  bool shouldRepaint(covariant _KarartmaBoyaci eski) =>
      eski.pencere != pencere;
}

class _Kose extends StatelessWidget {
  final Color renk;
  final bool ust, sol;
  const _Kose(this.renk, this.ust, this.sol);
  @override
  Widget build(BuildContext context) {
    final k = BorderSide(color: renk, width: 3);
    const n = BorderSide.none;
    return Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
            border: Border(
          top: ust ? k : n,
          bottom: ust ? n : k,
          left: sol ? k : n,
          right: sol ? n : k,
        )));
  }
}

class _KontrolButon extends StatelessWidget {
  final IconData ikon;
  final VoidCallback? onTap;
  final Color bg;
  final String? tooltip;
  const _KontrolButon(this.ikon, this.onTap, this.bg, {this.tooltip});
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: IconButton(
        icon: Icon(ikon, size: 20),
        color: Colors.white,
        disabledColor: Colors.white30,
        tooltip: tooltip,
        onPressed: onTap,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      ),
    );
  }
}
