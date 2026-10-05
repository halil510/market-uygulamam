// lib/ekranlar/toptan/masaustu/toptan_masaustu_gorunum.dart
//
// Toptan Satış paneli (bayi listesi) — masaüstü tablo görünümü: tablo + alt
// şerit + sağ tık menüsü + F1..F5 kısayolları. Sadece görünüm; bayi paneli,
// hızlı toptan satış ve alt ekranlara geçiş çağıran ekrandan gelir.
import '../../../widgetlar/masaustu/ekran_ustte.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../cekirdek/utils/para_utils.dart';
import '../../../modeller/cari_model.dart';
import '../../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../../uygulama/tema/uygulama_temasi.dart';
import '../../../widgetlar/masaustu/masaustu_alt_serit.dart';
import '../../../widgetlar/masaustu/masaustu_sag_tik_menu.dart';
import '../../../widgetlar/masaustu/masaustu_tablo.dart';

class ToptanMasaustuGorunum extends StatefulWidget {
  final List<CariModel> bayiler;
  final double bugunkuCiro;
  final void Function(CariModel bayi) onPanel;
  final VoidCallback onHizliSatis;
  final VoidCallback onUrunler;
  final VoidCallback onBekleyenSiparisler;
  final VoidCallback onFiyatGruplari;

  /// Liste boşken tablonun yerinde gösterilir; alt şerit (F1 Toptan Satış,
  /// Ürünler...) YİNE de görünür.
  final String bosMesaj;

  const ToptanMasaustuGorunum({
    super.key,
    required this.bayiler,
    required this.bugunkuCiro,
    required this.onPanel,
    required this.onHizliSatis,
    required this.onUrunler,
    required this.onBekleyenSiparisler,
    required this.onFiyatGruplari,
    this.bosMesaj = 'Bayi yok',
  });

  static bool limitAsildi(CariModel c) => c.limitTutari > 0 && c.bakiye > c.limitTutari;

  @override
  State<ToptanMasaustuGorunum> createState() => _ToptanMasaustuGorunumState();
}

class _ToptanMasaustuGorunumState extends State<ToptanMasaustuGorunum> {
  CariModel? _secili;

  late final List<TabloKolon<CariModel>> _kolonlar = [
    TabloKolon(
        baslik: 'Bayi / Ünvan',
        genislik: 260,
        esnek: true,
        deger: (c) => c.unvan,
        sirala: (c) => c.unvan.toLowerCase()),
    TabloKolon(
        baslik: 'Tip',
        genislik: 90,
        deger: (c) => c.musteriTipi,
        sirala: (c) => c.musteriTipi),
    TabloKolon(
        baslik: 'Telefon',
        genislik: 130,
        deger: (c) => c.telefon ?? '',
        sirala: (c) => c.telefon ?? ''),
    TabloKolon(
        baslik: 'Bakiye',
        genislik: 130,
        sagaYasli: true,
        deger: (c) => ParaUtils.formatla(c.bakiye, simge: ''),
        sirala: (c) => c.bakiye,
        renk: (c) => ToptanMasaustuGorunum.limitAsildi(c) ? TsRenk.hata : null),
    TabloKolon(
        baslik: 'Limit',
        genislik: 120,
        sagaYasli: true,
        deger: (c) => c.limitTutari > 0 ? ParaUtils.formatla(c.limitTutari, simge: '') : '',
        sirala: (c) => c.limitTutari),
    TabloKolon(
        baslik: 'Kalan Limit',
        genislik: 120,
        sagaYasli: true,
        deger: (c) => c.limitTutari > 0
            ? ParaUtils.formatla(c.limitTutari - c.bakiye, simge: '')
            : '',
        sirala: (c) => c.limitTutari > 0 ? c.limitTutari - c.bakiye : double.infinity,
        renk: (c) => ToptanMasaustuGorunum.limitAsildi(c) ? TsRenk.hata : null),
    TabloKolon(
        baslik: 'Vade (gün)',
        genislik: 105,
        sagaYasli: true,
        deger: (c) => c.vadeGun > 0 ? '${c.vadeGun}' : '',
        sirala: (c) => c.vadeGun),
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

  /// Liste yenilenince (arama/yükleme) seçili bayiyi güncel kopyasıyla eşle.
  CariModel? get _gecerliSecili {
    final s = _secili;
    if (s == null) return null;
    for (final c in widget.bayiler) {
      if (c.id == s.id) return c;
    }
    return null;
  }

  void _menu(CariModel c, Offset konum) {
    masaustuMenuAc(context, konum, [
      MenuOge('Bayi Paneli', () => widget.onPanel(c), ikon: Icons.storefront_outlined),
      MenuOge('Hızlı Toptan Satış', widget.onHizliSatis,
          ikon: Icons.add_shopping_cart, ayiracOnce: true),
    ]);
  }

  bool _tus(KeyEvent e) {
    if (e is! KeyDownEvent || !mounted) return false;
    if (!ekranUstte(context)) return false;
    final k = e.logicalKey;
    final s = _gecerliSecili;
    if (k == LogicalKeyboardKey.f1) {
      widget.onHizliSatis();
    } else if (k == LogicalKeyboardKey.f2) {
      if (s != null) widget.onPanel(s);
    } else if (k == LogicalKeyboardKey.f3) {
      widget.onUrunler();
    } else if (k == LogicalKeyboardKey.f4) {
      widget.onBekleyenSiparisler();
    } else if (k == LogicalKeyboardKey.f5) {
      widget.onFiyatGruplari();
    } else if (k == LogicalKeyboardKey.f6) {
      if (s != null) _menu(s, const Offset(400, 250));
    } else {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.bayiler;
    final s = _gecerliSecili;
    final alacak = l.fold<double>(0, (t, c) => t + (c.bakiye > 0 ? c.bakiye : 0));
    final asan = l.where(ToptanMasaustuGorunum.limitAsildi).length;
    return Column(children: [
      Expanded(
        child: l.isEmpty
            ? Center(child: Text(widget.bosMesaj, textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: context.textSecondary)))
            : MasaustuTablo<CariModel>(
          satirlar: l,
          kolonlar: _kolonlar,
          secili: s,
          onSec: (c) => setState(() => _secili = c),
          onCift: widget.onPanel,
          onSagTik: _menu,
        ),
      ),
      MasaustuAltSerit(
        ozetler: [
          AltOzet('Bayi Sayısı', '${l.length}'),
          AltOzet('Toplam Alacak', ParaUtils.formatla(alacak)),
          AltOzet('Limit Aşan', '$asan', renk: asan > 0 ? TsRenk.hata : null),
          AltOzet('Bugünkü Toptan Ciro', ParaUtils.formatla(widget.bugunkuCiro),
              renk: TsRenk.basarili),
        ],
        tuslar: [
          AltTus('F1', 'Toptan Satış', Icons.add_shopping_cart, const Color(0xFF2E7D32),
              widget.onHizliSatis),
          AltTus('F2', 'Bayi Paneli', Icons.storefront_outlined, const Color(0xFF1565C0),
              s == null ? null : () => widget.onPanel(s)),
          AltTus('F3', 'Ürünler', Icons.inventory_2_outlined, const Color(0xFF6A1B9A),
              widget.onUrunler),
          AltTus('F4', 'Siparişler', Icons.pending_actions_outlined, const Color(0xFFEF6C00),
              widget.onBekleyenSiparisler),
          AltTus('F5', 'Fiyat Grupları', Icons.sell_outlined, const Color(0xFF546E7A),
              widget.onFiyatGruplari),
        ],
      ),
    ]);
  }
}
