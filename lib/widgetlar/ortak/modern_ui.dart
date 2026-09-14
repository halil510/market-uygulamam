// lib/widgetlar/ortak/modern_ui.dart
// Modern UI bileşenleri — tüm ekranlarda tutarlılık
//
// NOT: StatKart ve BilgiSatiri artık tek kaynağa (lib/tasarim_sistemi/)
// yönlendirilir; bu dosyanın diğer sınıfları (ModernListTile, ModernAramaKutusu
// vb.) projede fiilen kullanılmadığı için (bkz. YOL_HARITASI.md) olduğu gibi
// bırakıldı — kaldırılmaları ayrı bir temizlik adımı olmalı.

import 'package:flutter/material.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/ts_kart.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';

// ── Modern Stat Kart ──────────────────────────────────────────────────────
class StatKart extends StatelessWidget {
  final String baslik;
  final String deger;
  final IconData ikon;
  final Color renk;
  final String? altBilgi;
  final VoidCallback? onTap;

  const StatKart({
    super.key,
    required this.baslik,
    required this.deger,
    required this.ikon,
    required this.renk,
    this.altBilgi,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TsKart.istatistik(
      baslik: baslik,
      deger: deger,
      altDeger: altBilgi,
      ikon: Icon(ikon),
      vurguRenk: renk,
      onTap: onTap,
    );
  }
}

// ── Modern Liste Öğesi ───────────────────────────────────────────────────
class ModernListTile extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final Color? selectedColor;

  const ModernListTile({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.selectedColor,
  });

  @override
  Widget build(BuildContext context) {
    final c = selectedColor ?? AppRenkler.primary;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: selected ? Color.fromARGB(15, c.red, c.green, c.blue) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? c : Colors.grey.shade200,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TsMetin.govdeVurgu,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ]),
        ),
      ),
    );
  }
}

// ── Modern Arama Kutusu ───────────────────────────────────────────────────
class ModernAramaKutusu extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTemizle;
  final Widget? suffix;

  const ModernAramaKutusu({
    super.key,
    required this.controller,
    this.hint = 'Ara...',
    this.onChanged,
    this.onTemizle,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
          prefixIcon: Icon(Icons.search, color: Colors.grey.shade400, size: 20),
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  color: Colors.grey.shade400,
                  onPressed: () {
                    controller.clear();
                    onTemizle?.call();
                  },
                )
              : suffix,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
}

// ── Boş Durum Widget ─────────────────────────────────────────────────────
class BosEkranWidget extends StatelessWidget {
  final IconData ikon;
  final String baslik;
  final String? aciklama;
  final Widget? buton;
  final Color? ikonRenk;

  const BosEkranWidget({
    super.key,
    required this.ikon,
    required this.baslik,
    this.aciklama,
    this.buton,
    this.ikonRenk,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Color.fromARGB(20, (ikonRenk ?? Colors.grey).red, (ikonRenk ?? Colors.grey).green, (ikonRenk ?? Colors.grey).blue),
                shape: BoxShape.circle,
              ),
              child: Icon(ikon, size: 48,
                  color: Color.fromARGB(153, (ikonRenk ?? Colors.grey).red, (ikonRenk ?? Colors.grey).green, (ikonRenk ?? Colors.grey).blue)),
            ),
            const SizedBox(height: 20),
            Text(baslik,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700,
                    color: Color(0xFF424242)),
                textAlign: TextAlign.center),
            if (aciklama != null) ...[
              const SizedBox(height: 8),
              Text(aciklama!,
                  style: TextStyle(
                      fontSize: 13, color: Colors.grey.shade500),
                  textAlign: TextAlign.center),
            ],
            if (buton != null) ...[const SizedBox(height: 24), buton!],
          ],
        ),
      ),
    );
  }
}

// ── Modern Özet Header ───────────────────────────────────────────────────
class OzetHeader extends StatelessWidget {
  final List<OzetItem> items;
  final Color? bgColor;

  const OzetHeader({super.key, required this.items, this.bgColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: bgColor ?? AppRenkler.primary,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
      ),
      child: Row(
        children: items
            .map((item) => Expanded(child: _OzetItemWidget(item: item)))
            .toList(),
      ),
    );
  }
}

class OzetItem {
  final String label;
  final String deger;
  final Color? renkOverride;
  const OzetItem(this.label, this.deger, {this.renkOverride});
}

class _OzetItemWidget extends StatelessWidget {
  final OzetItem item;
  const _OzetItemWidget({required this.item});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(item.deger,
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: item.renkOverride ?? Colors.white),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        Text(item.label,
            style: TextStyle(
                fontSize: 10,
                color: Color(0xB2FFFFFF),
                fontWeight: FontWeight.w500),
            textAlign: TextAlign.center),
      ],
    );
  }
}

// ── Modern Buton ─────────────────────────────────────────────────────────
class ModernButon extends StatelessWidget {
  final String label;
  final IconData? ikon;
  final VoidCallback? onTap;
  final Color? renk;
  final bool yukleniyor;
  final bool outlined;
  final double? genislik;

  const ModernButon({
    super.key,
    required this.label,
    this.ikon,
    this.onTap,
    this.renk,
    this.yukleniyor = false,
    this.outlined = false,
    this.genislik,
  });

  @override
  Widget build(BuildContext context) {
    final c = renk ?? AppRenkler.primary;
    if (outlined) {
      return SizedBox(
        width: genislik,
        height: 48,
        child: OutlinedButton.icon(
          onPressed: yukleniyor ? null : onTap,
          icon: yukleniyor
              ? SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: c))
              : (ikon != null ? Icon(ikon, size: 18) : const SizedBox.shrink()),
          label: Text(label),
          style: OutlinedButton.styleFrom(
            foregroundColor: c,
            side: BorderSide(color: c),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );
    }
    return SizedBox(
      width: genislik,
      height: 48,
      child: ElevatedButton.icon(
        onPressed: yukleniyor ? null : onTap,
        icon: yukleniyor
            ? const SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : (ikon != null ? Icon(ikon, size: 18, color: Colors.white) : const SizedBox.shrink()),
        label: Text(label,
            style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
        style: ElevatedButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: c,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}

// ── Status Badge ─────────────────────────────────────────────────────────
class StatusBadge extends StatelessWidget {
  final String metin;
  final Color renk;
  final double fontSize;

  const StatusBadge(this.metin, this.renk, {super.key, this.fontSize = 11});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Color.fromARGB(31, renk.red, renk.green, renk.blue),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Color.fromARGB(76, renk.red, renk.green, renk.blue)),
      ),
      child: Text(metin,
          style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              color: renk)),
    );
  }
}

// ── Bilgi Satırı ─────────────────────────────────────────────────────────
class BilgiSatiri extends StatelessWidget {
  final String label;
  final String deger;
  final Color? degerRenk;
  final FontWeight degerAgirlik;

  const BilgiSatiri(
    this.label,
    this.deger, {
    super.key,
    this.degerRenk,
    this.degerAgirlik = FontWeight.w600,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(fontSize: 13, color: context.textSecondary)),
          Text(deger,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: degerAgirlik,
                  color: degerRenk ?? context.textPrimary)),
        ],
      ),
    );
  }
}
