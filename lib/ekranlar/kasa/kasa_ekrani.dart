// lib/ekranlar/kasa/kasa_ekrani.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../depolar/kasa_deposu.dart';
import '../../modeller/kasa_hareket_model.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';

final _kasaBakiyeProvider = FutureProvider.autoDispose<double>(
    (_) => KasaDeposu().guncelBakiye());

final _kasaHareketlerProvider = FutureProvider.autoDispose<List<KasaHareketModel>>((ref) {
  final depo = KasaDeposu();
  final now  = DateTime.now();
  return depo.hareketleriniGetir(
      baslangic: DateTime(now.year, now.month, now.day),
      bitis:     DateTime(now.year, now.month, now.day, 23, 59, 59),
      limit:     100);
});

class KasaEkrani extends ConsumerWidget {
  const KasaEkrani({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bakiyeA   = ref.watch(_kasaBakiyeProvider);
    final hareketA  = ref.watch(_kasaHareketlerProvider);
    final fmt       = DateFormat('HH:mm');

    void yenile() {
      ref.invalidate(_kasaBakiyeProvider);
      ref.invalidate(_kasaHareketlerProvider);
    }

    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'Kasa',
        gradyanli: true,
        geriTusu: false,
        aksiyonlar: [
          IconButton(
            icon: const Icon(Icons.bar_chart_outlined, color: Colors.white),
            tooltip: 'Kasa Raporu',
            onPressed: () => context.push('/kasa/rapor')),
          IconButton(
            icon: const Icon(Icons.history, color: Colors.white),
            tooltip: 'Tüm Hareketler',
            onPressed: () => context.push('/kasa/hareket')),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: yenile),
        ],
      ),
      body: Column(children: [
        // Bakiye kartı
        bakiyeA.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, __) => Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Bakiye yüklenemedi: $e',
                style: TextStyle(color: TsRenk.hata, fontSize: 12)),
          ),
          data: (bakiye) => Container(
            width: double.infinity,
            margin: const EdgeInsets.all(TsBosluk.lg),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                colors: bakiye >= 0
                    ? [Colors.green.shade700, Colors.green.shade500]
                    : [Colors.red.shade700, Colors.red.shade500],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
            ),
            child: Column(children: [
              const Text('Güncel Kasa Bakiyesi',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 6),
              Text(ParaUtils.formatla(bakiye),
                  style: const TextStyle(color: Colors.white, fontSize: 32,
                      fontWeight: FontWeight.w900)),
            ]),
          ),
        ),

        // Bugünkü hareketler başlık
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: TsBosluk.lg),
          child: Row(children: [
            Text('Bugünkü Hareketler',
                style: TsMetin.baslikM.copyWith(color: TsRenk.metinBirincil(context))),
            const Spacer(),
            hareketA.whenOrNull(data: (h) {
              // KENDİ HATAM: tutar HER ZAMAN pozitif kaydediliyor (bkz.
              // kasa_deposu.dart) — bu yüzden `tutar > 0`/`tutar < 0`
              // kontrolü yanlıştı (giriş toplamı = tüm işlemler, çıkış
              // toplamı = her zaman 0 olurdu). hareketTipi'ne göre
              // düzeltildi.
              final giris = h.where((x) => KasaHareketModel.girisMi(x.hareketTipi))
                  .fold(0.0, (s, x) => s + x.tutar);
              final cikis = h.where((x) => !KasaHareketModel.girisMi(x.hareketTipi))
                  .fold(0.0, (s, x) => s + x.tutar);
              return Row(children: [
                Icon(Icons.arrow_upward, size: 12, color: TsRenk.basarili),
                Text(ParaUtils.formatla(giris),
                    style: TextStyle(fontSize: 12, color: TsRenk.basarili)),
                const SizedBox(width: 8),
                Icon(Icons.arrow_downward, size: 12, color: TsRenk.hata),
                Text(ParaUtils.formatla(cikis),
                    style: TextStyle(fontSize: 12, color: TsRenk.hata)),
              ]);
            }) ?? const SizedBox.shrink(),
          ]),
        ),
        const SizedBox(height: TsBosluk.sm),

        // Hareketler listesi
        Expanded(
          child: hareketA.when(
            loading: () => const TsYukleniyor(iskelet: true),
            error: (e, _) => TsBosDurum(
                ikon: Icons.error_outline, baslik: 'Hareketler yüklenemedi',
                altyazi: '$e', renk: TsRenk.hata),
            data: (hareketler) {
              if (hareketler.isEmpty) {
                return const TsBosDurum(
                  ikon: Icons.inbox_outlined,
                  baslik: 'Bugün hareket yok',
                );
              }
              return RefreshIndicator(
                onRefresh: () async => yenile(),
                child: ListView.separated(
                  padding: const EdgeInsets.all(TsBosluk.lg),
                  itemCount: hareketler.length,
                  separatorBuilder: (_, __) => const SizedBox(height: TsBosluk.sm),
                  itemBuilder: (_, i) {
                    final h = hareketler[i];
                    final giris = KasaHareketModel.girisMi(h.hareketTipi);
                    final renk = giris ? TsRenk.basarili : TsRenk.hata;
                    return TsKart(
                      padding: const EdgeInsets.all(12),
                      child: Row(children: [
                        Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(color: TsRenk.zemin(renk), shape: BoxShape.circle),
                          child: Icon(giris ? Icons.add : Icons.remove, color: renk, size: 18),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(h.aciklama ?? h.hareketTipi,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text(fmt.format(h.tarih),
                              style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context))),
                        ])),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text(
                            '${giris ? '+' : '-'}${ParaUtils.formatla(h.tutar.abs())}',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: renk)),
                          Text(ParaUtils.formatla(h.bakiyeSonrasi ?? 0),
                              style: TextStyle(fontSize: 10, color: TsRenk.metinIkincil(context))),
                        ]),
                      ]),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}


