// lib/ekranlar/toptan/masaustu/bekleyen_siparis_masaustu_gorunum.dart
//
// Bekleyen toptan siparişler — masaüstü tablo görünümü. Çift tık / Enter /
// F2 sipariş detayını (onay, iptal, faturaya çevirme) açar; iş mantığı
// çağıran ekrandadır.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../cekirdek/utils/para_utils.dart';
import '../../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../../uygulama/tema/uygulama_temasi.dart';
import '../../../widgetlar/masaustu/ekran_ustte.dart';
import '../../../widgetlar/masaustu/masaustu_alt_serit.dart';
import '../../../widgetlar/masaustu/masaustu_sag_tik_menu.dart';
import '../../../widgetlar/masaustu/masaustu_tablo.dart';

class BekleyenSiparisMasaustuGorunum extends StatefulWidget {
  final List<Map<String, dynamic>> siparisler;
  final void Function(Map<String, dynamic> s) onDetay;
  final Future<void> Function() onYenile;

  const BekleyenSiparisMasaustuGorunum({
    super.key,
    required this.siparisler,
    required this.onDetay,
    required this.onYenile,
  });

  @override
  State<BekleyenSiparisMasaustuGorunum> createState() =>
      _BekleyenSiparisMasaustuGorunumState();
}

class _BekleyenSiparisMasaustuGorunumState
    extends State<BekleyenSiparisMasaustuGorunum> {
  Object? _seciliId;

  static final _tarihBicim = DateFormat('dd.MM.yyyy HH:mm');

  static double _tutar(Map<String, dynamic> s) =>
      (s['genel_toplam'] as num?)?.toDouble() ?? 0;
  static DateTime _tarih(Map<String, dynamic> s) =>
      DateTime.tryParse(s['tarih']?.toString() ?? '') ?? DateTime(1970);

  late final List<TabloKolon<Map<String, dynamic>>> _kolonlar = [
    TabloKolon(
        baslik: 'Bayi / Müşteri',
        genislik: 260,
        esnek: true,
        deger: (s) => s['cari_unvan']?.toString() ?? '—',
        sirala: (s) => (s['cari_unvan']?.toString() ?? '').toLowerCase()),
    TabloKolon(
        baslik: 'Tarih',
        genislik: 140,
        deger: (s) => _tarihBicim.format(_tarih(s)),
        sirala: _tarih),
    TabloKolon(
        baslik: 'Tutar',
        genislik: 130,
        sagaYasli: true,
        deger: (s) => ParaUtils.formatla(_tutar(s)),
        sirala: _tutar),
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

  /// Yenilemede map nesneleri değişir; seçimi id ile yeniden bul.
  Map<String, dynamic>? get _secili {
    final id = _seciliId;
    if (id == null) return null;
    for (final s in widget.siparisler) {
      if (s['id'] == id) return s;
    }
    return null;
  }

  void _menu(Map<String, dynamic> s, Offset konum) {
    masaustuMenuAc(context, konum, [
      MenuOge('Detay / Onayla', () => widget.onDetay(s), ikon: Icons.open_in_new),
    ]);
  }

  bool _tus(KeyEvent e) {
    if (e is! KeyDownEvent || !mounted) return false;
    if (!ekranUstte(context)) return false;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.f2 || k == LogicalKeyboardKey.enter) {
      final s = _secili;
      if (s == null) return false;
      widget.onDetay(s);
      return true;
    }
    if (k == LogicalKeyboardKey.f5) {
      widget.onYenile();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.siparisler;
    final s = _secili;
    final toplam = l.fold(0.0, (t, x) => t + _tutar(x));
    return Column(children: [
      Expanded(
        child: l.isEmpty
            ? Center(
                child: Text('Bekleyen sipariş yok',
                    style: TextStyle(fontSize: 15, color: context.textSecondary)))
            : MasaustuTablo<Map<String, dynamic>>(
                satirlar: l,
                kolonlar: _kolonlar,
                secili: s,
                onSec: (x) => setState(() => _seciliId = x['id']),
                onCift: widget.onDetay,
                onSagTik: _menu,
              ),
      ),
      MasaustuAltSerit(
        ozetler: [
          AltOzet('Sipariş', '${l.length}'),
          AltOzet('Toplam', ParaUtils.formatla(toplam), renk: TsRenk.primary),
        ],
        tuslar: [
          AltTus('F2', 'Detay / Onayla', Icons.open_in_new,
              const Color(0xFF1565C0), s == null ? null : () => widget.onDetay(s)),
          AltTus('F5', 'Yenile', Icons.refresh, const Color(0xFF455A64),
              () => widget.onYenile()),
        ],
      ),
    ]);
  }
}
