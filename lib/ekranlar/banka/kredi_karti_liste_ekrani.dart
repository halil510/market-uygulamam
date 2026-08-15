// lib/ekranlar/banka/kredi_karti_liste_ekrani.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../modeller/kredi_karti_model.dart';
import '../../saglayicilar/riverpod/banka_provider.dart';
import '../../saglayicilar/riverpod/borc_provider.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';

class KrediKartiListeEkrani extends ConsumerWidget {
  final int? bankaId;
  const KrediKartiListeEkrani({super.key, this.bankaId});

  String _formatTarih(DateTime t) =>
      '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}.${t.year}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kartlarAsync = ref.watch(krediKartlariProvider(bankaId));

    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'Kredi Kartları',
        gradyanli: true,
        aksiyonlar: [
          TsYetkili(child: IconButton(icon: const Icon(Icons.add, color: Colors.white), tooltip: 'Kart Ekle', onPressed: () async {
            final eklendi = await context.push<bool>('/kredi-karti/ekle');
            if (eklendi == true) {
              ref.invalidate(krediKartlariProvider(bankaId));
              // Borç Dashboard kendi ayrı önbelleğini kullanıyor — kredi
              // kartı eklendiğinde orası da yenilenmezse eklenen kart
              // Borç Dashboard'da görünmüyordu.
              ref.invalidate(tumKrediKartlariProvider);
              ref.invalidate(borcDashboardProvider);
            }
          })),
        ],
      ),
      body: kartlarAsync.when(
        loading: () => const TsYukleniyor(iskelet: true),
        error: (e, _) => TsBosDurum(
          ikon: Icons.error_outline,
          baslik: 'Bir hata oluştu',
          altyazi: '$e',
          renk: TsRenk.hata,
          aksiyonMetni: 'Tekrar dene',
          aksiyon: () => ref.invalidate(krediKartlariProvider(bankaId)),
        ),
        data: (kartlar) => TsListe<KrediKartiModel>(
          ogeler: kartlar,
          aramaMetniAl: (k) => k.kartAdi,
          yenile: () async => ref.invalidate(krediKartlariProvider(bankaId)),
          bosBaslik: 'Kredi kartı bulunamadı',
          bosIkon: Icons.credit_card_outlined,
          kartOlustur: (context, kart, i) {
            final limitDoluluk = kart.kartLimit > 0 ? (kart.kullanilanLimit / kart.kartLimit * 100) : 0.0;
            final altSatirlar = [
              'Limit: ${kart.kartLimit.toStringAsFixed(2)} TL',
              if (limitDoluluk > 0) 'Kullanım: %${limitDoluluk.toStringAsFixed(0)}',
              if (kart.sonOdemeTarihi != null) 'Son Ödeme: ${_formatTarih(kart.sonOdemeTarihi!)}',
            ];
            return TsKart.liste(
              baslik: kart.kartAdi,
              altBaslik: altSatirlar.join(' · '),
              ikon: const Icon(Icons.credit_card),
              etiketler: limitDoluluk > 80
                  ? [const TsBadge(metin: 'LİMİT DOLUYOR', tur: TsBadgeTuru.hata)]
                  : null,
              onTap: () => context.push('/kredi-karti/detay/${kart.id}'),
            );
          },
        ),
      ),
    );
  }
}
