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

  @override
  void initState() {
    super.initState();
    // Şifre gücü göstergesi ve "eşleşiyor" ipucu canlı güncellensin diye —
    // TextFormField'ın kendi onChanged'i validator'ı tetikler ama görsel
    // geri bildirim (güç çubuğu/eşleşme rozeti) için ayrıca setState gerekir.
    _yeniCtrl.addListener(() => setState(() {}));
    _tekrarCtrl.addListener(() => setState(() {}));
  }

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

  /// 0 (boş) - 4 (çok güçlü) arası bir puan döner — uzunluk, rakam+harf
  /// karışımı ve büyük harf/sembol varlığına göre basit bir tahmin.
  int _sifreGucu(String s) {
    if (s.isEmpty) return 0;
    var puan = 1;
    if (s.length >= 6) puan++;
    if (s.length >= 10) puan++;
    if (RegExp(r'[0-9]').hasMatch(s) && RegExp(r'[a-zA-Z]').hasMatch(s)) puan++;
    if (RegExp(r'[A-Z]').hasMatch(s) && RegExp(r'[^A-Za-z0-9]').hasMatch(s)) puan++;
    return puan.clamp(0, 4);
  }

  (String, Color) _sifreGucuEtiket(int puan, BuildContext context) {
    switch (puan) {
      case 0:
      case 1:
        return ('Zayıf', TsRenk.hata);
      case 2:
        return ('Orta', Colors.orange);
      case 3:
        return ('İyi', TsRenk.bilgi);
      default:
        return ('Güçlü', TsRenk.basarili);
    }
  }

  @override
  Widget build(BuildContext context) {
    final gucu = _sifreGucu(_yeniCtrl.text);
    final (gucEtiket, gucRenk) = _sifreGucuEtiket(gucu, context);
    final eslesiyorMu =
        _tekrarCtrl.text.isNotEmpty && _tekrarCtrl.text == _yeniCtrl.text;

    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: const TsAppBar(baslik: 'Şifre Değiştir', gradyanli: true),
      body: Form(
        key: _form,
        // Tabletlerde tam genişliğe yayılıp dağınık görünmesin diye makul
        // bir genişlikte sınırlanıp ortalanıyor.
        child: LayoutBuilder(
          builder: (context, constraints) {
            final genisEkran = constraints.maxWidth > 600;
            return ListView(
              padding: EdgeInsets.symmetric(
                horizontal: genisEkran
                    ? (constraints.maxWidth - 460) / 2
                    : TsBosluk.lg,
                vertical: TsBosluk.xl,
              ),
              children: [
                // ── Başlık ikonu + kısa açıklama ────────────────────────
                Center(
                  child: Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [TsRenk.primary, TsRenk.primaryKoyu],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: TsRenk.primary.withAlpha(90),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.lock_person_outlined,
                        color: Colors.white, size: 32),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Şifrenizi Güncelleyin',
                  textAlign: TextAlign.center,
                  style: TsMetin.baslikL
                      .copyWith(color: TsRenk.metinBirincil(context)),
                ),
                const SizedBox(height: 4),
                Text(
                  'Hesap güvenliğiniz için önce mevcut şifrenizi doğrulayın,\n'
                  'sonra yeni bir şifre belirleyin.',
                  textAlign: TextAlign.center,
                  style: TsMetin.kucuk
                      .copyWith(color: TsRenk.metinIkincil(context)),
                ),
                const SizedBox(height: TsBosluk.xl),

                // ── Tek, birleşik kart — TÜM form burada ────────────────
                Container(
                  decoration: BoxDecoration(
                    color: TsRenk.kart(context),
                    borderRadius: BorderRadius.circular(TsRadius.lg),
                    border: Border.all(color: TsRenk.ayirac(context)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(14),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _bolumEtiketi(context, 'MEVCUT ŞİFRE'),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _eskiCtrl,
                        obscureText: !_eskiGoster,
                        decoration: _alanSusu(
                          context,
                          etiket: 'Mevcut Şifre',
                          ikon: Icons.lock_outline,
                          gosterDurumu: _eskiGoster,
                          gosterToggle: () =>
                              setState(() => _eskiGoster = !_eskiGoster),
                        ),
                        validator: (v) =>
                            v == null || v.isEmpty ? 'Mevcut şifre gerekli' : null,
                      ),

                      const SizedBox(height: 22),
                      Divider(color: TsRenk.ayirac(context), height: 1),
                      const SizedBox(height: 22),

                      _bolumEtiketi(context, 'YENİ ŞİFRE'),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _yeniCtrl,
                        obscureText: !_yeniGoster,
                        decoration: _alanSusu(
                          context,
                          etiket: 'Yeni Şifre',
                          ikon: Icons.lock_reset,
                          gosterDurumu: _yeniGoster,
                          gosterToggle: () =>
                              setState(() => _yeniGoster = !_yeniGoster),
                        ),
                        validator: (v) =>
                            v == null || v.length < 4 ? 'En az 4 karakter' : null,
                      ),
                      const SizedBox(height: 10),
                      _sifreGucuCubugu(context, gucu, gucEtiket, gucRenk),

                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _tekrarCtrl,
                        obscureText: !_yeniGoster,
                        decoration: _alanSusu(
                          context,
                          etiket: 'Yeni Şifre Tekrar',
                          ikon: Icons.check_circle_outline,
                          ekIkon: eslesiyorMu
                              ? const Icon(Icons.check_circle,
                                  color: TsRenk.basarili, size: 20)
                              : null,
                        ),
                        validator: (v) =>
                            v != _yeniCtrl.text ? 'Şifreler eşleşmiyor' : null,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: TsBosluk.lg),
                SizedBox(
                  height: 54,
                  child: TsButon(
                    metin: 'Şifreyi Değiştir',
                    ikon: Icons.save_outlined,
                    tamGenislik: true,
                    yukleniyor: _yukleniyor,
                    onPressed: _yukleniyor ? null : _degistir,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.info_outline,
                        size: 14, color: TsRenk.metinIkincil(context)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Şifreniz değiştikten sonra tekrar giriş yapmanız gerekmez.',
                        textAlign: TextAlign.center,
                        style: TsMetin.kucuk
                            .copyWith(color: TsRenk.metinIkincil(context)),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _bolumEtiketi(BuildContext context, String metin) => Text(
        metin,
        style: TsMetin.etiket.copyWith(
          color: TsRenk.metinIkincil(context),
          letterSpacing: 0.6,
          fontWeight: FontWeight.w700,
        ),
      );

  InputDecoration _alanSusu(
    BuildContext context, {
    required String etiket,
    required IconData ikon,
    bool? gosterDurumu,
    VoidCallback? gosterToggle,
    Widget? ekIkon,
  }) {
    return InputDecoration(
      labelText: etiket,
      prefixIcon: Icon(ikon, color: TsRenk.metinIkincil(context)),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: TsRenk.ayirac(context)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: TsRenk.ayirac(context)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: TsRenk.primary, width: 1.6),
      ),
      filled: true,
      fillColor: TsRenk.arkaplan(context),
      suffixIcon: ekIkon ??
          (gosterToggle != null
              ? IconButton(
                  icon: Icon(
                    gosterDurumu! ? Icons.visibility_off : Icons.visibility,
                    color: TsRenk.metinIkincil(context),
                  ),
                  onPressed: gosterToggle,
                )
              : null),
    );
  }

  Widget _sifreGucuCubugu(
      BuildContext context, int gucu, String etiket, Color renk) {
    if (_yeniCtrl.text.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(4, (i) {
            final dolu = i < gucu;
            return Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: EdgeInsets.only(right: i == 3 ? 0 : 4),
                height: 4,
                decoration: BoxDecoration(
                  color: dolu ? renk : TsRenk.ayirac(context),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 4),
        Text('Şifre gücü: $etiket',
            style: TsMetin.kucuk.copyWith(color: renk, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
