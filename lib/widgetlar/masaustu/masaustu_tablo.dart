// lib/widgetlar/masaustu/masaustu_tablo.dart
//
// Masaüstü için genel amaçlı VERİ TABLOSU (Stok, Cari, Satış listeleri…).
//  • Sütun başlığına tıkla = sırala (yüklü satırlar içinde)
//  • Satır: tek tık seç, çift tık aç, sağ tık menü, fare üstünde vurgu
//  • İsteğe bağlı ÇOKLU SEÇİM ([seciliAnahtarlar] + [onCokluSecim]):
//    Ctrl+tık ekle/çıkar, Shift+tık aralık, fareyle sürükleyerek aralık
//  • Dar pencerede yatay kaydırma; bir sütun kalan genişliği doldurur
//  • Dikey kaydırma denetleyicisi dışarıdan verilebilir (sayfalı yükleme)
import 'package:flutter/gestures.dart' show kPrimaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  /// Çoklu seçim: satırın kalıcı anahtarı (ör. id) — yeniden yüklemede
  /// nesne değişse de seçim korunur. [seciliAnahtarlar] ve [onCokluSecim]
  /// birlikte verilirse çoklu seçim açılır (seçim dışarıda tutulur).
  final Object Function(T satir)? anahtar;
  final Set<Object>? seciliAnahtarlar;
  final ValueChanged<Set<Object>>? onCokluSecim;

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
    this.anahtar,
    this.seciliAnahtarlar,
    this.onCokluSecim,
  });

  @override
  State<MasaustuTablo<T>> createState() => _MasaustuTabloState<T>();
}

class _MasaustuTabloState<T> extends State<MasaustuTablo<T>> {
  int? _siraKolon;
  bool _artan = true;
  int? _vurgu;
  final ScrollController _yatayScroll = ScrollController();
  final ScrollController _icDikey = ScrollController();
  ScrollController get _dikey => widget.scrollController ?? _icDikey;

  static const _satirYuksekligi = 34.0;

  // Çoklu seçim durumu (görünen sıradaki indeksler).
  int? _capa; // Shift+tık aralığının başlangıcı
  int? _surukleBas; // fare basılı tutulan satır
  bool _suruklendi = false;
  bool _basiliCtrl = false; // fareye basıldığı andaki tuş durumu
  bool _basiliShift = false;

  bool get _cokluAcik => widget.onCokluSecim != null && widget.seciliAnahtarlar != null;
  Object _anahtar(T s) => widget.anahtar?.call(s) ?? s as Object;

  @override
  void dispose() {
    _yatayScroll.dispose();
    _icDikey.dispose();
    super.dispose();
  }

  // ── Çoklu seçim ───────────────────────────────────────────────────────────
  void _tikla(List<T> liste, int i) {
    final s = liste[i];
    widget.onSec(s);
    if (!_cokluAcik) return;
    // Ctrl/Shift fareye BASILDIĞI an okunur: satırda çift tık da tanımlı
    // olduğundan onTap ~300 ms geç gelir; tuş o arada bırakılırsa seçim
    // sessizce düz tıka dönüyordu (canlı testte bulundu).
    final ctrl = _basiliCtrl;
    final shift = _basiliShift;
    final capa = _capa;
    if (shift && capa != null && capa < liste.length) {
      widget.onCokluSecim!(_aralik(liste, capa, i));
      return; // çapa yerinde kalır: Shift ile aralık genişletilebilir
    }
    if (ctrl) {
      final yeni = Set<Object>.of(widget.seciliAnahtarlar!);
      // İlk Ctrl+tıkta tek seçili satır (henüz kümede değil) da kümeye girer.
      final tekSecili = widget.secili;
      if (yeni.isEmpty && tekSecili != null && !identical(tekSecili, s)) {
        yeni.add(_anahtar(tekSecili));
      }
      final k = _anahtar(s);
      yeni.contains(k) ? yeni.remove(k) : yeni.add(k);
      widget.onCokluSecim!(yeni);
    } else {
      widget.onCokluSecim!({_anahtar(s)});
    }
    _capa = i;
  }

  Set<Object> _aralik(List<T> liste, int a, int b) {
    final bas = a < b ? a : b, son = a < b ? b : a;
    return {for (var j = bas; j <= son; j++) _anahtar(liste[j])};
  }

  int _satirIndeksi(Offset yerel, int adet) =>
      ((yerel.dy + (_dikey.hasClients ? _dikey.offset : 0)) ~/ _satirYuksekligi)
          .clamp(0, adet - 1);

  void _basildi(PointerDownEvent e, List<T> liste) {
    final klavye = HardwareKeyboard.instance;
    _basiliCtrl = klavye.isControlPressed || klavye.isMetaPressed;
    _basiliShift = klavye.isShiftPressed;
    if (!_cokluAcik || liste.isEmpty || e.buttons != kPrimaryMouseButton ||
        _basiliCtrl || _basiliShift) {
      return;
    }
    _surukleBas = _satirIndeksi(e.localPosition, liste.length);
    _suruklendi = false;
  }

  void _surukleniyor(PointerMoveEvent e, List<T> liste, double yukseklik) {
    final bas = _surukleBas;
    if (bas == null || e.buttons != kPrimaryMouseButton) return;
    // Kenara yaklaşınca listeyi kaydır (görünmeyen satırlara da uzanabilsin).
    if (_dikey.hasClients) {
      final p = _dikey.position;
      if (e.localPosition.dy > yukseklik - 16 && _dikey.offset < p.maxScrollExtent) {
        _dikey.jumpTo((_dikey.offset + _satirYuksekligi / 2).clamp(0, p.maxScrollExtent));
      } else if (e.localPosition.dy < 16 && _dikey.offset > 0) {
        _dikey.jumpTo((_dikey.offset - _satirYuksekligi / 2).clamp(0, p.maxScrollExtent));
      }
    }
    final i = _satirIndeksi(e.localPosition, liste.length);
    if (i == bas && !_suruklendi) return;
    _suruklendi = true;
    _capa = bas;
    widget.onCokluSecim!(_aralik(liste, bas, i));
  }

  void _birakildi() {
    _surukleBas = null;
    _suruklendi = false;
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
              child: LayoutBuilder(
                builder: (context, govde) => Listener(
                  onPointerDown: (e) => _basildi(e, liste),
                  onPointerMove: (e) => _surukleniyor(e, liste, govde.maxHeight),
                  onPointerUp: (_) => _birakildi(),
                  onPointerCancel: (_) => _birakildi(),
                  child: ListView.builder(
                    controller: _dikey,
                    itemExtent: _satirYuksekligi,
                    itemCount: liste.length,
                    itemBuilder: (_, i) => _satir(context, liste, i, gen),
                  ),
                ),
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

  Widget _satir(BuildContext context, List<T> liste, int i, double Function(TabloKolon<T>) gen) {
    final s = liste[i];
    final coklu = widget.seciliAnahtarlar;
    final secili = (coklu != null && coklu.isNotEmpty)
        ? coklu.contains(_anahtar(s))
        : identical(s, widget.secili) || s == widget.secili;
    final vurgu = _vurgu == i;
    final zemin = secili
        ? TsRenk.primary.withValues(alpha: 0.32)
        : vurgu
            ? TsRenk.primary.withValues(alpha: 0.15)
            : (i.isEven ? context.cardBg : context.scaffoldBg.withValues(alpha: 0.6));
    return MouseRegion(
      onEnter: (_) => setState(() => _vurgu = i),
      onExit: (_) => setState(() => _vurgu = null),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _tikla(liste, i),
        onDoubleTap: widget.onCift == null ? null : () => widget.onCift!(s),
        onSecondaryTapDown: widget.onSagTik == null
            ? null
            : (d) {
                // Çoklu seçimin İÇİNDEKİ satıra sağ tık seçimi bozmaz (menü
                // seçilenlere uygulanır); dışındaki satır tek seçim olur.
                final coklu = widget.seciliAnahtarlar;
                if (!(coklu != null && coklu.contains(_anahtar(s)))) {
                  widget.onSec(s);
                  if (_cokluAcik) widget.onCokluSecim!({_anahtar(s)});
                  _capa = i;
                }
                widget.onSagTik!(s, d.globalPosition);
              },
        child: ColoredBox(
          color: zemin,
          // Seçili satır belirgin: koyu zemin + sol kenarda 4px vurgu çubuğu.
          // Çubuk satırın üstüne ÇİZİLİR (kenarlık değil): kenarlık içeriği
          // 4px daraltıp satırı taşırıyor ve başlıkla kolonları kaydırıyordu.
          child: Stack(children: [
            Row(children: [
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
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 4,
              child: ColoredBox(
                  color: secili
                      ? TsRenk.primary
                      : (vurgu ? TsRenk.primary.withValues(alpha: 0.45) : Colors.transparent)),
            ),
          ]),
        ),
      ),
    );
  }
}
