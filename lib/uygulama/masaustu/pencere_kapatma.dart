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
import 'masaustu_yan_menu.dart' show mevcutRota;

class PencereKapatma with WindowListener {
  PencereKapatma._();
  static final PencereKapatma _i = PencereKapatma._();

  static Future<void> baslat() async {
    if (!Platform.isWindows) return;
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    // Kasa bilgisayarı: en küçük pencere boyutu + açılışta ekranı kapla.
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        minimumSize: Size(1024, 680),
        title: 'BarkoPro',
      ),
      () async {
        await windowManager.show();
        await windowManager.maximize();
        await windowManager.focus();
      },
    );
    windowManager.addListener(_i);
  }

  bool _soruAcik = false;

  @override
  Future<void> onWindowClose() async {
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) {
      await windowManager.destroy();
      return;
    }
    final router = GoRouter.of(ctx);
    // push ile açılan ekranlarda uri.path değişmez; son eşleşmenin adresi doğrudur.
    final rota = mevcutRota(router);
    final giris = rota == '/giris' || rota == '/splash';

    // Açık pencere/diyalog varsa önce onu kapat.
    if (!giris && router.canPop()) {
      router.pop();
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
