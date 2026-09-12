// lib/tasarim_sistemi/ts_kpi_kart.dart
//
// ERP/POS dashboard'larda tekrar eden "başlık + büyük rakam + ikon (+
// isteğe bağlı trend yüzdesi)" kartı — ÖNCEDEN dashboard_ekrani.dart gibi
// ekranlarda her biri kendi yerel widget'ıyla (_statKart) ayrı ayrı
// çiziliyordu. Tek kaynağa taşındı; davranış/görünüm aynı kalacak şekilde.
import 'package:flutter/material.dart';
import 'ts_token.dart';

class TsKpiKart extends StatelessWidget {
  final String baslik;
  final String deger;
  final IconData ikon;
  final Color renk;

  /// Pozitif/negatif trend yüzdesi (ör. 12.4 → "↑ %12.4"). null ise gösterilmez.
  final double? trendYuzde;
  final String? trendAciklama;

  const TsKpiKart({
    super.key,
    required this.baslik,
    required this.deger,
    required this.ikon,
    required this.renk,
    this.trendYuzde,
    this.trendAciklama,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(TsBosluk.lg),
      decoration: BoxDecoration(
        color: TsRenk.kart(context),
        borderRadius: BorderRadius.circular(TsRadius.lg),
        boxShadow: [
          BoxShadow(
            color: renk.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(TsBosluk.sm),
          decoration: BoxDecoration(
            color: TsRenk.zemin(renk, opaklik: 0.12),
            borderRadius: BorderRadius.circular(TsRadius.md),
          ),
          child: Icon(ikon, color: renk, size: 18),
        ),
        const Spacer(),
        Text(deger,
            style: TsMetin.baslikL.copyWith(color: renk),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        Text(baslik,
            style: TsMetin.kucuk.copyWith(color: TsRenk.metinIkincil(context))),
        if (trendYuzde != null) ...[
          const SizedBox(height: 6),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(trendYuzde! >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                size: 12,
                color: trendYuzde! >= 0 ? TsRenk.basarili : TsRenk.hata),
            const SizedBox(width: 2),
            Text('%${trendYuzde!.abs().toStringAsFixed(1)}',
                style: TsMetin.kucukVurgu.copyWith(
                    color: trendYuzde! >= 0 ? TsRenk.basarili : TsRenk.hata)),
            if (trendAciklama != null) ...[
              const SizedBox(width: 4),
              Text(trendAciklama!,
                  style: TsMetin.kucuk
                      .copyWith(color: TsRenk.metinIkincil(context))),
            ],
          ]),
        ],
      ]),
    );
  }
}
