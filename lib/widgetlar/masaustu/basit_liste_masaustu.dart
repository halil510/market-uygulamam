// lib/widgetlar/masaustu/basit_liste_masaustu.dart
//
// Kategori / Marka / Birim gibi basit tanım listeleri için masaüstü görünüm:
// arama kutusu + tablo + alt şerit (F1 Ekle, F2 Düzenle, F4 Sil) + sağ tık.
// Mobil kart listesi masaüstünde dev kartlar ve "sola kaydırarak sil" gibi
// fareyle zor etkileşimler gösteriyordu (canlı tarama 2026-10-08).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../cekirdek/utils/metin_arama.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import 'ekran_ustte.dart';
import 'masaustu_alt_serit.dart';
import 'masaustu_sag_tik_menu.dart';
import 'masaustu_tablo.dart';

class BasitListeMasaustu<T> extends StatefulWidget {
  final List<T> satirlar;
  final List<TabloKolon<T>> kolonlar;
  final String Function(T satir) aramaMetniAl;
  final String bosMesaj;
  final String kayitEtiketi;
  final VoidCallback? onEkle;
  final void Function(T satir)? onDuzenle;
  final void Function(T satir)? onSil;

  /// Satır silinebilir mi (ör. varsayılan birimler silinemez).
  final bool Function(T satir)? silinebilir;

  const BasitListeMasaustu({
    super.key,
    required this.satirlar,
    required this.kolonlar,
    required this.aramaMetniAl,
    this.bosMesaj = 'Kayıt yok — F1 ile ekleyin',
    this.kayitEtiketi = 'Kayıt',
    this.onEkle,
    this.onDuzenle,
    this.onSil,
    this.silinebilir,
  });

  @override
  State<BasitListeMasaustu<T>> createState() => _BasitListeMasaustuState<T>();
}

class _BasitListeMasaustuState<T> extends State<BasitListeMasaustu<T>> {
  final _aramaCtrl = TextEditingController();
  T? _secili;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_tus);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_tus);
    _aramaCtrl.dispose();
    super.dispose();
  }

  List<T> get _filtreli {
    final q = aramaNormalize(_aramaCtrl.text.trim());
    if (q.isEmpty) return widget.satirlar;
    return widget.satirlar
        .where((s) => aramaNormalize(widget.aramaMetniAl(s)).contains(q))
        .toList();
  }

  /// Liste yenilenince seçimi güncel listede yoksa bırak.
  T? get _gecerliSecili {
    final s = _secili;
    if (s == null || !widget.satirlar.contains(s)) return null;
    return s;
  }

  bool _silinebilir(T s) =>
      widget.onSil != null && (widget.silinebilir?.call(s) ?? true);

  void _menu(T s, Offset konum) {
    masaustuMenuAc(context, konum, [
      if (widget.onDuzenle != null)
        MenuOge('Düzenle', () => widget.onDuzenle!(s), ikon: Icons.edit_outlined),
      if (_silinebilir(s))
        MenuOge('Sil', () => widget.onSil!(s),
            ikon: Icons.delete_outline, ayiracOnce: widget.onDuzenle != null),
    ]);
  }

  bool _tus(KeyEvent e) {
    if (e is! KeyDownEvent || !mounted || !ekranUstte(context)) return false;
    final k = e.logicalKey;
    final s = _gecerliSecili;
    if (k == LogicalKeyboardKey.f1 && widget.onEkle != null) {
      widget.onEkle!();
    } else if (k == LogicalKeyboardKey.f2 && widget.onDuzenle != null) {
      if (s != null) widget.onDuzenle!(s);
    } else if (k == LogicalKeyboardKey.f4 && s != null && _silinebilir(s)) {
      widget.onSil!(s);
    } else {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l = _filtreli;
    final s = _gecerliSecili;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: TextField(
          controller: _aramaCtrl,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            hintText: 'Ara...',
            prefixIcon: Icon(Icons.search),
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
      ),
      Expanded(
        child: l.isEmpty
            ? Center(
                child: Text(
                    _aramaCtrl.text.isEmpty ? widget.bosMesaj : 'Eşleşen kayıt yok',
                    style: TextStyle(fontSize: 15, color: context.textSecondary)))
            : MasaustuTablo<T>(
                satirlar: l,
                kolonlar: widget.kolonlar,
                secili: s,
                onSec: (x) => setState(() => _secili = x),
                onCift: widget.onDuzenle,
                onSagTik: _menu,
              ),
      ),
      MasaustuAltSerit(
        ozetler: [AltOzet(widget.kayitEtiketi, '${widget.satirlar.length}')],
        tuslar: [
          if (widget.onEkle != null)
            AltTus('F1', 'Ekle', Icons.add_circle_outline,
                const Color(0xFF2E7D32), widget.onEkle),
          if (widget.onDuzenle != null)
            AltTus('F2', 'Düzenle', Icons.edit_outlined, const Color(0xFF1565C0),
                s == null ? null : () => widget.onDuzenle!(s)),
          if (widget.onSil != null)
            AltTus('F4', 'Sil', Icons.delete_outline, const Color(0xFFC62828),
                s == null || !_silinebilir(s) ? null : () => widget.onSil!(s)),
        ],
      ),
    ]);
  }
}
