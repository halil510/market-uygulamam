// lib/ekranlar/auth/giris_ekrani.dart
// Modern, profesyonel ve animasyonlu giriş ekranı
// - Akıcı sayfa geçişleri ve mikro etkileşimler
// - Yüksek performans (ValueNotifier + minimal setState)
// - Parmak izi / biyometrik destekli (pulse animasyonu)
// - Responsive ve şık tasarım

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
  // ─── ValueNotifier'lar (performans için) ────────────────────────────────
  final _sifre = ValueNotifier<String>('');
  final _hata = ValueNotifier<String>('');
  final _yukleniyor = ValueNotifier<bool>(false);
  final _kilitli = ValueNotifier<bool>(false);
  final _kullanicilar = ValueNotifier<List<String>>([]);
  final _seciliKullanici = ValueNotifier<String>('admin');

  // ─── Durum değişkenleri ──────────────────────────────────────────────────
  int _hataliGiris = 0;
  DateTime? _kilitBitis;

  // ─── Animasyon controller'ları ──────────────────────────────────────────
  late AnimationController _shakeCtrl;
  late Animation<double> _shakeAnim;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;
  late AnimationController _scaleCtrl;
  late Animation<double> _scaleAnim;

  // ─── Biyometrik ──────────────────────────────────────────────────────────
  final _localAuth = LocalAuthentication();
  bool _biyometrikMevcut = false;
  bool _biyometrikDestekli = false;

  // ─── INIT ──────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();

    // Sayfa açılış animasyonları
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnim = CurvedAnimation(
      parent: _fadeCtrl,
      curve: Curves.easeOut,
    );

    _scaleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleAnim = CurvedAnimation(
      parent: _scaleCtrl,
      curve: Curves.easeOutBack,
    );

    // Sallama animasyonu (hata durumu)
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeAnim = Tween<double>(begin: 0, end: 12)
        .chain(CurveTween(curve: Curves.elasticIn))
        .animate(_shakeCtrl);

    // Parmak izi nabız (pulse) animasyonu
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    // Verileri yükle
    _kullanicilariYukle();
    _biyometrikKontrolEt();

    // Animasyonları başlat
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fadeCtrl.forward();
      _scaleCtrl.forward();
    });
  }

  @override
  void dispose() {
    _sifre.dispose();
    _hata.dispose();
    _yukleniyor.dispose();
    _kilitli.dispose();
    _kullanicilar.dispose();
    _seciliKullanici.dispose();
    _shakeCtrl.dispose();
    _pulseCtrl.dispose();
    _fadeCtrl.dispose();
    _scaleCtrl.dispose();
    super.dispose();
  }

  // ─── VERİ YÜKLEME ────────────────────────────────────────────────────────
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
      if (_kullanicilar.value.isNotEmpty) {
        _seciliKullanici.value = _kullanicilar.value.first;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Kullanıcı yükleme hatası: $e');
    }
  }

  Future<void> _biyometrikKontrolEt() async {
    try {
      final destekleniyor = await _localAuth.isDeviceSupported();
      final mevcutBiyometrikler = await _localAuth.getAvailableBiometrics();
      const secure = FlutterSecureStorage();
      final kayitliSifre = await secure.read(key: 'biyometrik_sifre');

      if (mounted) {
        setState(() {
          _biyometrikDestekli = destekleniyor && mevcutBiyometrikler.isNotEmpty;
          _biyometrikMevcut = _biyometrikDestekli && kayitliSifre != null;
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Biyometrik kontrol hatası: $e');
      if (mounted) setState(() {
        _biyometrikMevcut = false;
        _biyometrikDestekli = false;
      });
    }
  }

  // ─── BİYOMETRİK GİRİŞ ──────────────────────────────────────────────────
  Future<void> _biyometrikGirisYap() async {
    if (!_biyometrikMevcut) return;
    try {
      final basarili = await _localAuth.authenticate(
        localizedReason: 'Giriş yapmak için parmak izinizi okutun',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      if (!basarili || !mounted) return;

      const secure = FlutterSecureStorage();
      final kayitliKullanici = await secure.read(key: 'kullanici_adi');
      final kayitliSifre = await secure.read(key: 'biyometrik_sifre');
      if (kayitliKullanici == null || kayitliSifre == null) {
        _hata.value = 'Kayıtlı giriş bilgisi bulunamadı. Lütfen önce şifrenizle giriş yapın.';
        return;
      }

      _yukleniyor.value = true;
      final sonuc = await ref.read(authProvider.notifier)
          .girisYap(kayitliKullanici, kayitliSifre);
      if (!mounted) return;
      _yukleniyor.value = false;

      if (sonuc == GirisSonucu.basarili) {
        if (mounted) context.go('/');
      } else {
        _hata.value = 'Parmak izi ile giriş başarısız. Şifrenizle giriş yapın.';
      }
    } catch (e) {
      _yukleniyor.value = false;
      if (mounted) {
        _hata.value = kDebugMode ? 'Parmak izi hatası: $e' : 'Parmak izi doğrulanamadı';
      }
    }
  }

  // ─── NUM PAD ──────────────────────────────────────────────────────────────
  void _rakamEkle(String r) {
    if (_sifre.value.length < 12) _sifre.value += r;
  }

  void _silSon() {
    if (_sifre.value.isNotEmpty) {
      _sifre.value = _sifre.value.substring(0, _sifre.value.length - 1);
    }
  }

  void _temizle() => _sifre.value = '';

  // ─── GİRİŞ İŞLEMİ ───────────────────────────────────────────────────────
  Future<void> _girisYap() async {
    if (_kilitli.value && _kilitBitis != null) {
      if (DateTime.now().isBefore(_kilitBitis!)) {
        final kalan = _kilitBitis!.difference(DateTime.now()).inSeconds;
        _hata.value = 'Kilitli — $kalan saniye bekleyin';
        return;
      }
      _kilitli.value = false;
      _hataliGiris = 0;
      _hata.value = '';
    }

    if (_sifre.value.isEmpty) {
      _hata.value = 'Şifre girin';
      _shakeCtrl.forward(from: 0);
      return;
    }

    _yukleniyor.value = true;
    _hata.value = '';

    try {
      final sonuc = await ref.read(authProvider.notifier)
          .girisYap(_seciliKullanici.value, _sifre.value);
      if (!mounted) return;

      if (sonuc == GirisSonucu.basarili) {
        _hataliGiris = 0;
        _kilitli.value = false;
        const secure = FlutterSecureStorage();
        await secure.write(key: 'kullanici_adi', value: _seciliKullanici.value);
        await secure.write(key: 'biyometrik_sifre', value: _sifre.value);
        if (mounted) context.go('/');
      } else if (sonuc == GirisSonucu.kilitli) {
        _kilitli.value = true;
        _kilitBitis = DateTime.now()
            .add(const Duration(seconds: UygSabitler.kilitSureSaniye));
        _hata.value = '${UygSabitler.kilitSureSaniye} saniye bekleyin.';
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
          _hata.value = '${UygSabitler.kilitSureSaniye} saniye bekleyin.';
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

  // ─── BUILD ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0F172A),
              Color(0xFF1E293B),
              Color(0xFF334155),
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: ScaleTransition(
                    scale: _scaleAnim,
                    child: _buildCard(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── GİRİŞ KARTI ────────────────────────────────────────────────────────
  Widget _buildCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(235),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(60),
            blurRadius: 40,
            offset: const Offset(0, 16),
          ),
          BoxShadow(
            color: Colors.black.withAlpha(30),
            blurRadius: 80,
            offset: const Offset(0, 30),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Logo ──────────────────────────────────────────────────────────
          _buildLogo(),

          const SizedBox(height: 8),
          Text(
            'Hoş Geldiniz',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF0F172A),
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Hesabınıza giriş yapın',
            style: TextStyle(
              fontSize: 13,
              color: const Color(0xFF64748B),
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 24),

          // ── Kullanıcı Seçici ─────────────────────────────────────────────
          _buildKullaniciSecici(),
          const SizedBox(height: 20),

          // ── PIN Göstergesi ──────────────────────────────────────────────
          _buildPinGosterge(),
          const SizedBox(height: 16),

          // ── Hata Mesajı ──────────────────────────────────────────────────
          _buildHataMesaji(),
          const SizedBox(height: 12),

          // ── NumPad ──────────────────────────────────────────────────────
          _buildNumPad(),
          const SizedBox(height: 16),

          // ── Giriş Butonu ────────────────────────────────────────────────
          _buildGirisButonu(),
          const SizedBox(height: 12),

          // ── Parmak İzi ──────────────────────────────────────────────────
          _buildBiometricButton(),

          const SizedBox(height: 6),
          Text(
            'v${UygSabitler.versiyon}',
            style: TextStyle(
              color: const Color(0xFF94A3B8),
              fontSize: 11,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  // ─── LOGO ──────────────────────────────────────────────────────────────────
  Widget _buildLogo() {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4361EE), Color(0xFF3A0CA3)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4361EE).withAlpha(80),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipOval(
        child: Image.asset(
          'assets/images/logo.png',
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Icon(
            Icons.storefront_rounded,
            color: Colors.white,
            size: 36,
          ),
        ),
      ),
    );
  }

  // ─── KULLANICI SEÇİCİ ──────────────────────────────────────────────────
  Widget _buildKullaniciSecici() {
    return ValueListenableBuilder<List<String>>(
      valueListenable: _kullanicilar,
      builder: (_, liste, __) {
        if (liste.isEmpty) return const SizedBox.shrink();
        return ValueListenableBuilder<String>(
          valueListenable: _seciliKullanici,
          builder: (_, secili, __) => Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: DropdownButtonFormField<String>(
              value: liste.contains(secili) ? secili : liste.first,
              isExpanded: true,
              icon: const Icon(Icons.expand_more, color: Color(0xFF64748B)),
              dropdownColor: Colors.white,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                prefixIcon: Icon(Icons.person_outline, color: Color(0xFF4361EE)),
              ),
              items: liste.map((k) {
                return DropdownMenuItem(
                  value: k,
                  child: Text(k),
                );
              }).toList(),
              onChanged: (v) {
                if (v != null) {
                  _seciliKullanici.value = v;
                  _sifre.value = '';
                  _hata.value = '';
                }
              },
            ),
          ),
        );
      },
    );
  }

  // ─── PIN GÖSTERGESİ ──────────────────────────────────────────────────────
  Widget _buildPinGosterge() {
    return ValueListenableBuilder<String>(
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
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              color: hata.isNotEmpty
                  ? const Color(0xFFFFF1F0)
                  : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: hata.isNotEmpty
                    ? const Color(0xFFFECACA)
                    : const Color(0xFFE2E8F0),
                width: hata.isNotEmpty ? 1.5 : 1,
              ),
            ),
            child: pin.isEmpty
                ? Text(
                    'Şifrenizi girin',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: const Color(0xFF94A3B8),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      pin.length,
                      (i) => Container(
                        width: 14,
                        height: 14,
                        margin: const EdgeInsets.symmetric(horizontal: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4361EE),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF4361EE).withAlpha(60),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  // ─── HATA MESAJI ──────────────────────────────────────────────────────────
  Widget _buildHataMesaji() {
    return ValueListenableBuilder<String>(
      valueListenable: _hata,
      builder: (_, hata, __) {
        if (hata.isEmpty) return const SizedBox.shrink();
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF1F0),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFECACA)),
          ),
          child: Row(
            children: [
              const Icon(Icons.error_outline, color: Color(0xFFDC2626), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hata,
                  style: const TextStyle(
                    color: Color(0xFFDC2626),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── NUM PAD ──────────────────────────────────────────────────────────────
  Widget _buildNumPad() {
    const tuslar = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['C', '0', '⌫'],
    ];

    return ValueListenableBuilder<bool>(
      valueListenable: _kilitli,
      builder: (_, kilitli, __) => Opacity(
        opacity: kilitli ? 0.4 : 1.0,
        child: Column(
          children: tuslar.map((satir) {
            return Row(
              children: satir.map((t) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: _buildNumTusu(t, kilitli),
                  ),
                );
              }).toList(),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildNumTusu(String t, bool kilitli) {
    final isSil = t == '⌫';
    final isTemizle = t == 'C';
    final isRakam = !isSil && !isTemizle;

    return Material(
      color: isTemizle
          ? const Color(0xFFFEE2E2)
          : isSil
              ? const Color(0xFFFFF3E0)
              : const Color(0xFFF1F5F9),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: kilitli
            ? null
            : () {
                if (isSil) _silSon();
                else if (isTemizle) _temizle();
                else _rakamEkle(t);
              },
        child: Container(
          height: 58,
          alignment: Alignment.center,
          child: isSil
              ? const Icon(Icons.backspace_outlined,
                  color: Color(0xFFF57C00), size: 24)
              : isTemizle
                  ? const Text('C',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFDC2626),
                      ))
                  : Text(t,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0F172A),
                      )),
        ),
      ),
    );
  }

  // ─── GİRİŞ BUTONU ────────────────────────────────────────────────────────
  Widget _buildGirisButonu() {
    return ValueListenableBuilder<bool>(
      valueListenable: _yukleniyor,
      builder: (_, yukleniyor, __) => ValueListenableBuilder<bool>(
        valueListenable: _kilitli,
        builder: (_, kilitli, __) => ValueListenableBuilder<String>(
          valueListenable: _sifre,
          builder: (_, pin, __) => SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton(
              onPressed: (yukleniyor || kilitli || pin.isEmpty) ? null : _girisYap,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF4361EE),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
                disabledBackgroundColor: const Color(0xFFCBD5E1),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
              child: yukleniyor
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : const Text('Giriş Yap'),
            ),
          ),
        ),
      ),
    );
  }

  // ─── PARMAK İZİ BUTONU ──────────────────────────────────────────────────
  Widget _buildBiometricButton() {
    if (_biyometrikMevcut) {
      return Column(
        children: [
          const Divider(height: 24, thickness: 0.5, color: Color(0xFFE2E8F0)),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedBuilder(
                animation: _pulseCtrl,
                builder: (_, child) {
                  final t = _pulseCtrl.value;
                  return Container(
                    padding: EdgeInsets.all(6 + t * 4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Color.lerp(
                          const Color(0xFF94A3B8),
                          const Color(0xFF4361EE),
                          t,
                        )!,
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
                      padding: EdgeInsets.all(14),
                      child: Icon(
                        Icons.fingerprint,
                        size: 28,
                        color: Color(0xFF4361EE),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Parmak İzi ile Giriş',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF475569),
                ),
              ),
            ],
          ),
        ],
      );
    } else if (_biyometrikDestekli) {
      // Henüz kayıt yoksa bilgi mesajı
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.fingerprint, size: 18, color: const Color(0xFF94A3B8)),
            const SizedBox(width: 8),
            const Text(
              'Şifreyle giriş yapın, parmak izi aktifleşsin',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF94A3B8),
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }
}