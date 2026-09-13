// lib/ekranlar/rapor/stok_devir_analizi_ekrani.dart
//
// FAZ 8 — Stok Devir Analizi (erp_roadmap madde 16). Salt-okunur rapor:
// hangi ürünler hızlı/yavaş dönüyor, hangileri HİÇ satılmadan stokta
// bekliyor (hareketsiz/ölü stok adayı).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../servisler/stok_devir_analizi_servisi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';

final _stokDevirProvider = FutureProvider.autoDispose
    .family<List<DevirSatiri>, int>((ref, gunSayisi) =>
        StokDevirAnaliziServisi().analizGetir(gunSayisi: gunSayisi));

class StokDevirAnaliziEkrani extends ConsumerStatefulWidget {
  const StokDevirAnaliziEkrani({super.key});
  @override
  ConsumerState<StokDevirAnaliziEkrani> createState() => _StokDevirAnaliziEkraniState();
}

class _StokDevirAnaliziEkraniState extends ConsumerState<StokDevirAnaliziEkrani> {
  int _gunSayisi = 90;
  static const _secenekler = [30, 90, 365];

  TsBadgeTuru _sinifBadgeTuru(DevirSinifi s) => switch (s) {
        DevirSinifi.hareketsiz => TsBadgeTuru.hata,
        DevirSinifi.yavas => TsBadgeTuru.uyari,
        DevirSinifi.normal => TsBadgeTuru.bilgi,
        DevirSinifi.hizli => TsBadgeTuru.basarili,
      };

  String _miktarStr(double m) =>
      m == m.roundToDouble() ? m.toStringAsFixed(0) : m.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_stokDevirProvider(_gunSayisi));
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'Stok Devir Analizi',
        gradyanli: true,
        aksiyonlar: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () => ref.invalidate(_stokDevirProvider(_gunSayisi)),
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
                  ikon: Icons.inventory_2_outlined,
                  baslik: 'Stokta ürün yok',
                  altyazi: 'Stoğu 0\'dan büyük aktif ürün bulunamadı.',
                );
              }
              final hareketsiz =
                  satirlar.where((s) => s.sinif == DevirSinifi.hareketsiz).length;
              return RefreshIndicator(
                onRefresh: () async => ref.invalidate(_stokDevirProvider(_gunSayisi)),
                child: ListView(
                  padding: const EdgeInsets.all(TsBosluk.lg),
                  children: [
                    if (hareketsiz > 0)
                      TsKart.istatistik(
                        baslik: 'Hareketsiz Ürün (bu dönemde hiç satılmadı)',
                        deger: '$hareketsiz ürün',
                        ikon: const Icon(Icons.warning_amber_outlined),
                        vurguRenk: TsRenk.hata,
                      ),
                    const SizedBox(height: TsBosluk.lg),
                    Text(
                      'Not: Devir hızı, dönem içindeki satılan miktarın MEVCUT '
                      'stoğa oranıdır (geçmiş stok değişimi izlenmediği için '
                      'ortalama stok yerine yaklaşık değer kullanılır).',
                      style: TsMetin.kucuk.copyWith(color: TsRenk.metinIkincil(context)),
                    ),
                    const SizedBox(height: TsBosluk.md),
                    ...satirlar.map((s) => Padding(
                          padding: const EdgeInsets.only(bottom: TsBosluk.sm),
                          child: TsKart.liste(
                            baslik: s.urunAdi,
                            altBaslik: 'Satılan: ${_miktarStr(s.satilanMiktar)}  ·  '
                                'Stok: ${_miktarStr(s.mevcutStok)}',
                            deger: s.devirHizi == null
                                ? '∞'
                                : '${s.devirHizi!.toStringAsFixed(1)}x',
                            etiketler: [
                              TsBadge(
                                metin: s.sinif.etiket,
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
