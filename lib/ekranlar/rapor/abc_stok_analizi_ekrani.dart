// lib/ekranlar/rapor/abc_stok_analizi_ekrani.dart
//
// FAZ 8 — ABC Stok Analizi (erp_roadmap madde 15). Salt-okunur rapor:
// hangi ürünler ciroyu taşıyor (A), hangileri orta (B), hangileri çok
// sayıda ama düşük cirolu (C). Hiçbir fiyat/stok kararını otomatik
// uygulamaz.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../servisler/abc_stok_analizi_servisi.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';

final _abcAnaliziProvider = FutureProvider.autoDispose
    .family<List<AbcUrunSatiri>, int>((ref, gunSayisi) =>
        AbcStokAnaliziServisi().analizGetir(gunSayisi: gunSayisi));

class AbcStokAnaliziEkrani extends ConsumerStatefulWidget {
  const AbcStokAnaliziEkrani({super.key});
  @override
  ConsumerState<AbcStokAnaliziEkrani> createState() => _AbcStokAnaliziEkraniState();
}

class _AbcStokAnaliziEkraniState extends ConsumerState<AbcStokAnaliziEkrani> {
  int _gunSayisi = 90;
  static const _secenekler = [30, 90, 365];

  TsBadgeTuru _sinifBadgeTuru(AbcSinifi s) => switch (s) {
        AbcSinifi.a => TsBadgeTuru.basarili,
        AbcSinifi.b => TsBadgeTuru.uyari,
        AbcSinifi.c => TsBadgeTuru.notr,
      };

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_abcAnaliziProvider(_gunSayisi));
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'ABC Stok Analizi',
        gradyanli: true,
        aksiyonlar: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () => ref.invalidate(_abcAnaliziProvider(_gunSayisi)),
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: TsBosluk.lg, vertical: TsBosluk.sm),
          child: Row(
            children: _secenekler.map((g) {
              final secili = g == _gunSayisi;
              return Padding(
                padding: const EdgeInsets.only(right: TsBosluk.sm),
                child: ChoiceChip(
                  label: Text('Son $g gün'),
                  selected: secili,
                  onSelected: (_) => setState(() => _gunSayisi = g),
                ),
              );
            }).toList(),
          ),
        ),
        Expanded(
          child: async.when(
            loading: () => const TsYukleniyor(iskelet: true),
            error: (e, _) => TsBosDurum(
                ikon: Icons.error_outline, baslik: 'Yüklenemedi: $e', renk: TsRenk.hata),
            data: (satirlar) {
              if (satirlar.isEmpty) {
                return const TsBosDurum(
                  ikon: Icons.bar_chart_outlined,
                  baslik: 'Bu dönemde satış yok',
                  altyazi: 'Seçilen dönemde hiç satış kaydı bulunamadı.',
                );
              }
              final aSayisi = satirlar.where((s) => s.sinif == AbcSinifi.a).length;
              final bSayisi = satirlar.where((s) => s.sinif == AbcSinifi.b).length;
              final cSayisi = satirlar.where((s) => s.sinif == AbcSinifi.c).length;
              return RefreshIndicator(
                onRefresh: () async => ref.invalidate(_abcAnaliziProvider(_gunSayisi)),
                child: ListView(
                  padding: const EdgeInsets.all(TsBosluk.lg),
                  children: [
                    Row(children: [
                      Expanded(
                          child: TsKart.istatistik(
                              baslik: 'A Sınıfı (%0-80 ciro)',
                              deger: '$aSayisi ürün',
                              ikon: const Icon(Icons.star_outline),
                              vurguRenk: TsRenk.basarili)),
                      const SizedBox(width: TsBosluk.sm),
                      Expanded(
                          child: TsKart.istatistik(
                              baslik: 'B Sınıfı (%80-95)',
                              deger: '$bSayisi ürün',
                              ikon: const Icon(Icons.star_half_outlined),
                              vurguRenk: TsRenk.uyari)),
                      const SizedBox(width: TsBosluk.sm),
                      Expanded(
                          child: TsKart.istatistik(
                              baslik: 'C Sınıfı (%95-100)',
                              deger: '$cSayisi ürün',
                              ikon: const Icon(Icons.star_border_outlined),
                              vurguRenk: TsRenk.notr)),
                    ]),
                    const SizedBox(height: TsBosluk.lg),
                    ...satirlar.map((s) => Padding(
                          padding: const EdgeInsets.only(bottom: TsBosluk.sm),
                          child: TsKart.liste(
                            baslik: s.urunAdi,
                            altBaslik:
                                'Kümülatif %${s.kumulatifYuzde.toStringAsFixed(1)}',
                            deger: ParaUtils.formatla(s.toplamTutar),
                            etiketler: [
                              TsBadge(
                                metin: '${s.sinif.etiket} Sınıfı',
                                tur: _sinifBadgeTuru(s.sinif),
                              ),
                            ],
                          ),
                        )),
                    const SizedBox(height: TsBosluk.xxxl),
                  ],
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}
