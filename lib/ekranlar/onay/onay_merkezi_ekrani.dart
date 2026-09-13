// lib/ekranlar/onay/onay_merkezi_ekrani.dart
//
// FAZ 9 — Onay Merkezi (bildirim tipi). Eşik aşan riskli işlemlerin
// (yüksek iskonto/iade, risk aşımı, kasa çıkışı, fiyat değişimi, stok
// düzeltme, yüksek gider, borç silme) SONRADAN incelenebildiği liste.
// İşlemler burada oluşmadan ÖNCE tamamlanmış olur — bu ekran salt
// görüntüleme + "görüldü" işaretleme yapar, hiçbir işlemi geri almaz.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../servisler/onay_merkezi_servisi.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';

final _onayTalepleriProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>(
        (ref) => OnayMerkeziServisi().listele());

class OnayMerkeziEkrani extends ConsumerWidget {
  const OnayMerkeziEkrani({super.key});

  TsBadgeTuru _turBadgeTuru(String kod) => switch (kod) {
        'risk_asimi' || 'borc_silme' => TsBadgeTuru.hata,
        'yuksek_iskonto' || 'yuksek_iade' || 'kasa_cikisi' => TsBadgeTuru.uyari,
        _ => TsBadgeTuru.bilgi,
      };

  String _turEtiket(String kod) => OnayTuru.values
      .firstWhere((t) => t.kod == kod, orElse: () => OnayTuru.yuksekIskonto)
      .etiket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_onayTalepleriProvider);
    final fmt = DateFormat('dd.MM.yyyy HH:mm');
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'Onay Merkezi',
        gradyanli: true,
        aksiyonlar: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () => ref.invalidate(_onayTalepleriProvider),
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
              ikon: Icons.verified_outlined,
              baslik: 'Bekleyen onay kaydı yok',
              altyazi: 'Eşik aşan riskli işlemler (yüksek iskonto/iade, risk '
                  'aşımı, kasa çıkışı vb.) burada listelenir.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(_onayTalepleriProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(TsBosluk.lg),
              itemCount: satirlar.length,
              separatorBuilder: (_, __) => const SizedBox(height: TsBosluk.sm),
              itemBuilder: (_, i) {
                final s = satirlar[i];
                final gorulduMu = (s['goruldu'] as int? ?? 0) == 1;
                final tur = s['tur'] as String? ?? '';
                final tutar = (s['tutar'] as num?)?.toDouble();
                final tarih = DateTime.tryParse(s['tarih'] as String? ?? '');
                return Opacity(
                  opacity: gorulduMu ? 0.55 : 1,
                  child: TsKart.liste(
                    baslik: _turEtiket(tur),
                    altBaslik: [
                      if (s['aciklama'] != null) s['aciklama'] as String,
                      if (s['kullanici_adi'] != null) s['kullanici_adi'] as String,
                      if (tarih != null) fmt.format(tarih),
                    ].join(' · '),
                    deger: tutar != null ? ParaUtils.formatla(tutar) : null,
                    etiketler: [
                      TsBadge(metin: _turEtiket(tur), tur: _turBadgeTuru(tur)),
                      if (gorulduMu) const TsBadge(metin: 'Görüldü'),
                    ],
                    sagAksiyon: gorulduMu
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.check_circle_outline),
                            tooltip: 'Görüldü işaretle',
                            onPressed: () async {
                              await OnayMerkeziServisi().goruldeIsaretle(s['id'] as int);
                              ref.invalidate(_onayTalepleriProvider);
                            },
                          ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
