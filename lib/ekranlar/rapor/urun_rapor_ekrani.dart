// lib/ekranlar/rapor/urun_rapor_ekrani.dart
//
// ÜRÜN RAPORU — iki sekme: SATIŞ ve ALIM. Filtreler: tarih, ana grup, marka,
// cari, arama; gruplama: ürün / ana grup / marka / cari.
// Mobil: özet kartları + kart listesi. Masaüstü (>1100 px): tablo + alt şerit
// (bkz. masaustu/urun_rapor_masaustu_gorunum.dart).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../cekirdek/utils/para_utils.dart';
import '../../depolar/urun_rapor_deposu.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import 'masaustu/urun_rapor_masaustu_gorunum.dart';
import 'urun_rapor_filtre_cubugu.dart';
import 'urun_rapor_ortak.dart';

class UrunRaporEkrani extends ConsumerStatefulWidget {
  const UrunRaporEkrani({super.key});
  @override
  ConsumerState<UrunRaporEkrani> createState() => _UrunRaporEkraniState();
}

class _UrunRaporEkraniState extends ConsumerState<UrunRaporEkrani>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  UrunRaporTuru get _tur =>
      _tab.index == 0 ? UrunRaporTuru.satis : UrunRaporTuru.alim;

  Future<void> _excel() async {
    try {
      final sonuc = await ref.read(urunRaporSonucProvider(_tur).future);
      await urunRaporExcelAktar(
          tur: _tur, filtre: ref.read(urunRaporFiltreProvider), sonuc: sonuc);
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Excel hatası: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final masaustu = MediaQuery.sizeOf(context).width > 1100;
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'Ürün Raporu',
        gradyanli: true,
        aksiyonlar: [
          IconButton(
            icon: const Icon(Icons.table_view, color: Colors.white),
            tooltip: 'Excel',
            onPressed: _excel,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Yenile',
            onPressed: () {
              ref.invalidate(urunRaporSonucProvider);
              ref.invalidate(urunRaporMarkalarProvider);
              ref.invalidate(urunRaporAnaGruplarProvider);
              ref.invalidate(urunRaporCarilerProvider);
            },
          ),
        ],
        alt: TabBar(
          controller: _tab,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [Tab(text: 'Satış'), Tab(text: 'Alım')],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        // Masaüstünde fare ile sürükleme sekmeyi kaydırmasın (tablo seçimiyle çakışır).
        physics: masaustu ? const NeverScrollableScrollPhysics() : null,
        children: [
          for (final t in UrunRaporTuru.values)
            masaustu ? UrunRaporMasaustuGorunum(tur: t) : _MobilGovde(tur: t),
        ],
      ),
    );
  }
}

class _MobilGovde extends ConsumerWidget {
  final UrunRaporTuru tur;
  const _MobilGovde({required this.tur});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final satis = tur == UrunRaporTuru.satis;
    final async = ref.watch(urunRaporSonucProvider(tur));
    final filtre = ref.watch(urunRaporFiltreProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(urunRaporSonucProvider(tur)),
      child: ListView(
        padding: const EdgeInsets.all(TsBosluk.lg),
        children: [
          const UrunRaporFiltreCubugu(),
          const SizedBox(height: TsBosluk.lg),
          async.when(
            loading: () => const TsYukleniyor(iskelet: true),
            error: (e, _) => TsBosDurum(
                ikon: Icons.error_outline,
                baslik: 'Yüklenemedi: $e',
                renk: TsRenk.hata),
            data: (s) {
              if (s.satirlar.isEmpty) {
                return TsBosDurum(
                    ikon: Icons.inbox_outlined,
                    baslik: satis
                        ? 'Bu filtrelerle satış bulunamadı'
                        : 'Bu filtrelerle alım bulunamadı');
              }
              return Column(children: [
                Row(children: [
                  Expanded(
                    child: TsKart.istatistik(
                      baslik: satis ? 'Ciro (KDV dahil)' : 'Alım Tutarı',
                      deger: ParaUtils.formatla(s.toplamTutar),
                      ikon: Icon(satis
                          ? Icons.trending_up
                          : Icons.shopping_basket_outlined),
                      vurguRenk: satis ? TsRenk.basarili : TsRenk.primary,
                    ),
                  ),
                  const SizedBox(width: TsBosluk.md),
                  Expanded(
                    child: TsKart.istatistik(
                      baslik: 'Miktar',
                      deger: urunRaporMiktarYaz(s.toplamMiktar),
                      ikon: const Icon(Icons.inventory_2_outlined),
                      vurguRenk: TsRenk.uyari,
                    ),
                  ),
                ]),
                if (satis) ...[
                  const SizedBox(height: TsBosluk.md),
                  Row(children: [
                    Expanded(
                      child: TsKart.istatistik(
                        baslik: 'Maliyet',
                        deger: ParaUtils.formatla(s.toplamMaliyet),
                        ikon: const Icon(Icons.payments_outlined),
                        vurguRenk: TsRenk.hata,
                      ),
                    ),
                    const SizedBox(width: TsBosluk.md),
                    Expanded(
                      child: TsKart.istatistik(
                        baslik: 'Brüt Kâr',
                        deger: ParaUtils.formatla(s.toplamKar),
                        ikon: const Icon(Icons.savings_outlined),
                        vurguRenk:
                            s.toplamKar >= 0 ? TsRenk.basarili : TsRenk.hata,
                      ),
                    ),
                  ]),
                ],
                const SizedBox(height: TsBosluk.lg),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                      '${filtre.gruplama.etiket} bazlı · ${s.satirlar.length} kayıt · ${s.fisSayisi} fiş',
                      style: TsMetin.baslikM
                          .copyWith(color: TsRenk.metinIkincil(context))),
                ),
                const SizedBox(height: TsBosluk.sm),
                for (var i = 0; i < s.satirlar.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: TsBosluk.sm),
                    child:
                        _satirKarti(context, s.satirlar[i], i + 1, satis, filtre),
                  ),
              ]);
            },
          ),
        ],
      ),
    );
  }

  Widget _satirKarti(BuildContext context, UrunRaporSatir r, int sira,
      bool satis, UrunRaporFiltre filtre) {
    final altParcalar = <String>[
      if (r.alt.isNotEmpty) r.alt,
      '${urunRaporMiktarYaz(r.miktar)} birim',
      if (satis)
        'Kâr ${ParaUtils.formatla(r.kar)} (%${r.karMarji.toStringAsFixed(0)})',
    ];
    return TsKart.liste(
      ikon: Text('$sira', style: const TextStyle(fontWeight: FontWeight.w800)),
      baslik: r.ad,
      altBaslik: altParcalar.join(' · '),
      deger: ParaUtils.formatla(r.tutar),
      onTap: filtre.gruplama == UrunRaporGruplama.urun
          ? () => context.push('/urun/detay/${r.anahtar}')
          : null,
    );
  }
}
