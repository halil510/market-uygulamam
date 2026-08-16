// lib/ekranlar/banka/banka_liste_ekrani.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../depolar/banka_deposu.dart';
import '../../modeller/banka_model.dart';
import '../../saglayicilar/riverpod/banka_provider.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';

class BankaListeEkrani extends ConsumerWidget {
  const BankaListeEkrani({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bankalarAsync = ref.watch(bankalarProvider);

    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'Bankalar',
        gradyanli: true,
        aksiyonlar: [
          TsYetkili(child: IconButton(icon: const Icon(Icons.add, color: Colors.white), tooltip: 'Banka Ekle', onPressed: () async {
            final eklendi = await context.push<bool>('/banka/ekle');
            if (eklendi == true) ref.invalidate(bankalarProvider);
          })),
          IconButton(icon: const Icon(Icons.refresh, color: Colors.white), onPressed: () => ref.invalidate(bankalarProvider)),
        ],
      ),
      body: bankalarAsync.when(
        loading: () => const TsYukleniyor(iskelet: true),
        error: (e, _) => TsBosDurum(
          ikon: Icons.error_outline,
          baslik: 'Bir hata oluştu',
          altyazi: '$e',
          renk: TsRenk.hata,
          aksiyonMetni: 'Tekrar dene',
          aksiyon: () => ref.invalidate(bankalarProvider),
        ),
        data: (bankalar) => TsListe<BankaModel>(
          ogeler: bankalar,
          aramaMetniAl: (b) => b.ad,
          yenile: () async => ref.invalidate(bankalarProvider),
          bosBaslik: 'Henüz banka eklenmemiş',
          bosIkon: Icons.business_outlined,
          kartOlustur: (context, banka, i) => TsKart.liste(
            baslik: banka.ad,
            altBaslik: banka.kod,
            ikon: const Icon(Icons.business),
            sagAksiyon: TsYetkili(child: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(icon: const Icon(Icons.edit_outlined, size: 20), onPressed: () async {
              final guncellendi = await context.push<bool>('/banka/ekle', extra: banka);
              if (guncellendi == true) ref.invalidate(bankalarProvider);
            }),
              IconButton(icon: const Icon(Icons.delete_outline, size: 20, color: TsRenk.hata), onPressed: () => _sil(context, ref, banka)),
            ])),
            onTap: () => context.push('/banka/detay/${banka.id}'),
          ),
        ),
      ),
    );
  }

  Future<void> _sil(BuildContext context, WidgetRef ref, BankaModel banka) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TsRadius.lg)),
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: Colors.red),
          SizedBox(width: 8),
          Text('Bankayı Sil'),
        ]),
        content: Text('${banka.ad} bankasını silmek istediğinize emin misiniz?'),
        actions: [
          TsButon(tur: TsButonTuru.metin, metin: 'İptal', onPressed: () => Navigator.pop(ctx, false)),
          TsButon.tehlike(metin: 'Sil', onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    if (onay != true) return;
    try {
      await BankaDeposu().sil(banka.id!);
      ref.invalidate(bankalarProvider);
      if (context.mounted) BildirimServisi.basari(context, 'Banka silindi');
    } catch (e) {
      if (context.mounted) BildirimServisi.hata(context, 'Hata: $e');
    }
  }
}
