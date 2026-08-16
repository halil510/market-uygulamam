// lib/widgetlar/ortak/app_widgetlar.dart
// Modern, yeniden kullanılabilir UI bileşenleri
// Her ekranda import 'app_widgetlar.dart' ile kullanılır
//
// NOT: Bu dosyadaki temel "durum" widget'ları (yükleniyor/boş/hata) artık
// lib/tasarim_sistemi/ altındaki TEK kaynağa (TsYukleniyor/TsBosDurum)
// yönlendirilir — 30+ ekranda kullanılan AppYukleniyor tek satırda güncellenip
// tüm ekranlar aynı anda tutarlı hale gelir.

import 'package:flutter/material.dart';
import '../../tasarim_sistemi/ts_token.dart';
import '../../tasarim_sistemi/ts_yukleniyor.dart';
import '../../tasarim_sistemi/ts_bos_durum.dart';
import '../../uygulama/tema/uygulama_temasi.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LOADING WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class AppYukleniyor extends StatelessWidget {
  final String? mesaj;
  const AppYukleniyor({super.key, this.mesaj});

  @override
  Widget build(BuildContext context) {
    if (mesaj == null) return const TsYukleniyor();
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(
          width: 40, height: 40,
          child: CircularProgressIndicator(strokeWidth: 3, color: TsRenk.primary),
        ),
        const SizedBox(height: 14),
        Text(mesaj!,
            style: TextStyle(fontSize: 13, color: context.textSecondary, fontWeight: FontWeight.w500)),
      ]),
    );
  }
}

/// Shimmer skeleton kartı
class ShimmerKart extends StatefulWidget {
  final double yukseklik;
  final double? genislik;
  final double radius;
  const ShimmerKart({
    super.key, this.yukseklik = 80,
    this.genislik, this.radius = 16});

  @override
  State<ShimmerKart> createState() => _ShimmerKartState();
}

class _ShimmerKartState extends State<ShimmerKart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: widget.genislik, height: widget.yukseklik,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          gradient: LinearGradient(
            begin: Alignment(-1 + _anim.value * 2, 0),
            end:   Alignment( 1 + _anim.value * 2, 0),
            colors: [
              context.shimmerBase,
              context.shimmerHighlight,
              context.shimmerBase,
            ],
          ),
        ),
      ),
    );
  }
}

/// Liste shimmer
class ShimmerListe extends StatelessWidget {
  final int adet;
  final double kartYukseklik;
  const ShimmerListe({super.key, this.adet = 5, this.kartYukseklik = 72});

  @override
  Widget build(BuildContext context) => ListView.separated(
    padding: const EdgeInsets.all(16),
    itemCount: adet,
    separatorBuilder: (_, __) => const SizedBox(height: 10),
    itemBuilder: (_, __) => ShimmerKart(yukseklik: kartYukseklik),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// EMPTY STATE WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class BosEkran extends StatelessWidget {
  final IconData ikon;
  final String baslik;
  final String? aciklama;
  final String? butonYazi;
  final VoidCallback? onButon;
  final Color? renk;

  const BosEkran({
    super.key,
    required this.ikon,
    required this.baslik,
    this.aciklama,
    this.butonYazi,
    this.onButon,
    this.renk,
  });

  @override
  Widget build(BuildContext context) => TsBosDurum(
        ikon: ikon,
        baslik: baslik,
        altyazi: aciklama,
        renk: renk,
        aksiyonMetni: butonYazi,
        aksiyon: onButon,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION HEADER
// ─────────────────────────────────────────────────────────────────────────────

class BolumBaslik extends StatelessWidget {
  final String baslik;
  final String? sag;
  final VoidCallback? onSag;
  final EdgeInsets padding;

  const BolumBaslik({
    super.key,
    required this.baslik,
    this.sag,
    this.onSag,
    this.padding = const EdgeInsets.fromLTRB(16, 20, 16, 8),
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Row(children: [
      Expanded(child: Text(baslik,
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
            color: context.textPrimary, letterSpacing: -0.3))),
      if (sag != null)
        GestureDetector(
          onTap: onSag,
          child: Text(sag!,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                color: context.primary)),
        ),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// STAT KARTI
// ─────────────────────────────────────────────────────────────────────────────

class StatKarti extends StatelessWidget {
  final String baslik;
  final String deger;
  final IconData ikon;
  final Color renk;
  final String? degisim;
  final bool degisimArti;
  final VoidCallback? onTap;

  const StatKarti({
    super.key,
    required this.baslik,
    required this.deger,
    required this.ikon,
    required this.renk,
    this.degisim,
    this.degisimArti = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
        boxShadow: [BoxShadow(
          color: Colors.black.withAlpha(8),
          blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: renk.withAlpha(26),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(ikon, color: renk, size: 18),
          ),
          const Spacer(),
          if (onTap != null)
            Icon(Icons.arrow_forward_ios_rounded, size: 12,
                color: context.textHint),
        ]),
        const SizedBox(height: 12),
        Text(deger,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800,
              color: context.textPrimary, letterSpacing: -0.5)),
        const SizedBox(height: 2),
        Text(baslik,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500,
              color: context.textSecondary)),
        if (degisim != null) ...[
          const SizedBox(height: 6),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(
              degisimArti ? Icons.trending_up : Icons.trending_down,
              size: 12,
              color: degisimArti ? AppRenkler.success : AppRenkler.error,
            ),
            const SizedBox(width: 3),
            Text(degisim!,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                  color: degisimArti ? AppRenkler.success : AppRenkler.error)),
          ]),
        ],
      ]),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// STATUS BADGE
// ─────────────────────────────────────────────────────────────────────────────

class DurumBadge extends StatelessWidget {
  final String metin;
  final Color renk;
  final IconData? ikon;

  const DurumBadge({
    super.key,
    required this.metin,
    required this.renk,
    this.ikon,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: renk.withAlpha(26),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: renk.withAlpha(77)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      if (ikon != null) ...[
        Icon(ikon, size: 12, color: renk),
        const SizedBox(width: 4),
      ],
      Text(metin,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
            color: renk)),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// MODERN APPBAR GRADIENT
// ─────────────────────────────────────────────────────────────────────────────

class GradientAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String baslik;
  final String? altBaslik;
  final List<Widget> actions;
  final Widget? leading;
  final bool gradient;

  const GradientAppBar({
    super.key,
    required this.baslik,
    this.altBaslik,
    this.actions = const [],
    this.leading,
    this.gradient = true,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    if (!gradient) {
      return AppBar(
        title: Text(baslik),
        leading: leading,
        actions: actions,
      );
    }

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF1A237E), Color(0xFF4361EE)],
        ),
      ),
      child: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: leading,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(baslik,
              style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.w700,
                color: Colors.white)),
            if (altBaslik != null)
              Text(altBaslik!,
                style: const TextStyle(
                  fontSize: 11, color: Colors.white70,
                  fontWeight: FontWeight.w400)),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        actions: actions,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PARA FORMATLI METİN
// ─────────────────────────────────────────────────────────────────────────────

class ParaMetin extends StatelessWidget {
  final double tutar;
  final double boyut;
  final FontWeight agirlik;
  final Color? renk;
  final bool pozitifYesil;

  const ParaMetin({
    super.key,
    required this.tutar,
    this.boyut = 14,
    this.agirlik = FontWeight.w600,
    this.renk,
    this.pozitifYesil = false,
  });

  @override
  Widget build(BuildContext context) {
    Color r;
    if (renk != null) {
      r = renk!;
    } else if (pozitifYesil) {
      r = tutar >= 0 ? AppRenkler.success : AppRenkler.error;
    } else {
      r = context.textPrimary;
    }

    return Text(
      _formatla(tutar),
      style: TextStyle(fontSize: boyut, fontWeight: agirlik, color: r),
    );
  }

  static String _formatla(double t) {
    if (t.abs() >= 1000000) {
      return '₺${(t/1000000).toStringAsFixed(1)}M';
    } else if (t.abs() >= 1000) {
      final str = t.abs().toStringAsFixed(2).replaceAll('.', ',');
      final parts = str.split(',');
      String binlikStr = '';
      final tam = parts[0];
      for (int i = 0; i < tam.length; i++) {
        if (i > 0 && (tam.length - i) % 3 == 0) binlikStr += '.';
        binlikStr += tam[i];
      }
      return '${t < 0 ? "-" : ""}₺$binlikStr,${parts[1]}';
    }
    return '₺${t.toStringAsFixed(2).replaceAll('.', ',')}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ONAY DİYALOGU
// ─────────────────────────────────────────────────────────────────────────────

Future<bool?> onayDiyalogu(
  BuildContext context, {
  required String baslik,
  required String mesaj,
  String onayMetin = 'Onayla',
  String iptalMetin = 'Vazgeç',
  bool tehlikeli = false,
  IconData? ikon,
}) => showDialog<bool>(
  context: context,
  builder: (ctx) => AlertDialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
    title: Row(children: [
      if (ikon != null) ...[
        Icon(ikon,
          color: tehlikeli ? AppRenkler.error : AppRenkler.primary,
          size: 22),
        const SizedBox(width: 8),
      ],
      Expanded(child: Text(baslik,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
    ]),
    content: Text(mesaj,
      style: TextStyle(fontSize: 14, color: ctx.textSecondary, height: 1.4)),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(ctx, false),
        child: Text(iptalMetin)),
      FilledButton(
        onPressed: () => Navigator.pop(ctx, true),
        style: tehlikeli
            ? FilledButton.styleFrom(foregroundColor: Colors.white,
          backgroundColor: AppRenkler.error)
            : null,
        child: Text(onayMetin)),
    ],
  ),
);

// ─────────────────────────────────────────────────────────────────────────────
// SNACKBAR YARDIMCISI
// ─────────────────────────────────────────────────────────────────────────────

void basariMesaji(BuildContext context, String mesaj) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Row(children: [
      const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
      const SizedBox(width: 8),
      Expanded(child: Text(mesaj,
        style: const TextStyle(fontWeight: FontWeight.w500))),
    ]),
    backgroundColor: AppRenkler.success,
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    duration: const Duration(seconds: 2),
  ));
}

void hataMesaji(BuildContext context, String mesaj) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Row(children: [
      const Icon(Icons.error_outline_rounded, color: Colors.white, size: 18),
      const SizedBox(width: 8),
      Expanded(child: Text(mesaj,
        style: const TextStyle(fontWeight: FontWeight.w500))),
    ]),
    backgroundColor: AppRenkler.error,
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    duration: const Duration(seconds: 3),
  ));
}

void bilgiMesaji(BuildContext context, String mesaj, {Color? renk}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(mesaj,
      style: const TextStyle(fontWeight: FontWeight.w500)),
    backgroundColor: renk ?? AppRenkler.info,
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    duration: const Duration(seconds: 2),
  ));
}
