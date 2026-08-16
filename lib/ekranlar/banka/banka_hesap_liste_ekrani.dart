// lib/ekranlar/banka/banka_hesap_liste_ekrani.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../modeller/banka_hesap_model.dart';
import '../../saglayicilar/riverpod/banka_provider.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';

class BankaHesapListeEkrani extends ConsumerWidget {
  final int bankaId;
  const BankaHesapListeEkrani({super.key, required this.bankaId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hesaplarAsync = ref.watch(bankaHesaplarProvider(bankaId));

    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'Banka Hesapları',
        gradyanli: true,
        aksiyonlar: [
          TsYetkili(child: IconButton(icon: const Icon(Icons.add, color: Colors.white), tooltip: 'Hesap Ekle', onPressed: () async {
            final eklendi = await context.push<bool>('/banka/hesap-ekle/$bankaId');
            if (eklendi == true) ref.invalidate(bankaHesaplarProvider(bankaId));
          })),
        ],
      ),
      body: hesaplarAsync.when(
        loading: () => const TsYukleniyor(iskelet: true),
        error: (e, _) => TsBosDurum(
          ikon: Icons.error_outline,
          baslik: 'Bir hata oluştu',
          altyazi: '$e',
          renk: TsRenk.hata,
          aksiyonMetni: 'Tekrar dene',
          aksiyon: () => ref.invalidate(bankaHesaplarProvider(bankaId)),
        ),
        data: (hesaplar) => TsListe<BankaHesapModel>(
          ogeler: hesaplar,
          aramaMetniAl: (h) => h.hesapAdi,
          yenile: () async => ref.invalidate(bankaHesaplarProvider(bankaId)),
          bosBaslik: 'Hesap bulunamadı',
          bosIkon: Icons.account_balance_outlined,
          kartOlustur: (context, hesap, i) => TsKart.liste(
            baslik: hesap.hesapAdi,
            altBaslik: 'No: ${hesap.hesapNo}${hesap.iban != null ? ' · IBAN: ${hesap.iban}' : ''}',
            ikon: const Icon(Icons.account_balance),
            deger: '${hesap.bakiye.toStringAsFixed(2)} ${hesap.paraBirimi}',
            onTap: () => context.push('/banka-hareket', extra: {'hesapId': hesap.id}),
          ),
        ),
      ),
    );
  }
}
