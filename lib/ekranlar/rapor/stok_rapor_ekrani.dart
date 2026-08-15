// lib/ekranlar/rapor/stok_rapor_ekrani.dart
//
// STOK RAPORU — dashboard'da vaat edilen ama hiç yapılmamış rapor.
// Envanter değeri, kritik/stoksuz ürün sayısı, en değerli ürünler.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../depolar/urun_deposu.dart';
import '../../modeller/urun_model.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';

final _stokIstatistikProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) => UrunDeposu().istatistikler());
final _kritikStoklarProvider =
    FutureProvider.autoDispose<List<UrunModel>>((ref) => UrunDeposu().kritikStoklar(limit: 20));

class StokRaporEkrani extends ConsumerWidget {
  const StokRaporEkrani({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final istatistikAsync = ref.watch(_stokIstatistikProvider);
    final kritikAsync = ref.watch(_kritikStoklarProvider);

    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'Stok Raporu',
        gradyanli: true,
        aksiyonlar: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () {
              ref.invalidate(_stokIstatistikProvider);
              ref.invalidate(_kritikStoklarProvider);
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(_stokIstatistikProvider);
          ref.invalidate(_kritikStoklarProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(TsBosluk.lg),
          children: [
            istatistikAsync.when(
              loading: () => const TsYukleniyor(iskelet: true),
              error: (e, _) => TsBosDurum(
                  ikon: Icons.error_outline, baslik: 'Yüklenemedi: $e', renk: TsRenk.hata),
              data: (ist) {
                final stokDegeri = (ist['stok_degeri'] as num?)?.toDouble() ?? 0;
                return Column(children: [
                  Row(children: [
                    Expanded(
                      child: TsKart.istatistik(
                        baslik: 'Toplam Stok Değeri (Alış)',
                        deger: ParaUtils.formatla(stokDegeri),
                        ikon: const Icon(Icons.inventory_2_outlined),
                        vurguRenk: TsRenk.primary,
                      ),
                    ),
                  ]),
                  const SizedBox(height: TsBosluk.md),
                  Row(children: [
                    Expanded(
                      child: TsKart.istatistik(
                        baslik: 'Aktif Ürün',
                        deger: '${ist['aktif'] ?? 0}',
                        ikon: const Icon(Icons.check_circle_outline),
                        vurguRenk: TsRenk.basarili,
                      ),
                    ),
                    const SizedBox(width: TsBosluk.md),
                    Expanded(
                      child: TsKart.istatistik(
                        baslik: 'Kritik Stok',
                        deger: '${ist['kritik'] ?? 0}',
                        ikon: const Icon(Icons.warning_amber_outlined),
                        vurguRenk: TsRenk.uyari,
                        onTap: () => context.push('/stok'),
                      ),
                    ),
                    const SizedBox(width: TsBosluk.md),
                    Expanded(
                      child: TsKart.istatistik(
                        baslik: 'Stoksuz',
                        deger: '${ist['stoksuz'] ?? 0}',
                        ikon: const Icon(Icons.remove_shopping_cart_outlined),
                        vurguRenk: TsRenk.hata,
                      ),
                    ),
                  ]),
                ]);
              },
            ),
            const SizedBox(height: TsBosluk.xl),
            istatistikAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (ist) => _StokDagilimGrafigi(ist: ist),
            ),
            const SizedBox(height: TsBosluk.xl),
            Text('Kritik Seviyedeki Ürünler (en düşükten)',
                style: TsMetin.baslikM.copyWith(color: TsRenk.metinIkincil(context))),
            const SizedBox(height: TsBosluk.sm),
            kritikAsync.when(
              loading: () => const TsYukleniyor(iskelet: true),
              error: (e, _) => TsBosDurum(
                  ikon: Icons.error_outline, baslik: 'Yüklenemedi: $e', renk: TsRenk.hata),
              data: (urunler) {
                if (urunler.isEmpty) {
                  return const TsBosDurum(
                      ikon: Icons.check_circle_outline,
                      baslik: 'Kritik seviyede ürün yok',
                      renk: TsRenk.basarili);
                }
                return Column(
                  children: urunler
                      .map((u) => Padding(
                            padding: const EdgeInsets.only(bottom: TsBosluk.sm),
                            child: TsKart.liste(
                              ikon: const Icon(Icons.inventory_2_outlined),
                              baslik: u.urunAdi,
                              altBaslik: u.barkod ?? u.kod ?? '',
                              deger: '${u.stok.toStringAsFixed(0)} ${u.birimAdi}',
                              onTap: () => context.push('/urun/detay/${u.id}'),
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

/// Stok sağlığı dağılımı — Sağlıklı / Kritik / Stoksuz oranını tek
/// bakışta gösteren donut grafik. Yeni bir sorgu gerektirmiyor,
/// zaten yüklenmiş olan istatistikler()'in üzerine kuruluyor.
class _StokDagilimGrafigi extends StatelessWidget {
  final Map<String, dynamic> ist;
  const _StokDagilimGrafigi({required this.ist});

  @override
  Widget build(BuildContext context) {
    final aktif = (ist['aktif'] as int?) ?? 0;
    final kritik = (ist['kritik'] as int?) ?? 0;
    final stoksuz = (ist['stoksuz'] as int?) ?? 0;
    // "Sağlıklı" = aktif olup kritik/stoksuz eşiğinin altına düşmemiş ürünler.
    final saglikli = (aktif - kritik - stoksuz).clamp(0, aktif);
    final toplam = saglikli + kritik + stoksuz;

    if (toplam == 0) {
      return TsKart(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: TsBosluk.lg),
            child: Text('Grafik için yeterli ürün verisi yok',
                style: TsMetin.govde.copyWith(color: TsRenk.metinIkincil(context))),
          ),
        ),
      );
    }

    final dilimler = [
      (etiket: 'Sağlıklı', deger: saglikli, renk: TsRenk.basarili),
      (etiket: 'Kritik', deger: kritik, renk: TsRenk.uyari),
      (etiket: 'Stoksuz', deger: stoksuz, renk: TsRenk.hata),
    ].where((d) => d.deger > 0).toList();

    return TsKart(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Stok Sağlığı Dağılımı',
              style: TsMetin.baslikM.copyWith(color: TsRenk.metinBirincil(context))),
          const SizedBox(height: TsBosluk.lg),
          Row(
            children: [
              SizedBox(
                width: 120,
                height: 120,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 34,
                        sections: dilimler
                            .map((d) => PieChartSectionData(
                                  value: d.deger.toDouble(),
                                  color: d.renk,
                                  radius: 26,
                                  showTitle: false,
                                ))
                            .toList(),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('$toplam',
                            style: TsMetin.baslikL.copyWith(color: TsRenk.metinBirincil(context))),
                        Text('ürün',
                            style: TsMetin.kucuk.copyWith(color: TsRenk.metinIkincil(context))),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: TsBosluk.xl),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: dilimler.map((d) {
                    final yuzde = toplam == 0 ? 0 : (d.deger * 100 / toplam).round();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: TsBosluk.sm),
                      child: Row(
                        children: [
                          Container(
                            width: 10, height: 10,
                            decoration: BoxDecoration(color: d.renk, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: TsBosluk.sm),
                          Expanded(
                            child: Text(d.etiket,
                                style: TsMetin.govde.copyWith(color: TsRenk.metinBirincil(context))),
                          ),
                          Text('${d.deger} · %$yuzde',
                              style: TsMetin.govdeVurgu.copyWith(color: d.renk)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
