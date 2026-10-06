// lib/ekranlar/vardiya/masaustu/vardiya_gecmis_masaustu_gorunum.dart
//
// Vardiya geçmişi — masaüstü tablo görünümü. Sayfalama (30'ar kayıt) ve PDF
// rapor çağıran ekrandadır; burada yalnız görünüm + F2 (PDF) / F7 (daha fazla
// yükle) kısayolu vardır.
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

class VardiyaGecmisMasaustuGorunum extends StatefulWidget {
  final List<Map<String, dynamic>> vardiyalar;
  final String Function(String? bas, String? bit) sureMetni;
  final void Function(Map<String, dynamic> v) onPdf;
  final bool dahaVarMi;
  final bool dahaYukleniyor;
  final VoidCallback onDahaFazla;

  const VardiyaGecmisMasaustuGorunum({
    super.key,
    required this.vardiyalar,
    required this.sureMetni,
    required this.onPdf,
    required this.dahaVarMi,
    required this.dahaYukleniyor,
    required this.onDahaFazla,
  });

  @override
  State<VardiyaGecmisMasaustuGorunum> createState() =>
      _VardiyaGecmisMasaustuGorunumState();
}

class _VardiyaGecmisMasaustuGorunumState
    extends State<VardiyaGecmisMasaustuGorunum> {
  Object? _seciliId;

  static final _tarih = DateFormat('dd.MM.yyyy HH:mm');

  static String _t(Map<String, dynamic> v, String alan) {
    final d = DateTime.tryParse(v[alan]?.toString() ?? '');
    return d == null ? '—' : _tarih.format(d);
  }

  static double _fark(Map<String, dynamic> v) =>
      (v['fark'] as num?)?.toDouble() ?? 0;

  late final List<TabloKolon<Map<String, dynamic>>> _kolonlar = [
    TabloKolon(
        baslik: 'Kasiyer',
        genislik: 180,
        esnek: true,
        deger: (v) => v['ad_soyad']?.toString() ?? '—',
        sirala: (v) => (v['ad_soyad']?.toString() ?? '').toLowerCase()),
    TabloKolon(
        baslik: 'Açılış',
        genislik: 135,
        deger: (v) => _t(v, 'acilis_tarihi'),
        sirala: (v) => v['acilis_tarihi']?.toString() ?? ''),
    TabloKolon(
        baslik: 'Kapanış',
        genislik: 135,
        deger: (v) => _t(v, 'kapanis_tarihi'),
        sirala: (v) => v['kapanis_tarihi']?.toString() ?? ''),
    TabloKolon(
        baslik: 'Süre',
        genislik: 90,
        deger: (v) => widget.sureMetni(
            v['acilis_tarihi']?.toString(), v['kapanis_tarihi']?.toString())),
    TabloKolon(
        baslik: 'Bitiş Bakiye',
        genislik: 120,
        sagaYasli: true,
        deger: (v) =>
            ParaUtils.formatla((v['bitis_bakiye'] as num?)?.toDouble() ?? 0),
        sirala: (v) => (v['bitis_bakiye'] as num?)?.toDouble() ?? 0),
    TabloKolon(
        baslik: 'Fark',
        genislik: 100,
        sagaYasli: true,
        deger: (v) => _fark(v).abs() > 0.01
            ? '${_fark(v) > 0 ? '+' : ''}${ParaUtils.formatla(_fark(v))}'
            : '',
        sirala: _fark,
        renk: (v) => _fark(v).abs() <= 0.01
            ? null
            : (_fark(v) > 0 ? TsRenk.primary : TsRenk.hata)),
    TabloKolon(
        baslik: 'Onaylayan',
        genislik: 140,
        deger: (v) => v['onaylayan_adi']?.toString() ?? '',
        sirala: (v) => v['onaylayan_adi']?.toString() ?? ''),
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
    final id = _seciliId;
    if (id == null) return null;
    for (final v in widget.vardiyalar) {
      if (v['id'] == id) return v;
    }
    return null;
  }

  void _menu(Map<String, dynamic> v, Offset konum) {
    masaustuMenuAc(context, konum, [
      MenuOge('PDF Rapor', () => widget.onPdf(v), ikon: Icons.picture_as_pdf_outlined),
    ]);
  }

  bool _tus(KeyEvent e) {
    if (e is! KeyDownEvent || !mounted) return false;
    if (!TickerMode.of(context) || !ekranUstte(context)) return false;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.f2) {
      final s = _secili;
      if (s == null) return false;
      widget.onPdf(s);
    } else if (k == LogicalKeyboardKey.f7 && widget.dahaVarMi) {
      widget.onDahaFazla();
    } else {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.vardiyalar;
    final s = _secili;
    final farkToplam = l.fold(0.0, (t, v) => t + _fark(v));
    return Column(children: [
      Expanded(
        child: l.isEmpty
            ? Center(
                child: Text('Geçmiş vardiya yok',
                    style: TextStyle(color: context.textSecondary)))
            : MasaustuTablo<Map<String, dynamic>>(
                satirlar: l,
                kolonlar: _kolonlar,
                secili: s,
                onSec: (v) => setState(() => _seciliId = v['id']),
                onCift: widget.onPdf,
                onSagTik: _menu,
              ),
      ),
      MasaustuAltSerit(
        ozetler: [
          AltOzet('Yüklenen', '${l.length}'),
          AltOzet('Fark Toplamı', ParaUtils.formatla(farkToplam),
              renk: farkToplam.abs() > 0.01 ? TsRenk.hata : null),
        ],
        tuslar: [
          AltTus('F2', 'PDF Rapor', Icons.picture_as_pdf_outlined,
              const Color(0xFFC62828), s == null ? null : () => widget.onPdf(s)),
          if (widget.dahaVarMi)
            AltTus('F7', widget.dahaYukleniyor ? 'Yükleniyor…' : 'Daha Fazla',
                Icons.expand_more, const Color(0xFF455A64),
                widget.dahaYukleniyor ? null : widget.onDahaFazla),
        ],
      ),
    ]);
  }
}
