// lib/ana.dart  (Riverpod versiyonu)
//
// DEĞIŞIKLIKLER:
//   - MultiProvider → ProviderScope
//   - Tüm ChangeNotifierProvider tanımları kaldırıldı (Riverpod lazy load eder)
//   - temaNotifier (ValueNotifier) → temaProvider (Riverpod StateNotifier)
//   - runZonedGuarded korundu

import 'uygulama/masaustu/pencere_kapatma.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:io' show Directory, File, Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show sqfliteFfiInit, databaseFactory, databaseFactoryFfi;
import 'uygulama/uygulama.dart';
import 'veri/database/veritabani.dart';
import 'servisler/bildirim_servisi.dart';
import 'servisler/bildirim_zamanlayici.dart';
import 'servisler/log_servisi.dart';
import 'servisler/bulut/bulut_manager.dart';
import 'servisler/bulut/anlik_bulut_dinleyici.dart';
import 'servisler/bulut/otomatik_bulut_cekme.dart';
import 'servisler/bulut/supabase_oturum.dart';
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

/// Windows: veritabanı çalışma klasörüne göre (.dart_tool/...) DEĞİL, sabit
/// bir kullanıcı klasörüne (%APPDATA%/BarkoPro/veri) yazılır. Kurulum
/// (Program Files) yazılamaz ve çalışma klasörü değişince veri "kaybolurdu".
/// Hedefte veritabanı yoksa ve eski konumda (çalışma klasörü ya da exe
/// klasörü) varsa -wal/-shm dosyalarıyla birlikte BİR KEZ kopyalanır; eski
/// dosyalar silinmez.
Future<void> _windowsVeriKlasorunuHazirla() async {
  try {
    final appData = Platform.environment['APPDATA'];
    if (appData == null || appData.isEmpty) return;
    final hedefDizin = Directory('$appData/BarkoPro/veri');
    await hedefDizin.create(recursive: true);
    final hedef = File('${hedefDizin.path}/market.db');
    if (!await hedef.exists()) {
      final exeDizin = File(Platform.resolvedExecutable).parent.path;
      for (final dizin in {Directory.current.path, exeDizin}) {
        final eski = '$dizin/.dart_tool/sqflite_common_ffi/databases';
        if (await File('$eski/market.db').exists()) {
          for (final ek in ['', '-wal', '-shm']) {
            final kaynak = File('$eski/market.db$ek');
            if (await kaynak.exists()) {
              await kaynak.copy('${hedef.path}$ek');
            }
          }
          break;
        }
      }
    }
    await databaseFactory.setDatabasesPath(hedefDizin.path);
  } catch (e) {
    // Hazırlanamazsa eski davranışla (çalışma klasörü) devam edilir.
    debugPrint('Windows veri klasörü hazırlanamadı: $e');
  }
}

Future<void> _baslatApp() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Masaüstü (Windows/Linux): sqflite yerel eklenti sağlamaz, FFI fabrikası
  // gerekir. Android/iOS'ta bu blok ÇALIŞMAZ — mobil akış aynen kalır.
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    if (Platform.isWindows) await _windowsVeriKlasorunuHazirla();
  }

  // Hata görünürlüğü — release modda ekranın "bembeyaz" kalmasını önler,
  // gerçek hata mesajını ekranda ve logcat'te gösterir.
  await PencereKapatma.baslat(); // Windows: pencere X → Hızlı Satış
  await CrashServisi.init();

  await LogServisi.init();
  // İşletme hesabı oturumu (varsa) — bulut istekleri başlamadan önce.
  await SupabaseOturum().yukle();
  await BulutManager().baslat(); // Bulut sync başlat
  // Diğer kasaların verisini (satış, stok, cari…) belirli aralıkla otomatik
  // çek — önceden yalnız "Buluttan Al" butonu / masa ekranı çekiyordu.
  await OtomatikBulutCekme().baslat();
  // Anlık düşme: Supabase Realtime bildirimiyle değişen tabloyu hemen çek.
  await AnlikBulutDinleyici().baslat();
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
        // Riverpod 3 hata veren provider'ları varsayılan olarak otomatik
        // tekrar dener. Kasa/DB hatalarının arka planda sessizce yeniden
        // denenmesi istenmez — Riverpod 2 davranışı (tekrar yok) korunur.
        retry: (_, _) => null,
        child: BarkoProApp(baslangicTema: baslangicTema),
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

final class _RiverpodLogger extends ProviderObserver {
  @override
  void didAddProvider(ProviderObserverContext context, Object? value) {
    final provider = context.provider;
    if (kDebugMode) debugPrint('[Riverpod] EKLENDI: ${provider.name ?? provider.runtimeType}');
  }

  @override
  void providerDidFail(
    ProviderObserverContext context,
    Object error,
    StackTrace stackTrace,
  ) {
    final provider = context.provider;
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
