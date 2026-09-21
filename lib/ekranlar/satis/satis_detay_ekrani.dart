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
import '../../cekirdek/utils/hata_utils.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../modeller/fatura_model.dart';
import '../../servisler/faturalandirma_servisi.dart';
import '../../depolar/fatura_deposu.dart';
import '../../widgetlar/ortak/onay_dialog.dart';

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
  bool _islemYapiliyor = false;
  final _fmt = DateFormat('dd.MM.yyyy HH:mm');

  // Kullanıcı bulgusu (2026-09-20): Karma ödemede "Ödeme Yöntemi" alanı
  // sadece düz "Karma" yazıyordu, hangi yöntemden ne kadar ödendiği
  // görünmüyordu. bkz. SatisDeposu.odemeDagilimiGetir.
  List<Map<String, dynamic>>? _odemeDagilimi;

  @override
  void initState() {
    super.initState();
    if (widget.satis.odemeYontemi == 'Karma' && widget.satis.id != null) {
      SatisDeposu().odemeDagilimiGetir(widget.satis.id!).then((v) {
        if (mounted) setState(() => _odemeDagilimi = v);
      });
    }
  }

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

    // 🔴🔴 DÜZELTME (Madde 23 — Fatura/E-Belge denetimi, 2026-09-20):
    // ÖNCEDEN satış iptali, bu satışa ait GİB'e GÖNDERİLMİŞ/ONAYLANMIŞ
    // bir e-Fatura olup olmadığını hiç kontrol etmiyordu — satış sessizce
    // iptal edilir, resmi olarak onaylanmış e-Fatura ise hiç
    // dokunulmadan, artık iptal edilmiş bir satışa referans veren
    // "öksüz" bir belge olarak kalırdı. e-Fatura'nın kendisini iptal
    // etmek AYRI ve resmi bir GİB işlemi (bkz. fatura_detay_ekrani.dart
    // _gibIptalEt) — burada OTOMATİK yapılmaz, sadece kullanıcı AÇIKÇA
    // uyarılır ve isterse faturayı önce kendisi halletsin diye durur.
    final faturaId = await FaturalandirmaServisi.mevcutFaturaId(satisId: widget.satis.id);
    if (faturaId != null && mounted) {
      final fatura = await FaturaDeposu().idileGetir(faturaId);
      final gibeGonderildi = fatura != null &&
          (fatura.eFaturaDurum == 'gonderildi' || fatura.eFaturaDurum == 'onaylandi');
      if (gibeGonderildi && mounted) {
        final devamEt = await OnayDialog.goster(context,
            baslik: 'Bu Satışın Onaylı Bir e-Faturası Var',
            icerik:
                'Bu satış için GİB\'e gönderilmiş ve onaylanmış bir e-Fatura '
                '(${fatura.faturaNo ?? ''}) mevcut. Satışı iptal etmek bu '
                'faturayı OTOMATİK OLARAK iptal ETMEZ — resmi GİB iptali '
                'ayrıca fatura ekranından yapılmalıdır. Satışı yine de iptal '
                'etmek istiyor musunuz?',
            onayYazi: 'Yine de İptal Et', onayRengi: Colors.red,
            ikon: Icons.warning_amber_rounded);
        if (!devamEt || !mounted) return;
      }
    }

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
      if (mounted) BildirimServisi.hata(context, kullaniciyaHataMetni(e));
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

      // 🔴 DÜZELTME (Madde 21 — GİB/fatura araToplam bulgusu, 2026-09-16):
      // araToplam ÖNCEDEN k.miktar*k.birimFiyat (KDV DAHİL, brüt) idi —
      // oysa FaturaDetayModel'in kendi iç mantığı (bkz.
      // faturalandirma_servisi.dart'ın varsayılan iskonto dalı, gib_servisi
      // .dart'taki LineExtensionAmount/TaxableAmount) bu alanın KDV HARİÇ
      // (matrah) olmasını varsayıyor. Yanlış (brüt) değer basılı faturada
      // "Ara Toplam + KDV ≠ Genel Toplam" gibi tutarsız bir görünüme YOL
      // AÇIYORDU ve e-Fatura XML'inde satır bazlı LineExtensionAmount
      // toplamı, LegalMonetaryTotal'daki (doğru) matrah ile UYUŞMUYORDU —
      // GİB şematron doğrulamasında reddedilme riski. k.toplamTutar (KDV
      // dahil, doğru) ve k.kdvTutar (İÇİNDEN doğru ayıklanmış KDV payı)
      // ARTIK doğru olduğundan, net araToplam bu ikisinden türetiliyor.
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
        araToplam: k.toplamTutar - k.kdvTutar,
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
      if (mounted) BildirimServisi.hata(context, 'Faturalandırma hatası: ${kullaniciyaHataMetni(e)}');
    } finally {
      if (mounted) setState(() => _islemYapiliyor = false);
    }
  }

  Future<void> _yazdir() async {
    try {
      await YazdirmaServisi().fisYazdir(widget.satis);
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Yazıcı hatası: ${kullaniciyaHataMetni(e)}');
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
              color: TsRenk.zemin(TsRenk.hata), borderRadius: BorderRadius.circular(12),
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
          // Karma ödemede artık düz "Karma" yazısı yerine (veya onunla
          // birlikte) yöntem+tutar dağılımı gösteriliyor.
          if (s.odemeYontemi != 'Karma')
            _Satir('Ödeme Yöntemi', s.odemeYontemi ?? '—')
          else ...[
            _Satir('Ödeme Yöntemi', 'Karma'),
            if (_odemeDagilimi == null)
              const Padding(
                padding: EdgeInsets.only(top: 4, bottom: 2),
                child: SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _odemeDagilimi!
                      .map((d) => Padding(
                            padding: const EdgeInsets.only(left: 12, top: 2),
                            child: Row(children: [
                              Icon(Icons.subdirectory_arrow_right,
                                  size: 14, color: TsRenk.metinIkincil(context)),
                              const SizedBox(width: 4),
                              Text('${d['yontem']}: ${ParaUtils.formatla(d['tutar'] as double)}',
                                  style: TextStyle(fontSize: 12, color: TsRenk.metinIkincil(context))),
                            ]),
                          ))
                      .toList(),
                ),
              ),
          ],
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
