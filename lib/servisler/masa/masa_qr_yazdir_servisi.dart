// lib/servisler/masa/masa_qr_yazdir_servisi.dart
//
// Masaya konulacak QR menü kartlarını (masa başına 1 sayfa) PDF olarak
// üretip yazdırır. URL mantığı MasaQrGosterEkrani ile aynıdır: Ayarlar'da
// "QR Menü Web Adresi" varsa o, yoksa yerel WiFi sunucusu kullanılır.
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../pdf_font_servisi.dart';
import 'qr_menu_sunucu_servisi.dart';

class MasaQrYazdirServisi {
  MasaQrYazdirServisi._();

  /// Masa için müşterinin okutacağı adres; üretilemezse null.
  static Future<String?> masaUrl(int masaId) async {
    final prefs = await SharedPreferences.getInstance();
    final bulutUrl = prefs.getString('qr_menu_web_url');
    if (bulutUrl != null && bulutUrl.trim().isNotEmpty) {
      final ayrac = bulutUrl.contains('?') ? '&' : '?';
      return '$bulutUrl${ayrac}masa=$masaId';
    }
    final ip = await QrMenuSunucuServisi().baslatVeIpAl();
    if (ip == null) return null;
    return QrMenuSunucuServisi().masaUrlOlustur(masaId);
  }

  /// [masalar]: (id, ad) çiftleri. Yazdırma penceresini açar.
  /// URL üretilemezse false döner.
  static Future<bool> yazdir(List<({int id, String ad})> masalar) async {
    if (masalar.isEmpty) return true;
    final font = await PdfFontServisi.normal();
    final kalin = await PdfFontServisi.kalin();
    final pdf = pw.Document(theme: pw.ThemeData.withFont(base: font, bold: kalin));
    for (final m in masalar) {
      final url = await masaUrl(m.id);
      if (url == null) return false;
      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(32),
        build: (_) => pw.Center(
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              pw.Text(m.ad,
                  style: pw.TextStyle(font: kalin, fontSize: 40),
                  textAlign: pw.TextAlign.center),
              pw.SizedBox(height: 24),
              pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: url,
                width: 260,
                height: 260,
              ),
              pw.SizedBox(height: 24),
              pw.Text('Menüyü görmek ve sipariş vermek için\nkameranızla QR kodu okutun',
                  style: pw.TextStyle(font: font, fontSize: 16),
                  textAlign: pw.TextAlign.center),
            ],
          ),
        ),
      ));
    }
    await Printing.layoutPdf(
        name: 'Masa QR Menü', onLayout: (_) async => pdf.save());
    return true;
  }
}
