// lib/ekranlar/satis/coklu_odeme_ekrani.dart
// v4.0 - Hesap makinesi tarzı, tek-ekran profesyonel çoklu ödeme.
//
// Akış: Toplam tutar üstte görünür, ortadaki büyük ekran "girilecek tutar"ı
// gösterir (başlangıçta TOPLAM tutar yazılıdır). Kullanıcı özel tuş takımı
// ile bir miktar yazar (örn. 80), bir ödeme yöntemine basar (örn. "Nakit")
// -> o yönteme 80 atanır, ekran KALAN'a (20) güncellenir ve hazır bekler.
// Kullanıcı yeni bir sayı yazmadan başka bir yönteme basarsa (örn. "Havale")
// ekrandaki KALAN miktar o yönteme atanır ve kalan 0 olduğunda satış otomatik
// tamamlanır. Zaten atanmış bir yönteme tekrar basmak o atamayı geri alır
// (düzeltme/silme).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';

class CokluOdemeEkrani extends ConsumerStatefulWidget {
  final double toplamTutar;
  final bool cariMevcut;
  const CokluOdemeEkrani({
    super.key,
    required this.toplamTutar,
    this.cariMevcut = false,
  });

  @override
  ConsumerState<CokluOdemeEkrani> createState() => _CokluOdemeEkraniState();
}

class _YontemBilgi {
  final String ad;
  final IconData ikon;
  final Color renk;
  const _YontemBilgi(this.ad, this.ikon, this.renk);
}

const _yontemler = [
  _YontemBilgi('Nakit', Icons.payments_outlined, Color(0xFF2E7D32)),
  _YontemBilgi('Kredi Kartı', Icons.credit_card, Color(0xFF1565C0)),
  _YontemBilgi('Havale/EFT', Icons.account_balance, Color(0xFF6A1B9A)),
  _YontemBilgi('Cari', Icons.person_outline, Color(0xFFEF6C00)),
];

class _CokluOdemeEkraniState extends ConsumerState<CokluOdemeEkrani> {
  final Map<String, double> _atamalar = {};
  String _ekran = '';
  bool _yeniGiris = true;

  List<_YontemBilgi> get _aktifYontemler =>
      widget.cariMevcut ? _yontemler : _yontemler.where((y) => y.ad != 'Cari').toList();

  double get _toplamAtanan => _atamalar.values.fold(0.0, (a, b) => a + b);
  double get _kalan => widget.toplamTutar - _toplamAtanan;
  double get _ekranDeger => double.tryParse(_ekran.isEmpty ? '0' : _ekran) ?? 0;

  String _fmtSayi(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    var s = v.toStringAsFixed(2);
    if (s.endsWith('0')) s = s.substring(0, s.length - 1);
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    return s;
  }

  @override
  void initState() {
    super.initState();
    _ekran = _fmtSayi(widget.toplamTutar);
    _yeniGiris = true;
  }

  // ── Tuş takımı ───────────────────────────────────────────────────────────
  void _rakamBas(String r) {
    setState(() {
      if (_yeniGiris) {
        _ekran = r == '0' ? '0' : r;
        _yeniGiris = false;
      } else {
        if (_ekran == '0') {
          _ekran = r;
        } else {
          final nokta = _ekran.indexOf('.');
          if (nokta >= 0 && _ekran.length - nokta - 1 >= 2) return;
          _ekran += r;
        }
      }
    });
  }

  void _noktaBas() {
    setState(() {
      if (_yeniGiris) {
        _ekran = '0.';
        _yeniGiris = false;
      } else if (!_ekran.contains('.')) {
        _ekran += '.';
      }
    });
  }

  void _silBas() {
    setState(() {
      if (_yeniGiris || _ekran.length <= 1) {
        _ekran = '0';
        _yeniGiris = true;
      } else {
        _ekran = _ekran.substring(0, _ekran.length - 1);
      }
    });
  }

  void _temizleBas() {
    setState(() {
      _ekran = '0';
      _yeniGiris = true;
    });
  }

  // ── Ödeme yöntemi butonu ─────────────────────────────────────────────────
  void _yontemBas(String yontem) {
    HapticFeedback.lightImpact();
    if (_atamalar.containsKey(yontem)) {
      setState(() {
        _atamalar.remove(yontem);
        _ekran = _fmtSayi(_kalan);
        _yeniGiris = true;
      });
      return;
    }

    final deger = _ekranDeger;
    if (deger <= 0) return;

    setState(() => _atamalar[yontem] = deger);

    final yeniKalan = _kalan;
    if (yeniKalan <= 0.005) {
      _tamamla();
    } else {
      setState(() {
        _ekran = _fmtSayi(yeniKalan);
        _yeniGiris = true;
      });
    }
  }

  void _tamamla() {
    if (_kalan > 0.005) return;
    final toplamOdenen = _toplamAtanan;
    final paraUstu = toplamOdenen > widget.toplamTutar ? toplamOdenen - widget.toplamTutar : 0.0;
    HapticFeedback.mediumImpact();
    Navigator.pop(context, {
      'kalemler': _atamalar.entries.map((e) => {'yontem': e.key, 'tutar': e.value}).toList(),
      'para_ustu': paraUstu,
      'toplam_odenen': toplamOdenen,
    });
  }

  // ── UI ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final tamamlanabilir = _kalan <= 0.005 && _atamalar.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: TsRenk.kart(context),
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 16)],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(children: [
                _buildEkran(),
                const SizedBox(height: 12),
                _buildYontemGrid(),
                const SizedBox(height: 12),
                _buildTusTakimi(),
              ]),
            ),
          ),
          _buildBottomBar(tamamlanabilir),
        ]),
      ),
    );
  }

  Widget _buildHeader() => Container(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
    ),
    child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Toplam Tutar', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
        Text(ParaUtils.formatla(widget.toplamTutar),
            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
      ])),
      IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
    ]),
  );

  Widget _buildEkran() {
    final etiket = _atamalar.isEmpty
        ? 'Tutar Girin'
        : (_kalan > 0.005 ? 'Kalan' : 'Para Üstü');
    final renk = _kalan > 0.005 ? const Color(0xFFD32F2F)
        : (_kalan < -0.005 ? const Color(0xFF2E7D32) : const Color(0xFF1565C0));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: renk.withAlpha(15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: renk.withAlpha(64)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Align(alignment: Alignment.centerLeft,
            child: Text(etiket, style: TsMetin.kucukVurgu.copyWith(color: renk))),
        const SizedBox(height: 4),
        FittedBox(fit: BoxFit.scaleDown, child: Text('₺ $_ekran',
            style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: renk, letterSpacing: 0.5))),
        if (_kalan < -0.005)
          Padding(padding: const EdgeInsets.only(top: 2),
              child: Text('${ParaUtils.formatla(-_kalan)} para üstü verilecek',
                  style: TextStyle(fontSize: 11.5, color: renk.withAlpha(204)))),
      ]),
    );
  }

  Widget _buildYontemGrid() => GridView.count(
    crossAxisCount: 2,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    mainAxisSpacing: 10, crossAxisSpacing: 10,
    childAspectRatio: 2.6,
    children: _aktifYontemler.map((y) {
      final atandi = _atamalar.containsKey(y.ad);
      final tutar = _atamalar[y.ad];
      return Material(
        color: atandi ? y.renk.withAlpha(31) : TsRenk.arkaplan(context),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _yontemBas(y.ad),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: atandi ? y.renk : TsRenk.ayirac(context), width: atandi ? 1.5 : 1),
            ),
            child: Row(children: [
              Icon(y.ikon, color: y.renk, size: 22),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(y.ad, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                    color: atandi ? y.renk : TsRenk.metinBirincil(context))),
                if (atandi)
                  Text(ParaUtils.formatla(tutar!), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: y.renk)),
              ])),
              if (atandi) Icon(Icons.close, size: 16, color: y.renk.withAlpha(179)),
            ]),
          ),
        ),
      );
    }).toList(),
  );

  Widget _buildTusTakimi() {
    Widget tus(String etiket, {VoidCallback? onTap, Color? bg, Color? fg, Widget? child}) => Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Material(
          color: bg ?? TsRenk.arkaplan(context),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Container(
              height: 52, alignment: Alignment.center,
              child: child ?? Text(etiket, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: fg ?? TsRenk.metinBirincil(context))),
            ),
          ),
        ),
      ),
    );

    return Column(children: [
      Row(children: [
        tus('1', onTap: () => _rakamBas('1')),
        tus('2', onTap: () => _rakamBas('2')),
        tus('3', onTap: () => _rakamBas('3')),
        tus('C', onTap: _temizleBas, bg: TsRenk.zemin(TsRenk.hata), fg: Colors.red),
      ]),
      Row(children: [
        tus('4', onTap: () => _rakamBas('4')),
        tus('5', onTap: () => _rakamBas('5')),
        tus('6', onTap: () => _rakamBas('6')),
        tus('⌫', onTap: _silBas, bg: TsRenk.zemin(TsRenk.uyari), fg: Colors.orange.shade800,
            child: Icon(Icons.backspace_outlined, size: 20, color: Colors.orange.shade800)),
      ]),
      Row(children: [
        tus('7', onTap: () => _rakamBas('7')),
        tus('8', onTap: () => _rakamBas('8')),
        tus('9', onTap: () => _rakamBas('9')),
        tus('Kalan', onTap: () => setState(() {
          _ekran = _fmtSayi(_kalan <= 0 ? 0 : _kalan);
          _yeniGiris = true;
        }), bg: TsRenk.zemin(TsRenk.bilgi), fg: Colors.blue.shade800,
            child: Text('Kalan', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.blue.shade800))),
      ]),
      Row(children: [
        tus('00', onTap: () { _rakamBas('0'); _rakamBas('0'); }),
        tus('0', onTap: () => _rakamBas('0')),
        tus('.', onTap: _noktaBas),
        const Expanded(child: SizedBox()),
      ]),
    ]);
  }

  Widget _buildBottomBar(bool tamamlanabilir) => Container(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
    decoration: BoxDecoration(color: TsRenk.kart(context), border: Border(top: BorderSide(color: TsRenk.ayirac(context)))),
    child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Ödenen', style: TextStyle(fontSize: 12, color: TsRenk.arkaplan(context))),
        Text(ParaUtils.formatla(_toplamAtanan),
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                color: tamamlanabilir ? Colors.green : TsRenk.metinBirincil(context))),
      ])),
      SizedBox(
        height: 52,
        child: FilledButton.icon(
          onPressed: tamamlanabilir ? _tamamla : null,
          icon: const Icon(Icons.check_circle_outline),
          label: Text(tamamlanabilir
              ? 'Satışı Tamamla'
              : (_atamalar.isEmpty ? 'Tutar girip yöntem seçin' : 'Kalan: ${ParaUtils.formatla(_kalan)}')),
          style: FilledButton.styleFrom(
            backgroundColor: tamamlanabilir ? const Color(0xFF2E7D32) : TsRenk.metinIkincil(context),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
    ]),
  );
}