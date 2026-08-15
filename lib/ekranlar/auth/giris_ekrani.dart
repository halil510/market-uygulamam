// lib/ekranlar/auth/giris_ekrani.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:go_router/go_router.dart';
import '../../saglayicilar/riverpod/auth_provider.dart';
import '../../depolar/kullanici_deposu.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../cekirdek/sabitler/uygulama_sabitleri.dart';

class GirisEkrani extends ConsumerStatefulWidget {
  const GirisEkrani({super.key});
  @override
  ConsumerState<GirisEkrani> createState() => _GirisEkraniState();
}

class _GirisEkraniState extends ConsumerState<GirisEkrani>
    with SingleTickerProviderStateMixin {
  final _sifre          = ValueNotifier<String>('');
  final _hata           = ValueNotifier<String>('');
  final _yukleniyor     = ValueNotifier<bool>(false);
  final _kilitli        = ValueNotifier<bool>(false);
  final _kullanicilar   = ValueNotifier<List<String>>([]);
  final _seciliKullanici = ValueNotifier<String>('admin');

  int _hataliGiris = 0;
  DateTime? _kilitBitis;
  late AnimationController _shakeCtrl;
  late Animation<double>   _shakeAnim;
  late AnimationController _nabizCtrl;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _shakeAnim = Tween<double>(begin: 0, end: 8)
        .chain(CurveTween(curve: Curves.elasticIn))
        .animate(_shakeCtrl);
    // Modern bankacılık uygulamalarındaki gibi yumuşak "nefes alma"
    // efekti — parmak izi butonunun canlı/tıklanabilir hissettirmesi için.
    _nabizCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
    _kullanicilariYukle();
    _biyometrikKontrolEt();
  }

  // Kullanıcı isteği: "şifre ekranında biyometrik giriş, parmak izi
  // okutarak" — cihazda parmak izi/yüz tanıma destekleniyorsa VE daha
  // önce kaydedilmiş bir kullanıcı/şifre varsa, "Parmak İzi ile Giriş"
  // seçeneği gösteriliyor.
  final _localAuth = LocalAuthentication();
  bool _biyometrikMevcut = false;
  bool _biyometrikDestekli = false; // cihaz destekliyor ama henüz kayıtlı bilgi yok

  Future<void> _biyometrikKontrolEt() async {
    try {
      final destekleniyor = await _localAuth.isDeviceSupported();
      // ÖNCEDEN sadece canCheckBiometrics kontrol ediliyordu — bu bazı
      // cihazlarda (özellikle üretici özelleştirmesi olan Android
      // cihazlarda) yanıltıcı olabiliyor. local_auth'un önerdiği daha
      // sağlam yöntem: getAvailableBiometrics() ile GERÇEKTEN
      // kayıtlı bir biyometrik yöntem olup olmadığını kontrol etmek.
      final mevcutBiyometrikler = await _localAuth.getAvailableBiometrics();
      const secure = FlutterSecureStorage();
      final kayitliSifre = await secure.read(key: 'biyometrik_sifre');
      if (kDebugMode) {
        debugPrint('[Biyometrik] destekleniyor=$destekleniyor, '
            'mevcutBiyometrikler=$mevcutBiyometrikler, '
            'kayitliSifreVarMi=${kayitliSifre != null}');
      }
      if (mounted) {
        setState(() {
          _biyometrikDestekli = destekleniyor && mevcutBiyometrikler.isNotEmpty;
          _biyometrikMevcut = _biyometrikDestekli && kayitliSifre != null;
        });
      }
    } catch (e, st) {
      // ÖNCEDEN hata sessizce yutuluyordu, ne olduğu hiç görünmüyordu.
      // Artık en azından debug modda gerçek hata görülebiliyor.
      if (kDebugMode) debugPrint('[Biyometrik] Kontrol hatası: $e\n$st');
      if (mounted) setState(() { _biyometrikMevcut = false; _biyometrikDestekli = false; });
    }
  }

  Future<void> _biyometrikGirisYap() async {
    try {
      if (kDebugMode) debugPrint('[Biyometrik] authenticate() çağrılıyor...');
      final basarili = await _localAuth.authenticate(
        localizedReason: 'Giriş yapmak için parmak izinizi okutun',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      if (kDebugMode) debugPrint('[Biyometrik] authenticate() sonucu: $basarili');
      if (!basarili || !mounted) return;

      const secure = FlutterSecureStorage();
      final kayitliKullanici = await secure.read(key: 'kullanici_adi');
      final kayitliSifre     = await secure.read(key: 'biyometrik_sifre');
      if (kDebugMode) {
        debugPrint('[Biyometrik] kayitliKullanici=$kayitliKullanici, '
            'kayitliSifreVarMi=${kayitliSifre != null}');
      }
      if (kayitliKullanici == null || kayitliSifre == null) {
        // ÖNCEDEN BURADA HİÇBİR ŞEY GÖSTERİLMEDEN sessizce return
        // ediliyordu — parmak izi başarılı olduğu halde kullanıcı
        // hiçbir geri bildirim görmüyordu, "parmak izi tarandı ama
        // giriş yapmadı" hissi tam olarak buradan kaynaklanıyor olabilir.
        if (mounted) {
          _hata.value = 'Kayıtlı giriş bilgisi bulunamadı. Lütfen '
              'önce şifrenizle bir kez giriş yapın.';
        }
        return;
      }

      _yukleniyor.value = true;
      if (kDebugMode) debugPrint('[Biyometrik] girisYap çağrılıyor: $kayitliKullanici');
      final sonuc = await ref.read(authProvider.notifier)
          .girisYap(kayitliKullanici, kayitliSifre);
      if (kDebugMode) debugPrint('[Biyometrik] girisYap sonucu: $sonuc');
      if (!mounted) return;
      _yukleniyor.value = false;
      if (sonuc == GirisSonucu.basarili) {
        if (mounted) context.go('/');
      } else if (mounted) {
        // ÖNCEDEN burada hangi GirisSonucu döndüğü görünmüyordu —
        // artık debug modda net şekilde görülebiliyor.
        _hata.value = kDebugMode
            ? 'Parmak izi ile giriş başarısız (sonuç: $sonuc) — '
              'kayıtlı şifreniz değişmiş olabilir, şifrenizle giriş yapın'
            : 'Parmak izi ile giriş başarısız — şifrenizle giriş yapın';
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Biyometrik] Giriş hatası: $e');
      _yukleniyor.value = false;
      if (mounted) {
        _hata.value = kDebugMode
            ? 'Parmak izi hatası: $e'
            : 'Parmak izi doğrulanamadı';
      }
    }
  }

  @override
  void dispose() {
    _sifre.dispose(); _hata.dispose(); _yukleniyor.dispose();
    _kilitli.dispose(); _kullanicilar.dispose(); _seciliKullanici.dispose();
    _shakeCtrl.dispose();
    _nabizCtrl.dispose();
    super.dispose();
  }

  Future<void> _kullanicilariYukle() async {
    try {
      final liste = await KullaniciDeposu().tumunuGetir();
      _kullanicilar.value = liste.map((k) => k.kullaniciAdi).toList();
      const secure = FlutterSecureStorage();
      final sonKullanici = await secure.read(key: 'kullanici_adi');
      if (sonKullanici != null && _kullanicilar.value.contains(sonKullanici)) {
        _seciliKullanici.value = sonKullanici;
        return;
      }
      if (_kullanicilar.value.isNotEmpty &&
          !_kullanicilar.value.contains(_seciliKullanici.value)) {
        _seciliKullanici.value = _kullanicilar.value.first;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Kullanıcı yükleme hatası: $e');
    }
  }

  void _rakamEkle(String r) { if (_sifre.value.length < 12) _sifre.value += r; }
  void _silSon() {
    if (_sifre.value.isNotEmpty)
      _sifre.value = _sifre.value.substring(0, _sifre.value.length - 1);
  }
  void _temizle() => _sifre.value = '';

  Future<void> _girisYap() async {
    if (_kilitli.value && _kilitBitis != null) {
      if (DateTime.now().isBefore(_kilitBitis!)) {
        final kalan = _kilitBitis!.difference(DateTime.now()).inSeconds;
        _hata.value = 'Kilitli — $kalan saniye bekleyin';
        return;
      }
      _kilitli.value = false;
      _hataliGiris   = 0;
      _hata.value    = '';
    }
    if (_sifre.value.isEmpty) {
      _hata.value = 'Şifre girin';
      _shakeCtrl.forward(from: 0);
      return;
    }
    _yukleniyor.value = true;
    _hata.value = '';
    try {
      // DÜZELTME: authProvider.notifier kullan (AuthNotifier singleton değil)
      final sonuc = await ref.read(authProvider.notifier)
          .girisYap(_seciliKullanici.value, _sifre.value);
      if (!mounted) return;

      if (sonuc == GirisSonucu.basarili) {
        _hataliGiris   = 0;
        _kilitli.value = false;
        // SecureStorage'a son kullanıcıyı kaydet
        const secure = FlutterSecureStorage();
        await secure.write(key: 'kullanici_adi', value: _seciliKullanici.value);
        // Kullanıcı isteği: parmak izi ile giriş — bunun için şifre de
        // güvenli depoya (Android Keystore ile şifrelenmiş) kaydediliyor.
        // Sadece biyometrik doğrulama BAŞARILI olduktan sonra okunuyor.
        await secure.write(key: 'biyometrik_sifre', value: _sifre.value);
        if (mounted) context.go('/');
      } else if (sonuc == GirisSonucu.kilitli) {
        _kilitli.value = true;
        _kilitBitis = DateTime.now()
            .add(const Duration(seconds: UygSabitler.kilitSureSaniye));
        _hata.value = '${UygSabitler.kilitSureSaniye} saniye beklemeniz gerekiyor.';
        _sifre.value = '';
      } else {
        _hataliGiris++;
        _sifre.value = '';
        _shakeCtrl.forward(from: 0);
        const maxGiris = UygSabitler.maxHataliGiris;
        if (_hataliGiris >= maxGiris) {
          _kilitli.value = true;
          _kilitBitis = DateTime.now()
              .add(const Duration(seconds: UygSabitler.kilitSureSaniye));
          _hata.value = '${UygSabitler.kilitSureSaniye} saniye beklemeniz gerekiyor.';
        } else {
          _hata.value = 'Hatalı şifre ($_hataliGiris/$maxGiris)';
        }
      }
    } catch (e) {
      if (mounted) _hata.value = 'Bağlantı hatası: $e';
    } finally {
      if (mounted) _yukleniyor.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end:   Alignment.bottomRight,
            colors: [Color(0xFF1A237E), Color(0xFF283593), Color(0xFF3949AB)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(children: [
                  // Logo
                  Container(
                    width: 90, height: 90,
                    decoration: BoxDecoration(
                      color:  Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 20)],
                    ),
                    child: ClipOval(
                      child: Image.asset('assets/images/logo.png',
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.storefront_rounded, size: 44, color: Color(0xFF3949AB))),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('BarkoPro',
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900,
                          color: Colors.white, letterSpacing: 1.2)),
                  const SizedBox(height: 4),
                  Text('Profesyonel Market Yönetimi',
                      style: TextStyle(fontSize: 13, color: Color(0xB2FFFFFF))),
                  const SizedBox(height: 32),

                  // Giriş Kartı
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [BoxShadow(color: Color(0x33000000),
                          blurRadius: 30, offset: const Offset(0, 10))],
                    ),
                    padding: const EdgeInsets.all(24),
                    child: Column(children: [
                      // Kullanıcı Seçici
                      ValueListenableBuilder<List<String>>(
                        valueListenable: _kullanicilar,
                        builder: (_, liste, __) {
                          if (liste.isEmpty) return const SizedBox();
                          return ValueListenableBuilder<String>(
                            valueListenable: _seciliKullanici,
                            builder: (_, secili, __) => DropdownButtonFormField<String>(
                              value: liste.contains(secili) ? secili : liste.first,
                              decoration: InputDecoration(
                                labelText: 'Kullanıcı',
                                prefixIcon: const Icon(Icons.person_outline, color: AppRenkler.primary),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: context.borderColor)),
                              ),
                              items: liste.map((k) => DropdownMenuItem(value: k, child: Text(k))).toList(),
                              onChanged: (v) {
                                if (v != null) {
                                  _seciliKullanici.value = v;
                                  _sifre.value = '';
                                  _hata.value  = '';
                                }
                              },
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 16),

                      // PIN Göstergesi
                      ValueListenableBuilder<String>(
                        valueListenable: _sifre,
                        builder: (_, pin, __) => AnimatedBuilder(
                          animation: _shakeAnim,
                          builder: (_, child) => Transform.translate(
                            offset: Offset(_shakeAnim.value * (pin.isEmpty ? 0 : 1), 0),
                            child: child,
                          ),
                          child: ValueListenableBuilder<String>(
                            valueListenable: _hata,
                            builder: (_, hata, __) => Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(
                                color: hata.isNotEmpty ? Colors.red.shade50 : context.borderColor,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: hata.isNotEmpty ? Colors.red.shade300 : context.borderColor),
                              ),
                              child: pin.isEmpty
                                  ? Text('Şifrenizi girin',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: context.textSecondary, fontSize: 14))
                                  : Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: List.generate(pin.length, (_) => Container(
                                        width: 12, height: 12,
                                        margin: const EdgeInsets.symmetric(horizontal: 4),
                                        decoration: const BoxDecoration(
                                            color: AppRenkler.primary, shape: BoxShape.circle),
                                      ))),
                            ),
                          ),
                        ),
                      ),

                      // Hata Mesajı
                      ValueListenableBuilder<String>(
                        valueListenable: _hata,
                        builder: (_, hata, __) {
                          if (hata.isEmpty) return const SizedBox(height: 8);
                          return Padding(
                            padding: const EdgeInsets.only(top: 8, bottom: 4),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.red.shade200)),
                              child: Row(children: [
                                const Icon(Icons.error_outline, color: Colors.red, size: 16),
                                const SizedBox(width: 6),
                                Expanded(child: Text(hata,
                                    style: const TextStyle(fontSize: 12, color: Colors.red))),
                              ]),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 12),

                      // NumPad
                      ValueListenableBuilder<bool>(
                        valueListenable: _kilitli,
                        builder: (_, kilitli, __) => _NumPad(
                          onRakam:   kilitli ? (_) {} : _rakamEkle,
                          onSil:     kilitli ? () {}  : _silSon,
                          onSifirla: kilitli ? () {}  : _temizle,
                          kilitli:   kilitli,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Giriş Butonu
                      ValueListenableBuilder<bool>(
                        valueListenable: _yukleniyor,
                        builder: (_, yuk, __) => ValueListenableBuilder<bool>(
                          valueListenable: _kilitli,
                          builder: (_, kit, __) => ValueListenableBuilder<String>(
                            valueListenable: _sifre,
                            builder: (_, pin, __) => SizedBox(width: double.infinity, height: 52, child: FilledButton(
                                onPressed: (yuk || kit || pin.isEmpty) ? null : _girisYap,
                                style: FilledButton.styleFrom(
                                  foregroundColor: Colors.white,
          backgroundColor: AppRenkler.primary,
                                  disabledBackgroundColor: context.borderColor,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14)),
                                  elevation: 0,
                                ),
                                child: yuk
                                    ? const SizedBox(width: 22, height: 22,
                                        child: CircularProgressIndicator(
                                            color: Colors.white, strokeWidth: 2.5))
                                    : const Text('Giriş Yap',
                                        style: TextStyle(fontSize: 16,
                                            fontWeight: FontWeight.w700, color: Colors.white)),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Kullanıcı isteği: parmak izi ile giriş — sadece
                      // cihaz destekliyorsa ve daha önce başarılı bir
                      // girişten kalma kayıtlı bilgi varsa gösteriliyor.
                      // 🔴 TASARIM YENİLEMESİ (kullanıcı isteği — "daha iyi
                      // tasarım olabilir"): ÖNCEDEN düz, kutu şeklinde bir
                      // "Parmak İzi ile Giriş" butonuydu. Artık modern
                      // bankacılık uygulamalarındaki gibi, hafif "nefes
                      // alan" (nabız) bir halkayla çevrili, dairesel/belirgin
                      // bir simge butonu — hem daha şık hem de "buraya
                      // dokun" hissini daha net veriyor.
                      if (_biyometrikMevcut) ...[
                        const SizedBox(height: 20),
                        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Column(children: [
                            AnimatedBuilder(
                              animation: _nabizCtrl,
                              builder: (_, child) {
                                final t = _nabizCtrl.value; // 0 -> 1 -> 0
                                return Container(
                                  padding: EdgeInsets.all(6 + t * 4),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Color.lerp(Colors.white24, Colors.white70, t)!,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: child,
                                );
                              },
                              child: Material(
                                color: Colors.white,
                                shape: const CircleBorder(),
                                elevation: 4,
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: _biyometrikGirisYap,
                                  child: const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Icon(Icons.fingerprint, size: 32, color: Color(0xFF3949AB)),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text('Parmak İzi ile Giriş',
                                style: TextStyle(color: Colors.white.withAlpha(230),
                                    fontSize: 12.5, fontWeight: FontWeight.w600)),
                          ]),
                        ]),
                      ] else if (_biyometrikDestekli) ...[
                        // "Parmak izi tanıtma nerede olacak?" sorusuna
                        // cevap: burada — henüz ilk kez şifreyle giriş
                        // yapılmadığı için buton görünmüyor. Artık düz bir
                        // metin satırı yerine, kesikli çerçeveli, ikonlu
                        // bir "ipucu kartı" — kullanıcının bunu bir hata
                        // değil, tasarımın bir parçası olarak fark etmesi
                        // için.
                        const SizedBox(height: 14),
                        DottedBorderKutu(
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.fingerprint, size: 18, color: Colors.white.withAlpha(160)),
                            const SizedBox(width: 8),
                            Flexible(child: Text(
                                'Şifreyle bir kez giriş yapın, bir sonrakinde '
                                'parmak izi seçeneği burada görünecek',
                                style: TextStyle(fontSize: 11.5, color: Colors.white.withAlpha(180), height: 1.3),
                                textAlign: TextAlign.center)),
                          ]),
                        ),
                      ],
                    ]),
                  ),
                  const SizedBox(height: 24),
                  Text('v${UygSabitler.versiyon}',
                      style: TextStyle(color: Color(0x66FFFFFF), fontSize: 11)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Kesikli çerçeveli, yuvarlak köşeli bir kutu — harici paket eklemeden
/// (dotted_border vb.) basit bir CustomPainter ile. Biyometrik "henüz
/// tanıtılmadı" ipucu kartında kullanılıyor.
class DottedBorderKutu extends StatelessWidget {
  final Widget child;
  const DottedBorderKutu({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _KesikliCerceve(renk: Colors.white.withAlpha(90)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: child,
      ),
    );
  }
}

class _KesikliCerceve extends CustomPainter {
  final Color renk;
  _KesikliCerceve({required this.renk});

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
        Offset.zero & size, const Radius.circular(14));
    final paint = Paint()
      ..color = renk
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    const dashUzunluk = 5.0, bosluk = 4.0;
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var mesafe = 0.0;
      while (mesafe < metric.length) {
        final sonraki = mesafe + dashUzunluk;
        canvas.drawPath(
            metric.extractPath(mesafe, sonraki.clamp(0, metric.length)), paint);
        mesafe = sonraki + bosluk;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _KesikliCerceve oldDelegate) => oldDelegate.renk != renk;
}

class _NumPad extends StatelessWidget {
  final void Function(String) onRakam;
  final VoidCallback onSil;
  final VoidCallback onSifirla;
  final bool kilitli;
  const _NumPad({required this.onRakam, required this.onSil,
    required this.onSifirla, this.kilitli = false});

  @override
  Widget build(BuildContext context) {
    const tuslar = [['1','2','3'],['4','5','6'],['7','8','9'],['C','0','⌫']];
    return Opacity(
      opacity: kilitli ? 0.4 : 1.0,
      child: Column(
        children: tuslar.map((satir) => Row(
          children: satir.map((t) => Expanded(
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Material(
                color: t == 'C'
                    ? Colors.red.shade50
                    : t == '⌫' ? Colors.orange.shade50 : context.borderColor,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    if (t == '⌫') onSil();
                    else if (t == 'C') onSifirla();
                    else onRakam(t);
                  },
                  child: Container(
                    height: 54, alignment: Alignment.center,
                    child: t == '⌫'
                        ? const Icon(Icons.backspace_outlined, color: Colors.orange, size: 22)
                        : t == 'C'
                            ? const Text('C', style: TextStyle(fontSize: 18,
                                fontWeight: FontWeight.w700, color: Colors.red))
                            : Text(t, style: const TextStyle(
                                fontSize: 24, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ),
          )).toList(),
        )).toList(),
      ),
    );
  }
}
