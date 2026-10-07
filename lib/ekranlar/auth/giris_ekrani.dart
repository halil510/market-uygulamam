// lib/ekranlar/auth/giris_ekrani.dart
// Modern, profesyonel ve animasyonlu giriş ekranı
// - Akıcı sayfa geçişleri ve mikro etkileşimler
// - Yüksek performans (ValueNotifier + minimal setState)
// - Parmak izi / biyometrik destekli (pulse animasyonu)
// - Responsive ve şık tasarım

import '../../cekirdek/utils/hata_utils.dart';
import 'dart:io' show Platform;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../saglayicilar/riverpod/auth_provider.dart';
import '../../depolar/kullanici_deposu.dart';
import '../../servisler/auth/biyometrik_giris_servisi.dart';
import '../../servisler/auth_servisi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../cekirdek/sabitler/uygulama_sabitleri.dart';

part 'giris_ekrani_gorunum.dart';

class GirisEkrani extends ConsumerStatefulWidget {
  const GirisEkrani({super.key});

  @override
  ConsumerState<GirisEkrani> createState() => _GirisEkraniState();
}

class _GirisEkraniState extends ConsumerState<GirisEkrani>
    with TickerProviderStateMixin {
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
  final _biyometrik = BiyometrikGirisServisi();
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
    if (Platform.isWindows) HardwareKeyboard.instance.addHandler(_klavyeTusu);
    _biyometrikKontrolEt();

    // Animasyonları başlat
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fadeCtrl.forward();
      _scaleCtrl.forward();
    });
  }

  @override
  void dispose() {
    if (Platform.isWindows) HardwareKeyboard.instance.removeHandler(_klavyeTusu);
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
      final sonKullanici = await _biyometrik.sonKullanici();
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
      final durum = await _biyometrik.durumKontrol();
      if (mounted) {
        setState(() {
          _biyometrikDestekli = durum.destekli;
          _biyometrikMevcut = durum.mevcut;
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Biyometrik kontrol hatası: $e');
      if (mounted) {
        setState(() {
          _biyometrikMevcut = false;
          _biyometrikDestekli = false;
        });
      }
    }
  }

  // ─── BİYOMETRİK GİRİŞ ──────────────────────────────────────────────────
  Future<void> _biyometrikGirisYap() async {
    if (!_biyometrikMevcut) return;
    try {
      final basarili = await _biyometrik.parmakIziDogrula();
      if (!basarili || !mounted) return;

      final kayit = await _biyometrik.kayitliBilgi();
      if (kayit == null) {
        _hata.value = 'Kayıtlı giriş bilgisi bulunamadı. Lütfen önce şifrenizle giriş yapın.';
        return;
      }

      _yukleniyor.value = true;
      final sonuc = await ref.read(authProvider.notifier)
          .girisYapBiyometrik(kayit.kullanici, kayit.token);
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

  // ─── FİZİKSEL KLAVYE (Windows) ────────────────────────────────────────────
  // Numpad'e ek olarak klavyeden şifre girişi: karakter → ekle, Backspace →
  // sil, Enter → giriş. Sadece Windows'ta devreye girer.
  bool _klavyeTusu(KeyEvent e) {
    if (e is! KeyDownEvent || !mounted) return false;
    if (_yukleniyor.value) return false;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.backspace) { _silSon(); return true; }
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      _girisYap();
      return true;
    }
    final c = e.character;
    if (c != null && c.length == 1 && c.codeUnitAt(0) >= 32) {
      _rakamEkle(c);
      return true;
    }
    return false;
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
        await _biyometrik.girisiHatirla(_seciliKullanici.value, AuthServisi().aktifId);
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
      if (mounted) _hata.value = 'Bağlantı hatası: ${bildirimMetniniSadelestir(e.toString())}';
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
                          padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 420),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildLogo(),
                                  const SizedBox(height: 12),
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
                                  const SizedBox(height: 16),
                                  _buildKullaniciSecici(),
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
}
