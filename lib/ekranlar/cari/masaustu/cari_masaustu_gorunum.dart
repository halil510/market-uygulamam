// lib/ekranlar/cari/masaustu/cari_masaustu_gorunum.dart
//
// Cari Listesi — masaüstü (geniş pencere) görünümü: tablo + alt şerit +
// sağ tık menüsü + F1/F2/F3/F4/F6 kısayolları. Sadece görünüm; silme ve
// yenileme çağıran ekrandan gelir.
//
// Bakiye işareti (uygulamadaki kural): bakiye > 0 → ALACAĞIMIZ var,
// bakiye < 0 → BORCUMUZ var.
import '../cari_secim_baglami.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../cekirdek/utils/para_utils.dart';
import '../../../modeller/cari_model.dart';
import '../../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../../widgetlar/masaustu/masaustu_alt_serit.dart';
import '../../../widgetlar/masaustu/masaustu_sag_tik_menu.dart';
import '../../../widgetlar/masaustu/masaustu_tablo.dart';

class CariMasaustuGorunum extends StatefulWidget {
  final List<CariModel> cariler;
  final Future<void> Function(CariModel cari) onSil;
  final Future<void> Function() onYenile;

  const CariMasaustuGorunum({
    super.key,
    required this.cariler,
    required this.onSil,
    required this.onYenile,
  });

  @override
  State<CariMasaustuGorunum> createState() => _CariMasaustuGorunumState();
}

class _CariMasaustuGorunumState extends State<CariMasaustuGorunum> {
  CariModel? _secili;

  static const _alacakRengi = Color(0xFF2E7D32);

  late final List<TabloKolon<CariModel>> _kolonlar = [
    TabloKolon(
        baslik: 'Cari Kod',
        genislik: 100,
        deger: (c) => c.cariKodu ?? '',
        sirala: (c) => c.cariKodu ?? ''),
    TabloKolon(
        baslik: 'Ünvan',
        genislik: 240,
        esnek: true,
        deger: (c) => c.unvan,
        sirala: (c) => c.unvan.toLowerCase()),
    TabloKolon(
        baslik: 'Tür',
        genislik: 120,
        deger: (c) => c.cariTipi,
        sirala: (c) => c.cariTipi),
    TabloKolon(baslik: 'Telefon', genislik: 120, deger: (c) => c.telefon ?? ''),
    TabloKolon(
        baslik: 'Bakiye',
        genislik: 120,
        sagaYasli: true,
        deger: (c) => ParaUtils.formatla(c.bakiye, simge: ''),
        sirala: (c) => c.bakiye,
        renk: (c) => c.bakiye > 0
            ? _alacakRengi
            : (c.bakiye < 0 ? TsRenk.hata : null)),
    TabloKolon(
        baslik: 'Limit',
        genislik: 100,
        sagaYasli: true,
        deger: (c) =>
            c.limitTutari > 0 ? ParaUtils.formatla(c.limitTutari, simge: '') : '',
        sirala: (c) => c.limitTutari),
    TabloKolon(
        baslik: 'Vade (gün)',
        genislik: 85,
        sagaYasli: true,
        deger: (c) => c.vadeGun > 0 ? '${c.vadeGun}' : ''),
    TabloKolon(
        baslik: 'Ana Grup',
        genislik: 120,
        deger: (c) => c.anaGrup ?? '',
        sirala: (c) => c.anaGrup ?? ''),
  ];

  Future<void> _git(String yol, [Object? extra]) async {
    await context.push(yol, extra: extra);
    if (mounted) widget.onYenile();
  }

  void _duzenle(CariModel c) => _git('/cari/ekle', c);
  void _tahsilat(CariModel c) => _git('/cari/tahsilat/${c.id}');

  void _menu(CariModel c, Offset konum) {
    masaustuMenuAc(context, konum, [
      MenuOge('Cari Detayı', () => _git('/cari/detay/${c.id}'),
          ikon: Icons.person_outline),
      MenuOge('Cari Hareketleri', () => _git('/cari/hareket/${c.id}'),
          ikon: Icons.receipt_long_outlined),
      MenuOge('Tahsilat / Ödeme (Al/Ver)', () => _tahsilat(c),
          ikon: Icons.swap_horiz),
      MenuOge('Düzenle', () => _duzenle(c), ikon: Icons.edit_outlined, ayiracOnce: true),
      MenuOge('Sil', () => widget.onSil(c),
          ikon: Icons.delete_outline, ayiracOnce: true),
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
    if (ModalRoute.of(context)?.isCurrent == false) return false;
    final k = e.logicalKey;
    final s = _secili;
    if (k == LogicalKeyboardKey.f1) {
      _git('/cari/ekle');
    } else if (k == LogicalKeyboardKey.f2) {
      if (s != null) _duzenle(s);
    } else if (k == LogicalKeyboardKey.f3) {
      if (s != null) widget.onSil(s);
    } else if (k == LogicalKeyboardKey.f4) {
      if (s != null) _tahsilat(s);
    } else if (k == LogicalKeyboardKey.f6) {
      if (s != null) _menu(s, const Offset(400, 250));
    } else {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.cariler;
    final alacak = l.where((c) => c.bakiye > 0).fold<double>(0, (t, c) => t + c.bakiye);
    final borc = l.where((c) => c.bakiye < 0).fold<double>(0, (t, c) => t - c.bakiye);
    final s = _secili;
    return Column(children: [
      Expanded(
        child: MasaustuTablo<CariModel>(
          satirlar: l,
          kolonlar: _kolonlar,
          secili: s,
          onSec: (c) => setState(() => _secili = c),
          onCift: (c) {
            final secim = CariSecimBaglami.maybeOf(context);
            if (secim != null) { secim.onSec(c); return; }
            _git('/cari/detay/${c.id}');
          },
          onSagTik: _menu,
        ),
      ),
      MasaustuAltSerit(
        ozetler: [
          AltOzet('Cari Sayısı', '${l.length}'),
          AltOzet('Toplam Alacak', ParaUtils.formatla(alacak), renk: _alacakRengi),
          AltOzet('Toplam Borç', ParaUtils.formatla(borc), renk: TsRenk.hata),
          AltOzet('Toplam Bakiye', ParaUtils.formatla(alacak - borc)),
        ],
        tuslar: [
          AltTus('F1', 'Ekle', Icons.person_add_alt, const Color(0xFF2E7D32),
              () => _git('/cari/ekle')),
          AltTus('F2', 'Düzenle', Icons.edit_outlined, const Color(0xFF1565C0),
              s == null ? null : () => _duzenle(s)),
          AltTus('F3', 'Sil', Icons.delete_outline, const Color(0xFFC62828),
              s == null ? null : () => widget.onSil(s)),
          AltTus('F4', 'Al / Ver', Icons.swap_horiz, const Color(0xFF6A1B9A),
              s == null ? null : () => _tahsilat(s)),
          AltTus('F6', 'Menü', Icons.menu, const Color(0xFF546E7A),
              s == null ? null : () => _menu(s, const Offset(400, 250))),
        ],
      ),
    ]);
  }
}
