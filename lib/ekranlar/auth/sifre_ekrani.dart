// lib/ekranlar/auth/sifre_ekrani.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../depolar/kullanici_deposu.dart';
import '../../servisler/auth_servisi.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';

class SifreEkrani extends ConsumerStatefulWidget {
  const SifreEkrani({super.key});
  @override
  ConsumerState<SifreEkrani> createState() => _SifreEkraniState();
}

class _SifreEkraniState extends ConsumerState<SifreEkrani> {
  final _form = GlobalKey<FormState>();
  final _eskiCtrl = TextEditingController();
  final _yeniCtrl = TextEditingController();
  final _tekrarCtrl = TextEditingController();
  bool _yukleniyor = false;
  bool _eskiGoster = false;
  bool _yeniGoster = false;

  Future<void> _degistir() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _yukleniyor = true);
    try {
      final kullanici = AuthServisi().aktifKullanici!;
      final kontrol = await KullaniciDeposu().girisKontrol(kullanici.kullaniciAdi, _eskiCtrl.text);
      if (!mounted) return;
      if (kontrol == null) {
        BildirimServisi.hata(context, 'Mevcut şifre hatalı');
        return;
      }
      await KullaniciDeposu().sifreDegistir(kullanici.id!, _yeniCtrl.text);
      if (mounted) {
        BildirimServisi.basari(context, 'Şifre değiştirildi ✓');
        context.pop();
      }
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Değiştirilemedi: $e');
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  @override
  void dispose() {
    _eskiCtrl.dispose();
    _yeniCtrl.dispose();
    _tekrarCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: const TsAppBar(baslik: 'Şifre Değiştir', gradyanli: true),
      body: Form(
        key: _form,
        // ÖNCEDEN bu form tabletlerde TAM GENİŞLİĞE yayılıyordu — geniş
        // ekranlarda input alanları aşırı uzayıp kötü/dağınık
        // görünüyordu. Artık makul bir genişlikte sınırlanıp ortalanıyor
        // — hem dikey hem yatay tablet kullanımında iyi görünüyor.
        child: LayoutBuilder(
          builder: (context, constraints) {
            final genisEkran = constraints.maxWidth > 600;
            return ListView(
              padding: EdgeInsets.symmetric(
                horizontal: genisEkran
                    ? (constraints.maxWidth - 440) / 2
                    : TsBosluk.lg,
                vertical: TsBosluk.lg,
              ),
              children: [
            const SizedBox(height: TsBosluk.md),
            TextFormField(
              controller: _eskiCtrl,
              obscureText: !_eskiGoster,
              decoration: InputDecoration(
                labelText: 'Mevcut Şifre',
                prefixIcon: const Icon(Icons.lock_outline),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: TsRenk.arkaplan(context),
                suffixIcon: IconButton(
                  icon: Icon(_eskiGoster ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _eskiGoster = !_eskiGoster),
                ),
              ),
              validator: (v) => v == null || v.isEmpty ? 'Mevcut şifre gerekli' : null,
            ),
            const SizedBox(height: TsBosluk.md),
            TextFormField(
              controller: _yeniCtrl,
              obscureText: !_yeniGoster,
              decoration: InputDecoration(
                labelText: 'Yeni Şifre',
                prefixIcon: const Icon(Icons.lock_reset),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: TsRenk.arkaplan(context),
                suffixIcon: IconButton(
                  icon: Icon(_yeniGoster ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _yeniGoster = !_yeniGoster),
                ),
              ),
              validator: (v) => v == null || v.length < 4 ? 'En az 4 karakter' : null,
            ),
            const SizedBox(height: TsBosluk.md),
            TextFormField(
              controller: _tekrarCtrl,
              obscureText: !_yeniGoster,
              decoration: InputDecoration(
                labelText: 'Yeni Şifre Tekrar',
                prefixIcon: const Icon(Icons.lock_reset),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: TsRenk.arkaplan(context),
              ),
              validator: (v) => v != _yeniCtrl.text ? 'Şifreler eşleşmiyor' : null,
            ),
            const SizedBox(height: TsBosluk.xl),
            SizedBox(
              height: 54,
              child: TsButon(
                metin: 'Değiştir',
                ikon: Icons.save,
                tamGenislik: true,
                yukleniyor: _yukleniyor,
                onPressed: _yukleniyor ? null : _degistir,
              ),
            ),
              ],
            );
          },
        ),
      ),
    );
  }
}
