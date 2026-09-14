// lib/cekirdek/servisler/crash_servisi.dart
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "../../servisler/log_servisi.dart";

class CrashServisi {
  static final CrashServisi _instance = CrashServisi._();
  factory CrashServisi() => _instance;
  CrashServisi._();

  static Future<void> init() async {
    FlutterError.onError = (details) {
      // ÖNEMLİ: Artık debug/release fark etmeksizin HER ZAMAN konsola
      // (adb logcat) yazılıyor. Öncesinde release modda hata tamamen
      // yutuluyordu — ekran bembeyaz kalıyor ama sebebi hiçbir yerde
      // görünmüyordu. debugPrint release'de de çalışır (sadece çok uzun
      // stringleri kırpar), bu yüzden güvenle kullanılabilir.
      debugPrint('🔴 [FLUTTER HATASI] ${details.exception}');
      debugPrint('🔴 Konum: ${details.context}');
      if (details.stack != null) debugPrint('🔴 Stack:\n${details.stack}');
      _kaydet(details.exception, details.stack);
      if (kDebugMode) {
        FlutterError.presentError(details);
      }
    };

    // Flutter'ın VARSAYILAN ErrorWidget'ı, hata mesajını bir assert() bloğu
    // içinde ürettiği için RELEASE modda mesaj boş kalır — ekranda sadece
    // metinsiz gri/boş bir kutu görünür (tam ekran bir widget'ta bu "bembeyaz
    // boş ekran" gibi algılanır). Burada assert'e bağlı olmadan HER ZAMAN
    // gerçek hata metnini basan bir sürüme geçiyoruz.
    ErrorWidget.builder = (details) => hataGoster(details);

    if (kDebugMode) debugPrint('CrashServisi başlatıldı');
  }

  /// Debug modda hatayı EKRANDA göstermek için — bembeyaz/boş ekran yerine
  /// en azından hangi hatanın oluştuğunu okuyabilirsiniz.
  ///
  /// 🔴🔴 GÜVENLİK/KALİTE DÜZELTMESİ (komple derin analizde bulundu): bu
  /// widget ÖNCEDEN debug/release AYRIMI YAPMADAN her zaman ham
  /// `details.exception` VE TAM stack trace'i doğrudan ekranda kullanıcıya
  /// (ör. gerçek bir kasiyer/müşteride) gösteriyordu — projenin kendi hata
  /// yönetimi ilkesini ("kullanıcıya teknik değil anlaşılır hata göster,
  /// teknik detay log'a yazılsın") doğrudan ihlal ediyordu. Loglama
  /// (`_kaydet`) bundan ETKİLENMEDİ — hata detayları her zaman olduğu gibi
  /// Sistem Logları'na kaydedilmeye devam ediyor, sadece EKRANDA gösterim
  /// artık debug/release'e göre ayrışıyor.
  static Widget hataGoster(FlutterErrorDetails details) {
    if (kDebugMode) {
      return Material(
        color: Colors.white,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('⚠️ Ekran Hatası (DEBUG)',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red)),
                const SizedBox(height: 12),
                Text('${details.exception}',
                    style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
                const SizedBox(height: 12),
                Text('${details.stack}',
                    style: const TextStyle(fontSize: 10, color: Colors.grey, fontFamily: 'monospace')),
              ],
            ),
          ),
        ),
      );
    }
    // RELEASE: gerçek kullanıcıya teknik detay/stack trace gösterilmez.
    return Material(
      color: Colors.white,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, size: 48, color: Colors.red),
                const SizedBox(height: 12),
                const Text('Bir şeyler ters gitti',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text(
                  'Bu ekran yüklenirken beklenmeyen bir hata oluştu.\n'
                  'Lütfen tekrar deneyin. Sorun devam ederse Ayarlar > '
                  'Sistem Logları üzerinden destek ile paylaşabilirsiniz.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static void _kaydet(Object hata, StackTrace? stack) {
    // ─────────────────────────────────────────────────────────────────
    // TODO (canlıya çıkmadan önce şart): Sentry veya Firebase Crashlytics
    // buraya bağlanmalı. Şu an hatalar sadece cihazın kendi Sistem
    // Logları'na (uygulama içi) kaydediliyor — bir müşteride hata olursa,
    // Ayarlar > Sistem Logları'ndan görülebilir AMA UZAKTAN (sizin
    // ofisinizden) göremezsiniz, müşterinin ekranını görmeniz/o ekranı
    // paylaşmasını istemeniz gerekir. Birden fazla müşteriye dağıtılan
    // profesyonel bir uygulamada bu ciddi bir sınırlamadır.
    //
    // Örnek (Sentry ile, pubspec.yaml'a `sentry_flutter` eklendikten sonra):
    //   Sentry.captureException(hata, stackTrace: stack);
    //
    // Örnek (Firebase Crashlytics ile):
    //   FirebaseCrashlytics.instance.recordError(hata, stack);
    // ─────────────────────────────────────────────────────────────────
    debugPrint('[CRASH] $hata');
    if (stack != null) debugPrint(stack.toString());
    // ÖNCEDEN BURADA BİR TUTARSIZLIK VARDI: ana.dart'taki asenkron hata
    // yakalayıcı (runZonedGuarded) hataları LogServisi().kritik() ile
    // Sistem Logları'na (veritabanına) kalıcı olarak kaydediyordu, ama
    // BU fonksiyon (senkron Flutter hataları için) SADECE konsola
    // yazıyordu — uygulama kapanınca o hata kaydı tamamen kayboluyordu.
    // Artık ikisi de aynı şekilde kalıcı olarak kaydediliyor.
    try {
      LogServisi().kritik('FlutterHatasi', hata: hata, yigin: stack);
    } catch (_) {
      // LogServisi'nin kendisi başlatılmamışsa (çok erken bir hata) sessizce geç
    }
  }

  static void hataRaporla(Object hata, StackTrace stack, {String? aciklama}) {
    debugPrint('[HATA] ${aciklama ?? ""}: $hata');
  }
}
