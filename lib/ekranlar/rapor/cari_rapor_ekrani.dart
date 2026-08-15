// lib/ekranlar/rapor/cari_rapor_ekrani.dart
//
// CARİ RAPORU — dashboard'da vaat edilen ama hiç yapılmamış rapor.
// Toplam alacak/borç özeti, müşteri/tedarikçi sayısı, vadesi geçmiş
// cariler listesi (en riskli olanlar üstte).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../depolar/cari_deposu.dart';
import '../../modeller/cari_model.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';

final _cariIstatistikProvider =
    FutureProvider.autoDispose<Map<String, double>>((ref) => CariDeposu().istatistikler());
final _vadesiGecmislerProvider =
    FutureProvider.autoDispose<List<CariModel>>((ref) => CariDeposu().vadesiGecmisler());

class CariRaporEkrani extends ConsumerWidget {
  const CariRaporEkrani({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final istatistikAsync = ref.watch(_cariIstatistikProvider);
    final vadesiGecmisAsync = ref.watch(_vadesiGecmislerProvider);

    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'Cari Raporu',
        gradyanli: true,
        aksiyonlar: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () {
              ref.invalidate(_cariIstatistikProvider);
              ref.invalidate(_vadesiGecmislerProvider);
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(_cariIstatistikProvider);
          ref.invalidate(_vadesiGecmislerProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(TsBosluk.lg),
          children: [
            istatistikAsync.when(
              loading: () => const TsYukleniyor(iskelet: true),
              error: (e, _) => TsBosDurum(
                  ikon: Icons.error_outline, baslik: 'Yüklenemedi: $e', renk: TsRenk.hata),
              data: (ist) => Column(children: [
                Row(children: [
                  Expanded(
                    child: TsKart.istatistik(
                      baslik: 'Toplam Alacak',
                      deger: ParaUtils.formatla(ist['toplam_alacak'] ?? 0),
                      ikon: const Icon(Icons.arrow_downward_rounded),
                      vurguRenk: TsRenk.basarili,
                    ),
                  ),
                  const SizedBox(width: TsBosluk.md),
                  Expanded(
                    child: TsKart.istatistik(
                      baslik: 'Toplam Borç',
                      deger: ParaUtils.formatla(ist['toplam_borc'] ?? 0),
                      ikon: const Icon(Icons.arrow_upward_rounded),
                      vurguRenk: TsRenk.hata,
                    ),
                  ),
                ]),
                const SizedBox(height: TsBosluk.md),
                Row(children: [
                  Expanded(
                    child: TsKart.istatistik(
                      baslik: 'Müşteri',
                      deger: '${(ist['musteri'] ?? 0).toInt()}',
                      ikon: const Icon(Icons.person_outline),
                      vurguRenk: TsRenk.bilgi,
                      onTap: () => context.push('/cari'),
                    ),
                  ),
                  const SizedBox(width: TsBosluk.md),
                  Expanded(
                    child: TsKart.istatistik(
                      baslik: 'Tedarikçi',
                      deger: '${(ist['tedarikci'] ?? 0).toInt()}',
                      ikon: const Icon(Icons.local_shipping_outlined),
                      vurguRenk: TsRenk.primary,
                      onTap: () => context.push('/cari'),
                    ),
                  ),
                ]),
              ]),
            ),
            const SizedBox(height: TsBosluk.xl),
            istatistikAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (ist) => _AlacakBorcGrafigi(
                alacak: ist['toplam_alacak'] ?? 0,
                borc: ist['toplam_borc'] ?? 0,
              ),
            ),
            const SizedBox(height: TsBosluk.xl),
            Text('Vadesi Geçmiş Cariler (en yüksek bakiyeden)',
                style: TsMetin.baslikM.copyWith(color: TsRenk.metinIkincil(context))),
            const SizedBox(height: TsBosluk.sm),
            vadesiGecmisAsync.when(
              loading: () => const TsYukleniyor(iskelet: true),
              error: (e, _) => TsBosDurum(
                  ikon: Icons.error_outline, baslik: 'Yüklenemedi: $e', renk: TsRenk.hata),
              data: (cariler) {
                if (cariler.isEmpty) {
                  return const TsBosDurum(
                      ikon: Icons.check_circle_outline,
                      baslik: 'Vadesi geçmiş cari yok',
                      renk: TsRenk.basarili);
                }
                return Column(
                  children: cariler
                      .map((c) => Padding(
                            padding: const EdgeInsets.only(bottom: TsBosluk.sm),
                            child: TsKart.liste(
                              ikon: const Icon(Icons.warning_amber_outlined),
                              baslik: c.unvan,
                              altBaslik: c.telefon ?? c.cariTipi,
                              deger: ParaUtils.formatla(c.bakiye),
                              etiketler: const [TsBadge(metin: 'VADESİ GEÇTİ', tur: TsBadgeTuru.hata)],
                              onTap: () => context.push('/cari/detay/${c.id}'),
                            ),
                          ))
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Toplam alacak vs toplam borç karşılaştırması — net durumu (pozitif/
/// negatif) tek bakışta gösteren yatay çubuk grafik. Zaten yüklenmiş
/// istatistikler()'in üzerine kuruluyor, yeni sorgu gerektirmiyor.
class _AlacakBorcGrafigi extends StatelessWidget {
  final double alacak;
  final double borc;
  const _AlacakBorcGrafigi({required this.alacak, required this.borc});

  @override
  Widget build(BuildContext context) {
    if (alacak == 0 && borc == 0) {
      return TsKart(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: TsBosluk.lg),
            child: Text('Grafik için yeterli cari verisi yok',
                style: TsMetin.govde.copyWith(color: TsRenk.metinIkincil(context))),
          ),
        ),
      );
    }
    final maxDeger = [alacak, borc].reduce((a, b) => a > b ? a : b);
    final net = alacak - borc;
    final netRenk = net >= 0 ? TsRenk.basarili : TsRenk.hata;

    return TsKart(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Alacak / Borç Dengesi',
                  style: TsMetin.baslikM.copyWith(color: TsRenk.metinBirincil(context))),
              const Spacer(),
              TsBadge(
                metin: '${net >= 0 ? "NET ALACAKLI" : "NET BORÇLU"} · ${ParaUtils.formatla(net.abs())}',
                tur: net >= 0 ? TsBadgeTuru.basarili : TsBadgeTuru.hata,
              ),
            ],
          ),
          const SizedBox(height: TsBosluk.xl),
          SizedBox(
            height: 140,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxDeger == 0 ? 1 : maxDeger * 1.2,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (v, meta) => Padding(
                        padding: const EdgeInsets.only(top: TsBosluk.xs),
                        child: Text(v == 0 ? 'Alacak' : 'Borç',
                            style: TsMetin.kucuk.copyWith(color: TsRenk.metinIkincil(context))),
                      ),
                    ),
                  ),
                ),
                barGroups: [
                  BarChartGroupData(x: 0, barRods: [
                    BarChartRodData(
                        toY: alacak, color: TsRenk.basarili, width: 40,
                        borderRadius: BorderRadius.circular(TsRadius.sm)),
                  ]),
                  BarChartGroupData(x: 1, barRods: [
                    BarChartRodData(
                        toY: borc, color: TsRenk.hata, width: 40,
                        borderRadius: BorderRadius.circular(TsRadius.sm)),
                  ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
