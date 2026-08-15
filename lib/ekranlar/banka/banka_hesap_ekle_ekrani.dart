// lib/ekranlar/banka/banka_hesap_ekle_ekrani.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../depolar/banka_hesap_deposu.dart';
import '../../modeller/banka_hesap_model.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../saglayicilar/riverpod/banka_provider.dart';
import '../../saglayicilar/riverpod/borc_provider.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';

class BankaHesapEkleEkrani extends ConsumerStatefulWidget {
  final int bankaId;
  const BankaHesapEkleEkrani({super.key, required this.bankaId});

  @override
  ConsumerState<BankaHesapEkleEkrani> createState() => _BankaHesapEkleEkraniState();
}

class _BankaHesapEkleEkraniState extends ConsumerState<BankaHesapEkleEkrani> {
  final _formKey = GlobalKey<FormState>();
  final _hesapAdiCtrl = TextEditingController();
  final _hesapNoCtrl = TextEditingController();
  final _ibanCtrl = TextEditingController();
  final _subeAdiCtrl = TextEditingController();
  final _subeKoduCtrl = TextEditingController();
  final _bakiyeCtrl = TextEditingController(text: '0');
  String _paraBirimi = 'TRY';
  String _hesapTuru = 'Vadesiz';
  bool _aktif = true;
  bool _kayit = false;

  static const _paraBirimleri = ['TRY', 'USD', 'EUR'];
  static const _hesapTurleri = ['Vadesiz', 'Vadeli', 'Kredi', 'Döviz'];

  @override
  void dispose() {
    _hesapAdiCtrl.dispose();
    _hesapNoCtrl.dispose();
    _ibanCtrl.dispose();
    _subeAdiCtrl.dispose();
    _subeKoduCtrl.dispose();
    _bakiyeCtrl.dispose();
    super.dispose();
  }

  Future<void> _kaydet() async {
    if (widget.bankaId <= 0) {
      BildirimServisi.uyari(context, 'Geçersiz banka seçimi!');
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    final bakiye = double.tryParse(_bakiyeCtrl.text.replaceAll(',', '.')) ?? 0;

    setState(() => _kayit = true);
    try {
      final hesap = BankaHesapModel(
        bankaId: widget.bankaId,
        hesapAdi: _hesapAdiCtrl.text.trim(),
        hesapNo: _hesapNoCtrl.text.trim(),
        iban: _ibanCtrl.text.trim().isEmpty ? null : _ibanCtrl.text.trim(),
        subeAdi: _subeAdiCtrl.text.trim().isEmpty ? null : _subeAdiCtrl.text.trim(),
        subeKodu: _subeKoduCtrl.text.trim().isEmpty ? null : _subeKoduCtrl.text.trim(),
        paraBirimi: _paraBirimi,
        bakiye: bakiye,
        kullanilabilirBakiye: bakiye,
        hesapTuru: _hesapTuru,
        aktif: _aktif,
      );
      await BankaHesapDeposu().ekle(hesap);
      if (mounted) {
        ref.invalidate(bankaHesaplarProvider);
        ref.invalidate(borcDashboardProvider);
        ref.invalidate(borcOzetProvider);
        BildirimServisi.basari(context, 'Hesap kaydedildi ✓');
        context.pop(true);
      }
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Kaydedilemedi: $e');
    } finally {
      if (mounted) setState(() => _kayit = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'Hesap Ekle',
        gradyanli: true,
        aksiyonlar: [
          IconButton(
            icon: const Icon(Icons.save, color: Colors.white),
            onPressed: _kayit ? null : _kaydet,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(TsBosluk.lg),
          children: [
            TsInput(etiket: 'Hesap Adı *', controller: _hesapAdiCtrl, oncilIkon: Icons.account_balance,
                dogrula: (v) => (v == null || v.trim().isEmpty) ? 'Zorunlu' : null),
            const SizedBox(height: TsBosluk.md),
            TsInput(etiket: 'Hesap Numarası *', controller: _hesapNoCtrl, oncilIkon: Icons.numbers,
                dogrula: (v) => (v == null || v.trim().isEmpty) ? 'Zorunlu' : null),
            const SizedBox(height: TsBosluk.md),
            TsInput(etiket: 'IBAN', controller: _ibanCtrl, oncilIkon: Icons.code),
            const SizedBox(height: TsBosluk.md),
            Row(children: [
              Expanded(child: TsInput(etiket: 'Şube Adı', controller: _subeAdiCtrl, oncilIkon: Icons.location_city)),
              const SizedBox(width: 10),
              Expanded(child: TsInput(etiket: 'Şube Kodu', controller: _subeKoduCtrl, oncilIkon: Icons.numbers)),
            ]),
            const SizedBox(height: TsBosluk.md),
            DropdownButtonFormField<String>(
              value: _paraBirimi,
              decoration: InputDecoration(
                labelText: 'Para Birimi',
                prefixIcon: const Icon(Icons.attach_money),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: TsRenk.arkaplan(context),
              ),
              items: _paraBirimleri.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
              onChanged: (v) => setState(() => _paraBirimi = v!),
            ),
            const SizedBox(height: TsBosluk.md),
            DropdownButtonFormField<String>(
              value: _hesapTuru,
              decoration: InputDecoration(
                labelText: 'Hesap Türü',
                prefixIcon: const Icon(Icons.category),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: TsRenk.arkaplan(context),
              ),
              items: _hesapTurleri.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
              onChanged: (v) => setState(() => _hesapTuru = v!),
            ),
            const SizedBox(height: TsBosluk.md),
            TsInput(
              etiket: 'Açılış Bakiyesi',
              controller: _bakiyeCtrl,
              oncilIkon: Icons.attach_money,
              klavyeTuru: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: TsBosluk.md),
            TsKart(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(children: [
                Text('Aktif', style: TextStyle(fontSize: 14, color: TsRenk.metinBirincil(context))),
                const Spacer(),
                Switch(value: _aktif, onChanged: (v) => setState(() => _aktif = v)),
              ]),
            ),
            const SizedBox(height: TsBosluk.xl),
            SizedBox(
              height: 54,
              child: TsButon(
                metin: 'Kaydet',
                ikon: Icons.save_outlined,
                tamGenislik: true,
                yukleniyor: _kayit,
                onPressed: _kayit ? null : _kaydet,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
