// lib/ekranlar/borc/widgets/borc_odeme_bottom_sheet.dart
//
// PAYLAŞILAN BORÇ ÖDEME BİLEŞENİ
// ------------------------------------------------------------------
// Önceden borc_dashboard_ekrani.dart içinde özel (private) bir widget'tı.
// Artık public ve paylaşılan bir bileşen — hem Borç Merkezi (dashboard),
// hem Borç Detayı, hem de bağımsız ödeme rotası AYNI, eksiksiz mantığı
// (banka hesabı seçimi, kredi kartı seçimi, Gider kaydı) kullanır.
// Bkz. borc_odeme_islem_servisi.dart (gerçek iş mantığı).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../saglayicilar/riverpod/borc_provider.dart';

import '../../../modeller/borc_model.dart';
import '../../../modeller/banka_hesap_model.dart';
import '../../../modeller/kredi_karti_model.dart';
import '../../../cekirdek/utils/para_utils.dart';
import '../../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../../servisler/bildirim_servisi.dart';
import '../../../servisler/borc_odeme_islem_servisi.dart';

// ─── Ödeme Bottom Sheet (Banka Entegreli) ─────────────────────────────────────

class BorcOdemeBottomSheet extends ConsumerStatefulWidget {
  final BorcModel borc;
  final List<BankaHesapModel> bankaHesaplari;
  final List<KrediKartiModel> krediKartlari;
  final VoidCallback onOdemeYapildi;

  const BorcOdemeBottomSheet({
    super.key,
    required this.borc,
    required this.bankaHesaplari,
    required this.krediKartlari,
    required this.onOdemeYapildi,
  });

  @override
  ConsumerState<BorcOdemeBottomSheet> createState() => BorcOdemeBottomSheetState();
}

class BorcOdemeBottomSheetState extends ConsumerState<BorcOdemeBottomSheet> {
  final _tutarCtrl = TextEditingController();
  final _aciklamaCtrl = TextEditingController();
  String _odemeYontemi = 'Nakit';
  BankaHesapModel? _secilenHesap;
  KrediKartiModel? _secilenKart;
  bool _yukleniyor = false;

  final List<String> _yontemler = ['Nakit', 'Banka', 'Kredi Kartı', 'Havale'];

  @override
  void initState() {
    super.initState();
    _tutarCtrl.text = widget.borc.kalanTutar.toStringAsFixed(2);
    if (widget.bankaHesaplari.isNotEmpty) {
      _secilenHesap = widget.bankaHesaplari.first;
    }
    if (widget.krediKartlari.isNotEmpty) {
      _secilenKart = widget.krediKartlari.first;
    }
  }

  @override
  void dispose() {
    _tutarCtrl.dispose();
    _aciklamaCtrl.dispose();
    super.dispose();
  }

  bool get _bankaSecimiGerekli =>
      _odemeYontemi == 'Banka' || _odemeYontemi == 'Havale';
  bool get _kartSecimiGerekli => _odemeYontemi == 'Kredi Kartı';

  Future<void> _odemeYap() async {
    final tutar = double.tryParse(_tutarCtrl.text.replaceAll(',', '.'));
    if (tutar == null || tutar <= 0) {
      BildirimServisi.uyari(context, 'Geçerli tutar girin');
      return;
    }
    if (tutar > widget.borc.kalanTutar + 0.01) {
      BildirimServisi.uyari(context, 'Kalan borçtan fazla ödeme yapılamaz');
      return;
    }
    if (_bankaSecimiGerekli && _secilenHesap == null) {
      BildirimServisi.uyari(context, 'Banka hesabı seçiniz');
      return;
    }
    if (_kartSecimiGerekli && _secilenKart == null) {
      BildirimServisi.uyari(context, 'Kredi kartı seçiniz');
      return;
    }

    setState(() => _yukleniyor = true);
    try {
      // Tüm iş mantığı (ödeme geçmişi + banka/kart/kasa hareketi + Gider
      // kaydı) artık tek, merkezi bir serviste — bkz.
      // borc_odeme_islem_servisi.dart. Böylece hem bu ekran hem de
      // BorcOdemeEkrani (bağımsız ödeme ekranı) aynı, eksiksiz mantığı
      // kullanır; biri diğerinden eksik kalmaz.
      await BorcOdemeIslemServisi().odemeYap(
        borc: widget.borc,
        tutar: tutar,
        odemeYontemi: _odemeYontemi,
        bankaHesapId: _bankaSecimiGerekli ? _secilenHesap?.id : null,
        krediKartiId: _kartSecimiGerekli ? _secilenKart?.id : null,
        aciklama: _aciklamaCtrl.text.trim().isEmpty ? null : _aciklamaCtrl.text.trim(),
        referansNo: widget.borc.referansNo,
      );

      if (mounted) {
        // ÖNCEDEN burada hiçbir provider geçersiz kılınmıyordu — sadece
        // widget.onOdemeYapildi() callback'ine güveniliyordu, bu da
        // çağıran ekrana göre eksik kalabilirdi. Cari bakiyesinde
        // bulunan AYNI sınıf sorun burada da düzeltiliyor.
        ref.invalidate(borcOzetProvider);
        ref.invalidate(tumBorclarProvider);
        ref.invalidate(aktifBorclarProvider);
        ref.invalidate(odenenBorclarProvider);
        ref.invalidate(borcDashboardProvider);
        if (_kartSecimiGerekli) {
          ref.invalidate(krediKartlariToplamProvider);
          ref.invalidate(tumKrediKartlariProvider);
        }
        Navigator.pop(context);
        widget.onOdemeYapildi();
      }
    } catch (e) {
      if (mounted) {
        BildirimServisi.hata(context, 'Ödeme kaydedilemedi: $e');
        setState(() => _yukleniyor = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: TsRenk.kart(context),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: TsRenk.ayirac(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [
            const Icon(Icons.payment_rounded, color: TsRenk.primaryKoyu),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Ödeme Yap', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  Text(widget.borc.baslik,
                      style: TextStyle(fontSize: 12, color: TsRenk.metinIkincil(context)),
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: TsRenk.zemin(TsRenk.uyari),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Kalan: ${ParaUtils.formatla(widget.borc.kalanTutar)}',
                style: TextStyle(fontSize: 12, color: Colors.orange.shade700, fontWeight: FontWeight.w600),
              ),
            ),
          ]),
          const SizedBox(height: 20),
          TextField(
            controller: _tutarCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Tutar (₺)',
              prefixIcon: const Icon(Icons.attach_money_rounded),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: TsRenk.arkaplan(context),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _odemeYontemi,
            decoration: InputDecoration(
              labelText: 'Ödeme Yöntemi',
              prefixIcon: const Icon(Icons.payment_rounded),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: TsRenk.arkaplan(context),
            ),
            items: _yontemler.map((y) => DropdownMenuItem(value: y, child: Text(y))).toList(),
            onChanged: (v) => setState(() => _odemeYontemi = v!),
          ),
          const SizedBox(height: 12),
          if (_bankaSecimiGerekli && widget.bankaHesaplari.isNotEmpty) ...[
            DropdownButtonFormField<BankaHesapModel>(
              value: _secilenHesap,
              decoration: InputDecoration(
                labelText: 'Hangi Hesaptan?',
                prefixIcon: const Icon(Icons.account_balance_rounded),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: TsRenk.zemin(TsRenk.bilgi),
              ),
              items: widget.bankaHesaplari
                  .map((h) => DropdownMenuItem(
                        value: h,
                        child: Row(children: [
                          Expanded(child: Text(h.hesapAdi, overflow: TextOverflow.ellipsis)),
                          const SizedBox(width: 8),
                          Text(ParaUtils.formatla(h.bakiye),
                              style: TextStyle(
                                  fontSize: 11,
                                  color: h.bakiye >= 0 ? Colors.green : Colors.red,
                                  fontWeight: FontWeight.w600)),
                        ]),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _secilenHesap = v),
            ),
            const SizedBox(height: 12),
          ] else if (_bankaSecimiGerekli && widget.bankaHesaplari.isEmpty) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: TsRenk.zemin(TsRenk.uyari),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Banka hesabı bulunamadı. Önce bir hesap ekleyin veya "Nakit" seçin.',
                style: TextStyle(fontSize: 11, color: Colors.orange.shade800),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_kartSecimiGerekli && widget.krediKartlari.isNotEmpty) ...[
            DropdownButtonFormField<KrediKartiModel>(
              value: _secilenKart,
              decoration: InputDecoration(
                labelText: 'Hangi Kart?',
                prefixIcon: const Icon(Icons.credit_card_rounded),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: TsRenk.zemin(TsRenk.accent),
              ),
              items: widget.krediKartlari
                  .map((k) => DropdownMenuItem(
                        value: k,
                        child: Row(children: [
                          Expanded(child: Text(k.kartAdi, overflow: TextOverflow.ellipsis)),
                          const SizedBox(width: 8),
                          Text('Limit: ${ParaUtils.formatla(k.kalanLimit)}',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: k.kalanLimit >= 0 ? Colors.green : Colors.red,
                                  fontWeight: FontWeight.w600)),
                        ]),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _secilenKart = v),
            ),
            const SizedBox(height: 12),
          ] else if (_kartSecimiGerekli && widget.krediKartlari.isEmpty) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: TsRenk.zemin(TsRenk.uyari),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Kredi kartı bulunamadı. Önce bir kart ekleyin veya başka yöntem seçin.',
                style: TextStyle(fontSize: 11, color: Colors.orange.shade800),
              ),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _aciklamaCtrl,
            decoration: InputDecoration(
              labelText: 'Açıklama (opsiyonel)',
              prefixIcon: const Icon(Icons.notes_rounded),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: TsRenk.arkaplan(context),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              onPressed: _yukleniyor ? null : _odemeYap,
              icon: _yukleniyor
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check_rounded),
              label: Text(_yukleniyor ? 'Kaydediliyor...' : 'Ödemeyi Onayla'),
              style: FilledButton.styleFrom(
                backgroundColor: TsRenk.primaryKoyu,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
