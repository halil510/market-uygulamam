// lib/ana.dart  (Riverpod versiyonu)
//
// DEĞIŞIKLIKLER:
//   - MultiProvider → ProviderScope
//   - Tüm ChangeNotifierProvider tanımları kaldırıldı (Riverpod lazy load eder)
//   - temaNotifier (ValueNotifier) → temaProvider (Riverpod StateNotifier)
//   - runZonedGuarded korundu

import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'uygulama/uygulama.dart';
import 'veri/database/veritabani.dart';
import 'servisler/bildirim_servisi.dart';
import 'servisler/bildirim_zamanlayici.dart';
import 'servisler/log_servisi.dart';
import 'servisler/bulut/bulut_manager.dart';
import 'servisler/masa/qr_siparis_cekici_servisi.dart';
import 'servisler/bildirim_merkezi_servisi.dart';
import 'servisler/borc/borc_bildirim_servisi.dart';
import 'cekirdek/servisler/crash_servisi.dart';

void main() {
  runZonedGuarded(_baslatApp, (error, stack) {
    LogServisi().kritik('UnhandledAsyncError', hata: error, yigin: stack);
    if (kDebugMode) debugPrint('UNHANDLED: $error\n$stack');
    // Sentry aktifse (Ayarlar > Hata İzleme'den DSN girilmişse) bu
    // yakalanmamış asenkron hatalar da uzaktan görünür olsun.
    CrashServisi.hataRaporla(error, stack, aciklama: 'UnhandledAsyncError');
  });
}

Future<void> _baslatApp() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Hata görünürlüğü — release modda ekranın "bembeyaz" kalmasını önler,
  // gerçek hata mesajını ekranda ve logcat'te gösterir.
  await CrashServisi.init();

  await LogServisi.init();
  await BulutManager().baslat(); // Bulut sync başlat
  // Kullanıcı isteği: müşteriler kendi telefonlarıyla (internetten,
  // mobil veri dahil) QR menüden sipariş versin — bu servis,
  // Supabase'de bekleyen QR siparişlerini periyodik olarak çekip
  // otomatik olarak masaya düşürüyor.
  QrSiparisCekiciServisi().baslat();
  // Kullanıcı isteği: "bildirim merkezi — stok azaldı, borç günü
  // geldi, son kullanma, kasada açık var." Var olan (önceden boş
  // kalan) bildirimler tablosunu canlı koşullardan otomatik besliyor.
  BildirimMerkeziServisi().baslat();
 

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  try {
    // Başlangıç tema (Riverpod init öncesi — ilk frame için)
    final prefs       = await SharedPreferences.getInstance();
    final baslangicTema = prefs.getString('tema_adi') ?? 'light';

    // 🔴 DÜZELTME (derin analiz bulgusu): burada ÖNCEDEN
    // `statusBarIconBrightness: Brightness.dark` SABİT olarak
    // ayarlanıyordu. Koyu temada (tema_adi == 'dark') durum çubuğu
    // arka planı koyu, ikonlar da koyu olduğu için saat/pil/sinyal
    // ikonları GÖRÜNMEZ hale geliyordu. Artık seçili temaya göre
    // belirleniyor.
    final koyuMu = baslangicTema == 'dark';
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor:          Colors.transparent,
      statusBarIconBrightness: koyuMu ? Brightness.light : Brightness.dark,
      statusBarBrightness:     koyuMu ? Brightness.dark  : Brightness.light,
    ));

    await BildirimServisi.init();
    await BildirimZamanlayici().baslat();
    await Veritabani().db; // migration burada çalışır
    // 🔴 DÜZELTME (Madde 27 — Yedekleme denetimi, 2026-09-16): "Otomatik
    // Yedekleme", BildirimZamanlayici içinde sadece uygulama süreci CANLI
    // İKEN çalışan bir Timer ile her gün 23:30'da tetikleniyordu. Bir
    // market/POS uygulaması akşam kapandıktan sonra genelde kapatıldığı
    // için bu saat pratikte hemen hiç yakalanmıyor, "Son Otomatik Yedek"
    // kullanıcıya güven verse de yedek fiilen alınmıyor olabiliyordu.
    // Artık DB hazır olur olmaz (migration bittikten SONRA) açılışta bir
    // "kaçırılmış yedek var mı" kontrolü de yapılıyor — arka planda,
    // UI'ı bloklamadan.
    unawaited(BildirimZamanlayici().kacirilanYedekKontrolEt());
    await BorcBildirimServisi().baslat();

    runApp(
      ProviderScope(
        // ─── Riverpod override'lar — test/dev için kullanılabilir ───────
        overrides: const [],
        // ─── Riverpod observer — prod'da logları izle ────────────────────
        observers: [if (_debugMod) _RiverpodLogger()],
        child: MarketPlusApp(baslangicTema: baslangicTema),
      ),
    );
  } catch (e, st) {
    LogServisi().kritik('StartupError', hata: e, yigin: st);
    runApp(_HataApp(hata: e.toString()));
  }
}

// Sadece debug modda Riverpod log'ları
const _debugMod = bool.fromEnvironment('dart.vm.product') == false;

// ── Riverpod Observer (debug) ────────────────────────────────────────────────

class _RiverpodLogger extends ProviderObserver {
  @override
  void didAddProvider(
    ProviderBase<Object?> provider,
    Object? value,
    ProviderContainer container,
  ) {
    if (kDebugMode) debugPrint('[Riverpod] EKLENDI: ${provider.name ?? provider.runtimeType}');
  }

  @override
  void providerDidFail(
    ProviderBase<Object?> provider,
    Object error,
    StackTrace stackTrace,
    ProviderContainer container,
  ) {
    if (kDebugMode) debugPrint(
        '[Riverpod] HATA: ${provider.name ?? provider.runtimeType}: $error');
  }
}

// ── Hata Uygulaması ──────────────────────────────────────────────────────────

class _HataApp extends StatelessWidget {
  final String hata;
  const _HataApp({required this.hata});

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.error_outline, size: 72, color: Colors.red),
            const SizedBox(height: 16),
            const Text('Uygulama Başlatılamadı',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text(hata,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 24),
            const Text('Uygulamayı kapatıp yeniden açın.',
                textAlign: TextAlign.center),
          ]),
        ),
      ),
    ),
  );
}
