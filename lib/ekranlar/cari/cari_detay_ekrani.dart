// lib/ekranlar/cari/cari_detay_ekrani.dart
import 'package:flutter/foundation.dart';
import 'fis_detay_ekrani.dart';
import 'package:flutter/material.dart';
import '../../widgetlar/ortak/app_widgetlar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../saglayicilar/riverpod/cari_provider.dart';
import '../../modeller/cari_model.dart';
import '../../modeller/cari_hareket_model.dart';
import '../../modeller/fatura_model.dart';
import '../../depolar/satis_deposu.dart';
import '../../servisler/faturalandirma_servisi.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../depolar/cari_deposu.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';

class CariDetayEkrani extends ConsumerWidget {
  final int cariId;
  const CariDetayEkrani({super.key, required this.cariId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(cariDetayProvider(cariId));
    return async.when(
      loading: () => const Scaffold(body: Center(child: const AppYukleniyor())),
      error: (e, _) => Scaffold(
        appBar: TsAppBar(
        baslik: 'Hata',
        gradyanli: false,
      ),
        body: BosEkran(ikon: Icons.inbox_outlined, baslik: '$e')),
      data: (cari) {
        if (cari == null) return Scaffold(
          appBar: TsAppBar(
        baslik: 'Bulunamadı',
        gradyanli: false,
      ),
          body: const BosEkran(ikon: Icons.inbox_outlined, baslik: 'Cari bulunamadı'));
        return _CariDetayIcerik(cari: cari);
      },
    );
  }
}

class _CariDetayIcerik extends ConsumerStatefulWidget {
  final CariModel cari;
  const _CariDetayIcerik({required this.cari});
  @override
  ConsumerState<_CariDetayIcerik> createState() => _CariDetayIcerikState();
}

class _CariDetayIcerikState extends ConsumerState<_CariDetayIcerik>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<dynamic> _hareketler = [];
  bool _yukl = false;
  final _fmt = DateFormat('dd.MM.yyyy HH:mm');

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _hareketYukle();
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _hareketYukle() async {
    if (!mounted) return;
    setState(() => _yukl = true);
    try {
      final h = await CariDeposu().hareketleriniGetir(widget.cari.id!);
      if (mounted) setState(() { _hareketler = h; _yukl = false; });
    } catch (e) {
      if (kDebugMode) debugPrint('CariDetay hareketYukle hata: $e');
      if (mounted) setState(() => _yukl = false);
    }
  }

  Future<void> _hareketFaturalandir(CariHareketModel h) async {
    if (h.fisId == null) return;
    setState(() => _yukl = true);
    try {
      final satis = await SatisDeposu().idileGetir(h.fisId!);
      if (satis == null || satis.kalemler == null || satis.kalemler!.isEmpty) {
        if (mounted) BildirimServisi.hata(context, 'Satış kalemleri bulunamadı.');
        return;
      }

      // Bu satış için daha önce fatura kesildiyse tekrar oluşturma
      final mevcutId = await FaturalandirmaServisi.mevcutFaturaId(satisId: h.fisId);
      if (mevcutId != null) {
        if (!mounted) return;
        BildirimServisi.basari(context, 'Bu satış için zaten bir fatura mevcut, ona yönlendiriliyorsunuz.');
        context.push('/fatura/detay/$mevcutId');
        return;
      }

      final kontrol = await FaturalandirmaServisi.kontrolEt(widget.cari.id!);
      if (kontrol == null) return;

      if (!kontrol.hazir) {
        if (!mounted) return;
        final git = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Text('Eksik Cari Bilgisi'),
            ]),
            content: Column(mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("${widget.cari.unvan} için fatura kesilebilmesi için "
                  "aşağıdaki bilgiler eksik:"),
              const SizedBox(height: 10),
              ...kontrol.eksikAlanlar.map((e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(children: [
                      const Icon(Icons.circle, size: 6, color: Colors.orange),
                      const SizedBox(width: 8),
                      Text(e),
                    ]),
                  )),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cari Düzenle')),
            ],
          ),
        );
        if (git == true && mounted) {
          await context.push('/cari/ekle', extra: widget.cari);
        }
        return;
      }

      final detaylar = satis.kalemler!.map((k) => FaturaDetayModel(
        urunId: k.urunId, urunAdi: k.urunAdi, barkod: k.barkod,
        miktar: k.miktar, birimFiyat: k.birimFiyat,
        iskontoOrani: k.iskontoOran, iskontoTutari: k.iskontoTutar,
        kdvOrani: k.kdvOran, kdvTutari: k.kdvTutar,
        araToplam: k.miktar * k.birimFiyat, toplamTutar: k.toplamTutar,
      )).toList();

      final yeniId = await FaturalandirmaServisi.faturaOlustur(
        kontrol: kontrol, kalemler: detaylar, faturaTipi: 'Satis',
        satisId: satis.id, tarih: satis.tarih, odenenTutar: satis.odenenTutar,
      );

      if (!mounted) return;
      BildirimServisi.basari(context, 'Fatura oluşturuldu');
      context.push('/fatura/detay/$yeniId');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Faturalandırma hatası: $e');
    } finally {
      if (mounted) setState(() => _yukl = false);
    }
  }

  Color get _bakiyeRenk {
    final c = widget.cari;
    if (c.bakiye == 0) return context.textSecondary;
    final musteri = c.cariTipi.contains('Müşteri');
    if (musteri) return c.bakiye > 0 ? Colors.green.shade700 : Colors.blue.shade700;
    return c.bakiye < 0 ? Colors.red.shade700 : Colors.blue.shade700;
  }

  String get _bakiyeEtiket {
    final c = widget.cari;
    if (c.bakiye == 0) return 'Dengede';
    final musteri = c.cariTipi.contains('Müşteri');
    if (musteri) return c.bakiye > 0 ? 'Alacağımız' : 'Fazla Ödedi';
    return c.bakiye < 0 ? 'Borcumuz' : 'Fazla Ödedik';
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.cari;
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslikWidget: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(child: Text(c.unvan, style: const TextStyle(fontSize: 15), overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 6),
          _eFaturaRozeti(c),
        ]),
        aksiyonlar: [
          if (c.cariTipi.contains('Müşteri'))
            IconButton(
              icon: const Icon(Icons.stars_outlined, color: Colors.amber),
              tooltip: 'Puanlar',
              onPressed: () => context.push('/cari/puan/${c.id}',
                  extra: {'unvan': c.unvan}),
            ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Düzenle',
            onPressed: () => context.push('/cari/ekle', extra: c).then((_) {
              ref.invalidate(cariDetayProvider(c.id!));
              ref.read(carilerProvider.notifier).yukle();
            }),
          ),
        ],
        alt: TabBar(
          controller: _tab,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [Tab(text: 'Bilgi'), Tab(text: 'Hareketler')],
        ),
      ),
      body: TabBarView(controller: _tab, children: [
        _bilgiTab(context, c),
        _hareketTab(),
      ]),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'hareket',
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            child: const Icon(Icons.receipt_long_outlined),
            onPressed: () => context.push('/cari/hareket/${c.id}'),
            tooltip: 'Hareket Ekle',
          ),
          const SizedBox(height: 8),
          FloatingActionButton.extended(
        elevation: 6,
            heroTag: 'tahsilat',
            backgroundColor: AppRenkler.primary,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.payments_outlined),
            label: const Text('Tahsilat/Ödeme'),
            onPressed: () async {
              await context.push('/cari/tahsilat/${c.id}');
              ref.invalidate(cariDetayProvider(c.id!));
              ref.read(carilerProvider.notifier).yukle();
              _hareketYukle();
            },
          ),
        ],
      ),
    );
  }

  /// VKN (10 hane) → e-Fatura mükellefi (kurumsal), TC (11 hane) → e-Arşiv (bireysel).
  /// GİB canlı sorgusu yapılmaz; format bazlı tahmindir, tooltip'te belirtilir.
  Widget _eFaturaRozeti(CariModel c) {
    final vkn = c.vergiNo?.trim();
    final tc  = c.tcKimlik?.trim();
    String etiket; IconData ikon; Color renk;
    if (vkn != null && vkn.length == 10) {
      etiket = 'e-Fatura'; ikon = Icons.verified_outlined; renk = const Color(0xFF2E7D32);
    } else if (tc != null && tc.length == 11) {
      etiket = 'e-Arşiv'; ikon = Icons.description_outlined; renk = const Color(0xFF1565C0);
    } else {
      return const SizedBox.shrink();
    }
    return Tooltip(
      message: vkn != null && vkn.length == 10
          ? 'VKN (10 hane) — Kurumsal mükellef. Fatura kesilirken e-Fatura olarak '
            'düzenlenir (GİB üzerinden gerçek mükellefiyet teyidi yapılmaz).'
          : 'TC Kimlik No (11 hane) — Bireysel müşteri. Fatura kesilirken '
            'e-Arşiv Fatura olarak düzenlenir.',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: Color.fromARGB(40, renk.red, renk.green, renk.blue),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Color.fromARGB(90, renk.red, renk.green, renk.blue)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(ikon, size: 13, color: renk),
          const SizedBox(width: 3),
          Text(etiket, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: renk)),
        ]),
      ),
    );
  }

  Widget _bilgiTab(BuildContext ctx, CariModel c) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      // Bakiye kartı
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [_bakiyeRenk, Color.fromARGB(178, _bakiyeRenk.red, _bakiyeRenk.green, _bakiyeRenk.blue)],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(
              color: Color.fromARGB(76, _bakiyeRenk.red, _bakiyeRenk.green, _bakiyeRenk.blue), blurRadius: 12, offset: const Offset(0, 6))],
        ),
        child: Column(children: [
          Text(_bakiyeEtiket, style: const TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 4),
          Text(ParaUtils.formatla(c.bakiye.abs()),
              style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900)),
        ]),
      ),
      const SizedBox(height: 16),
      _Kart(children: [
        _Satir('Cari Tipi', c.cariTipi),
        if (c.cariKodu != null) _Satir('Cari Kodu', c.cariKodu!),
        if (c.telefon != null) _Satir('Telefon', c.telefon!),
        if (c.email != null) _Satir('E-Posta', c.email!),

        if (c.vergiNo != null) _Satir('Vergi No', c.vergiNo!),
        if (c.tcKimlik != null) _Satir('TC Kimlik No', c.tcKimlik!),
        if (c.vergiDairesi != null) _Satir('Vergi Dairesi', c.vergiDairesi!),
        if (c.limitTutari != null && c.limitTutari! > 0)
          _Satir('Kredi Limiti', ParaUtils.formatla(c.limitTutari!)),
      ]),
      const SizedBox(height: 80),
    ],
  );

  Widget _hareketTab() {
    if (_yukl) return const Center(child: const AppYukleniyor());
    if (_hareketler.isEmpty) return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.receipt_long_outlined, size: 48, color: context.textSecondary),
        const SizedBox(height: 8),
        Text('Hareket yok', style: TextStyle(color: context.textSecondary)),
      ]));
    return RefreshIndicator(
      onRefresh: _hareketYukle,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _hareketler.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (_, i) {
          final h = _hareketler[i];
          final borc = (h.borc ?? 0.0) as double;
          final alacak = (h.alacak ?? 0.0) as double;
          final giris = alacak > 0;
          final satisMi = h.fisTipi == 'Satış' && h.fisId != null;

          // 🔴 DÜZELTME (kullanıcı bulgusu — "hangi ürün olduğu belli
          // mi artık"): Toptan satış / bekleyen sipariş onayı / masa
          // satışı hareketlerine dokununca HİÇBİR ŞEY olmuyordu —
          // `onTap` sadece BİREBİR 'Satış' fisTipi'nde tetikleniyordu.
          // Kullanıcı hangi ürünlerin satıldığını göremiyordu.
          //
          // 'Satış' fisTipi'nin mevcut davranışına (dokununca doğrudan
          // faturalandırma akışını başlatması) DOKUNULMADI — bu turun
          // kapsamı sadece eksik olan görüntüleme yolu.
          final detayGorulebilirMi = h.fisId != null && !satisMi && (
              h.fisTipi == 'Toptan Satış' ||
              h.fisTipi == 'Toptan Satış (Sipariş)' ||
              h.fisTipi == 'Masa Satış');
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: TsRenk.kart(context), borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: Color(0x0A000000), blurRadius: 4)]),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: satisMi
                  ? () => _hareketFaturalandir(h)
                  : detayGorulebilirMi
                      ? () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => FisDetayEkrani(
                            fisId: h.fisId!,
                            fisTipi: h.fisTipi,
                            cariUnvan: widget.cari.unvan,
                          ),
                        ))
                      : null,
              child: Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: (giris ? Colors.green : Colors.red).withAlpha(26),
                  shape: BoxShape.circle),
                child: Icon(
                  giris ? Icons.add : Icons.remove,
                  color: giris ? Colors.green : Colors.red, size: 18)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(h.fisTipi ?? '—', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                if (h.aciklama != null)
                  Text(h.aciklama!, style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context))),
                Text(_fmt.format(h.tarih), style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context))),
              ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                if (borc > 0) Text('+${ParaUtils.formatla(borc)}',
                    style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w700, fontSize: 13)),
                if (alacak > 0) Text('+${ParaUtils.formatla(alacak)}',
                    style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w700, fontSize: 13)),
              ]),
              if (satisMi) ...[
                const SizedBox(width: 6),
                Icon(Icons.receipt_long_outlined, size: 18, color: TsRenk.metinIkincil(context)),
              ],
            ]),
            ),
          );
        },
      ),
    );
  }
}

class _Kart extends StatelessWidget {
  final List<Widget> children;
  const _Kart({required this.children});
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: TsRenk.kart(context), borderRadius: BorderRadius.circular(14),
      boxShadow: [BoxShadow(color: Color(0x0D000000), blurRadius: 6)]),
    child: Column(children: children),
  );
}

class _Satir extends StatelessWidget {
  final String etiket, deger;
  const _Satir(this.etiket, this.deger);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.borderColor))),
    child: Row(children: [
      Text(etiket, style: TextStyle(fontSize: 13, color: context.textSecondary)),
      const Spacer(),
      Flexible(child: Text(deger,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          textAlign: TextAlign.right)),
    ]),
  );
}
