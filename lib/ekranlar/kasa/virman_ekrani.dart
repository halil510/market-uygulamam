// lib/ekranlar/kasa/virman_ekrani.dart — Hesaplar arası virman
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../depolar/kasa_deposu.dart';
import '../../saglayicilar/riverpod/kasa_rapor_provider.dart';
import '../../modeller/kasa_hareket_model.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';

class VirmanEkrani extends ConsumerStatefulWidget {
  const VirmanEkrani({super.key});
  @override
  ConsumerState<VirmanEkrani> createState() => _VirmanEkraniState();
}

class _VirmanEkraniState extends ConsumerState<VirmanEkrani> {
  final _tutarCtrl = TextEditingController();
  final _aciklamaCtrl = TextEditingController();
  final _depo = KasaDeposu();
  double _kasaBakiye = 0;
  String _kaynakHesap = 'Kasa';
  String _hedefHesap  = 'Banka';
  bool _islem = false;

  static const _hesaplar = ['Kasa', 'Banka', 'Kredi Kartı', 'Havale/EFT', 'Diğer'];

  @override
  void initState() {
    super.initState();
    _kasaBakiyeYukle();
  }

  @override
  void dispose() {
    _tutarCtrl.dispose();
    _aciklamaCtrl.dispose();
    super.dispose();
  }

  Future<void> _kasaBakiyeYukle() async {
    try {
      final b = await _depo.guncelBakiye();
      if (mounted) setState(() => _kasaBakiye = b);
    } catch (_) {
      // sessizce geç — bakiye kartı 0 gösterir, ekranı bloklamaz
    }
  }

  Future<void> _virmanYap() async {
    final tutar = double.tryParse(_tutarCtrl.text.replaceAll(',', '.')) ?? 0;
    if (tutar <= 0) {
      BildirimServisi.uyari(context, 'Geçerli tutar girin');
      return;
    }
    if (_kaynakHesap == _hedefHesap) {
      BildirimServisi.uyari(context, 'Kaynak ve hedef farklı olmalı');
      return;
    }
    // 🔴 Derin analizde bulundu: Kasa çıkış tarafındaysa mevcut bakiyeyi
    // aşıp aşmadığı hiç kontrol edilmiyordu — kasayı negatife düşüren bir
    // virman hiçbir uyarı olmadan onaylanabiliyordu.
    if (_kaynakHesap == 'Kasa' && tutar > _kasaBakiye + 0.01) {
      BildirimServisi.uyari(context,
          'Kasa bakiyesi (${ParaUtils.formatla(_kasaBakiye)}) yetersiz');
      return;
    }

    setState(() => _islem = true);
    try {
      final now = DateTime.now();
      final acik = _aciklamaCtrl.text.isEmpty
          ? '$_kaynakHesap → $_hedefHesap Virman'
          : _aciklamaCtrl.text;

      // ÖNCEDEN: Kasa hiçbir tarafta seçili olmasa bile (ör. Banka →
      // Kredi Kartı) kasa hareketleri tablosuna "Virman Çıkış" + "Virman
      // Giriş" kaydı ekleniyordu. Net bakiye etkisi sıfırdı (biri artırır
      // biri azaltır) ama kasa hareket geçmişinde kasayla hiç ilgisi
      // olmayan "hayalet" kayıtlar oluşuyordu. Artık sadece Kasa gerçekten
      // taraflardan biriyse kasa hareketi kaydediliyor.
      final kasaDahil = _kaynakHesap == 'Kasa' || _hedefHesap == 'Kasa';
      if (kasaDahil) {
        if (_kaynakHesap == 'Kasa') {
          await _depo.hareketEkle(KasaHareketModel(
            hareketTipi: 'Virman Çıkış',
            tutar: tutar, tarih: now,
            aciklama: '$acik (Çıkış)',
            referansTuru: 'virman',
          ));
        }
        if (_hedefHesap == 'Kasa') {
          await _depo.hareketEkle(KasaHareketModel(
            hareketTipi: 'Virman Giriş',
            tutar: tutar, tarih: now,
            aciklama: '$acik (Giriş)',
            referansTuru: 'virman',
          ));
        }
        await _kasaBakiyeYukle();
      }
      // ÖNCEDEN Kasa Raporu ekranı (başka bir sekmede/ekranda açıksa)
      // virman sonrası eski veriyi göstermeye devam ederdi. Cari
      // bakiyesinde bulunan AYNI sınıf soruna karşı önlem.
      ref.invalidate(kasaRaporProvider);

      _tutarCtrl.clear();
      _aciklamaCtrl.clear();
      if (mounted) {
        // 🔴 Derin analizde bulundu: kasa taraf olmadığında (ör.
        // Banka → Kredi Kartı) önce "✓ virman yapıldı" başarı mesajı
        // gösterilip HEMEN ARDINDAN "aslında hiçbir yere kaydedilmedi"
        // uyarısı veriliyordu — kısa süreliğine yanıltıcıydı. Artık bu
        // durumda başarı mesajı hiç gösterilmiyor, sadece açıklayıcı
        // uyarı gösteriliyor.
        if (kasaDahil) {
          BildirimServisi.basari(context, '${ParaUtils.formatla(tutar)} virman yapıldı ✓');
        } else {
          BildirimServisi.uyari(context,
              'Kasa bu virmanda taraf olmadığı için kasa hareket '
              'geçmişine kaydedilmedi. Banka/kart hesapları arası hareket '
              'için ilgili hesap ekranından işlem yapın.');
        }
      }
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Virman yapılamadı: $e');
    } finally {
      if (mounted) setState(() => _islem = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: TsRenk.arkaplan(context),
    appBar: const TsAppBar(baslik: 'Virman', gradyanli: true),
    body: ListView(padding: const EdgeInsets.all(TsBosluk.lg), children: [
      // Kasa bakiye kartı
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [TsRenk.primaryKoyu, TsRenk.primary]),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(children: [
          const Icon(Icons.account_balance_wallet_outlined, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Kasa Bakiyesi', style: TextStyle(color: Colors.white70, fontSize: 12)),
            Text(ParaUtils.formatla(_kasaBakiye),
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
          ]),
        ]),
      ),
      const SizedBox(height: TsBosluk.xl),

      // Hesap seçimi
      TsKart(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Row(children: [
            Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: TsRenk.zemin(TsRenk.hata), borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.arrow_upward, color: TsRenk.hata, size: 18)),
            const SizedBox(width: 10),
            Text('Kaynak Hesap', style: TextStyle(fontWeight: FontWeight.w600, color: TsRenk.metinBirincil(context))),
            const Spacer(),
            DropdownButton<String>(
              value: _kaynakHesap,
              underline: const SizedBox.shrink(),
              items: _hesaplar.map((h) => DropdownMenuItem(value: h, child: Text(h))).toList(),
              onChanged: (v) => setState(() => _kaynakHesap = v!)),
          ]),
          const SizedBox(height: 8),
          Center(child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: TsRenk.ayirac(context), shape: BoxShape.circle),
            child: Icon(Icons.swap_vert, color: TsRenk.metinIkincil(context)))),
          const SizedBox(height: 8),
          Row(children: [
            Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: TsRenk.zemin(TsRenk.basarili), borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.arrow_downward, color: TsRenk.basarili, size: 18)),
            const SizedBox(width: 10),
            Text('Hedef Hesap', style: TextStyle(fontWeight: FontWeight.w600, color: TsRenk.metinBirincil(context))),
            const Spacer(),
            DropdownButton<String>(
              value: _hedefHesap,
              underline: const SizedBox.shrink(),
              items: _hesaplar.map((h) => DropdownMenuItem(value: h, child: Text(h))).toList(),
              onChanged: (v) => setState(() => _hedefHesap = v!)),
          ]),
        ]),
      ),
      const SizedBox(height: TsBosluk.md),

      TsInput(
        etiket: 'Virman Tutarı (₺)',
        controller: _tutarCtrl,
        oncilIkon: Icons.attach_money,
        klavyeTuru: const TextInputType.numberWithOptions(decimal: true),
      ),
      const SizedBox(height: TsBosluk.sm),
      TsInput(
        etiket: 'Açıklama (İsteğe bağlı)',
        controller: _aciklamaCtrl,
        oncilIkon: Icons.notes_outlined,
      ),
      const SizedBox(height: TsBosluk.xl),
      SizedBox(
        height: 54,
        child: TsButon(
          metin: 'Virmanı Gerçekleştir',
          ikon: Icons.swap_horiz,
          tamGenislik: true,
          yukleniyor: _islem,
          onPressed: _islem ? null : _virmanYap,
        ),
      ),
    ]),
  );
}
