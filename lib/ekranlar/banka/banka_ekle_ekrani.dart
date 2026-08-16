// lib/ekranlar/banka/banka_ekle_ekrani.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../depolar/banka_deposu.dart';
import '../../modeller/banka_model.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../saglayicilar/riverpod/banka_provider.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';

class BankaEkleEkrani extends ConsumerStatefulWidget {
  final BankaModel? duzenlenecek;
  const BankaEkleEkrani({super.key, this.duzenlenecek});

  @override
  ConsumerState<BankaEkleEkrani> createState() => _BankaEkleEkraniState();
}

class _BankaEkleEkraniState extends ConsumerState<BankaEkleEkrani> {
  final _formKey = GlobalKey<FormState>();
  final _adCtrl = TextEditingController();
  final _kodCtrl = TextEditingController();
  final _telCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _webCtrl = TextEditingController();
  final _adresCtrl = TextEditingController();
  final _yetkiliCtrl = TextEditingController();
  bool _aktif = true;
  bool _kayit = false;

  @override
  void initState() {
    super.initState();
    if (widget.duzenlenecek != null) {
      _adCtrl.text = widget.duzenlenecek!.ad;
      _kodCtrl.text = widget.duzenlenecek!.kod ?? '';
      _telCtrl.text = widget.duzenlenecek!.tel ?? '';
      _emailCtrl.text = widget.duzenlenecek!.email ?? '';
      _webCtrl.text = widget.duzenlenecek!.web ?? '';
      _adresCtrl.text = widget.duzenlenecek!.adres ?? '';
      _yetkiliCtrl.text = widget.duzenlenecek!.yetkili ?? '';
      _aktif = widget.duzenlenecek!.aktif;
    }
  }

  @override
  void dispose() {
    _adCtrl.dispose();
    _kodCtrl.dispose();
    _telCtrl.dispose();
    _emailCtrl.dispose();
    _webCtrl.dispose();
    _adresCtrl.dispose();
    _yetkiliCtrl.dispose();
    super.dispose();
  }

  Future<void> _kaydet() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _kayit = true);
    try {
      final banka = BankaModel(
        id: widget.duzenlenecek?.id,
        ad: _adCtrl.text.trim(),
        kod: _kodCtrl.text.trim().isEmpty ? null : _kodCtrl.text.trim(),
        tel: _telCtrl.text.trim().isEmpty ? null : _telCtrl.text.trim(),
        email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        web: _webCtrl.text.trim().isEmpty ? null : _webCtrl.text.trim(),
        adres: _adresCtrl.text.trim().isEmpty ? null : _adresCtrl.text.trim(),
        yetkili: _yetkiliCtrl.text.trim().isEmpty ? null : _yetkiliCtrl.text.trim(),
        aktif: _aktif,
      );
      if (widget.duzenlenecek == null) {
        await BankaDeposu().ekle(banka);
      } else {
        await BankaDeposu().guncelle(banka);
      }
      if (mounted) {
        // ÖNCEDEN: kayıt sonrası hiçbir yer yenilenmiyordu (aynı desendeki
        // diğer düzeltmelerle tutarlı olarak eklendi).
        ref.invalidate(bankalarProvider);
        BildirimServisi.basari(context, 'Banka kaydedildi ✓');
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
    final duzenle = widget.duzenlenecek != null;
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: duzenle ? 'Banka Düzenle' : 'Banka Ekle',
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
            _alan(_adCtrl, 'Banka Adı *', Icons.business, zorunlu: true),
            const SizedBox(height: TsBosluk.md),
            _alan(_kodCtrl, 'Banka Kodu', Icons.code),
            const SizedBox(height: TsBosluk.md),
            _alan(_telCtrl, 'Telefon', Icons.phone, klavye: TextInputType.phone),
            const SizedBox(height: TsBosluk.md),
            _alan(_emailCtrl, 'E-posta', Icons.email, klavye: TextInputType.emailAddress),
            const SizedBox(height: TsBosluk.md),
            _alan(_webCtrl, 'Web Sitesi', Icons.language),
            const SizedBox(height: TsBosluk.md),
            _alan(_adresCtrl, 'Adres', Icons.location_on, maxLines: 2),
            const SizedBox(height: TsBosluk.md),
            _alan(_yetkiliCtrl, 'Yetkili Kişi', Icons.person),
            const SizedBox(height: TsBosluk.lg),
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

  Widget _alan(
    TextEditingController ctrl,
    String etiket,
    IconData ikon, {
    bool zorunlu = false,
    int maxLines = 1,
    TextInputType klavye = TextInputType.text,
  }) =>
      TsInput(
        etiket: etiket,
        controller: ctrl,
        oncilIkon: ikon,
        klavyeTuru: klavye,
        maksSatir: maxLines,
        dogrula: zorunlu ? (v) => (v == null || v.trim().isEmpty) ? 'Zorunlu' : null : null,
      );
}
