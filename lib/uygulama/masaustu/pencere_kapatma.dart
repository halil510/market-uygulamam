// lib/uygulama/masaustu/pencere_kapatma.dart
//
// Windows: pencerenin kapat (X) düğmesi uygulamayı doğrudan kapatmaz.
//  • Hızlı Satış dışındaki bir ekrandaysa → Hızlı Satış'a döner.
//  • Hızlı Satış'taysa (veya giriş ekranındaysa) → onay sorup kapatır.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';
import '../router/uygulama_router.dart';

class PencereKapatma with WindowListener {
  PencereKapatma._();
  static final PencereKapatma _i = PencereKapatma._();

  static Future<void> baslat() async {
    if (!Platform.isWindows) return;
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    windowManager.addListener(_i);
  }

  bool _soruAcik = false;

  @override
  void onWindowClose() async {
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) {
      await windowManager.destroy();
      return;
    }
    final router = GoRouter.of(ctx);
    final rota = router.routerDelegate.currentConfiguration.uri.path;
    final giris = rota == '/giris' || rota == '/splash';

    // Açık pencere/diyalog varsa önce onu kapat.
    final nav = rootNavigatorKey.currentState;
    if (!giris && nav != null && nav.canPop()) {
      nav.pop();
      return;
    }
    if (!giris && rota != '/satis') {
      router.go('/satis');
      return;
    }
    if (_soruAcik) return;
    _soruAcik = true;
    try {
      final kapat = await showDialog<bool>(
        context: ctx,
        builder: (d) => AlertDialog(
          title: const Text('Uygulamayı kapat'),
          content: const Text('BarkoPro kapatılsın mı?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(d, false),
                child: const Text('Vazgeç')),
            FilledButton(
                onPressed: () => Navigator.pop(d, true),
                child: const Text('Kapat')),
          ],
        ),
      );
      if (kapat == true) await windowManager.destroy();
    } finally {
      _soruAcik = false;
    }
  }
}
