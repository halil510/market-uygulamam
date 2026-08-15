// lib/cekirdek/utils/tarih_utils.dart
import 'package:intl/intl.dart';

class TarihUtils {
  static final _gmt  = DateFormat('dd.MM.yyyy', 'tr_TR');
  static final _gtm  = DateFormat('dd.MM.yyyy HH:mm', 'tr_TR');
  static final _saat = DateFormat('HH:mm', 'tr_TR');

  static String tarihFormatla(DateTime? dt) =>
      dt == null ? '-' : _gmt.format(dt);

  static String tarihSaatFormatla(DateTime? dt) =>
      dt == null ? '-' : _gtm.format(dt);

  static String saatFormatla(DateTime? dt) =>
      dt == null ? '-' : _saat.format(dt);

  static DateTime bugunBaslangic() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  static DateTime bugunBitis() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, 23, 59, 59);
  }

  static DateTime haftaBaslangici() =>
      DateTime.now().subtract(const Duration(days: 6));

  static DateTime ayBaslangici() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, 1);
  }

  static String kacGunOnce(DateTime dt) {
    final fark = DateTime.now().difference(dt).inDays;
    if (fark == 0) return 'Bugün';
    if (fark == 1) return 'Dün';
    if (fark < 7) return '$fark gün önce';
    return tarihFormatla(dt);
  }
}
