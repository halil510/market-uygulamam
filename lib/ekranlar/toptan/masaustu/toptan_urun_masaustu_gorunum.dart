// lib/ekranlar/toptan/masaustu/toptan_urun_masaustu_gorunum.dart
//
// Toptan satış ürün listesi — masaüstü tablo görünümü: fiyat kırılımı sütunlar
// halinde (alış / KDV dahil alış / satış / toptan / koli), sağ tık ve F4 ile
// "Listeden Kaldır". Ürün EKLEME çağıran ekrandaki arama kutusundan yapılır.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../cekirdek/utils/para_utils.dart';
import '../../../modeller/urun_model.dart';
import '../../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../../widgetlar/masaustu/ekran_ustte.dart';
import '../../../widgetlar/masaustu/masaustu_alt_serit.dart';
import '../../../widgetlar/masaustu/masaustu_sag_tik_menu.dart';
import '../../../widgetlar/masaustu/masaustu_tablo.dart';

class ToptanUrunMasaustuGorunum extends StatefulWidget {
  final List<UrunModel> urunler;
  final void Function(UrunModel u) onKaldir;

  const ToptanUrunMasaustuGorunum({
    super.key,
    required this.urunler,
    required this.onKaldir,
  });

  @override
  State<ToptanUrunMasaustuGorunum> createState() => _ToptanUrunMasaustuGorunumState();
}

class _ToptanUrunMasaustuGorunumState extends State<ToptanUrunMasaustuGorunum> {
  UrunModel? _secili;

  static String _para(double v) => v > 0 ? ParaUtils.formatla(v) : '—';

  late final List<TabloKolon<UrunModel>> _kolonlar = [
    TabloKolon(
        baslik: 'Ürün',
        genislik: 240,
        esnek: true,
        deger: (u) => u.urunAdi,
        sirala: (u) => u.urunAdi.toLowerCase()),
    TabloKolon(
        baslik: 'Barkod',
        genislik: 130,
        deger: (u) => u.barkod ?? '',
        sirala: (u) => u.barkod ?? ''),
    TabloKolon(
        baslik: 'Alış',
        genislik: 100,
        sagaYasli: true,
        deger: (u) => _para(u.alisFiyat),
        sirala: (u) => u.alisFiyat),
    TabloKolon(
        baslik: 'Alış (KDV D.)',
        genislik: 110,
        sagaYasli: true,
        deger: (u) => _para(u.alisFiyatKdvDahil),
        sirala: (u) => u.alisFiyatKdvDahil),
    TabloKolon(
        baslik: 'Satış',
        genislik: 100,
        sagaYasli: true,
        deger: (u) => _para(u.satisFiyati),
        sirala: (u) => u.satisFiyati),
    TabloKolon(
        baslik: 'Toptan',
        genislik: 100,
        sagaYasli: true,
        deger: (u) => _para(u.toptanFiyat),
        sirala: (u) => u.toptanFiyat,
        renk: (u) => TsRenk.primary),
    TabloKolon(
        baslik: 'Koli',
        genislik: 110,
        deger: (u) => u.koliIciMiktar > 0
            ? '${u.koliBirimAdi} (${u.koliIciMiktar.toStringAsFixed(u.koliIciMiktar % 1 == 0 ? 0 : 2)})'
            : '',
        sirala: (u) => u.koliIciMiktar),
    TabloKolon(
        baslik: 'Stok',
        genislik: 80,
        sagaYasli: true,
        deger: (u) => u.stok.toStringAsFixed(u.stok % 1 == 0 ? 0 : 2),
        sirala: (u) => u.stok),
  ];

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_tus);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_tus);
    super.dispose();
  }

  UrunModel? get _gecerliSecili {
    final s = _secili;
    if (s == null) return null;
    for (final u in widget.urunler) {
      if (u.id == s.id) return u;
    }
    return null;
  }

  void _menu(UrunModel u, Offset konum) {
    masaustuMenuAc(context, konum, [
      MenuOge('Listeden Kaldır', () => widget.onKaldir(u), ikon: Icons.remove_circle_outline),
    ]);
  }

  bool _tus(KeyEvent e) {
    if (e is! KeyDownEvent || !mounted) return false;
    if (!ekranUstte(context)) return false;
    if (e.logicalKey == LogicalKeyboardKey.f4) {
      final s = _gecerliSecili;
      if (s != null) widget.onKaldir(s);
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final s = _gecerliSecili;
    return Column(children: [
      Expanded(
        child: MasaustuTablo<UrunModel>(
          satirlar: widget.urunler,
          kolonlar: _kolonlar,
          secili: s,
          onSec: (u) => setState(() => _secili = u),
          onSagTik: _menu,
        ),
      ),
      MasaustuAltSerit(
        ozetler: [AltOzet('Ürün', '${widget.urunler.length}')],
        tuslar: [
          AltTus('F4', 'Listeden Kaldır', Icons.remove_circle_outline,
              const Color(0xFFC62828), s == null ? null : () => widget.onKaldir(s)),
        ],
      ),
    ]);
  }
}
