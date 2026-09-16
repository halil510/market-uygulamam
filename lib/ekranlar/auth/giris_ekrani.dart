// lib/ekranlar/auth/giris_ekrani.dart
// Modern, profesyonel ve animasyonlu giriş ekranı
// - Akıcı sayfa geçişleri ve mikro etkileşimler
// - Yüksek performans (ValueNotifier + minimal setState)
// - Parmak izi / biyometrik destekli (pulse animasyonu)
// - Responsive ve şık tasarım

import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:go_router/go_router.dart';

import '../../saglayicilar/riverpod/auth_provider.dart';
import '../../depolar/kullanici_deposu.dart';
import '../../servisler/auth_servisi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../cekirdek/sabitler/uygulama_sabitleri.dart';

// Secure storage anahtarları — biyometrik giriş.
// 🔴 GÜVENLİK DÜZELTMESİ: 'biyometrik_sifre' anahtarı ÖNCEDEN kullanıcının
// ham şifresini saklıyordu. Artık şifre hiç saklanmıyor; sadece rastgele,
// tuzlanmış hash'i DB'de tutulan bir token saklanıyor (bkz. AuthServisi.
// girisYapBiyometrikToken / BiyometrikDeposu). Eski anahtar sadece bir
// kereliğine sessizce yeni şemaya taşınıp siliniyor (bkz. _biyometrikKontrolEt).
const _eskiBiyometrikSifreAnahtari = 'biyometrik_sifre';
const _biyometrikTokenAnahtari = 'biyometrik_token';

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

      var kayitliToken = await secure.read(key: _biyometrikTokenAnahtari);
      kayitliToken ??= await _eskiBiyometrikKaydiTasi(secure);

      if (mounted) {
        setState(() {
          _biyometrikDestekli = destekleniyor && mevcutBiyometrikler.isNotEmpty;
          _biyometrikMevcut = _biyometrikDestekli && kayitliToken != null;
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

  /// Bir önceki sürümden kalma, ham şifre içeren eski anahtarı bulursa
  /// sessizce yeni token şemasına taşır (kullanıcı yeniden "kaydolmak"
  /// zorunda kalmaz) ve eski anahtarı siler. Şifre yeni şemada HİÇ
  /// saklanmaz — sadece token üretmek için bir kereliğine kullanılır.
  Future<String?> _eskiBiyometrikKaydiTasi(FlutterSecureStorage secure) async {
    final eskiSifre = await secure.read(key: _eskiBiyometrikSifreAnahtari);
    final kullaniciAdi = await secure.read(key: 'kullanici_adi');
    if (eskiSifre == null || kullaniciAdi == null) {
      if (eskiSifre != null) await secure.delete(key: _eskiBiyometrikSifreAnahtari);
      return null;
    }
    try {
      final kullanici = await KullaniciDeposu().girisKontrol(kullaniciAdi, eskiSifre);
      if (kullanici?.id == null) {
        await secure.delete(key: _eskiBiyometrikSifreAnahtari);
        return null;
      }
      final token = await AuthServisi().biyometrikKaydet(kullanici!.id!);
      await secure.write(key: _biyometrikTokenAnahtari, value: token);
      await secure.delete(key: _eskiBiyometrikSifreAnahtari);
      return token;
    } catch (e) {
      if (kDebugMode) debugPrint('Biyometrik kayıt taşıma hatası: $e');
      await secure.delete(key: _eskiBiyometrikSifreAnahtari);
      return null;
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
      final kayitliToken = await secure.read(key: _biyometrikTokenAnahtari);
      if (kayitliKullanici == null || kayitliToken == null) {
        _hata.value = 'Kayıtlı giriş bilgisi bulunamadı. Lütfen önce şifrenizle giriş yapın.';
        return;
      }

      _yukleniyor.value = true;
      final sonuc = await ref.read(authProvider.notifier)
          .girisYapBiyometrik(kayitliKullanici, kayitliToken);
      if (!mounted) return;
      _yukleniyor.value = false;

      if (sonuc == GirisSonucu.basarili) {
        if (mounted) await _girisSonrasiYonlendir();
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

  // ─── MASTER ERP DEEP AUDIT — Madde 17 (Authentication) sertleştirmesi ──
  // ÖNCEDEN: admin hâlâ varsayılan "1234" şifresini kullanıyorsa sadece
  // Dashboard'da göz ardı edilebilir bir uyarı banner'ı gösteriliyordu —
  // kullanıcı bunu hiç kapatmadan sonsuza kadar uygulamayı kullanmaya
  // devam edebilirdi. Denetim dosyasının istediği "zorunlu parola
  // değişimi → 1234 tamamen geçersiz" akışı hiç yoktu. Artık başarılı
  // her girişten (şifre veya biyometrik) SONRA bu kontrol yapılıyor;
  // varsayılan şifre hâlâ kullanılıyorsa ana uygulamaya (`/`) DEĞİL,
  // geri tuşu kapalı zorunlu şifre değiştirme ekranına yönlendirilir.
  Future<void> _girisSonrasiYonlendir() async {
    final varsayilanSifre = await AuthServisi().varsayilanSifreKullaniliyorMu();
    if (!mounted) return;
    if (varsayilanSifre) {
      context.go('/sifre', extra: {'zorunlu': true});
    } else {
      context.go('/');
    }
  }

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
        // Şifre ARTIK saklanmıyor — sadece bu cihaza özel rastgele bir
        // token üretilip hash'i DB'de tutuluyor (bkz. AuthServisi.
        // biyometrikKaydet / BiyometrikDeposu).
        final userId = AuthServisi().aktifId;
        if (userId != null) {
          final token = await AuthServisi().biyometrikKaydet(userId);
          await secure.write(key: _biyometrikTokenAnahtari, value: token);
        }
        if (mounted) await _girisSonrasiYonlendir();
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
  // 🔴 KULLANICI İSTEĞİ — İKİ KATMANLI KART YAPISI TAMAMEN KALDIRILDI: bu
  // ekran önceden koyu gradyanlı TAM EKRAN bir arka plan ÜZERİNE, ayrıca
  // yuvarlak köşeli/gölgeli/neredeyse opak KENDİ arka planı olan (TsRenk
  // .kart(context).withAlpha(235)) tek büyük bir "kart" içine HER ŞEYİ
  // (logo, karşılama metni, kullanıcı seçici, PIN, numpad, buton, parmak
  // izi) gömüyordu — bu, "ekran içinde ekran" gibi görünen, istenmeyen bir
  // iki katmanlı görünüme yol açıyordu. Artık TEK, kesintisiz bir dikey
  // düzlem: üst kısım (logo/amblem + kullanıcı seçici + PIN göstergesi)
  // doğrudan gradyan arka planın üzerinde akıyor, alt kısım (numerik
  // klavye + giriş butonu + parmak izi) ekranın en altına gerçekten
  // KAYNAŞMIŞ, hafif buzlu-cam (BackdropFilter blur + %5-7 beyaz saydamlık)
  // tek bir panel. GÜVENLİK/VALUENOTIFIER ALTYAPISI (biyometrik token,
  // ValueNotifier'lar, şifreleme/kilit mantığı) HİÇ DOKUNULMADI — sadece
  // bu build() ve altındaki saf-görsel yardımcı widget'lar değişti.
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
        child: Stack(
          children: [
            // ── Dekoratif ışık lekeleri (derinlik hissi, salt görsel) ─────────
            Positioned(
              top: -80,
              left: -60,
              child: _buildGlowBlob(const Color(0xFF4361EE), 260),
            ),
            Positioned(
              bottom: -100,
              right: -70,
              child: _buildGlowBlob(const Color(0xFF3A0CA3), 300),
            ),
            SafeArea(
              child: FadeTransition(
                opacity: _fadeAnim,
                child: ScaleTransition(
                  scale: _scaleAnim,
                  child: Column(
                    children: [
                      // ── ÜST BÖLÜM: amblem + kullanıcı seçici + PIN ─────────
                      // Taşarsa kaydırılabilir (SingleChildScrollView) ama
                      // artık ayrı bir "kart" değil — arka planla TEK düzlem.
                      Expanded(
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(24, 28, 24, 8),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 420),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildLogo(),
                                  const SizedBox(height: 20),
                                  const Text(
                                    'Hoş Geldiniz',
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'Hesabınıza giriş yapın',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.white70,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                  const SizedBox(height: 28),
                                  _buildKullaniciSecici(),
                                  const SizedBox(height: 20),
                                  _buildPinGosterge(),
                                  const SizedBox(height: 10),
                                  _buildHataMesaji(),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      // ── ALT PANEL: numpad + giriş butonu + parmak izi ──────
                      _buildAltPanel(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlowBlob(Color renk, double boyut) {
    return IgnorePointer(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
        child: Container(
          width: boyut,
          height: boyut,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: renk.withAlpha(90),
          ),
        ),
      ),
    );
  }

  // ─── ALT PANEL (entegre numerik klavye) ─────────────────────────────────
  // Ekranın en alt kenarına KAYNAŞMIŞ, sadece üst köşeleri yuvarlatılmış,
  // hafif buzlu-cam (Glassmorphism) tek bir panel — üstteki bölümle AYNI
  // koyu gradyan arka planın devamı gibi görünür, ayrı bir "kart" DEĞİL.
  Widget _buildAltPanel() {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(14),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: const Border(
              top: BorderSide(color: Colors.white12, width: 1),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildNumPad(),
                  const SizedBox(height: 16),
                  _buildGirisButonu(),
                  const SizedBox(height: 12),
                  _buildBiometricButton(),
                  const SizedBox(height: 6),
                  Text(
                    'v${UygSabitler.versiyon}',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── LOGO ──────────────────────────────────────────────────────────────────
  // 🔴 KULLANICI İSTEĞİ (2026-09-16): "ekran hareketli olmasın" — sürekli
  // tekrar eden (infinite repeat) nabız animasyonu kaldırıldı, statik bir
  // halka ile değiştirildi. Tek seferlik açılış animasyonu (fade/scale)
  // ve hatalı şifrede sallanma KORUNDU — bunlar "sürekli hareket" değil.
  Widget _buildLogo() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: SweepGradient(
          colors: [
            Color(0x004361EE),
            Color(0xB44361EE),
            Color(0xB43A0CA3),
            Color(0x004361EE),
          ],
          stops: [0.0, 0.35, 0.65, 1.0],
        ),
      ),
      child: Container(
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
              color: const Color(0xFF4361EE).withAlpha(90),
              blurRadius: 28,
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
              color: Colors.white.withAlpha(18),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withAlpha(35)),
            ),
            child: DropdownButtonFormField<String>(
              value: liste.contains(secili) ? secili : liste.first,
              isExpanded: true,
              icon: const Icon(Icons.expand_more, color: Colors.white70),
              dropdownColor: const Color(0xFF1E293B),
              style: const TextStyle(
                color: Colors.white,
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
                  child: Text(k, style: const TextStyle(color: Colors.white)),
                );
              }).toList(),
              // 🔴 KULLANICI BULGUSU (2026-09-16): kapalı haldeki (seçili)
              // metin bazı Flutter/Material sürümlerinde 'style'
              // parametresini değil, ortamdaki (genelde koyu/siyah) form
              // temasını kullanıyordu — koyu arka plan üzerinde görünmez
              // hale geliyordu. selectedItemBuilder, kapalı haldeki
              // gösterimi tema/ortamdan bağımsız, açıkça beyaz olarak
              // sabitler.
              selectedItemBuilder: (context) => liste
                  .map((k) => Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          k,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ))
                  .toList(),
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
                  ? TsRenk.zemin(TsRenk.hata, opaklik: 0.18)
                  : Colors.white.withAlpha(14),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: hata.isNotEmpty
                    ? TsRenk.hata.withAlpha(140)
                    : Colors.white.withAlpha(30),
                width: hata.isNotEmpty ? 1.5 : 1,
              ),
            ),
            child: pin.isEmpty
                ? const Text(
                    'Şifrenizi girin',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      pin.length,
                      (i) => TweenAnimationBuilder<double>(
                        key: ValueKey('pin_dot_$i'),
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutBack,
                        builder: (_, deger, child) => Transform.scale(
                          scale: deger,
                          child: child,
                        ),
                        child: Container(
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
            color: TsRenk.zemin(TsRenk.hata),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: TsRenk.hata.withAlpha(120)),
          ),
          child: Row(
            children: [
              Icon(Icons.error_outline, color: TsRenk.hata, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hata,
                  style: TextStyle(
                    color: TsRenk.hata,
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
          ? TsRenk.zemin(TsRenk.hata, opaklik: 0.18)
          : isSil
              ? TsRenk.zemin(Colors.orange, opaklik: 0.18)
              : Colors.white.withAlpha(16),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: kilitli
            ? null
            : () {
                HapticFeedback.lightImpact();
                if (isSil) _silSon();
                else if (isTemizle) _temizle();
                else _rakamEkle(t);
              },
        child: Container(
          height: 58,
          alignment: Alignment.center,
          child: isSil
              ? const Icon(Icons.backspace_outlined,
                  color: Colors.orange, size: 24)
              : isTemizle
                  ? const Text('C',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: TsRenk.hata,
                      ))
                  : Text(t,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
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
          builder: (_, pin, __) {
            final aktif = !(yukleniyor || kilitli || pin.isEmpty);
            return SizedBox(
              width: double.infinity,
              height: 56,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: aktif
                      ? const LinearGradient(
                          colors: [Color(0xFF4361EE), Color(0xFF3A0CA3)],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        )
                      : null,
                  color: aktif ? null : Colors.white.withAlpha(20),
                  boxShadow: aktif
                      ? [
                          BoxShadow(
                            color: const Color(0xFF4361EE).withAlpha(90),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ]
                      : null,
                ),
                child: FilledButton(
                  onPressed: aktif ? _girisYap : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                    disabledBackgroundColor: Colors.transparent,
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
            );
          },
        ),
      ),
    );
  }

  // ─── PARMAK İZİ BUTONU ──────────────────────────────────────────────────
  Widget _buildBiometricButton() {
    if (_biyometrikMevcut) {
      return Column(
        children: [
          const Divider(height: 24, thickness: 0.5, color: Colors.white24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF4361EE),
                    width: 1.5,
                  ),
                ),
                child: Material(
                  color: Colors.white.withAlpha(18),
                  shape: const CircleBorder(),
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
                  color: Colors.white70,
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
            const Icon(Icons.fingerprint, size: 18, color: Colors.white54),
            const SizedBox(width: 8),
            Text(
              'Şifreyle giriş yapın, parmak izi aktifleşsin',
              style: TsMetin.kucuk.copyWith(color: Colors.white60),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }
}