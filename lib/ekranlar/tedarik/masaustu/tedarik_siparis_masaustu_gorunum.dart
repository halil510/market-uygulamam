// lib/ekranlar/tedarik/masaustu/tedarik_siparis_masaustu_gorunum.dart
//
// Tedarikçi Siparişleri — masaüstü tablo görünümü (canlı tarama 2026-10-08:
// masaüstünde telefon kartları görünüyordu). Tablo + alt şerit + sağ tık:
// F1 Sipariş Ver, F2 Detay, F3 Teslim Al, F4 İptal. İşlemler çağıran
// ekrandan gelir; sipariş verme yetkisi mobildekiyle aynı (Admin/Müdür).
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

class TedarikSiparisMasaustuGorunum extends StatefulWidget {
  final List<Map<String, dynamic>> siparisler;
  final String bosMesaj;
  final bool siparisVerebilir;
  final VoidCallback onSiparisVer;
  final void Function(Map<String, dynamic> s) onDetay;
  final void Function(Map<String, dynamic> s) onTeslimAl;
  final void Function(Map<String, dynamic> s) onIptal;
  final String Function(String durum) durumEtiket;
  final Color Function(String durum) durumRenk;

  const TedarikSiparisMasaustuGorunum({
    super.key,
    required this.siparisler,
    required this.bosMesaj,
    required this.siparisVerebilir,
    required this.onSiparisVer,
    required this.onDetay,
    required this.onTeslimAl,
    required this.onIptal,
    required this.durumEtiket,
    required this.durumRenk,
  });

  @override
  State<TedarikSiparisMasaustuGorunum> createState() =>
      _TedarikSiparisMasaustuGorunumState();
}

class _TedarikSiparisMasaustuGorunumState extends State<TedarikSiparisMasaustuGorunum> {
  int? _seciliId;
  static final _tarih = DateFormat('dd.MM.yyyy');

  static DateTime? _tarihi(Map<String, dynamic> s) =>
      DateTime.tryParse(s['siparis_tarihi']?.toString() ?? '');
  static double _tutar(Map<String, dynamic> s) =>
      (s['toplam_tutar'] as num?)?.toDouble() ?? 0;
  static String _durum(Map<String, dynamic> s) => s['durum'] as String? ?? '';

  late final List<TabloKolon<Map<String, dynamic>>> _kolonlar = [
    TabloKolon(
        baslik: 'Sipariş No',
        genislik: 170,
        deger: (s) => '${s['siparis_no'] ?? '—'}',
        sirala: (s) => '${s['siparis_no'] ?? ''}'),
    TabloKolon(
        baslik: 'Tarih',
        genislik: 110,
        deger: (s) {
          final t = _tarihi(s);
          return t == null ? '—' : _tarih.format(t);
        },
        sirala: (s) => _tarihi(s) ?? DateTime(2000)),
    TabloKolon(
        baslik: 'Tedarikçi',
        genislik: 300,
        esnek: true,
        deger: (s) => s['tedarikci_adi'] as String? ?? 'Tedarikçi',
        sirala: (s) => (s['tedarikci_adi'] as String? ?? '').toLowerCase()),
    TabloKolon(
        baslik: 'Durum',
        genislik: 130,
        deger: (s) => widget.durumEtiket(_durum(s)),
        renk: (s) => widget.durumRenk(_durum(s))),
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

  Map<String, dynamic>? get _secili {
    for (final s in widget.siparisler) {
      if (s['id'] == _seciliId) return s;
    }
    return null;
  }

  bool _bekliyor(Map<String, dynamic>? s) => s != null && _durum(s) == 'beklemede';

  void _menu(Map<String, dynamic> s, Offset konum) {
    masaustuMenuAc(context, konum, [
      MenuOge('Detay', () => widget.onDetay(s), ikon: Icons.receipt_long_outlined),
      if (_bekliyor(s)) ...[
        MenuOge('Teslim Al', () => widget.onTeslimAl(s), ikon: Icons.check),
        MenuOge('İptal Et', () => widget.onIptal(s),
            ikon: Icons.close, ayiracOnce: true),
      ],
    ]);
  }

  bool _tus(KeyEvent e) {
    if (e is! KeyDownEvent || !mounted || !ekranUstte(context)) return false;
    final k = e.logicalKey;
    final s = _secili;
    if (k == LogicalKeyboardKey.f1 && widget.siparisVerebilir) {
      widget.onSiparisVer();
    } else if (k == LogicalKeyboardKey.f2 && s != null) {
      widget.onDetay(s);
    } else if (k == LogicalKeyboardKey.f3 && _bekliyor(s)) {
      widget.onTeslimAl(s!);
    } else if (k == LogicalKeyboardKey.f4 && _bekliyor(s)) {
      widget.onIptal(s!);
    } else {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.siparisler;
    final s = _secili;
    final toplam = l.fold<double>(0, (t, x) => t + _tutar(x));
    return Column(children: [
      Expanded(
        child: l.isEmpty
            ? Center(
                child: Text(widget.bosMesaj,
                    style: TextStyle(fontSize: 15, color: context.textSecondary)))
            : MasaustuTablo<Map<String, dynamic>>(
                satirlar: l,
                kolonlar: _kolonlar,
                secili: s,
                onSec: (x) => setState(() => _seciliId = x['id'] as int?),
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
          if (widget.siparisVerebilir)
            AltTus('F1', 'Sipariş Ver', Icons.add_shopping_cart,
                const Color(0xFF2E7D32), widget.onSiparisVer),
          AltTus('F2', 'Detay', Icons.receipt_long_outlined, const Color(0xFF1565C0),
              s == null ? null : () => widget.onDetay(s)),
          AltTus('F3', 'Teslim Al', Icons.check, const Color(0xFF00897B),
              _bekliyor(s) ? () => widget.onTeslimAl(s!) : null),
          AltTus('F4', 'İptal Et', Icons.close, const Color(0xFFC62828),
              _bekliyor(s) ? () => widget.onIptal(s!) : null),
        ],
      ),
    ]);
  }
}
