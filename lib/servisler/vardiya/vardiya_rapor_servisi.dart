// lib/servisler/vardiya/vardiya_rapor_servisi.dart
//
// Vardiya PDF raporu ve süre metni — vardiya_ekrani.dart'tan ayrıldı
// (2026-10-07 refactor): ekran yalnız "PDF" eylemini tetikler.
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../cekirdek/utils/dosya_paylasim.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../depolar/vardiya_deposu.dart';

class VardiyaRaporServisi {
  VardiyaRaporServisi._();

  static final _tarih = DateFormat('dd.MM.yyyy HH:mm');

  /// "3s 25dk" biçiminde süre; bitiş yoksa şu ana kadar, başlangıç yoksa '—'.
  static String sureMetni(String? bas, String? bit, {DateTime? simdi}) {
    final b = DateTime.tryParse(bas ?? '');
    if (b == null) return '—';
    final e = DateTime.tryParse(bit ?? '');
    final sure = (e ?? simdi ?? DateTime.now()).difference(b);
    return '${sure.inHours}s ${sure.inMinutes.remainder(60)}dk';
  }

  /// [vardiya] satırının raporunu oluşturup paylaşım/kaydetme penceresini açar.
  static Future<void> pdfPaylas(Map<String, dynamic> vardiya) async {
    final ozet = await VardiyaDeposu().pdfSatisOzetiGetir(vardiya['acilis_tarihi'].toString());
    final pdf = pw.Document()..addPage(_sayfa(vardiya, ozet));
    await DosyaPaylasim.pdfPaylas(
        await pdf.save(), 'vardiya_raporu_${DateTime.now().millisecondsSinceEpoch}.pdf');
  }

  static String _tarihMetni(Object? iso) =>
      iso == null ? '—' : _tarih.format(DateTime.parse(iso.toString()));

  static String _tutar(Map<String, dynamic> m, String alan) =>
      ParaUtils.formatla((m[alan] as num?)?.toDouble() ?? 0);

  static pw.Page _sayfa(Map<String, dynamic> v, Map<String, dynamic> ozet) {
    final kalin = pw.TextStyle(fontWeight: pw.FontWeight.bold);
    pw.Widget bilgi(String etiket, String deger) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [pw.Text(etiket, style: kalin), pw.Text(deger)]);
    pw.Widget baslik(String metin) =>
        pw.Text(metin, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13));
    // pdf widget'ları yerleşim durumu tutar; her ayraç yeni örnek olmalı.
    List<pw.Widget> ayrac() => [pw.SizedBox(height: 12), pw.Divider(), pw.SizedBox(height: 8)];

    return pw.Page(
      pageFormat: PdfPageFormat.a5,
      margin: const pw.EdgeInsets.all(24),
      build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Center(
            child: pw.Text('VARDİYA RAPORU',
                style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold))),
        pw.SizedBox(height: 4),
        pw.Divider(),
        pw.SizedBox(height: 8),
        bilgi('Personel:', v['ad_soyad']?.toString() ?? '—'),
        pw.SizedBox(height: 4),
        bilgi('Açılış:', _tarihMetni(v['acilis_tarihi'])),
        bilgi('Kapanış:', _tarihMetni(v['kapanis_tarihi'])),
        bilgi('Süre:', sureMetni(v['acilis_tarihi']?.toString(), v['kapanis_tarihi']?.toString())),
        ...ayrac(),
        baslik('SATIŞ ÖZETİ'),
        pw.SizedBox(height: 6),
        _satir('Toplam Satış', '${ozet['sayi']} adet'),
        _satir('Toplam Ciro', _tutar(ozet, 'ciro')),
        _satir('Nakit', _tutar(ozet, 'nakit')),
        _satir('Kredi Kartı', _tutar(ozet, 'kart')),
        _satir('Cari', _tutar(ozet, 'cari_toplam')),
        _satir('İskonto', _tutar(ozet, 'iskonto')),
        ...ayrac(),
        baslik('KASA'),
        pw.SizedBox(height: 6),
        _satir('Başlangıç', _tutar(v, 'baslangic_bakiye')),
        _satir('Nakit Satış', _tutar(ozet, 'nakit')),
        _satir('Sayım', _tutar(v, 'nakit_sayim')),
        _satir('Fark', _tutar(v, 'fark'), kalin: true),
        pw.SizedBox(height: 20),
        pw.Center(
            child: pw.Text('BarkoPro © ${DateTime.now().year}',
                style: const pw.TextStyle(fontSize: 9))),
      ]),
    );
  }

  static pw.Widget _satir(String etiket, String deger, {bool kalin = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(etiket),
          pw.Text(deger, style: kalin ? pw.TextStyle(fontWeight: pw.FontWeight.bold) : null),
        ]),
      );
}
