// lib/widgetlar/ortak/bulut_durum_widget.dart
// AppBar'a küçük bulut ikonu — sync durumunu gösterir
import 'package:flutter/material.dart';
import '../../servisler/bulut/bulut_manager.dart';

class BulutDurumIkonu extends StatelessWidget {
  const BulutDurumIkonu({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BulutDurum>(
      valueListenable: BulutManager().durum,
      builder: (_, durum, __) {
        if (durum == BulutDurum.yapilandirilmamis ||
            durum == BulutDurum.bagli_degil) {
          return const SizedBox.shrink();
        }

        return Tooltip(
          message: durum.metin,
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _ikon(durum),
          ),
        );
      },
    );
  }

  Widget _ikon(BulutDurum d) {
    switch (d) {
      case BulutDurum.bagli:
        return const Icon(Icons.cloud_done_rounded,
            color: Color(0xFF2ECC71), size: 20);
      case BulutDurum.gonderiliyor:
        return const SizedBox(
          width: 18, height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2, color: Color(0xFF4361EE)));
      case BulutDurum.bekliyor:
        return const Icon(Icons.cloud_upload_outlined,
            color: Color(0xFFF39C12), size: 20);
      case BulutDurum.hata:
        return const Icon(Icons.cloud_off_rounded,
            color: Color(0xFFE74C3C), size: 20);
      case BulutDurum.baglaniyor:
        return const SizedBox(
          width: 18, height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2, color: Colors.blue));
      default:
        return const SizedBox.shrink();
    }
  }
}

/// AppBar actions'a eklenecek zorla sync butonu
class BulutSyncButon extends StatelessWidget {
  const BulutSyncButon({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BulutDurum>(
      valueListenable: BulutManager().durum,
      builder: (_, durum, __) {
        if (!durum.aktif) return const SizedBox.shrink();
        return IconButton(
          icon: const Icon(Icons.sync_rounded, size: 20),
          tooltip: 'Şimdi senkronize et',
          onPressed: () => BulutManager().zorlaGonder(),
        );
      },
    );
  }
}
