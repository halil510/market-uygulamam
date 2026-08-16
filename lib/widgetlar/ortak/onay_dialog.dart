// lib/widgetlar/ortak/onay_dialog.dart
import 'package:flutter/material.dart';

class OnayDialog extends StatelessWidget {
  final String baslik;
  final String icerik;
  final String onayYazi;
  final String iptalYazi;
  final Color? onayRengi;
  final IconData? ikon;

  const OnayDialog({
    super.key,
    required this.baslik,
    required this.icerik,
    this.onayYazi = 'Evet',
    this.iptalYazi = 'İptal',
    this.onayRengi,
    this.ikon,
  });

  static Future<bool> goster(
    BuildContext context, {
    required String baslik,
    required String icerik,
    String onayYazi = 'Evet',
    String iptalYazi = 'İptal',
    Color? onayRengi,
    IconData? ikon,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => OnayDialog(
        baslik: baslik, icerik: icerik,
        onayYazi: onayYazi, iptalYazi: iptalYazi,
        onayRengi: onayRengi, ikon: ikon,
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final renk = onayRengi ?? Theme.of(context).colorScheme.primary;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(children: [
        if (ikon != null) ...[Icon(ikon, color: renk), const SizedBox(width: 8)],
        Text(baslik),
      ]),
      content: Text(icerik),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(iptalYazi),
        ),
        FilledButton(
          style: FilledButton.styleFrom(foregroundColor: Colors.white,
          backgroundColor: renk),
          onPressed: () => Navigator.pop(context, true),
          child: Text(onayYazi, style: const TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
