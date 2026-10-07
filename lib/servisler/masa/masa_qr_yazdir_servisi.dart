// lib/servisler/masa/masa_qr_yazdir_servisi.dart
//
// Masaya konulacak QR menü kartlarını (masa başına 1 sayfa) PDF olarak
// üretip yazdırır. Adres kaynağı MasaQrGosterEkrani ile ortaktır
// (bkz. QrMenuAdresi).
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../pdf_font_servisi.dart';
import 'qr_menu_adresi.dart';

class MasaQrYazdirServisi {
  MasaQrYazdirServisi._();

  /// [masalar]: (id, ad) çiftleri. Yazdırma penceresini açar.
  /// Adres üretilemezse (yerel ağ yok, bulut adresi tanımsız) false döner;
  /// PDF/yazdırma hatalarını çağırana iletir.
  static Future<bool> yazdir(List<({int id, String ad})> masalar) async {
    if (masalar.isEmpty) return true;
    // Adres kaynağı tüm masalar için BİR kez çözülür (önceden her masada
    // tercihler okunup IP yeniden aranıyordu).
    final adres = await QrMenuAdresi.coz();
    if (adres == null) return false;

    final font = await PdfFontServisi.normal();
    final kalin = await PdfFontServisi.kalin();
    final pdf = pw.Document(theme: pw.ThemeData.withFont(base: font, bold: kalin));
    for (final m in masalar) {
      pdf.addPage(_masaSayfasi(m.ad, adres.masaUrl(m.id), font: font, kalin: kalin));
    }
    await Printing.layoutPdf(name: 'Masa QR Menü', onLayout: (_) => pdf.save());
    return true;
  }

  static pw.Page _masaSayfasi(String masaAdi, String url,
      {required pw.Font font, required pw.Font kalin}) {
    return pw.Page(
      pageFormat: PdfPageFormat.a5,
      margin: const pw.EdgeInsets.all(32),
      build: (_) => pw.Center(
        child: pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            pw.Text(masaAdi,
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
    );
  }
}
