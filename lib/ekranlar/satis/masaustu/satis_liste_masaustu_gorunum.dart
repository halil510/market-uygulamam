// lib/ekranlar/satis/masaustu/satis_liste_masaustu_gorunum.dart
//
// Satış Listesi — masaüstü (geniş pencere) görünümü: tablo + alt şerit +
// sağ tık menüsü + F2/F3/F5 kısayolları. Sadece görünüm; seçim/silme/yenileme
// çağıran ekrandan (satislarProvider) gelir.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../cekirdek/utils/para_utils.dart';
import '../../../modeller/satis_model.dart';
import '../../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../../widgetlar/masaustu/masaustu_alt_serit.dart';
import '../../../widgetlar/masaustu/masaustu_sag_tik_menu.dart';
import '../../../widgetlar/masaustu/masaustu_tablo.dart';

class SatisListeMasaustuGorunum extends StatefulWidget {
  final List<SatisModel> satislar;
  final Set<int> seciliIds;
  final double seciliToplam;
  final void Function(SatisModel satis) onDetay;
  final void Function(SatisModel satis) onSecToggle;
  final Future<void> Function() onYenile;

  const SatisListeMasaustuGorunum({
    super.key,
    required this.satislar,
    required this.seciliIds,
    required this.seciliToplam,
    required this.onDetay,
    required this.onSecToggle,
    required this.onYenile,
  });

  @override
  State<SatisListeMasaustuGorunum> createState() =>
      _SatisListeMasaustuGorunumState();
}

class _SatisListeMasaustuGorunumState extends State<SatisListeMasaustuGorunum> {
  SatisModel? _secili;
  static final _tarihFmt = DateFormat('dd.MM.yyyy HH:mm');

  late final List<TabloKolon<SatisModel>> _kolonlar = [
    TabloKolon(
        baslik: 'Fiş No',
        genislik: 240,
        deger: (s) =>
            '${s.id != null && widget.seciliIds.contains(s.id) ? '✓ ' : ''}${s.fisNo ?? '#${s.id ?? ''}'}',
        sirala: (s) => s.fisNo ?? ''),
    TabloKolon(
        baslik: 'Tarih',
        genislik: 150,
        deger: (s) => _tarihFmt.format(s.tarih),
        sirala: (s) => s.tarih),
    TabloKolon(
        baslik: 'Müşteri',
        genislik: 200,
        esnek: true,
        deger: (s) => s.cariAdi ?? 'Peşin müşteri',
        sirala: (s) => (s.cariAdi ?? '').toLowerCase()),
    TabloKolon(
        baslik: 'Ödeme',
        genislik: 110,
        deger: (s) => s.odemeYontemi,
        sirala: (s) => s.odemeYontemi),
    TabloKolon(
        baslik: 'Ara Toplam',
        genislik: 110,
        sagaYasli: true,
        deger: (s) => ParaUtils.formatla(s.toplamTutar, simge: ''),
        sirala: (s) => s.toplamTutar),
    TabloKolon(
        baslik: 'İndirim',
        genislik: 90,
        sagaYasli: true,
        deger: (s) => s.iskonto > 0 ? ParaUtils.formatla(s.iskonto, simge: '') : '',
        sirala: (s) => s.iskonto),
    TabloKolon(
        baslik: 'Genel Toplam',
        genislik: 120,
        sagaYasli: true,
        deger: (s) => ParaUtils.formatla(s.genelToplam, simge: ''),
        sirala: (s) => s.genelToplam),
    TabloKolon(
        baslik: 'Kalan',
        genislik: 100,
        sagaYasli: true,
        deger: (s) =>
            s.kalanTutar > 0.005 ? ParaUtils.formatla(s.kalanTutar, simge: '') : '',
        renk: (s) => s.kalanTutar > 0.005 ? TsRenk.hata : null),
    TabloKolon(
        baslik: 'Durum',
        genislik: 90,
        deger: (s) => s.iptal ? 'İPTAL' : '',
        renk: (s) => s.iptal ? TsRenk.hata : null),
  ];

  void _menu(SatisModel s, Offset konum) {
    final secili = s.id != null && widget.seciliIds.contains(s.id);
    masaustuMenuAc(context, konum, [
      MenuOge('Satış Detayı', () => widget.onDetay(s),
          ikon: Icons.receipt_long_outlined),
      MenuOge(secili ? 'Seçimden Çıkar' : 'Silmek / İptal İçin Seç',
          () => widget.onSecToggle(s),
          ikon: secili ? Icons.check_box_outline_blank : Icons.check_box_outlined,
          ayiracOnce: true),
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
    if (k == LogicalKeyboardKey.f2) {
      if (s != null) widget.onDetay(s);
    } else if (k == LogicalKeyboardKey.f3) {
      if (s != null) widget.onSecToggle(s);
    } else if (k == LogicalKeyboardKey.f5) {
      widget.onYenile();
    } else {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.satislar;
    final gecerli = l.where((s) => !s.iptal);
    final toplam = gecerli.fold<double>(0, (t, s) => t + s.genelToplam);
    final iptalli = l.length - gecerli.length;
    final s = _secili;
    final secimVar = widget.seciliIds.isNotEmpty;
    return Column(children: [
      Expanded(
        child: MasaustuTablo<SatisModel>(
          satirlar: l,
          kolonlar: _kolonlar,
          secili: s,
          onSec: (x) => setState(() => _secili = x),
          onCift: widget.onDetay,
          onSagTik: _menu,
        ),
      ),
      MasaustuAltSerit(
        ozetler: [
          AltOzet('Satış Sayısı', '${l.length}'),
          AltOzet('Toplam (iptalsiz)', ParaUtils.formatla(toplam),
              renk: const Color(0xFF2E7D32)),
          if (iptalli > 0) AltOzet('İptal', '$iptalli', renk: TsRenk.hata),
          if (secimVar)
            AltOzet('Seçili (${widget.seciliIds.length})',
                ParaUtils.formatla(widget.seciliToplam)),
        ],
        tuslar: [
          AltTus('F2', 'Detay', Icons.receipt_long_outlined,
              const Color(0xFF1565C0),
              s == null ? null : () => widget.onDetay(s)),
          AltTus('F3', 'Seç', Icons.check_box_outlined, const Color(0xFFC62828),
              s == null ? null : () => widget.onSecToggle(s)),
          AltTus('F5', 'Yenile', Icons.refresh, const Color(0xFF2E7D32),
              () => widget.onYenile()),
        ],
      ),
    ]);
  }
}
