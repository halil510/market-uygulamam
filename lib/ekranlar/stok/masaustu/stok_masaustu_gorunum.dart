// lib/ekranlar/stok/masaustu/stok_masaustu_gorunum.dart
//
// Stok Listesi — masaüstü (geniş pencere) tablo görünümü: sıralanabilir
// kolonlar, sağ tık menüsü, alt özet şeridi ve F2/F5 kısayolları. Veri ve
// yükleme çağıran ekrandan gelir (sadece görünüm).
import '../../../widgetlar/masaustu/ekran_ustte.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../cekirdek/utils/para_utils.dart';
import '../../../modeller/urun_model.dart';
import '../../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../../widgetlar/masaustu/masaustu_alt_serit.dart';
import '../../../widgetlar/masaustu/masaustu_sag_tik_menu.dart';
import '../../../widgetlar/masaustu/masaustu_tablo.dart';

class StokMasaustuGorunum extends StatefulWidget {
  final List<UrunModel> urunler;
  final ScrollController scrollController;
  final VoidCallback onYenile;

  /// Seçim varsa yalnız seçilenleri, yoksa listenin tamamını Excel'e aktarır.
  final VoidCallback onExcel;

  /// Çoklu seçim (Ctrl+tık, Shift+tık, sürükleme, Ctrl+A).
  final Set<int> seciliIds;
  final ValueChanged<Set<int>> onCokluSecim;

  const StokMasaustuGorunum({
    super.key,
    required this.urunler,
    required this.scrollController,
    required this.onYenile,
    required this.onExcel,
    required this.seciliIds,
    required this.onCokluSecim,
  });

  @override
  State<StokMasaustuGorunum> createState() => _StokMasaustuGorunumState();
}

class _StokMasaustuGorunumState extends State<StokMasaustuGorunum> {
  UrunModel? _secili;

  static String _sayi(double d) =>
      d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toStringAsFixed(3);

  static TabloKolon<UrunModel> _yazi(
          String b, double g, String? Function(UrunModel) al,
          {bool esnek = false}) =>
      TabloKolon(
          baslik: b,
          genislik: g,
          esnek: esnek,
          deger: (u) => al(u) ?? '',
          sirala: (u) => (al(u) ?? '').toLowerCase());

  static TabloKolon<UrunModel> _tutar(
          String b, double g, double Function(UrunModel) al) =>
      TabloKolon(
          baslik: b,
          genislik: g,
          sagaYasli: true,
          deger: (u) => ParaUtils.formatla(al(u), simge: ''),
          sirala: al);

  static final List<TabloKolon<UrunModel>> _kolonlar = [
    _yazi('Kod', 120, (u) => u.kod),
    _yazi('Barkod', 140, (u) => u.barkod),
    _yazi('Ürün Adı', 240, (u) => u.urunAdi, esnek: true),
    _yazi('Ana Grup', 130, (u) => u.anaGrup),
    TabloKolon(baslik: 'Birim', genislik: 70, deger: (u) => u.birimAdi),
    TabloKolon(
        baslik: 'Stok',
        genislik: 90,
        sagaYasli: true,
        deger: (u) => _sayi(u.stok),
        sirala: (u) => u.stok,
        renk: (u) => u.stok <= 0
            ? TsRenk.hata
            : (u.kritikStok ? TsRenk.uyari : null)),
    TabloKolon(
        baslik: 'Min. Stok',
        genislik: 85,
        sagaYasli: true,
        deger: (u) => u.minimumStok == 0 ? '' : _sayi(u.minimumStok),
        sirala: (u) => u.minimumStok),
    _tutar('Alış (KDV Dahil)', 120, (u) => u.alisFiyatKdvDahil),
    _tutar('Satış Fiyatı', 100, (u) => u.satisFiyati),
    _tutar('Stok Değeri (KDV Dahil)', 165, (u) => u.stok * u.alisFiyatKdvDahil),
  ];

  void _detay(UrunModel u) => context.push('/urun/detay/${u.id}');

  bool get _coklu => widget.seciliIds.length >= 2;

  void _menu(UrunModel u, Offset konum) {
    if (_coklu) {
      final n = widget.seciliIds.length;
      masaustuMenuAc(context, konum, [
        MenuOge("Seçilenleri Excel'e Aktar ($n ürün)", widget.onExcel,
            ikon: Icons.download_outlined),
        MenuOge('Seçimi Kaldır', () => widget.onCokluSecim({}),
            ikon: Icons.deselect, ayiracOnce: true),
      ]);
      return;
    }
    masaustuMenuAc(context, konum, [
      MenuOge('Ürün Detayı', () => _detay(u), ikon: Icons.info_outline),
      MenuOge('Stok Hareketleri', () => context.push('/stok/hareket'),
          ikon: Icons.swap_vert),
      MenuOge('Excel Aktar', widget.onExcel,
          ikon: Icons.download_outlined, ayiracOnce: true),
    ]);
  }

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

  bool _tus(KeyEvent e) {
    if (e is! KeyDownEvent || !mounted) return false;
    if (!ekranUstte(context)) return false;
    final k = e.logicalKey;
    if (HardwareKeyboard.instance.isControlPressed && k == LogicalKeyboardKey.keyA) {
      if (yaziAlaniOdakta()) return false;
      widget.onCokluSecim({for (final u in widget.urunler) if (u.id != null) u.id!});
    } else if (k == LogicalKeyboardKey.f2) {
      if (_secili != null) _detay(_secili!);
    } else if (k == LogicalKeyboardKey.f5) {
      widget.onYenile();
    } else if (k == LogicalKeyboardKey.f6) {
      widget.onExcel();
    } else {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.urunler;
    final stokToplam = u.fold<double>(0, (t, x) => t + x.stok);
    final maliyet = u.fold<double>(0, (t, x) => t + x.stok * x.alisFiyatKdvDahil);
    final satis = u.fold<double>(0, (t, x) => t + x.stok * x.satisFiyati);
    return Column(children: [
      Expanded(
        child: MasaustuTablo<UrunModel>(
          satirlar: u,
          kolonlar: _kolonlar,
          secili: _secili,
          scrollController: widget.scrollController,
          onSec: (x) => setState(() => _secili = x),
          onCift: _detay,
          onSagTik: _menu,
          anahtar: (x) => x.id ?? x,
          seciliAnahtarlar: widget.seciliIds,
          onCokluSecim: (a) => widget.onCokluSecim(a.whereType<int>().toSet()),
        ),
      ),
      MasaustuAltSerit(
        ozetler: [
          if (_coklu) AltOzet('Seçili', '${widget.seciliIds.length} ürün'),
          AltOzet('Çeşit Sayısı', '${u.length}'),
          AltOzet('Stok Miktarı', _sayi(stokToplam)),
          AltOzet('Maliyet (KDV Dahil)', ParaUtils.formatla(maliyet)),
          AltOzet('Satış Değeri', ParaUtils.formatla(satis)),
        ],
        tuslar: [
          AltTus('F2', 'Detay', Icons.info_outline, const Color(0xFF1565C0),
              _secili == null ? null : () => _detay(_secili!)),
          AltTus('F6', _coklu ? 'Excel (${widget.seciliIds.length})' : 'Excel',
              Icons.download_outlined, const Color(0xFF2E7D32),
              widget.onExcel),
          AltTus('F5', 'Yenile', Icons.refresh, const Color(0xFF546E7A),
              widget.onYenile),
        ],
      ),
    ]);
  }
}
