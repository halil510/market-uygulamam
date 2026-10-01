// lib/widgetlar/masaustu/masaustu_tablo.dart
//
// Masaüstü için genel amaçlı VERİ TABLOSU (Stok, Cari, Satış listeleri…).
//  • Sütun başlığına tıkla = sırala (yüklü satırlar içinde)
//  • Satır: tek tık seç, çift tık aç, sağ tık menü, fare üstünde vurgu
//  • Dar pencerede yatay kaydırma; bir sütun kalan genişliği doldurur
//  • Dikey kaydırma denetleyicisi dışarıdan verilebilir (sayfalı yükleme)
import 'package:flutter/material.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../uygulama/tema/uygulama_temasi.dart';

class TabloKolon<T> {
  final String baslik;
  final String Function(T satir) deger;

  /// Sabit genişlik (px). [esnek] true ise en az bu kadar, kalanı doldurur.
  final double genislik;
  final bool esnek;
  final bool sagaYasli;

  /// Sıralama anahtarı (yoksa sütun sıralanamaz).
  final Comparable Function(T satir)? sirala;
  final Color? Function(T satir)? renk;

  const TabloKolon({
    required this.baslik,
    required this.deger,
    this.genislik = 100,
    this.esnek = false,
    this.sagaYasli = false,
    this.sirala,
    this.renk,
  });
}

class MasaustuTablo<T> extends StatefulWidget {
  final List<T> satirlar;
  final List<TabloKolon<T>> kolonlar;
  final T? secili;
  final ValueChanged<T> onSec;
  final ValueChanged<T>? onCift;
  final void Function(T satir, Offset konum)? onSagTik;
  final ScrollController? scrollController;
  final Color baslikRengi;

  const MasaustuTablo({
    super.key,
    required this.satirlar,
    required this.kolonlar,
    required this.onSec,
    this.secili,
    this.onCift,
    this.onSagTik,
    this.scrollController,
    this.baslikRengi = const Color(0xFF1F2A5C),
  });

  @override
  State<MasaustuTablo<T>> createState() => _MasaustuTabloState<T>();
}

class _MasaustuTabloState<T> extends State<MasaustuTablo<T>> {
  int? _siraKolon;
  bool _artan = true;
  int? _vurgu;
  final ScrollController _yatayScroll = ScrollController();

  @override
  void dispose() {
    _yatayScroll.dispose();
    super.dispose();
  }

  List<T> get _gorunen {
    final k = _siraKolon;
    if (k == null) return widget.satirlar;
    final f = widget.kolonlar[k].sirala;
    if (f == null) return widget.satirlar;
    final kopya = List<T>.of(widget.satirlar);
    kopya.sort((a, b) => _artan ? f(a).compareTo(f(b)) : f(b).compareTo(f(a)));
    return kopya;
  }

  void _baslikaTikla(int i) {
    if (widget.kolonlar[i].sirala == null) return;
    setState(() {
      if (_siraKolon == i) {
        _artan = !_artan;
      } else {
        _siraKolon = i;
        _artan = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final sabit = widget.kolonlar
        .where((k) => !k.esnek)
        .fold<double>(0, (t, k) => t + k.genislik);
    final esnekMin = widget.kolonlar
        .where((k) => k.esnek)
        .fold<double>(0, (t, k) => t + k.genislik);
    return LayoutBuilder(builder: (context, kisit) {
      final toplam =
          kisit.maxWidth > sabit + esnekMin ? kisit.maxWidth : sabit + esnekMin;
      final esnekGen = (toplam - sabit) /
          (widget.kolonlar.where((k) => k.esnek).length.clamp(1, 99));
      double gen(TabloKolon<T> k) => k.esnek ? esnekGen : k.genislik;
      final liste = _gorunen;
      return Scrollbar(
        controller: _yatayScroll,
        thumbVisibility: true,
        notificationPredicate: (n) => n.depth == 0,
        child: SingleChildScrollView(
        controller: _yatayScroll,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: toplam,
          child: Column(children: [
            _baslik(gen),
            Expanded(
              child: ListView.builder(
                controller: widget.scrollController,
                itemExtent: 34,
                itemCount: liste.length,
                itemBuilder: (_, i) => _satir(context, liste[i], i, gen),
              ),
            ),
          ]),
        ),
      ),
      );
    });
  }

  Widget _baslik(double Function(TabloKolon<T>) gen) {
    return Container(
      height: 36,
      color: widget.baslikRengi,
      child: Row(children: [
        for (var i = 0; i < widget.kolonlar.length; i++)
          InkWell(
            onTap: () => _baslikaTikla(i),
            child: SizedBox(
              width: gen(widget.kolonlar[i]),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisAlignment: widget.kolonlar[i].sagaYasli
                      ? MainAxisAlignment.end
                      : MainAxisAlignment.start,
                  children: [
                    Flexible(
                      child: Text(widget.kolonlar[i].baslik,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700)),
                    ),
                    if (_siraKolon == i)
                      Icon(_artan ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                          size: 18, color: Colors.white),
                  ],
                ),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _satir(BuildContext context, T s, int i, double Function(TabloKolon<T>) gen) {
    final secili = identical(s, widget.secili) || s == widget.secili;
    final vurgu = _vurgu == i;
    final zemin = secili
        ? TsRenk.primary.withValues(alpha: 0.16)
        : vurgu
            ? TsRenk.primary.withValues(alpha: 0.07)
            : (i.isEven ? context.cardBg : context.scaffoldBg.withValues(alpha: 0.6));
    return MouseRegion(
      onEnter: (_) => setState(() => _vurgu = i),
      onExit: (_) => setState(() => _vurgu = null),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onSec(s),
        onDoubleTap: widget.onCift == null ? null : () => widget.onCift!(s),
        onSecondaryTapDown: widget.onSagTik == null
            ? null
            : (d) {
                widget.onSec(s);
                widget.onSagTik!(s, d.globalPosition);
              },
        child: Container(
          color: zemin,
          child: Row(children: [
            for (final k in widget.kolonlar)
              SizedBox(
                width: gen(k),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(k.deger(s),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: k.sagaYasli ? TextAlign.right : TextAlign.left,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: secili ? FontWeight.w700 : FontWeight.w500,
                          color: k.renk?.call(s) ?? context.textPrimary)),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
