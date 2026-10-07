// lib/ekranlar/masa/widgets/masa_durum_rozeti.dart
//
// Masa durumunun (boş/dolu/hesap istendi/rezerve) renkli rozeti —
// masa_detay_ekrani.dart'tan ayrıldı (2026-10-07 refactor).
import 'package:flutter/material.dart';

import '../../../uygulama/tema/uygulama_temasi.dart';

class MasaDurumRozeti extends StatelessWidget {
  final String durum;
  const MasaDurumRozeti({super.key, required this.durum});

  static String etiket(String durum) => switch (durum) {
        'bos' => 'Boş',
        'dolu' => 'Dolu',
        'hesap_istendi' => 'Hesap İstendi',
        'rezerve' => 'Rezerve',
        _ => durum,
      };

  static IconData ikon(String durum) => switch (durum) {
        'bos' => Icons.check_circle_outline,
        'dolu' => Icons.restaurant_menu,
        'hesap_istendi' => Icons.notifications_active,
        'rezerve' => Icons.event_busy,
        _ => Icons.table_restaurant,
      };

  static Color renk(BuildContext context, String durum) => switch (durum) {
        'bos' => const Color(0xFF2E7D32),
        'dolu' => const Color(0xFFF57C00),
        'hesap_istendi' => const Color(0xFFD32F2F),
        'rezerve' => const Color(0xFF1976D2),
        _ => context.textSecondary,
      };

  @override
  Widget build(BuildContext context) {
    final r = renk(context, durum);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: r.withAlpha(51), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(ikon(durum), size: 14, color: r),
        const SizedBox(width: 4),
        Text(etiket(durum), style: TextStyle(fontSize: 12, color: r)),
      ]),
    );
  }
}
