// lib/ekranlar/rapor/risk_merkezi_ekrani.dart
//
// FAZ 11 — Risk Merkezi (erp_roadmap madde 21). Kredi limiti tanımlı
// tüm müşterilerin risk kullanım %'sini tek listede gösterir. Salt
// okunur — hiçbir bakiye/limit değişikliği yapmaz.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../servisler/risk_merkezi_servisi.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';

final _riskMerkeziProvider =
    FutureProvider.autoDispose<List<RiskSatiri>>((ref) => RiskMerkeziServisi().analizGetir());

class RiskMerkeziEkrani extends ConsumerWidget {
  const RiskMerkeziEkrani({super.key});

  Color _seviyeRenk(RiskSeviyesi s) => switch (s) {
        RiskSeviyesi.kritik => TsRenk.hata,
        RiskSeviyesi.dikkat => TsRenk.uyari,
        RiskSeviyesi.iyi => TsRenk.basarili,
      };

  TsBadgeTuru _seviyeBadgeTuru(RiskSeviyesi s) => switch (s) {
        RiskSeviyesi.kritik => TsBadgeTuru.hata,
        RiskSeviyesi.dikkat => TsBadgeTuru.uyari,
        RiskSeviyesi.iyi => TsBadgeTuru.basarili,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_riskMerkeziProvider);
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'Risk Merkezi',
        gradyanli: true,
        aksiyonlar: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () => ref.invalidate(_riskMerkeziProvider),
          ),
        ],
      ),
      body: async.when(
        loading: () => const TsYukleniyor(iskelet: true),
        error: (e, _) => TsBosDurum(
            ikon: Icons.error_outline, baslik: 'Yüklenemedi: $e', renk: TsRenk.hata),
        data: (satirlar) {
          if (satirlar.isEmpty) {
            return const TsBosDurum(
              ikon: Icons.shield_outlined,
              baslik: 'Kredi limiti tanımlı müşteri yok',
              altyazi: 'Cari kartında "Kredi Limiti" alanı dolu olan müşteriler burada listelenir.',
            );
          }
          final kritik = satirlar.where((s) => s.seviye == RiskSeviyesi.kritik).length;
          final dikkat = satirlar.where((s) => s.seviye == RiskSeviyesi.dikkat).length;
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(_riskMerkeziProvider),
            child: ListView(
              padding: const EdgeInsets.all(TsBosluk.lg),
              children: [
                Row(children: [
                  Expanded(
                      child: TsKart.istatistik(
                          baslik: 'Kritik (≥%90)',
                          deger: '$kritik müşteri',
                          ikon: const Icon(Icons.warning_amber_outlined),
                          vurguRenk: TsRenk.hata)),
                  const SizedBox(width: TsBosluk.sm),
                  Expanded(
                      child: TsKart.istatistik(
                          baslik: 'Dikkat (≥%60)',
                          deger: '$dikkat müşteri',
                          ikon: const Icon(Icons.visibility_outlined),
                          vurguRenk: TsRenk.uyari)),
                ]),
                const SizedBox(height: TsBosluk.lg),
                ...satirlar.map((s) => Padding(
                      padding: const EdgeInsets.only(bottom: TsBosluk.sm),
                      child: TsKart(
                        onTap: () => context.push('/cari/detay/${s.cariId}'),
                        child: Padding(
                          padding: const EdgeInsets.all(TsBosluk.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Expanded(
                                  child: Text(s.unvan,
                                      style: TsMetin.baslikM
                                          .copyWith(color: TsRenk.metinBirincil(context))),
                                ),
                                TsBadge(
                                  metin: '${s.seviye.etiket} · %${(s.riskOrani * 100).clamp(0, 999).toStringAsFixed(0)}',
                                  tur: _seviyeBadgeTuru(s.seviye),
                                ),
                              ]),
                              const SizedBox(height: TsBosluk.xs),
                              Text(
                                'Bakiye: ${ParaUtils.formatla(s.bakiye)}  ·  '
                                'Limit: ${ParaUtils.formatla(s.limitTutari)}',
                                style: TsMetin.kucuk.copyWith(color: TsRenk.metinIkincil(context)),
                              ),
                              const SizedBox(height: TsBosluk.sm),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(
                                  value: s.riskOrani.clamp(0.0, 1.0),
                                  minHeight: 8,
                                  backgroundColor: TsRenk.ayirac(context),
                                  color: _seviyeRenk(s.seviye),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )),
                const SizedBox(height: TsBosluk.xxxl),
              ],
            ),
          );
        },
      ),
    );
  }
}
