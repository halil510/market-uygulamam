// lib/servisler/hata_izleme_ayarlari.dart
//
// Sentry crash reporting DSN'inin TEK okuma/yazma noktası.
//
// BARKOPRO ULTIMATE denetiminde bulunan eksiklik: uygulama hatalarını
// sadece cihazın kendi Sistem Logları'na kaydediyordu — birden fazla
// müşteriye dağıtılmış bir üründe, uzaktan (ofisten) hata görünürlüğü
// yoktu. DSN, `supabase_ayarlari.dart` ile AYNI desende (güvenli depoda,
// çalışma zamanında girilebilir) saklanıyor — böylece kullanıcı kendi
// (ücretsiz) Sentry hesabını açıp DSN'i Ayarlar'dan yapıştırabilir,
// APK'yı yeniden derlemeye gerek kalmaz.
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class HataIzlemeAyarlari {
  static const _secure = FlutterSecureStorage();
  static const _kDsn = 'mp_sentry_dsn_secure';

  static Future<String?> dsnOku() => _secure.read(key: _kDsn);

  static Future<void> kaydet(String dsn) => _secure.write(key: _kDsn, value: dsn);

  static Future<void> temizle() => _secure.delete(key: _kDsn);
}
