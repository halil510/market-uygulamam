// lib/ekranlar/urun/masaustu/urun_masaustu_gorunum.dart
//
// Ürün Listesi — masaüstü (geniş pencere) görünümü: tablo + alt şerit +
// sağ tık menüsü + F1/F2/F3/F6 kısayolları. Veri ve iş mantığı çağıran
// ekrandan gelir (sadece görünüm).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../cekirdek/utils/para_utils.dart';
import '../../../depolar/urun_deposu.dart';
import '../../../modeller/urun_model.dart';
import '../../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../../widgetlar/masaustu/masaustu_alt_serit.dart';
import '../../../widgetlar/masaustu/masaustu_sag_tik_menu.dart';
import '../../../widgetlar/masaustu/masaustu_tablo.dart';

class UrunMasaustuGorunum extends StatefulWidget {
  final List<UrunModel> urunler;
  final ScrollController scrollController;
  final VoidCallback onEkle;
  final void Function(UrunModel urun) onSil;
  final VoidCallback onExcel;
  final VoidCallback onYenile;

  const UrunMasaustuGorunum({
    super.key,
    required this.urunler,
    required this.scrollController,
    required this.onEkle,
    required this.onSil,
    required this.onExcel,
    required this.onYenile,
  });

  @override
  State<UrunMasaustuGorunum> createState() => _UrunMasaustuGorunumState();
}

class _UrunMasaustuGorunumState extends State<UrunMasaustuGorunum> {
  UrunModel? _secili;

  static String _sayi(double d) =>
      d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toStringAsFixed(3);

  late final List<TabloKolon<UrunModel>> _kolonlar = [
    TabloKolon(
        baslik: 'Kod',
        genislik: 120,
        deger: (u) => u.kod ?? '',
        sirala: (u) => u.kod ?? ''),
    TabloKolon(
        baslik: 'Barkod',
        genislik: 140,
        deger: (u) => u.barkod ?? '',
        sirala: (u) => u.barkod ?? ''),
    TabloKolon(
        baslik: 'Ürün Adı',
        genislik: 220,
        esnek: true,
        deger: (u) => u.urunAdi,
        sirala: (u) => u.urunAdi.toLowerCase()),
    TabloKolon(baslik: 'Birim', genislik: 70, deger: (u) => u.birimAdi),
    TabloKolon(
        baslik: 'Alış Fiyat',
        genislik: 95,
        sagaYasli: true,
        deger: (u) => ParaUtils.formatla(u.alisFiyat, simge: ''),
        sirala: (u) => u.alisFiyat),
    TabloKolon(
        baslik: 'Satış Fiyatı',
        genislik: 100,
        sagaYasli: true,
        deger: (u) => ParaUtils.formatla(u.satisFiyati, simge: ''),
        sirala: (u) => u.satisFiyati),
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
        baslik: 'KDV %',
        genislik: 60,
        sagaYasli: true,
        deger: (u) => u.kdvOran),
    TabloKolon(
        baslik: 'Ana Grup',
        genislik: 130,
        deger: (u) => u.anaGrup ?? '',
        sirala: (u) => u.anaGrup ?? ''),
    TabloKolon(
        baslik: 'Kâr %',
        genislik: 70,
        sagaYasli: true,
        deger: (u) => u.karOrani.toStringAsFixed(1),
        sirala: (u) => u.karOrani),
  ];

  void _duzenle(UrunModel u) => context.push('/urun/ekle', extra: u).then((_) {
        widget.onYenile();
      });

  void _menu(UrunModel u, Offset konum) {
    masaustuMenuAc(context, konum, [
      MenuOge('Düzenle', () => _duzenle(u), ikon: Icons.edit_outlined),
      MenuOge('Ürün Detayı', () => context.push('/urun/detay/${u.id}'),
          ikon: Icons.info_outline),
      MenuOge('Stok Hareketleri', () => context.push('/stok/hareket'),
          ikon: Icons.swap_vert),
      MenuOge('PLU paneline ekle', () async {
        await UrunDeposu().pluyaEkle(u.id!);
        widget.onYenile();
      }, ikon: Icons.grid_view, ayiracOnce: true),
      MenuOge('Toplu İşlem', () => context.push('/urun/toplu-islem', extra: [u.id]),
          ikon: Icons.build_outlined),
      MenuOge('Excel Aktar', widget.onExcel, ikon: Icons.download_outlined),
      MenuOge('Sil', () => widget.onSil(u),
          ikon: Icons.delete_outline, ayiracOnce: true),
    ]);
  }

  // ── Klavye kısayolları (F1 ekle, F2 düzenle, F3 sil, F6 menü) ────────────
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
    if (ModalRoute.of(context)?.isCurrent == false) return false;
    final k = e.logicalKey;
    final s = _secili;
    if (k == LogicalKeyboardKey.f1) {
      widget.onEkle();
    } else if (k == LogicalKeyboardKey.f2) {
      if (s != null) _duzenle(s);
    } else if (k == LogicalKeyboardKey.f3) {
      if (s != null) widget.onSil(s);
    } else if (k == LogicalKeyboardKey.f6) {
      if (s != null) {
        final box = context.findRenderObject() as RenderBox;
        _menu(s, box.localToGlobal(const Offset(300, 120)));
      }
    } else {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.urunler;
    final stokToplam = u.fold<double>(0, (t, x) => t + x.stok);
    final satisDeger = u.fold<double>(0, (t, x) => t + x.stok * x.satisFiyati);
    final maliyet = u.fold<double>(0, (t, x) => t + x.stok * x.alisFiyat);
    return Column(children: [
      Expanded(
        child: MasaustuTablo<UrunModel>(
          satirlar: u,
          kolonlar: _kolonlar,
          secili: _secili,
          scrollController: widget.scrollController,
          onSec: (x) => setState(() => _secili = x),
          onCift: _duzenle,
          onSagTik: _menu,
        ),
      ),
      MasaustuAltSerit(
        ozetler: [
          AltOzet('Çeşit Sayısı', '${u.length}'),
          AltOzet('Stok Miktarı', _sayi(stokToplam)),
          AltOzet('Satış Değeri', ParaUtils.formatla(satisDeger)),
          AltOzet('Maliyet Değeri', ParaUtils.formatla(maliyet)),
        ],
        tuslar: [
          AltTus('F1', 'Ekle', Icons.add, const Color(0xFF2E7D32), widget.onEkle),
          AltTus('F2', 'Düzenle', Icons.edit_outlined, const Color(0xFF1565C0),
              _secili == null ? null : () => _duzenle(_secili!)),
          AltTus('F3', 'Sil', Icons.delete_outline, const Color(0xFFC62828),
              _secili == null ? null : () => widget.onSil(_secili!)),
          AltTus('F6', 'Menü', Icons.menu, const Color(0xFF546E7A),
              _secili == null ? null : () => _menu(_secili!, const Offset(400, 300))),
        ],
      ),
    ]);
  }
}
