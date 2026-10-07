// lib/servisler/masa/qr_menu_adresi.dart
//
// Müşterinin okutacağı QR menü adresinin TEK kaynağı. Önceden bu karar
// (Ayarlar'da bulut adresi varsa o, yoksa yerel WiFi sunucusu) hem
// MasaQrGosterEkrani'nda hem MasaQrYazdirServisi'nde ayrı ayrı yazılıydı;
// yazdırmada da her masa için tercihler ve IP yeniden okunuyordu.
import 'package:shared_preferences/shared_preferences.dart';

import 'qr_menu_sunucu_servisi.dart';

class QrMenuAdresi {
  /// Ayarlar > "QR Menü Web Adresi" tercih anahtarı.
  static const bulutUrlAnahtari = 'qr_menu_web_url';

  /// true: internet üzerinden (mobil veriyle de) erişilir;
  /// false: yalnız işletmenin yerel ağından erişilir.
  final bool bulut;

  /// Bulut modunda web adresi, yerel modda cihazın yerel IP'si.
  final String _taban;

  const QrMenuAdresi._(this._taban, {required this.bulut});

  /// Geçerli adres kaynağını çözer. Bulut adresi yoksa yerel sunucuyu
  /// başlatır; yerel ağ (WiFi/kablolu) da yoksa null döner.
  static Future<QrMenuAdresi?> coz() async {
    final prefs = await SharedPreferences.getInstance();
    final bulutUrl = prefs.getString(bulutUrlAnahtari)?.trim() ?? '';
    if (bulutUrl.isNotEmpty) return QrMenuAdresi._(bulutUrl, bulut: true);

    final ip = await QrMenuSunucuServisi().baslatVeIpAl();
    return ip == null ? null : QrMenuAdresi._(ip, bulut: false);
  }

  String masaUrl(int masaId) {
    if (!bulut) return QrMenuSunucuServisi.yerelMasaUrl(_taban, masaId);
    final ayrac = _taban.contains('?') ? '&' : '?';
    return '$_taban${ayrac}masa=$masaId';
  }
}
