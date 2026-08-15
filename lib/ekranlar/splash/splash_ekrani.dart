// lib/ekranlar/splash/splash_ekrani.dart
import 'dart:async';
import '../../uygulama/tema/uygulama_temasi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../saglayicilar/riverpod/providers.dart';
import '../../veri/database/veritabani.dart';
import '../../uygulama/tema/acik_tema.dart';
import '../../cekirdek/sabitler/uygulama_sabitleri.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../servisler/yazdirma_servisi.dart';
import '../../servisler/aktif_sube_servisi.dart';

class SplashEkrani extends ConsumerStatefulWidget {
  const SplashEkrani({super.key});
  @override
  ConsumerState<SplashEkrani> createState() => _SplashEkraniState();
}

class _SplashEkraniState extends ConsumerState<SplashEkrani>
    with TickerProviderStateMixin {
  // Animasyon kontrolörleri
  late final AnimationController _logoCtrl;
  late final AnimationController _fadeCtrl;
  late final AnimationController _progressCtrl;
  late final AnimationController _pulseCtrl;

  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _textOpacity;
  late final Animation<double> _pulse;

  String _yuklemeMesaj = 'Başlatılıyor…';
  double _ilerleme = 0;

  @override
  void initState() {
    super.initState();
    _logoCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _progressCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200));
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);

    _logoScale   = CurvedAnimation(parent: _logoCtrl, curve: Curves.elasticOut);
    _logoOpacity = CurvedAnimation(parent: _logoCtrl, curve: Curves.easeIn);
    _textOpacity = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn);
    _pulse       = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _baslat();
  }

  Future<void> _baslat() async {
    await _logoCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 200));
    _fadeCtrl.forward();

    // DB başlatma
    await _adim('Veritabanı hazırlanıyor…', 0.25, () => Veritabani().db);
    await _adim('Kullanıcı bilgileri yükleniyor…', 0.55, () async {
      // Auth provider build'da _oturumKontrol() çalıştırır
      // Yukleniyor durumundan çıkmasını bekle
      int deneme = 0;
      while (ref.read(authProvider).yukleniyor && deneme < 30) {
        await Future.delayed(const Duration(milliseconds: 100));
        deneme++;
      }
    });
    await _adim('Ayarlar yükleniyor…', 0.80, () => Future.delayed(const Duration(milliseconds: 200)));
    // Yazıcı bağlantısı arka planda (fire-and-forget) deneniyor —
    // uygulama açılışını BEKLETMİYOR, başarısız olursa sessizce geçiyor.
    // Kullanıcı isteği: "yazıcı otomatik bağlansın, açılıp kapanmada
    // açmıyor" — önceden bu adım hiç yoktu.
    unawaited(YazdirmaServisi().otomatikBaglan());
    await _adim('Hazır!', 1.0, () => Future.delayed(const Duration(milliseconds: 400)));

    if (!mounted) return;

    final giris = ref.read(girisYapildiMiProvider);
    // Aktif Şube servisi başlatılıyor — SADECE giriş yapılmışsa (kullanıcı
    // bilgisi hazır olduğunda) çağrılıyor, aksi halde AuthServisi
    // henüz boş olur ve yanlış/varsayılan bir şube seçilebilirdi.
    if (giris) await AktifSubeServisi().baslat();
    // AktifSubeServisi.baslat() await'i sonrası — splash kapanmış olabilir
    if (!mounted) return;
    // ÖNCEDEN BURADA ÇOK CİDDİ BİR HATA VARDI: '/dashboard' rotası
    // ROUTER'DA HİÇ TANIMLI DEĞİLDİ (Dashboard gerçekte '/' adresinde) —
    // yani zaten giriş yapmış (en yaygın senaryo!) her kullanıcı,
    // uygulamayı her açtığında splash ekranından sonra HATA EKRANI
    // görüyordu. Düzeltildi.
    context.go(giris ? '/' : '/giris');
  }

  Future<void> _adim(String mesaj, double ilerleme, Future Function() islem) async {
    if (mounted) setState(() { _yuklemeMesaj = mesaj; _ilerleme = ilerleme; });
    await islem();
  }

  @override
  void dispose() {
    _logoCtrl.dispose(); _fadeCtrl.dispose();
    _progressCtrl.dispose(); _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      body: Container(
        width: double.infinity, height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFF1A237E), Color(0xFF4361EE), Color(0xFF7209B7)],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: Stack(children: [
          // Arka plan daireler
          _ArkaplanDaireler(size: size),

          // İçerik
          SafeArea(child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 2),

              // Logo
              ScaleTransition(
                scale: _logoScale,
                child: FadeTransition(
                  opacity: _logoOpacity,
                  child: ScaleTransition(
                    scale: _pulse,
                    child: Container(
                      width: 120, height: 120,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(32),
                        boxShadow: [BoxShadow(
                          color: Colors.black.withAlpha(77),
                          blurRadius: 32, offset: const Offset(0, 12))],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(32),
                        child: Image.asset(
                          'assets/images/logo.png',
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.store_mall_directory_rounded,
                            size: 60, color: AppRenkler.primary),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // Başlık
              FadeTransition(
                opacity: _textOpacity,
                child: Column(children: [
                  const Text('BarkoPro',
                    style: TextStyle(
                      fontFamily: 'Poppins', fontSize: 32,
                      fontWeight: FontWeight.w800, color: Colors.white,
                      letterSpacing: -0.5)),
                  const SizedBox(height: 6),
                  Text('Profesyonel Market Yönetimi',
                    style: TextStyle(
                      fontFamily: 'Poppins', fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: Colors.white.withAlpha(204),
                      letterSpacing: 0.3)),
                ]),
              ),

              const Spacer(flex: 2),

              // İlerleme çubuğu
              FadeTransition(
                opacity: _textOpacity,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 48),
                  child: Column(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: _ilerleme),
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeOutCubic,
                        builder: (_, v, __) => LinearProgressIndicator(
                          value: v,
                          minHeight: 6,
                          backgroundColor: Colors.white.withAlpha(51),
                          valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(_yuklemeMesaj,
                      style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 12,
                        color: Colors.white.withAlpha(179),
                        fontWeight: FontWeight.w400)),
                  ]),
                ),
              ),

              const SizedBox(height: 24),

              // Versiyon
              FadeTransition(
                opacity: _textOpacity,
                child: Text('v${UygSabitler.versiyon}',
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 11,
                    color: Colors.white.withAlpha(128))),
              ),

              const SizedBox(height: 32),
            ],
          )),
        ]),
      ),
    );
  }
}

class _ArkaplanDaireler extends StatelessWidget {
  final Size size;
  const _ArkaplanDaireler({required this.size});

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Positioned(top: -80, right: -60,
        child: _Daire(boyut: 280, renk: Colors.white.withAlpha(13))),
      Positioned(top: 120, left: -100,
        child: _Daire(boyut: 320, renk: Colors.white.withAlpha(8))),
      Positioned(bottom: -60, right: 40,
        child: _Daire(boyut: 200, renk: Colors.white.withAlpha(10))),
      Positioned(bottom: 100, left: -40,
        child: _Daire(boyut: 160, renk: Colors.white.withAlpha(8))),
    ]);
  }
}

class _Daire extends StatelessWidget {
  final double boyut;
  final Color renk;
  const _Daire({required this.boyut, required this.renk});

  @override
  Widget build(BuildContext context) => Container(
    width: boyut, height: boyut,
    decoration: BoxDecoration(color: renk, shape: BoxShape.circle));
}
