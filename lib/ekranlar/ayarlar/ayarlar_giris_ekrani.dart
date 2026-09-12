// lib/ekranlar/ayarlar/ayarlar_giris_ekrani.dart
//
// Ayarlar ekranına giriş için şifre doğrulama.
// - Admin veya 'ayarlar' yetkisi olan kullanıcılar kendi şifresiyle girer.
// - Yetkisi olmayan kullanıcılar admin şifresi girmek zorunda.
// - 3 yanlış denemede 60 saniye kilit.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../depolar/kullanici_deposu.dart';
import '../../servisler/auth_servisi.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';

class AyarlarGirisEkrani extends ConsumerStatefulWidget {
  const AyarlarGirisEkrani({super.key});
  @override
  ConsumerState<AyarlarGirisEkrani> createState() => _AyarlarGirisEkraniState();
}

class _AyarlarGirisEkraniState extends ConsumerState<AyarlarGirisEkrani> {
  final _depo = KullaniciDeposu();
  String _pin = '';
  String _hata = '';
  bool _dogruluyor = false;
  int _hataliGiris = 0;
  bool _kilitli = false;
  DateTime? _kilitBitis;

  // 🔴 Derin analizde bulundu: yorum "'ayarlar' yetkisi var mı?" diyordu
  // ama gerçek kontrol sadece admin/müdür ROLÜNE bakıyordu — granüler
  // yetkiVarSync('ayarlar') hiç kullanılmıyordu (uygulama_router.dart'taki
  // aynı kök hata — bkz. o dosyadaki düzeltme notu). Sonuç: 'ayarlar'
  // yetkisi AÇIKÇA verilmiş ama müdür OLMAYAN bir personel bile buraya
  // "admin şifresi gerekiyor" akışına yanlışlıkla yönlendiriliyordu.
  bool get _yetkiVar =>
      AuthServisi().isAdmin || AuthServisi().yetkiVarSync('ayarlar');

  String get _aciklama => _yetkiVar
      ? 'Kendi şifrenizi girin'
      : 'Admin şifresi gereklidir';

  void _rakamEkle(String r) {
    if (_pin.length < 12) setState(() => _pin += r);
  }

  void _silSon() {
    if (_pin.isNotEmpty) {
      setState(() => _pin = _pin.substring(0, _pin.length - 1));
    }
  }

  void _temizle() => setState(() => _pin = '');

  Future<void> _dogrula() async {
    if (_pin.isEmpty) return;

    // Kilit kontrolü
    if (_kilitli && _kilitBitis != null) {
      if (DateTime.now().isBefore(_kilitBitis!)) {
        final kalan = _kilitBitis!.difference(DateTime.now()).inSeconds;
        _hata = 'Kilitli — $kalan saniye bekleyin';
        if (mounted) setState(() {});
        return;
      }
      setState(() { _kilitli = false; _hataliGiris = 0; _hata = ''; });
    }

    setState(() { _dogruluyor = true; _hata = ''; });

    try {
      bool basarili = false;

      if (_yetkiVar) {
        // Kendi şifresiyle doğrula
        final kullanici = await _depo.girisKontrol(
          AuthServisi().aktifKullanici!.kullaniciAdi,
          _pin,
        );
        basarili = kullanici != null;
      } else {
        // Admin şifresiyle doğrula
        final admin = await _depo.girisKontrol(
          'admin',
          _pin,
        );
        basarili = admin != null;
      }

      if (!mounted) return;

      if (basarili) {
        // Session'ı işaretle (5 dakika geçerli)
        AuthServisi().ayarlariDogrula();
        if (!mounted) return;
        context.go('/ayarlar/icerik');
      } else {
        _hataliGiris++;
        if (_hataliGiris >= 3) {
          _kilitli = true;
          _kilitBitis = DateTime.now().add(const Duration(seconds: 60));
            _hata = 'Çok fazla hatalı giriş. 60 saniye bekleyin.';
            _pin = '';
          if (mounted) setState(() {});
        } else {
            _hata = 'Hatalı şifre ($_hataliGiris/3)';
            _pin = '';
          if (mounted) setState(() {});
        }
      }
    } catch (e) {
      if (mounted) _hata = 'Doğrulama hatası: $e';
      if (mounted) setState(() {});
    } finally {
      if (mounted) _dogruluyor = false;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'Ayarlara Erişim',
        lider: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(children: [
                // İkon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppRenkler.primary.withAlpha(26),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: AppRenkler.primary.withAlpha(76), width: 2),
                  ),
                  child: const Icon(Icons.settings_outlined,
                      size: 40, color: AppRenkler.primary),
                ),
                const SizedBox(height: 20),
                const Text('Ayarlar',
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: AppRenkler.primary)),
                const SizedBox(height: 6),
                Text(
                  _aciklama,
                  style: TextStyle(
                      fontSize: 14, color: TsRenk.metinIkincil(context)),
                  textAlign: TextAlign.center,
                ),
                if (!_yetkiVar) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Color(0x1AFF9800),
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: Color(0x4CFF9800)),
                    ),
                    child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                      const Icon(Icons.lock_outline,
                          color: Colors.orange, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        '${AuthServisi().aktifAd} — Yetkisiz',
                        style: const TextStyle(
                            fontSize: 12,
                            color: Colors.orange,
                            fontWeight: FontWeight.w600),
                      ),
                    ]),
                  ),
                ],
                const SizedBox(height: 28),

                // PIN kartı
                Container(
                  decoration: BoxDecoration(
                    color: TsRenk.kart(context),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: TsRenk.ayirac(context)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(children: [
                      // PIN dots
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: TsRenk.arkaplan(context),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: _hata.isNotEmpty
                                  ? AppRenkler.error.withAlpha(102)
                                  : TsRenk.ayirac(context)),
                        ),
                        child: Center(
                          child: _pin.isEmpty
                              ? Text(
                                  'Şifrenizi girin',
                                  style: TextStyle(
                                      color: TsRenk.metinIkincil(context),
                                      fontSize: 14),
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: List.generate(
                                    _pin.length,
                                    (_) => Container(
                                      width: 12,
                                      height: 12,
                                      margin: const EdgeInsets.symmetric(
                                          horizontal: 4),
                                      decoration: const BoxDecoration(
                                          color: AppRenkler.primary,
                                          shape: BoxShape.circle),
                                    ),
                                  ),
                                ),
                        ),
                      ),

                      // Hata mesajı
                      if (_hata.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppRenkler.error.withAlpha(20),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(children: [
                            Icon(Icons.error_outline,
                                color: AppRenkler.error, size: 16),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(_hata,
                                  style: TextStyle(
                                      color: AppRenkler.error,
                                      fontSize: 12)),
                            ),
                          ]),
                        ),
                      ],

                      const SizedBox(height: 16),

                      // NumPad
                      _NumPad(
                        onRakam: _kilitli ? (_) {} : _rakamEkle,
                        onSil: _kilitli ? () {} : _silSon,
                        onTemizle: _kilitli ? () {} : _temizle,
                        kilitli: _kilitli,
                      ),

                      const SizedBox(height: 16),

                      // Giriş butonu
                      SizedBox(width: double.infinity, height: 52, child: FilledButton(
                          onPressed:
                              (_dogruluyor || _kilitli || _pin.isEmpty)
                                  ? null
                                  : _dogrula,
                          style: FilledButton.styleFrom(
                            foregroundColor: Colors.white,
          backgroundColor: AppRenkler.primary,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          child: _dogruluyor
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2.5))
                              : const Text('Doğrula',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white)),
                        ),
                      ),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ── NumPad ───────────────────────────────────────────────────────────────────
class _NumPad extends StatelessWidget {
  final void Function(String) onRakam;
  final VoidCallback onSil;
  final VoidCallback onTemizle;
  final bool kilitli;

  const _NumPad({
    required this.onRakam,
    required this.onSil,
    required this.onTemizle,
    this.kilitli = false,
  });

  @override
  Widget build(BuildContext context) {
    final tuslar = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['C', '0', '⌫'],
    ];
    return Column(
      children: tuslar
          .map((satir) => Row(
                children: satir
                    .map((t) => Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(3),
                            child: Opacity(
                              opacity: kilitli ? 0.4 : 1.0,
                              child: Material(
                                color: t == 'C'
                                    ? AppRenkler.error.withAlpha(26)
                                    : t == '⌫'
                                        ? Color(0x1AFF9800)
                                        : TsRenk.arkaplan(context),
                                borderRadius: BorderRadius.circular(12),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () {
                                    if (t == '⌫') onSil();
                                    else if (t == 'C') onTemizle();
                                    else onRakam(t);
                                  },
                                  child: Container(
                                    height: 52,
                                    alignment: Alignment.center,
                                    child: t == '⌫'
                                        ? const Icon(
                                            Icons.backspace_outlined,
                                            color: Colors.orange, size: 22)
                                        : t == 'C'
                                            ? Text(t,
                                                style: TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w700,
                                                    color: AppRenkler.error))
                                            : Text(t,
                                                style: const TextStyle(
                                                    fontSize: 22,
                                                    fontWeight: FontWeight.w600)),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ))
                    .toList(),
              ))
          .toList(),
    );
  }
}
