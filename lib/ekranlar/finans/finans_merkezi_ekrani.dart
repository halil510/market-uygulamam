// lib/ekranlar/finans/finans_merkezi_ekrani.dart
//
// FİNANS MERKEZİ
// ------------------------------------------------------------------
// Ana ekrandaki "Finans" butonu önceden var olmayan bir rotaya
// (/finans) gidiyordu — bu ekran o eksikliği tamamlıyor. Banka, kredi
// kartı, borç takip, kasa ve giderler tek bir sade merkezden erişilir.
// Yeni bir modül eklemiyor — sadece var olan, çalışan ekranlara
// (banka_liste_ekrani, borc_dashboard_ekrani vb.) düzenli bir giriş
// kapısı sağlıyor.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../saglayicilar/riverpod/banka_provider.dart';
import '../../saglayicilar/riverpod/borc_provider.dart';import '../../cekirdek/utils/para_utils.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';

class FinansMerkeziEkrani extends ConsumerWidget {
  const FinansMerkeziEkrani({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final borcOzetAsync = ref.watch(borcOzetProvider);
    final bankaHesaplariAsync = ref.watch(bankaHesaplarProvider(null));

    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: const TsAppBar(baslik: 'Finans Merkezi', gradyanli: true),
      body: ListView(
        padding: const EdgeInsets.all(TsBosluk.lg),
        children: [
          // Özet kartları
          Row(children: [
            Expanded(
              child: borcOzetAsync.when(
                loading: () => const TsKart.istatistik(baslik: 'Kalan Borç', deger: '…'),
                error: (_, __) => const TsKart.istatistik(baslik: 'Kalan Borç', deger: '—'),
                data: (ozet) => TsKart.istatistik(
                  baslik: 'Kalan Borç',
                  deger: ParaUtils.formatla(ozet['kalan_borc'] ?? 0),
                  ikon: const Icon(Icons.money_off_outlined),
                  vurguRenk: TsRenk.hata,
                  onTap: () => context.push('/borc-dashboard'),
                ),
              ),
            ),
            const SizedBox(width: TsBosluk.md),
            Expanded(
              child: bankaHesaplariAsync.when(
                loading: () => const TsKart.istatistik(baslik: 'Banka Bakiyesi', deger: '…'),
                error: (_, __) => const TsKart.istatistik(baslik: 'Banka Bakiyesi', deger: '—'),
                data: (hesaplar) {
                  final toplam = hesaplar.fold<double>(0, (t, h) => t + h.bakiye);
                  return TsKart.istatistik(
                    baslik: 'Banka Bakiyesi',
                    deger: ParaUtils.formatla(toplam),
                    ikon: const Icon(Icons.account_balance_outlined),
                    vurguRenk: TsRenk.basarili,
                    onTap: () => context.push('/banka'),
                  );
                },
              ),
            ),
          ]),
          const SizedBox(height: TsBosluk.xl),

          Text('Modüller',
              style: TsMetin.baslikM.copyWith(color: TsRenk.metinIkincil(context))),
          const SizedBox(height: TsBosluk.sm),

          TsKart.liste(
            ikon: const Icon(Icons.account_balance),
            baslik: 'Banka Hesapları',
            altBaslik: 'Hesaplar, bakiyeler, hareketler',
            onTap: () => context.push('/banka'),
          ),
          const SizedBox(height: TsBosluk.sm),
          TsKart.liste(
            ikon: const Icon(Icons.credit_card),
            baslik: 'Kredi Kartları',
            altBaslik: 'Limit, ekstre, ödeme takibi',
            onTap: () => context.push('/kredi-karti'),
          ),
          const SizedBox(height: TsBosluk.sm),
          TsKart.liste(
            ikon: const Icon(Icons.payment),
            baslik: 'Borç Takip',
            altBaslik: 'Fatura, kira, vergi ve diğer borçlar',
            onTap: () => context.push('/borc-dashboard'),
          ),
          const SizedBox(height: TsBosluk.sm),
          TsKart.liste(
            ikon: const Icon(Icons.point_of_sale_outlined),
            baslik: 'Kasa',
            altBaslik: 'Nakit giriş/çıkış, vardiya kasası',
            onTap: () => context.push('/kasa'),
          ),
          const SizedBox(height: TsBosluk.sm),
          TsKart.liste(
            ikon: const Icon(Icons.money_off),
            baslik: 'Giderler',
            altBaslik: 'İşletme giderleri ve kategorileri',
            onTap: () => context.push('/gider'),
          ),
        ],
      ),
    );
  }
}
