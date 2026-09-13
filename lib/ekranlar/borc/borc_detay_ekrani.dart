// lib/ekranlar/borc/borc_detay_ekrani.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../modeller/borc_model.dart';
import '../../modeller/borc_odeme_model.dart';
import '../../depolar/borc_deposu.dart';
import '../../depolar/borc_odeme_deposu.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../servisler/onay_merkezi_servisi.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../widgetlar/ortak/app_widgetlar.dart';
import '../../widgetlar/ortak/yonetici_sifre_dialogu.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../saglayicilar/riverpod/banka_provider.dart';
import '../../saglayicilar/riverpod/auth_provider.dart';
import '../../saglayicilar/riverpod/borc_provider.dart';
import 'widgets/borc_odeme_bottom_sheet.dart';

class BorcDetayEkrani extends ConsumerStatefulWidget {
  final int borcId;
  const BorcDetayEkrani({super.key, required this.borcId});

  @override
  ConsumerState<BorcDetayEkrani> createState() => _BorcDetayEkraniState();
}

class _BorcDetayEkraniState extends ConsumerState<BorcDetayEkrani> {
  final _depo = BorcDeposu();
  final _odemeDepo = BorcOdemeDeposu();
  BorcModel? _borc;
  // 🔴 YENİ (kullanıcı isteği: "3. maddeyi yap" — Borç Ödeme Geçmişi):
  // BorcOdemeDeposu.odemeleriGetir() zaten hazırdı ama bu ekran hiç
  // çağırmıyordu — taksitli/kısım kısım ödenen bir borçta kullanıcı
  // "ne zaman ne kadar ödedim" bilgisini hiç göremiyordu.
  List<BorcOdemeModel> _odemeler = [];
  bool _yukleniyor = true;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
  setState(() => _yukleniyor = true);
  try {
    final borc = await _depo.idileGetir(widget.borcId);
    final odemeler = await _odemeDepo.odemeleriGetir(borcId: widget.borcId, limit: 100);
    if (!mounted) return;
    setState(() { _borc = borc; _odemeler = odemeler; _yukleniyor = false; });
  } catch (e) {
    setState(() => _yukleniyor = false);
    if (mounted) BildirimServisi.hata(context, 'Yüklenemedi: $e');
  }
}

  Future<void> _odemeYap() async {
    if (_borc == null) return;
    // Artık aynı, eksiksiz ödeme bileşeni kullanılıyor (banka hesabı/kredi
    // kartı seçimi + otomatik Gider kaydı) — bkz. borc_odeme_islem_servisi.dart
    // ve widgets/borc_odeme_bottom_sheet.dart. Önceden burada sadece tutar
    // giren basit bir dialog vardı; ödeme yöntemi hiçbir yere kaydedilmiyordu.
    final bankaHesaplari = await ref.read(bankaHesaplarProvider(null).future);
    final krediKartlari = await ref.read(krediKartlariProvider(null).future);
    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BorcOdemeBottomSheet(
        borc: _borc!,
        bankaHesaplari: bankaHesaplari,
        krediKartlari: krediKartlari,
        onOdemeYapildi: () async {
          await _yukle();
          if (mounted) BildirimServisi.basari(context, 'Ödeme kaydedildi ✓');
        },
      ),
    );
  }

  // Kullanıcı isteği (2026-09-13): "Borç Silme" — BorcDeposu.sil() zaten
  // vardı (doğru soft-delete: is_deleted=1, hard delete yok) ama HİÇBİR
  // ekrandan çağrılmıyordu — ölü koddu. Hatayla girilmiş bir borç kaydını
  // (kira/vergi/kredi kartı vb.) düzeltmek için kullanılır. borc_odemeler
  // kayıtları SİLİNMEZ (tarihsel iz olarak kalır) — bu yüzden zaten
  // ödeme yapılmış bir borç silinirse kullanıcı önce açıkça uyarılır.
  Future<void> _borcSil(BuildContext context) async {
    if (_borc == null) return;
    if (!ref.read(authProvider).isMudur) return;
    final b = _borc!;

    final odemeUyarisi = b.odenenTutar > 0
        ? '\n\n⚠️ Bu borca ${ParaUtils.formatla(b.odenenTutar)} ödeme '
            'yapılmış. Silinirse ödeme geçmişi kalır ama bu borç kaydı '
            'artık hiçbir listede görünmez.'
        : '';
    final sebepCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.delete_outline, color: Colors.red),
          SizedBox(width: 8),
          Text('Borç Kaydını Sil'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${b.baslik} (${ParaUtils.formatla(b.tutar)}) silinecek.$odemeUyarisi',
                style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 12),
            TextField(
              controller: sebepCtrl,
              decoration: const InputDecoration(
                  labelText: 'Sebep (zorunlu)', border: OutlineInputBorder(), isDense: true),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Devam Et'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final sebep = sebepCtrl.text.trim();
    if (sebep.isEmpty) {
      if (context.mounted) BildirimServisi.uyari(context, 'Sebep girilmesi zorunludur');
      return;
    }

    if (!context.mounted) return;
    final onaylandi = await yoneticiSifresiIleOnayIste(
      context,
      baslik: 'Borç Silme Onayı',
      aciklama: '"${b.baslik}" borç kaydı silinecek. Devam etmek için şifrenizi girin.',
    );
    if (!onaylandi) return;
    if (!context.mounted) return;
    if (!ref.read(authProvider).isMudur) return; // savunma: eylem anında ikinci kez doğrula

    try {
      await _depo.sil(b.id!);
      await OnayMerkeziServisi().kaydet(
        tur: OnayTuru.borcSilme,
        tutar: b.kalanTutar,
        esikTutar: OnayEsikleri.borcSilmeTutari,
        referansTuru: 'borclar',
        referansId: b.id,
        aciklama: '${b.baslik}: $sebep',
      );
      if (context.mounted) {
        ref.invalidate(tumBorclarProvider);
        BildirimServisi.basari(context, 'Borç kaydı silindi');
        context.pop();
      }
    } catch (e) {
      if (context.mounted) BildirimServisi.hata(context, 'Silinemedi: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_yukleniyor) {
      return const Scaffold(body: Center(child: AppYukleniyor()));
    }
    if (_borc == null) {
      return Scaffold(
        appBar: TsAppBar(
        baslik: 'Borç Detay',
        gradyanli: false,
      ),
        body: const BosEkran(ikon: Icons.inbox_outlined, baslik: 'Bulunamadı'),
      );
    }

    final b = _borc!;
    final vadesiGecti = b.vadesiGecti;
    final fmt = DateFormat('dd.MM.yyyy');

    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslikWidget: Text(b.baslik),
        aksiyonlar: [
          IconButton(
            icon: const Icon(Icons.payments_outlined),
            onPressed: b.odendi ? null : _odemeYap,
            tooltip: 'Ödeme Yap',
          ),
          if (ref.read(authProvider).isMudur)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _borcSil(context),
              tooltip: 'Borç Kaydını Sil',
            ),
        ],
        gradyanli: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          // Durum kartı
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: b.odendi
                    ? [Colors.green.shade700, Colors.green.shade500]
                    : vadesiGecti
                        ? [Colors.red.shade700, Colors.red.shade500]
                        : [Colors.blue.shade700, Colors.blue.shade500],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(children: [
              Text(
                b.odendi ? 'ÖDENDİ' : vadesiGecti ? 'VADESİ GEÇTİ' : 'BEKLEMEDE',
                style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                b.odendi ? '✓ Tamamlandı' : ParaUtils.formatla(b.kalanTutar),
                style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900),
              ),
              if (!b.odendi)
                Text(
                  'Kalan Borç',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
            ]),
          ),
          const SizedBox(height: 16),

          // Bilgiler
          _Kart(children: [
            _Satir('Borç Türü', _turEtiket(b.tur)),
            if (b.altTur != null) _Satir('Kurum/Banka', b.altTur!),
            _Satir('Toplam Tutar', ParaUtils.formatla(b.tutar), bold: true),
            if (b.odenenTutar > 0) _Satir('Ödenen', ParaUtils.formatla(b.odenenTutar)),
            if (!b.odendi) _Satir('Kalan', ParaUtils.formatla(b.kalanTutar),
                renk: vadesiGecti ? Colors.red : Colors.orange),
            _Satir('Kesim Tarihi', fmt.format(b.kesimTarihi)),
            _Satir('Son Ödeme', fmt.format(b.sonOdemeTarihi),
                renk: vadesiGecti ? Colors.red : null),
            if (b.taksitSayisi > 1) _Satir('Taksit', '${b.odenenTaksit}/${b.taksitSayisi}'),
            if (b.aciklama != null) _Satir('Açıklama', b.aciklama!),
            if (b.dosyaNo != null) _Satir('Dosya No', b.dosyaNo!),
            if (b.referansNo != null) _Satir('Referans No', b.referansNo!),
            _Satir('Öncelik', _oncelikEtiket(b.oncelik), renk: _oncelikRenk(b.oncelik)),
          ]),

          const SizedBox(height: 24),

          // Ödeme butonu
          if (!b.odendi)
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: _odemeYap,
                icon: const Icon(Icons.payments_outlined),
                label: Text('Ödeme Yap (${ParaUtils.formatla(b.kalanTutar)})'),
              ),
            ),

          // 🔴 YENİ: Ödeme Geçmişi — standart fintech deseni (tarih
          // sırasına göre kronolojik liste + ilerleme göstergesi).
          const SizedBox(height: 24),
          Row(children: [
            Text('Ödeme Geçmişi', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: TsRenk.metinBirincil(context))),
            const Spacer(),
            if (_odemeler.isNotEmpty)
              Text('${_odemeler.length} ödeme', style: TextStyle(fontSize: 12, color: TsRenk.metinIkincil(context))),
          ]),
          const SizedBox(height: 10),
          if (b.tutar > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: (b.odenenTutar / b.tutar).clamp(0.0, 1.0),
                    minHeight: 10,
                    backgroundColor: TsRenk.ayirac(context),
                    valueColor: AlwaysStoppedAnimation(b.odendi ? Colors.green : Colors.blue),
                  ),
                ),
                const SizedBox(height: 4),
                Row(children: [
                  Text('${ParaUtils.formatla(b.odenenTutar)} ödendi',
                      style: const TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text('%${(b.tutar > 0 ? (b.odenenTutar / b.tutar * 100) : 0).toStringAsFixed(0)}',
                      style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context))),
                ]),
              ]),
            ),
          if (_yukleniyor)
            const Padding(padding: EdgeInsets.all(20), child: const TsYukleniyor())
          else if (_odemeler.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: TsRenk.kart(context), borderRadius: BorderRadius.circular(14)),
              child: Center(child: Text('Henüz ödeme yapılmadı',
                  style: TextStyle(color: TsRenk.metinIkincil(context), fontSize: 13))),
            )
          else
            ..._odemeler.map((o) => _OdemeSatiri(odeme: o)),
        ]),
      ),
    );
  }

  String _turEtiket(String tur) {
    switch (tur) {
      case 'kredi_karti': return 'Kredi Kartı';
      case 'vergi': return 'Vergi';
      case 'sgk': return 'SGK';
      case 'kira': return 'Kira';
      case 'fatura': return 'Fatura';
      default: return tur;
    }
  }

  String _oncelikEtiket(int oncelik) {
    switch (oncelik) {
      case 1: return 'Kritik';
      case 2: return 'Orta';
      case 3: return 'Düşük';
      default: return 'Orta';
    }
  }

  Color _oncelikRenk(int oncelik) {
    switch (oncelik) {
      case 1: return Colors.red;
      case 2: return Colors.orange;
      case 3: return Colors.green;
      default: return context.textSecondary;
    }
  }
}

class _OdemeSatiri extends StatelessWidget {
  final BorcOdemeModel odeme;
  const _OdemeSatiri({required this.odeme});

  IconData get _ikon {
    switch (odeme.odemeYontemi) {
      case 'Banka': case 'Havale': return Icons.account_balance_outlined;
      case 'Kredi Kartı': return Icons.credit_card_outlined;
      default: return Icons.payments_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd.MM.yyyy HH:mm');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TsRenk.kart(context),
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 4)],
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(color: Colors.green.withAlpha(30), shape: BoxShape.circle),
          child: Icon(_ikon, color: Colors.green, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(odeme.odemeYontemi, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: TsRenk.metinBirincil(context))),
            Text(fmt.format(odeme.tarih), style: TextStyle(fontSize: 11.5, color: TsRenk.metinIkincil(context))),
            if (odeme.aciklama != null && odeme.aciklama!.isNotEmpty)
              Text(odeme.aciklama!, style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context), fontStyle: FontStyle.italic)),
          ]),
        ),
        Text('+${ParaUtils.formatla(odeme.tutar)}',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: Colors.green)),
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
      boxShadow: [BoxShadow(color: Color(0x0D000000), blurRadius: 6)],
    ),
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