// lib/cekirdek/servisler/crash_servisi.dart
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:sentry_flutter/sentry_flutter.dart";
import "../../servisler/log_servisi.dart";
import "../../servisler/hata_izleme_ayarlari.dart";

class CrashServisi {
  static final CrashServisi _instance = CrashServisi._();
  factory CrashServisi() => _instance;
  CrashServisi._();

  // 🔴 KOMPLE DERİN ANALİZ — üretim görünürlüğü eksikliği düzeltildi:
  // hatalar ÖNCEDEN sadece cihazın kendi Sistem Logları'na (yerel
  // SQLite) kaydediliyordu — birden fazla müşteriye dağıtılan bir
  // üründe bu, ofisten UZAKTAN hiçbir hata görünürlüğü olmadığı anlamına
  // geliyordu. Sentry, kullanıcı Ayarlar > Hata İzleme'den KENDİ (ücretsiz)
  // DSN'ini girerse devreye girer — DSN girilmemişse (varsayılan/eski
  // davranış) hiçbir şey değişmez, sadece yerel loglama çalışır.
  static bool _sentryAktif = false;

  static Future<void> init() async {
    await _sentryBaslat();

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

  /// Kullanıcı Ayarlar > Hata İzleme'den bir Sentry DSN'i kaydetmişse
  /// Sentry SDK'sını başlatır. DSN yoksa (varsayılan durum) HİÇBİR ŞEY
  /// yapmaz — üçüncü taraf bir servise ASLA sessizce veri gönderilmez,
  /// sadece kullanıcı açıkça bir DSN girip onayladıysa aktif olur.
  static Future<void> _sentryBaslat() async {
    try {
      final dsn = await HataIzlemeAyarlari.dsnOku();
      if (dsn == null || dsn.trim().isEmpty) return;
      await SentryFlutter.init((options) {
        options.dsn = dsn.trim();
        // Debug modda geliştirici konsolunu Sentry ağ trafiğiyle
        // doldurmamak için sadece release'de otomatik gönderim aktif.
        options.debug = false;
        options.environment = kReleaseMode ? 'production' : 'debug';
        // Bu bir POS/ERP uygulaması — satış/cari/fatura gibi tablolardan
        // gelen değerler stack trace/breadcrumb içine sızabilir. Performans
        // izleme (tracing) KAPALI — sadece hata yakalama için kullanılıyor.
        options.tracesSampleRate = 0.0;
      });
      _sentryAktif = true;
    } catch (e) {
      // Sentry başlatılamazsa (ör. geçersiz DSN) uygulama ASLA bundan
      // etkilenmemeli — sessizce devre dışı kalır, yerel loglama sürer.
      _sentryAktif = false;
      if (kDebugMode) debugPrint('Sentry başlatılamadı: $e');
    }
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
    _sentryeGonder(hata, stack);
  }

  /// Sentry aktifse hatayı gönderir; değilse hiçbir şey yapmaz. `await`
  /// EDİLMİYOR (çağıranlar senkron kalsın diye) — gönderim başarısız
  /// olursa sessizce yutulur, ana akış ASLA bundan etkilenmez.
  static void _sentryeGonder(Object hata, StackTrace? stack) {
    if (!_sentryAktif) return;
    Sentry.captureException(hata, stackTrace: stack).catchError((e) {
      if (kDebugMode) debugPrint('Sentry gönderimi başarısız: $e');
      return const SentryId.empty();
    });
  }

  static void hataRaporla(Object hata, StackTrace stack, {String? aciklama}) {
    debugPrint('[HATA] ${aciklama ?? ""}: $hata');
    _sentryeGonder(hata, stack);
  }
}
