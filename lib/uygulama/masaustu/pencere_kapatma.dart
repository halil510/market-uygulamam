// lib/uygulama/masaustu/pencere_kapatma.dart
//
// Windows: pencerenin kapat (X) düğmesi uygulamayı doğrudan kapatmaz.
//  • Hızlı Satış dışındaki bir ekrandaysa → Hızlı Satış'a döner.
//  • Hızlı Satış'taysa (veya giriş ekranındaysa) → onay sorup kapatır.
//    Satılmamış ürünlü sepet (herhangi bir alışveriş sekmesinde) varsa
//    sekme sekme ürün/tutar gösterilir, varsayılan düğme "Satışa Dön".
//  • Windows kapanışı / kurulum güncellemesi soru sormadan kapatır
//    (windows/runner/flutter_window.cpp WM_ENDSESSION).
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:window_manager/window_manager.dart';
import '../../saglayicilar/riverpod/sepet_provider.dart';
import '../../tasarim_sistemi/ts_token.dart';
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
        builder: (d) => _kapatmaDiyalogu(d, giris ? null : _sepetDurumu(ctx)),
      );
      if (kapat == true) await windowManager.destroy();
    } finally {
      _soruAcik = false;
    }
  }

  /// Sepetler yalnız bellekte durur: kapatınca satılmamış ürünler kaybolur.
  ({List<({int no, int urunSayisi, double toplam, String? musteri})> dolu, bool isleniyor})?
      _sepetDurumu(BuildContext ctx) {
    try {
      final c = ProviderScope.containerOf(ctx, listen: false);
      final dolu = c
          .read(sepetProvider.notifier)
          .sekmeler
          .where((s) => s.urunSayisi > 0)
          .toList();
      final isleniyor = c.read(sepetProvider).satisIsleniyor;
      if (dolu.isEmpty && !isleniyor) return null;
      return (dolu: dolu, isleniyor: isleniyor);
    } catch (_) {
      return null;
    }
  }

  Widget _kapatmaDiyalogu(
    BuildContext d,
    ({List<({int no, int urunSayisi, double toplam, String? musteri})> dolu, bool isleniyor})? sepet,
  ) {
    if (sepet == null) {
      return AlertDialog(
        title: const Text('Uygulamayı kapat'),
        content: const Text('BarkoPro kapatılsın mı?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Vazgeç')),
          FilledButton(
              autofocus: true,
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Kapat')),
        ],
      );
    }
    final para = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');
    return AlertDialog(
      icon: const Icon(Icons.shopping_cart_outlined, color: TsRenk.uyari, size: 40),
      title: Text(sepet.isleniyor ? 'Satış kaydediliyor' : 'Sepette satılmamış ürün var'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (sepet.isleniyor)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('Şu an bir satış kaydediliyor. Bitmesini bekleyin.'),
              ),
            for (final s in sepet.dolu)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      'Alışveriş ${s.no}'
                      '${s.musteri != null ? ' — ${s.musteri}' : ''}'
                      ' · ${s.urunSayisi} ürün',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(para.format(s.toplam),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ]),
              ),
            if (sepet.dolu.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text(
                  'Kapatırsanız bu sepetler satış yapılmadan silinir.',
                  style: TextStyle(color: TsRenk.hata, fontWeight: FontWeight.w600)),
            ],
          ],
        ),
      ),
      actions: [
        // Varsayılan (Enter) güvenli seçenek: kasada yanlışlıkla sepet silinmesin.
        FilledButton(
            autofocus: true,
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Satışa Dön')),
        TextButton(
            style: TextButton.styleFrom(foregroundColor: TsRenk.hata),
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Yine de Kapat')),
      ],
    );
  }
}
