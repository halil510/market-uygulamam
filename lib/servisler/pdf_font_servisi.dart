import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;

/// PDF fontları — uygulamayla paketlenmiş Poppins (Türkçe karakter destekli).
///
/// Önceden `PdfGoogleFonts.robotoRegular()` kullanılıyordu: her PDF/yazdırma
/// öncesi fontu İNTERNETTEN indiriyordu (yavaş ağda saniyelerce bekleme,
/// çevrimdışıyken hiç çalışmama). Artık yerel asset'ten bir kez yüklenip
/// bellekte tutulur.
class PdfFontServisi {
  PdfFontServisi._();

  static pw.Font? _normal;
  static pw.Font? _kalin;

  static Future<pw.Font> normal() async => _normal ??= pw.Font.ttf(
      await rootBundle.load('assets/fonts/Poppins-Regular.ttf'));

  static Future<pw.Font> kalin() async =>
      _kalin ??= pw.Font.ttf(await rootBundle.load('assets/fonts/Poppins-Bold.ttf'));
}
