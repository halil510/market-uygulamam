// lib/ekranlar/bayi/bayi_siparislerim_ekrani.dart
//
// Bayi Portalı MVP — bayinin KENDİ geçmiş/bekleyen siparişlerini
// listeler. Sorgu HER ZAMAN cari_id = widget.cariId ile filtrelenir —
// bir bayi başka bir bayinin siparişini asla göremez (bkz. dosya başı
// notu, bu ekranın var oluş amacı budur).
//
// 🔴 DÜZELTME (Madde 2 mimari denetimi — katman ihlali temizliği):
// önceden bu ekran veritabani.dart'ı doğrudan import edip db.query
// çağırıyordu (repository katmanını atlıyordu). Artık BekleyenSiparisDeposu
// üzerinden okuyor — 'durum: null' ile TÜM durumlar (bekliyor/onaylandi/
// iptal) tek listede gelsin diye depo metoduna nullable durum desteği
// eklendi (bkz. bekleyen_siparis_deposu.dart). Davranış değişmedi.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../depolar/bekleyen_siparis_deposu.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';

final _bayiSiparislerimProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, int>((ref, cariId) async {
  return BekleyenSiparisDeposu().bekleyenSiparisleriGetir(
    cariId: cariId,
    durum: null,
  );
});

class BayiSiparislerimEkrani extends ConsumerWidget {
  final int cariId;
  const BayiSiparislerimEkrani({super.key, required this.cariId});

  TsBadgeTuru _durumBadgeTuru(String durum) => switch (durum) {
        'onaylandi' => TsBadgeTuru.basarili,
        'iptal' => TsBadgeTuru.hata,
        'Hazırlanıyor' => TsBadgeTuru.bilgi,
        _ => TsBadgeTuru.uyari,
      };

  String _durumEtiket(String durum) => switch (durum) {
        'bekliyor' => 'Onay Bekliyor',
        'onaylandi' => 'Onaylandı',
        'iptal' => 'İptal Edildi',
        _ => durum,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_bayiSiparislerimProvider(cariId));
    final fmt = DateFormat('dd.MM.yyyy HH:mm');
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'Siparişlerim',
        gradyanli: true,
        aksiyonlar: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () => ref.invalidate(_bayiSiparislerimProvider(cariId)),
          ),
        ],
      ),
      body: async.when(
        loading: () => const TsYukleniyor(iskelet: true),
        error: (e, _) => TsBosDurum(
            ikon: Icons.error_outline, baslik: 'Yüklenemedi: $e', renk: TsRenk.hata),
        data: (siparisler) {
          if (siparisler.isEmpty) {
            return const TsBosDurum(
              ikon: Icons.receipt_long_outlined,
              baslik: 'Henüz siparişiniz yok',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(_bayiSiparislerimProvider(cariId)),
            child: ListView.separated(
              padding: const EdgeInsets.all(TsBosluk.lg),
              itemCount: siparisler.length,
              separatorBuilder: (_, __) => const SizedBox(height: TsBosluk.sm),
              itemBuilder: (_, i) {
                final s = siparisler[i];
                final durum = s['durum'] as String? ?? 'bekliyor';
                final tarih = DateTime.tryParse(s['tarih'] as String? ?? '');
                return TsKart.liste(
                  baslik: 'Sipariş #${s['id']}',
                  altBaslik: tarih != null ? fmt.format(tarih) : '',
                  deger: ParaUtils.formatla((s['genel_toplam'] as num?)?.toDouble() ?? 0),
                  etiketler: [
                    TsBadge(metin: _durumEtiket(durum), tur: _durumBadgeTuru(durum)),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}
