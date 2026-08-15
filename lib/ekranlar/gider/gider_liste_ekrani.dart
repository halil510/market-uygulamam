// lib/ekranlar/gider/gider_liste_ekrani.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../cekirdek/utils/para_utils.dart';
import '../../depolar/gider_deposu.dart';
import '../../modeller/gider_model.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../saglayicilar/riverpod/auth_provider.dart';

final _giderListeProvider = FutureProvider.autoDispose<List<GiderModel>>((ref) {
  return GiderDeposu().tumunuGetir();
});

class GiderListeEkrani extends ConsumerWidget {
  const GiderListeEkrani({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_giderListeProvider);
    final fmt = DateFormat('dd.MM.yyyy');

    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'Giderler',
        gradyanli: true,
        geriTusu: false,
        aksiyonlar: [
          IconButton(icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: () => ref.invalidate(_giderListeProvider)),
        ],
      ),
      body: async.when(
        loading: () => const TsYukleniyor(iskelet: true),
        error: (e, _) => TsBosDurum(
          ikon: Icons.error_outline,
          baslik: 'Bir hata oluştu',
          altyazi: '$e',
          renk: TsRenk.hata,
          aksiyonMetni: 'Tekrar dene',
          aksiyon: () => ref.invalidate(_giderListeProvider),
        ),
        data: (giderler) {
          final toplam = giderler.fold(0.0, (s, g) => s + g.tutar);
          return Column(children: [
            if (giderler.isNotEmpty)
              Container(
                color: TsRenk.kart(context),
                padding: const EdgeInsets.symmetric(horizontal: TsBosluk.lg, vertical: TsBosluk.sm),
                child: Row(children: [
                  Text('${giderler.length} kayıt',
                      style: TsMetin.kucuk.copyWith(color: TsRenk.metinIkincil(context))),
                  const Spacer(),
                  Text('Toplam: ${ParaUtils.formatla(toplam)}',
                      style: TsMetin.govdeVurgu.copyWith(color: TsRenk.hata)),
                ]),
              ),
            Expanded(
              child: TsListe<GiderModel>(
                ogeler: giderler,
                yenile: () => ref.refresh(_giderListeProvider.future),
                bosBaslik: 'Gider kaydı yok',
                bosIkon: Icons.money_off_outlined,
                kartOlustur: (ctx, g, i) {
                  final silYetkisiVar = ref.watch(authProvider.select((s) => s.isMudur));
                  return Dismissible(
                  key: ValueKey('g_${g.id}'),
                  direction: silYetkisiVar ? DismissDirection.endToStart : DismissDirection.none,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: TsBosluk.xl),
                    decoration: BoxDecoration(color: TsRenk.hata, borderRadius: BorderRadius.circular(TsRadius.lg)),
                    child: const Icon(Icons.delete_outline, color: Colors.white),
                  ),
                  confirmDismiss: (_) async {
                    final onay = await showDialog<bool>(
                      context: ctx,
                      builder: (c) => AlertDialog(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TsRadius.lg)),
                        title: const Text('Gider Sil'),
                        content: Text('${g.aciklama} silinecek?'),
                        actions: [
                          TsButon(tur: TsButonTuru.metin, metin: 'İptal', onPressed: () => Navigator.pop(c, false)),
                          TsButon.tehlike(metin: 'Sil', onPressed: () => Navigator.pop(c, true)),
                        ],
                      ),
                    );
                    if (onay == true) {
                      await GiderDeposu().sil(g.id!);
                      ref.invalidate(_giderListeProvider);
                    }
                    return false;
                  },
                  child: TsKart.liste(
                    baslik: g.aciklama ?? '—',
                    // 🔴 DÜZELTME: `kategoriAdi ?? 'Genel'` HİÇ ÇALIŞMIYORDU.
                    // GiderModel.kategoriAdi non-nullable ve fromMap'te
                    // `?? ''` ile boş string'e düşüyor — yani null hiç
                    // olmuyor, `?? 'Genel'` yedeği devreye girmiyordu.
                    // Kategorisiz giderler listede "12.03.2026 · " diye
                    // yarım görünüyordu.
                    altBaslik: '${fmt.format(g.tarih)} · '
                        '${g.kategoriAdi.isEmpty ? 'Genel' : g.kategoriAdi}',
                    ikon: const Icon(Icons.money_off_outlined),
                    deger: ParaUtils.formatla(g.tutar),
                    // 🔴 DÜZELTME (derin analizde bulundu): Bir gideri
                    // düzenlemenin hiçbir yolu yoktu — kullanıcı yanlış
                    // girdiği bir gideri sadece silip yeniden ekleyebiliyordu.
                    onTap: () => context.push('/gider/ekle', extra: g)
                        .then((_) => ref.invalidate(_giderListeProvider)),
                  ),
                );
                },
              ),
            ),
          ]);
        },
      ),
      floatingActionButton: TsYetkili(child: FloatingActionButton.extended(
        elevation: 6,
        backgroundColor: TsRenk.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Gider Ekle'),
        onPressed: () => context.push('/gider/ekle').then((_) => ref.invalidate(_giderListeProvider)),
      )),
    );
  }
}
