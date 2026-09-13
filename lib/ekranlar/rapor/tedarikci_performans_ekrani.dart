// lib/ekranlar/rapor/tedarikci_performans_ekrani.dart
//
// FAZ 8 — Tedarikçi Performansı (erp_roadmap madde 18). Salt-okunur
// rapor: her tedarikçinin sipariş tamamlanma oranı, ortalama teslim
// süresi, ortalama sipariş tutarı.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../servisler/tedarikci_performans_servisi.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';

final _tedarikciPerformansProvider =
    FutureProvider.autoDispose<List<TedarikciPerformansSatiri>>(
        (ref) => TedarikciPerformansServisi().analizGetir());

class TedarikciPerformansEkrani extends ConsumerWidget {
  const TedarikciPerformansEkrani({super.key});

  TsBadgeTuru _sinifBadgeTuru(TedarikciPerformansSinifi s) => switch (s) {
        TedarikciPerformansSinifi.zayif => TsBadgeTuru.hata,
        TedarikciPerformansSinifi.normal => TsBadgeTuru.uyari,
        TedarikciPerformansSinifi.iyi => TsBadgeTuru.basarili,
        TedarikciPerformansSinifi.veriYok => TsBadgeTuru.notr,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_tedarikciPerformansProvider);
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'Tedarikçi Performansı',
        gradyanli: true,
        aksiyonlar: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () => ref.invalidate(_tedarikciPerformansProvider),
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
              ikon: Icons.local_shipping_outlined,
              baslik: 'Henüz tedarikçi siparişi yok',
              altyazi: 'Tedarikçi Siparişleri ekranından sipariş oluşturduğunuzda '
                  'burada performans özeti görünecek.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(_tedarikciPerformansProvider),
            child: ListView(
              padding: const EdgeInsets.all(TsBosluk.lg),
              children: <Widget>[
                ...satirlar.map((s) => Padding(
                        padding: const EdgeInsets.only(bottom: TsBosluk.sm),
                        child: TsKart(
                          child: Padding(
                            padding: const EdgeInsets.all(TsBosluk.md),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Expanded(
                                    child: Text(s.tedarikciAdi,
                                        style: TsMetin.baslikM.copyWith(
                                            color: TsRenk.metinBirincil(context))),
                                  ),
                                  TsBadge(
                                    metin: s.sinif.etiket,
                                    tur: _sinifBadgeTuru(s.sinif),
                                  ),
                                ]),
                                const SizedBox(height: TsBosluk.sm),
                                Wrap(spacing: TsBosluk.lg, runSpacing: TsBosluk.xs, children: [
                                  _bilgi(context, 'Toplam Sipariş', '${s.toplamSiparis}'),
                                  _bilgi(context, 'Teslim Alınan', '${s.teslimAlinan}'),
                                  _bilgi(context, 'İptal', '${s.iptalEdilen}'),
                                  _bilgi(context, 'Bekleyen', '${s.bekleyen}'),
                                  if (s.tamamlanmaOrani != null)
                                    _bilgi(context, 'Tamamlanma',
                                        '%${(s.tamamlanmaOrani! * 100).toStringAsFixed(0)}'),
                                  if (s.ortalamaTeslimSuresiGun != null)
                                    _bilgi(context, 'Ort. Teslim Süresi',
                                        '${s.ortalamaTeslimSuresiGun!.toStringAsFixed(1)} gün'),
                                  _bilgi(context, 'Ort. Sipariş Tutarı',
                                      ParaUtils.formatla(s.ortalamaSiparisTutari)),
                                ]),
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

  Widget _bilgi(BuildContext context, String etiket, String deger) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(etiket, style: TsMetin.kucuk.copyWith(color: TsRenk.metinIkincil(context))),
          Text(deger,
              style: TsMetin.govdeVurgu.copyWith(color: TsRenk.metinBirincil(context))),
        ],
      );
}
