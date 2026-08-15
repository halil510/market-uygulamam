// lib/ekranlar/satis/satis_detay_ekrani.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../saglayicilar/riverpod/satis_provider.dart';
import '../../depolar/satis_deposu.dart';
import '../../modeller/satis_model.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../servisler/yazdirma_servisi.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../modeller/fatura_model.dart';
import '../../servisler/faturalandirma_servisi.dart';

class SatisDetayEkrani extends ConsumerWidget {
  final int satisId;
  const SatisDetayEkrani({super.key, required this.satisId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(satisDetayiProvider(satisId));
    return async.when(
      loading: () => const Scaffold(body: const TsYukleniyor()),
      error: (e, _) => Scaffold(
        appBar: TsAppBar(
        baslik: 'Hata',
        gradyanli: false,
      ),
        body: Center(child: Text('$e'))),
      data: (satis) {
        if (satis == null) return Scaffold(
          appBar: TsAppBar(
        baslik: 'Bulunamadı',
        gradyanli: false,
      ),
          body: const Center(child: Text('Satış bulunamadı')));
        return _SatisDetayIcerik(satis: satis, ref: ref);
      },
    );
  }
}

class _SatisDetayIcerik extends ConsumerStatefulWidget {
  final SatisModel satis;
  final WidgetRef ref;
  const _SatisDetayIcerik({required this.satis, required this.ref});
  @override
  ConsumerState<_SatisDetayIcerik> createState() => _SatisDetayIcerikState();
}

class _SatisDetayIcerikState extends ConsumerState<_SatisDetayIcerik> {
  String _kisaFisNo(String? fisNo) {
    if (fisNo == null) return 'Satış Detayı';
    if (fisNo.length == 16) {
      return '${fisNo.substring(0, 3)}-${(int.tryParse(fisNo.substring(7)) ?? 0).toString().padLeft(6, '0')}';
    }
    return fisNo;
  }

  bool _islemYapiliyor = false;
  final _fmt = DateFormat('dd.MM.yyyy HH:mm');

  Future<void> _iptal() async {
    final onay = await showDialog<String>(context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Satış İptal'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Fiş: ${widget.satis.fisNo}', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            TextField(controller: ctrl,
              decoration: const InputDecoration(
                labelText: 'İptal nedeni', border: OutlineInputBorder())),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
            FilledButton(
              style: FilledButton.styleFrom(foregroundColor: Colors.white,
          backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, ctrl.text.isEmpty ? 'İptal' : ctrl.text),
              child: const Text('İptal Et')),
          ],
        );
      });
    if (onay == null || !mounted) return;
    setState(() => _islemYapiliyor = true);
    try {
      // 🔴🔴 KRİTİK DÜZELTME (derin analizde bulundu): Bu, uygulamadaki
      // ANA "Satış İptal Et" düğmesi — önceden SatisDeposu().satisIptal()
      // çağırıyordu. Bu fonksiyon SADECE satışın 'iptal' bayrağını
      // işaretler; STOK GERİ YÜKLENMEZ, MÜŞTERİNİN CARİ BORCU GERİ
      // ALINMAZ, KASA HAREKETİ GERİ ALINMAZ. SatisDeposu.sil() ise TAM
      // OLARAK bunları yapan kapsamlı geri alma fonksiyonu — ve zaten
      // parametre olarak bir 'neden' de kabul ediyor (iptal_nedeni
      // olarak kaydediliyor). Bu düzeltilmeden önce, HER satış iptali
      // stoğu yapay olarak düşük, müşteri bakiyesini yanlış ve kasayı
      // fazla gösteren bir duruma yol açıyordu.
      await SatisDeposu().sil(widget.satis.id!, neden: onay);
      ref.invalidate(satisDetayiProvider(widget.satis.id!));
      ref.read(satislarProvider.notifier).yukle();
      if (mounted) { BildirimServisi.basari(context, 'Satış iptal edildi'); context.pop(); }
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Hata: $e');
    } finally {
      if (mounted) setState(() => _islemYapiliyor = false);
    }
  }

  Future<void> _faturalandir() async {
    final s = widget.satis;
    if (s.cariId == null) {
      BildirimServisi.uyari(context,
          "Bu satışta cari seçilmemiş. Faturalandırma için satışın bir Cari'ye bağlı olması gerekir.");
      return;
    }
    setState(() => _islemYapiliyor = true);
    try {
      // Bu satış için daha önce fatura kesildiyse tekrar oluşturma
      final mevcut = await FaturalandirmaServisi.mevcutFaturaId(satisId: s.id);
      if (mevcut != null) {
        if (!mounted) return;
        BildirimServisi.bilgi(context, 'Bu satış için zaten bir fatura mevcut, ona yönlendiriliyorsunuz.');
        context.push('/fatura/detay/$mevcut');
        return;
      }

      final kontrol = await FaturalandirmaServisi.kontrolEt(s.cariId!);
      if (kontrol == null) {
        if (mounted) BildirimServisi.hata(context, 'Cari bulunamadı.');
        return;
      }

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
              Text("${kontrol.cari.unvan.isEmpty ? 'Bu cari' : kontrol.cari.unvan} için "
                  "fatura kesilebilmesi için aşağıdaki bilgiler eksik:"),
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
          await context.push('/cari/ekle', extra: kontrol.cari);
        }
        return;
      }

      final detaylar = s.kalemler!.map((k) => FaturaDetayModel(
        urunId: k.urunId,
        urunAdi: k.urunAdi,
        barkod: k.barkod,
        miktar: k.miktar,
        birimFiyat: k.birimFiyat,
        iskontoOrani: k.iskontoOran,
        iskontoTutari: k.iskontoTutar,
        kdvOrani: k.kdvOran,
        kdvTutari: k.kdvTutar,
        araToplam: k.miktar * k.birimFiyat,
        toplamTutar: k.toplamTutar,
      )).toList();

      final yeniId = await FaturalandirmaServisi.faturaOlustur(
        kontrol: kontrol,
        kalemler: detaylar,
        faturaTipi: 'Satis',
        satisId: s.id,
        tarih: s.tarih,
        odenenTutar: s.odenenTutar,
      );

      if (!mounted) return;
      BildirimServisi.basari(context, 'Fatura oluşturuldu');
      context.push('/fatura/detay/$yeniId');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Faturalandırma hatası: $e');
    } finally {
      if (mounted) setState(() => _islemYapiliyor = false);
    }
  }

  Future<void> _yazdir() async {
    try {
      await YazdirmaServisi().fisYazdir(widget.satis);
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Yazıcı hatası: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.satis;
    final iptal = s.iptal;
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslikWidget: Text(ParaUtils.kisaFisNo(s.fisNo)),
        aksiyonlar: [
          if (!iptal) ...[
            IconButton(icon: const Icon(Icons.print_outlined, color: Colors.white), onPressed: _yazdir, tooltip: 'Yazdır'),
            IconButton(
              icon: _islemYapiliyor
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.receipt_long_outlined, color: Colors.white),
              onPressed: _islemYapiliyor ? null : _faturalandir,
              tooltip: 'Faturalandır'),
            IconButton(
              icon: _islemYapiliyor
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.cancel_outlined, color: Colors.white),
              onPressed: _islemYapiliyor ? null : _iptal,
              tooltip: 'İptal Et'),
          ],
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // İptal uyarısı
        if (iptal)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.red.shade50, borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.shade300)),
            child: Row(children: [
              const Icon(Icons.cancel_outlined, color: Colors.red),
              const SizedBox(width: 8),
              Expanded(child: Text('Bu satış iptal edilmiştir${s.iptalNedeni != null ? ": ${s.iptalNedeni}" : ""}',
                  style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600))),
            ]),
          ),

        // Özet kart
        _Kart(children: [
          _Satir('Fiş No',        s.fisNo ?? '—'),
          _Satir('Tarih',         _fmt.format(s.tarih)),
          _Satir('Ödeme Yöntemi', s.odemeYontemi ?? '—'),
          if (s.cariAdi != null) _Satir('Müşteri', s.cariAdi!),
          if (s.kasiyerId != null) _Satir('Kasiyer', s.kasiyerId.toString()),
        ]),

        const SizedBox(height: 12),

        // Kalemler
        if (s.kalemler != null && s.kalemler!.isNotEmpty) ...[
          const Text('Ürünler', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: TsRenk.kart(context), borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Color(0x0D000000), blurRadius: 6)]),
            child: Column(children: [
              ...s.kalemler!.map((k) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: TsRenk.ayirac(context)))),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(k.urunAdi, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                    Text('${k.miktar.toStringAsFixed(k.miktar.truncateToDouble() == k.miktar ? 0 : 2)} × ${ParaUtils.formatla(k.birimFiyat)}',
                        style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context))),
                  ])),
                  Text(ParaUtils.formatla(k.toplamTutar),
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                ]),
              )),
            ]),
          ),
        ],

        const SizedBox(height: 12),

        // Toplamlar
        _Kart(children: [
          if ((s.iskonto ?? 0) > 0)
            _Satir('İskonto', '-${ParaUtils.formatla(s.iskonto ?? 0)}',
                renk: Colors.orange.shade700),
          _Satir('Toplam', ParaUtils.formatla(s.genelToplam), bold: true),
          if ((s.odenenTutar ?? 0) > 0 && (s.odenenTutar ?? 0) != s.genelToplam)
            _Satir('Ödenen', ParaUtils.formatla(s.odenenTutar!)),
        ]),
        const SizedBox(height: 80),
      ]),
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
  final bool bold;
  final Color? renk;
  const _Satir(this.etiket, this.deger, {this.bold = false, this.renk});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: TsRenk.ayirac(context)))),
    child: Row(children: [
      Text(etiket, style: TextStyle(fontSize: 13, color: TsRenk.metinIkincil(context))),
      const Spacer(),
      Text(deger, style: TextStyle(fontSize: 13,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          color: renk)),
    ]),
  );
}
