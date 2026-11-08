// lib/widgetlar/ortak/bulut_durum_widget.dart
// AppBar'a küçük bulut ikonu — sync durumunu gösterir
import '../../tasarim_sistemi/ts_token.dart';
import 'package:flutter/material.dart';
import '../../servisler/bulut/bulut_manager.dart';
import '../../servisler/bulut/saat_farki.dart';

class BulutDurumIkonu extends StatelessWidget {
  const BulutDurumIkonu({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BulutDurum>(
      valueListenable: BulutManager().durum,
      builder: (_, durum, _) {
        if (durum == BulutDurum.yapilandirilmamis ||
            durum == BulutDurum.bagliDegil) {
          return const SizedBox.shrink();
        }

        return Row(mainAxisSize: MainAxisSize.min, children: [
          const _SaatUyarisi(),
          Tooltip(
            message: durum.metin,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _ikon(durum),
            ),
          ),
        ]);
      },
    );
  }

  Widget _ikon(BulutDurum d) {
    switch (d) {
      case BulutDurum.bagli:
        return const Icon(Icons.cloud_done_rounded,
            color: TsRenk.basarili, size: 20);
      case BulutDurum.gonderiliyor:
        return const SizedBox(
          width: 18, height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2, color: TsRenk.primary));
      case BulutDurum.bekliyor:
        return const Icon(Icons.cloud_upload_outlined,
            color: TsRenk.uyari, size: 20);
      case BulutDurum.hata:
        return const Icon(Icons.cloud_off_rounded,
            color: TsRenk.hata, size: 20);
      case BulutDurum.baglaniyor:
        return const SizedBox(
          width: 18, height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2, color: TsRenk.bilgi));
      default:
        return const SizedBox.shrink();
    }
  }
}

/// Cihaz saati sunucudan belirgin farklıysa kırmızı saat ikonu: senkronda
/// "hangi kayıt daha yeni" kararı kayıt saatine dayanır, yanlış saat
/// eski değişikliğin yeniyi ezmesine yol açabilir (2026-11-08).
class _SaatUyarisi extends StatelessWidget {
  const _SaatUyarisi();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Duration?>(
      valueListenable: BulutManager().saatFarki,
      builder: (_, fark, _) {
        if (!SaatFarki.sapmaVar(fark)) return const SizedBox.shrink();
        return Tooltip(
          message: '${SaatFarki.metin(fark!)}.\n'
              'Senkronda yeni/eski kayıt yanlış seçilebilir — cihazın tarih/saat '
              'ayarında "otomatik saat"i açın.',
          child: const Padding(
            padding: EdgeInsets.only(right: 6),
            child: Icon(Icons.schedule_rounded, color: TsRenk.hata, size: 20),
          ),
        );
      },
    );
  }
}

/// AppBar actions'a eklenecek zorla sync butonu
class BulutSyncButon extends StatelessWidget {
  const BulutSyncButon({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BulutDurum>(
      valueListenable: BulutManager().durum,
      builder: (_, durum, _) {
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
