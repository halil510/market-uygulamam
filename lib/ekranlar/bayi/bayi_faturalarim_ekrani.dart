// lib/ekranlar/bayi/bayi_faturalarim_ekrani.dart
//
// Bayi Portalı — "bayi kendi görebileceği ürün/fiyat/sipariş/fatura"
// roadmap maddesinin son parçası. Sorgu HER ZAMAN cariId ile
// filtrelenir (FaturaDeposu.listele zaten bunu destekliyor) — bir bayi
// başka bir cariye kesilmiş faturayı asla göremez.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../depolar/fatura_deposu.dart';
import '../../modeller/fatura_model.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import 'bayi_fatura_detay_ekrani.dart';

final _bayiFaturalarimProvider = FutureProvider.autoDispose
    .family<List<FaturaModel>, int>((ref, cariId) => FaturaDeposu().listele(cariId: cariId, limit: 100));

class BayiFaturalarimEkrani extends ConsumerWidget {
  final int cariId;
  const BayiFaturalarimEkrani({super.key, required this.cariId});

  TsBadgeTuru _odemeBadgeTuru(String durum) => switch (durum) {
        'odendi' => TsBadgeTuru.basarili,
        'kısmen' => TsBadgeTuru.uyari,
        _ => TsBadgeTuru.hata,
      };

  String _odemeEtiket(String durum) => switch (durum) {
        'odendi' => 'Ödendi',
        'kısmen' => 'Kısmen Ödendi',
        _ => 'Ödeme Bekliyor',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_bayiFaturalarimProvider(cariId));
    final fmt = DateFormat('dd.MM.yyyy');
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'Faturalarım',
        gradyanli: true,
        aksiyonlar: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () => ref.invalidate(_bayiFaturalarimProvider(cariId)),
          ),
        ],
      ),
      body: async.when(
        loading: () => const TsYukleniyor(iskelet: true),
        error: (e, _) => TsBosDurum(
            ikon: Icons.error_outline, baslik: 'Yüklenemedi: $e', renk: TsRenk.hata),
        data: (faturalar) {
          if (faturalar.isEmpty) {
            return const TsBosDurum(
              ikon: Icons.description_outlined,
              baslik: 'Henüz faturanız yok',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(_bayiFaturalarimProvider(cariId)),
            child: ListView.separated(
              padding: const EdgeInsets.all(TsBosluk.lg),
              itemCount: faturalar.length,
              separatorBuilder: (_, __) => const SizedBox(height: TsBosluk.sm),
              itemBuilder: (_, i) {
                final f = faturalar[i];
                return TsKart.liste(
                  baslik: f.faturaNo ?? 'Fatura #${f.id}',
                  altBaslik: '${fmt.format(f.tarih)}  ·  ${f.faturaTipi ?? ''}',
                  deger: ParaUtils.formatla(f.genelToplam),
                  etiketler: [
                    TsBadge(metin: _odemeEtiket(f.odemeDurumu), tur: _odemeBadgeTuru(f.odemeDurumu)),
                  ],
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => BayiFaturaDetayEkrani(fatura: f),
                  )),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
