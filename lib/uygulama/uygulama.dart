// lib/uygulama/uygulama.dart  (Riverpod versiyonu)
//
// DEĞIŞIKLIKLER:
//   - StatefulWidget → ConsumerStatefulWidget
//   - temaNotifier.addListener → ref.listen(temaProvider, ...)
//   - ValueNotifier dispose() ihtiyacı kalktı

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'router/uygulama_router.dart';
import 'tema/uygulama_temasi.dart';
import '../saglayicilar/riverpod/auth_provider.dart';
import '../saglayicilar/riverpod/tema_provider.dart';

class MarketPlusApp extends ConsumerStatefulWidget {
  final String baslangicTema;
  const MarketPlusApp({super.key, required this.baslangicTema});

  @override
  ConsumerState<MarketPlusApp> createState() => _MarketPlusAppState();
}

class _MarketPlusAppState extends ConsumerState<MarketPlusApp> {
  late final MarketBackButtonDispatcher _dispatcher;

  @override
  void initState() {
    super.initState();
    _dispatcher = MarketBackButtonDispatcher(UygulamaRouter.router(ref));
  }

  @override
  Widget build(BuildContext context) {
    // temaProvider değişince sadece bu build tetiklenir
    final temaAdi = ref.watch(temaProvider);

    return MaterialApp.router(
      title: 'BarkoPro',
      debugShowCheckedModeBanner: false,
      theme: UygulamaTemasi.getTema(temaAdi),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('tr', 'TR')],
      locale:           const Locale('tr', 'TR'),
      routerDelegate:           UygulamaRouter.router(ref).routerDelegate,
      routeInformationParser:   UygulamaRouter.router(ref).routeInformationParser,
      routeInformationProvider: UygulamaRouter.router(ref).routeInformationProvider,
      backButtonDispatcher:     _dispatcher,
    );
  }
}

// ── Back Button Dispatcher ───────────────────────────────────────────────────

class MarketBackButtonDispatcher extends RootBackButtonDispatcher {
  final GoRouter router;
  MarketBackButtonDispatcher(this.router);

  @override
  Future<bool> didPopRoute() async {
    final rootNav = rootNavigatorKey.currentState;
    if (rootNav != null && rootNav.canPop()) {
      rootNav.pop();
      return true;
    }

    final rota = _mevcutRota();
    if (rota != '/') {
      router.go('/');
      return true;
    }

    await _cikisDialogu();
    return true;
  }

  String _mevcutRota() {
    try {
      return router.routerDelegate.currentConfiguration.last.matchedLocation;
    } catch (_) {
      return '/';
    }
  }

  Future<void> _cikisDialogu() async {
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;

    final cevap = await showDialog<String>(
      context: ctx,
      barrierDismissible: true,
      builder: (dCtx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 68, height: 68,
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.security_outlined,
                  color: Colors.orange.shade600, size: 34),
            ),
            const SizedBox(height: 16),
            const Text('Güvenli Çıkış',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('Ne yapmak istersiniz?',
                // 🔴 DÜZELTME: bu sınıf RootBackButtonDispatcher — State
                // değil, context getter'ı yok. Doğru olan dialog
                // builder'ının kendi context'i (dCtx).
                style: TextStyle(fontSize: 13, color: dCtx.textSecondary)),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: Icon(Icons.lock_outline, size: 18,
                    color: Colors.orange.shade700),
                label: Text('Şifre Ekranına Dön',
                    style: TextStyle(fontWeight: FontWeight.w700,
                        fontSize: 14, color: Colors.orange.shade700)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.orange.shade400, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Navigator.pop(dCtx, 'kilit'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.power_settings_new, size: 18),
                label: const Text('Uygulamayı Kapat',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                style: FilledButton.styleFrom(
                  foregroundColor: Colors.white,
          backgroundColor: Colors.red.shade600,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Navigator.pop(dCtx, 'cikis'),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.pop(dCtx, 'iptal'),
              child: Text('Vazgeç',
                  style: TextStyle(color: dCtx.textSecondary,
                      fontWeight: FontWeight.w600, fontSize: 14)),
            ),
          ]),
        ),
      ),
    );

    if (cevap == 'kilit') {
      final c = rootNavigatorKey.currentContext;
      if (c != null && c.mounted) {
        // Riverpod ref üzerinden çıkış
        final container = ProviderScope.containerOf(c);
        await container.read(authProvider.notifier).cikisYap();
        if (c.mounted) c.go('/giris');
      }
    } else if (cevap == 'cikis') {
      SystemNavigator.pop();
      // 🔴 DÜZELTME (kullanıcı bulgusu — "dashboard'da uygulamayı kapat
      // dediğimizde kapanmıyor"): SystemNavigator.pop() TEK BAŞINA
      // Android'de sadece görevi (task) kaldırır — süreç (process)
      // arka planda hayatta kalabilir, bazı cihazlarda/Android
      // sürümlerinde uygulama "gerçekten kapanmamış" gibi görünür.
      // Bu uygulamanın kendisi zaten BAŞKA yerlerde (ayarlar_ekrani.dart
      // — veritabanı içe aktarma/temizleme sonrası, ve çıkış onayında)
      // gerçek/kesin kapatma için exit(0) kullanıyor — buradaki
      // tutarsızlık giderildi. iOS'ta exit(0) KASITLI OLARAK
      // çağrılmıyor: Apple, uygulamaların kendi kendini sonlandırmasını
      // App Store kurallarında yasaklıyor — SystemNavigator.pop() (arka
      // plana atma) iOS'ta zaten beklenen ve tek uygun davranış.
      if (Platform.isAndroid) {
        await Future.delayed(const Duration(milliseconds: 300));
        exit(0);
      }
    }
  }
}
