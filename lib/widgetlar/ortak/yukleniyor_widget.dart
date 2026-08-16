// lib/widgetlar/ortak/yukleniyor_widget.dart
import 'package:flutter/material.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import 'package:shimmer/shimmer.dart';

/// Ekran ortasında gösterilen yükleniyor widget'ı
class YukleniyorWidget extends StatelessWidget {
  final String? mesaj;
  const YukleniyorWidget({super.key, this.mesaj});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const CircularProgressIndicator(strokeWidth: 3),
      if (mesaj != null) ...[
        const SizedBox(height: 16),
        Text(mesaj!, style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color, fontSize: 13)),
      ],
    ]),
  );
}

/// Shimmer liste iskelet — gerçek shimmer animasyonu
class SatirYukleniyorWidget extends StatelessWidget {
  final int satirSayisi;
  final bool kart;
  const SatirYukleniyorWidget({super.key, this.satirSayisi = 6, this.kart = false});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? context.textSecondary : context.borderColor;
    final highlightColor = isDark ? context.textSecondary : context.borderColor;

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: kart ? _kartSkeleton() : _listeSkeleton(),
    );
  }

  Widget _listeSkeleton() => ListView.builder(
    itemCount: satirSayisi,
    padding: const EdgeInsets.all(12),
    physics: const NeverScrollableScrollPhysics(),
    itemBuilder: (_, __) => Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Container(width: 44, height: 44,
            decoration: BoxDecoration(color: Colors.white,
                borderRadius: BorderRadius.circular(8))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(height: 13, width: double.infinity,
              decoration: BoxDecoration(color: Colors.white,
                  borderRadius: BorderRadius.circular(4))),
          const SizedBox(height: 8),
          Container(height: 11, width: 130,
              decoration: BoxDecoration(color: Colors.white,
                  borderRadius: BorderRadius.circular(4))),
        ])),
        Container(width: 60, height: 16,
            decoration: BoxDecoration(color: Colors.white,
                borderRadius: BorderRadius.circular(4))),
      ]),
    ),
  );

  Widget _kartSkeleton() => GridView.builder(
    itemCount: satirSayisi,
    padding: const EdgeInsets.all(12),
    physics: const NeverScrollableScrollPhysics(),
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10,
      childAspectRatio: 0.85),
    itemBuilder: (_, __) => Container(
      decoration: BoxDecoration(color: Colors.white,
          borderRadius: BorderRadius.circular(14)),
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(height: 80, width: double.infinity,
            decoration: BoxDecoration(color: Colors.white,
                borderRadius: BorderRadius.circular(8))),
        const SizedBox(height: 10),
        Container(height: 13, width: double.infinity,
            decoration: BoxDecoration(color: Colors.white,
                borderRadius: BorderRadius.circular(4))),
        const SizedBox(height: 6),
        Container(height: 11, width: 80,
            decoration: BoxDecoration(color: Colors.white,
                borderRadius: BorderRadius.circular(4))),
      ]),
    ),
  );
}

/// Sayfa seviyesi tam ekran shimmer
class SayfaYukleniyorWidget extends StatelessWidget {
  const SayfaYukleniyorWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Shimmer.fromColors(
      baseColor: isDark ? context.textSecondary : context.borderColor,
      highlightColor: isDark ? context.textSecondary : context.borderColor,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        physics: const NeverScrollableScrollPhysics(),
        child: Column(children: [
          // Header kart
          Container(height: 120, width: double.infinity,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: Colors.white,
                  borderRadius: BorderRadius.circular(16))),
          // Grid KPI
          Row(children: List.generate(2, (_) => Expanded(child: Container(
            height: 80, margin: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: Colors.white,
                borderRadius: BorderRadius.circular(12)))))),
          const SizedBox(height: 16),
          // Liste satırları
          ...List.generate(5, (_) => Container(
            height: 72, margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(color: Colors.white,
                borderRadius: BorderRadius.circular(12)))),
        ]),
      ),
    );
  }
}

/// Progress dialog
class ProgressDialog extends StatelessWidget {
  final String mesaj;
  final String? altMesaj;
  const ProgressDialog({super.key, required this.mesaj, this.altMesaj});

  @override
  Widget build(BuildContext context) => AlertDialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    content: Column(mainAxisSize: MainAxisSize.min, children: [
      const SizedBox(height: 8),
      const CircularProgressIndicator(strokeWidth: 3),
      const SizedBox(height: 20),
      Text(mesaj, style: const TextStyle(fontSize: 14), textAlign: TextAlign.center),
      if (altMesaj != null) ...[
        const SizedBox(height: 4),
        Text(altMesaj!, style: TextStyle(fontSize: 12, color: Theme.of(context).textTheme.bodySmall?.color),
            textAlign: TextAlign.center),
      ],
      const SizedBox(height: 8),
    ]),
  );
}
