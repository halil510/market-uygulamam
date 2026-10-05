// lib/ekranlar/borc/masaustu/borc_masaustu_gorunum.dart
//
// Borç listesi (Aktif Borçlar / Ödenenler) — masaüstü tablo görünümü:
// tablo + alt şerit + sağ tık menüsü + F1/F2/F3 kısayolları. Sadece görünüm;
// ödeme ve yenileme çağıran taraftan gelir.
import '../../../widgetlar/masaustu/ekran_ustte.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../cekirdek/utils/para_utils.dart';
import '../../../modeller/borc_model.dart';
import '../../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../../widgetlar/masaustu/masaustu_alt_serit.dart';
import '../../../widgetlar/masaustu/masaustu_sag_tik_menu.dart';
import '../../../widgetlar/masaustu/masaustu_tablo.dart';

class BorcMasaustuGorunum extends StatefulWidget {
  final List<BorcModel> borclar;

  /// true → Ödenenler listesi (Öde butonu yok, "Ödeme Tarihi" sütunu var).
  final bool odenenMod;
  final void Function(BorcModel borc)? onOde;
  final Future<void> Function() onYenile;

  const BorcMasaustuGorunum({
    super.key,
    required this.borclar,
    required this.onYenile,
    this.odenenMod = false,
    this.onOde,
  });

  @override
  State<BorcMasaustuGorunum> createState() => _BorcMasaustuGorunumState();
}

class _BorcMasaustuGorunumState extends State<BorcMasaustuGorunum> {
  BorcModel? _secili;

  static final _tarih = DateFormat('dd.MM.yyyy');

  static String _turEtiket(String tur) {
    const map = {
      'kredi_karti': 'Kredi Kartı',
      'vergi': 'Vergi',
      'sgk': 'SGK',
      'stopaj': 'Stopaj',
      'kira': 'Kira',
      'fatura': 'Fatura',
    };
    return map[tur] ?? 'Diğer';
  }

  late final List<TabloKolon<BorcModel>> _kolonlar = [
    TabloKolon(
        baslik: 'Başlık',
        genislik: 240,
        esnek: true,
        deger: (b) => b.baslik,
        sirala: (b) => b.baslik.toLowerCase()),
    TabloKolon(
        baslik: 'Tür',
        genislik: 110,
        deger: (b) => _turEtiket(b.tur),
        sirala: (b) => b.tur),
    TabloKolon(
        baslik: 'Kesim',
        genislik: 95,
        deger: (b) => _tarih.format(b.kesimTarihi),
        sirala: (b) => b.kesimTarihi),
    TabloKolon(
        baslik: widget.odenenMod ? 'Ödeme Tarihi' : 'Son Ödeme',
        genislik: 105,
        deger: (b) => _tarih.format(
            widget.odenenMod ? (b.odemeTarihi ?? b.sonOdemeTarihi) : b.sonOdemeTarihi),
        sirala: (b) =>
            widget.odenenMod ? (b.odemeTarihi ?? b.sonOdemeTarihi) : b.sonOdemeTarihi,
        renk: (b) => b.vadesiGecti ? TsRenk.hata : null),
    TabloKolon(
        baslik: 'Tutar',
        genislik: 115,
        sagaYasli: true,
        deger: (b) => ParaUtils.formatla(b.tutar, simge: ''),
        sirala: (b) => b.tutar),
    if (!widget.odenenMod) ...[
      TabloKolon(
          baslik: 'Ödenen',
          genislik: 115,
          sagaYasli: true,
          deger: (b) => ParaUtils.formatla(b.odenenTutar, simge: ''),
          sirala: (b) => b.odenenTutar),
      TabloKolon(
          baslik: 'Kalan',
          genislik: 115,
          sagaYasli: true,
          deger: (b) => ParaUtils.formatla(b.kalanTutar, simge: ''),
          sirala: (b) => b.kalanTutar,
          renk: (b) => b.vadesiGecti ? TsRenk.hata : null),
      TabloKolon(
          baslik: 'Durum',
          genislik: 110,
          deger: (b) => b.vadesiGecti
              ? 'GECİKTİ'
              : (b.kalanGun >= 0 && b.kalanGun <= 7 ? '${b.kalanGun} gün kaldı' : ''),
          sirala: (b) => b.kalanGun,
          renk: (b) => b.vadesiGecti ? TsRenk.hata : null),
    ],
    TabloKolon(
        baslik: 'Taksit',
        genislik: 80,
        sagaYasli: true,
        deger: (b) => b.taksitSayisi > 1 ? '${b.odenenTaksit}/${b.taksitSayisi}' : ''),
    TabloKolon(
        baslik: 'Alt Tür',
        genislik: 130,
        deger: (b) => b.altTur ?? '',
        sirala: (b) => b.altTur ?? ''),
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

  Future<void> _git(String yol) async {
    await context.push(yol);
    if (mounted) widget.onYenile();
  }

  Future<void> _ekle() async {
    final eklendi = await context.push<bool>('/borc-ekle');
    if (eklendi == true && mounted) widget.onYenile();
  }

  void _detay(BorcModel b) => _git('/borc-detay/${b.id}');

  void _ode(BorcModel b) {
    if (widget.onOde != null && !b.odendi) widget.onOde!(b);
  }

  void _menu(BorcModel b, Offset konum) {
    masaustuMenuAc(context, konum, [
      MenuOge('Borç Detayı', () => _detay(b), ikon: Icons.info_outline),
      if (!widget.odenenMod && !b.odendi)
        MenuOge('Ödeme Yap', () => _ode(b), ikon: Icons.payments_outlined),
    ]);
  }

  bool _tus(KeyEvent e) {
    if (e is! KeyDownEvent || !mounted) return false;
    // Sekme görünür değilse (TabBarView yan sekmesi) tuşu işleme.
    if (!TickerMode.of(context)) return false;
    if (!ekranUstte(context)) return false;
    final k = e.logicalKey;
    final s = _secili;
    if (k == LogicalKeyboardKey.f1) {
      _ekle();
    } else if (k == LogicalKeyboardKey.f2) {
      if (s != null) _ode(s);
    } else if (k == LogicalKeyboardKey.f3) {
      if (s != null) _detay(s);
    } else if (k == LogicalKeyboardKey.f6) {
      if (s != null) _menu(s, const Offset(400, 250));
    } else {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.borclar;
    final s = _secili;
    final toplam = l.fold<double>(0, (t, b) => t + b.tutar);
    final kalan = l.fold<double>(0, (t, b) => t + (b.odendi ? 0 : b.kalanTutar));
    final geciken = l.where((b) => b.vadesiGecti).length;
    return Column(children: [
      Expanded(
        child: MasaustuTablo<BorcModel>(
          satirlar: l,
          kolonlar: _kolonlar,
          secili: s,
          onSec: (b) => setState(() => _secili = b),
          onCift: _detay,
          onSagTik: _menu,
        ),
      ),
      MasaustuAltSerit(
        ozetler: [
          AltOzet('Borç Sayısı', '${l.length}'),
          AltOzet('Toplam Tutar', ParaUtils.formatla(toplam)),
          if (!widget.odenenMod) ...[
            AltOzet('Toplam Kalan', ParaUtils.formatla(kalan), renk: TsRenk.hata),
            AltOzet('Geciken', '$geciken', renk: geciken > 0 ? TsRenk.hata : null),
          ],
        ],
        tuslar: [
          AltTus('F1', 'Borç Ekle', Icons.add_circle_outline, const Color(0xFF2E7D32), _ekle),
          if (!widget.odenenMod)
            AltTus('F2', 'Öde', Icons.payments_outlined, const Color(0xFF1565C0),
                s == null || s.odendi ? null : () => _ode(s)),
          AltTus('F3', 'Detay', Icons.info_outline, const Color(0xFF6A1B9A),
              s == null ? null : () => _detay(s)),
          AltTus('F6', 'Menü', Icons.menu, const Color(0xFF546E7A),
              s == null ? null : () => _menu(s, const Offset(400, 250))),
        ],
      ),
    ]);
  }
}
