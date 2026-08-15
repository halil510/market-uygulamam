// lib/tasarim_sistemi/ts_bos_durum.dart
import 'package:flutter/material.dart';
import 'ts_token.dart';

/// Tek boş-durum / hata-durumu gösterimi. Daha önce bos_widget.dart,
/// hata_widget.dart ve AppStiller.bosEkran() olarak 3 ayrı yerde vardı.
class TsBosDurum extends StatelessWidget {
  final IconData ikon;
  final String baslik;
  final String? altyazi;
  final Color? renk;
  final String? aksiyonMetni;
  final VoidCallback? aksiyon;

  const TsBosDurum({
    super.key,
    this.ikon = Icons.inbox_outlined,
    required this.baslik,
    this.altyazi,
    this.renk,
    this.aksiyonMetni,
    this.aksiyon,
  });

  @override
  Widget build(BuildContext context) {
    final r = renk ?? TsRenk.metinIkincil(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(TsBosluk.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(TsBosluk.lg),
              decoration: BoxDecoration(
                color: TsRenk.zemin(r, opaklik: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(ikon, size: 40, color: r),
            ),
            const SizedBox(height: TsBosluk.lg),
            Text(baslik,
                style: TsMetin.baslikM
                    .copyWith(color: TsRenk.metinBirincil(context)),
                textAlign: TextAlign.center),
            if (altyazi != null) ...[
              const SizedBox(height: TsBosluk.xs),
              Text(altyazi!,
                  style: TsMetin.govde
                      .copyWith(color: TsRenk.metinIkincil(context)),
                  textAlign: TextAlign.center),
            ],
            if (aksiyonMetni != null && aksiyon != null) ...[
              const SizedBox(height: TsBosluk.xl),
              FilledButton(onPressed: aksiyon, child: Text(aksiyonMetni!)),
            ],
          ],
        ),
      ),
    );
  }
}
