// lib/servisler/raf_etiket_pdf_servisi.dart
//
// Raf etiketi şablonlarını (bkz. cekirdek/etiket/raf_etiket_sablonlari.dart) PDF'e çizer; termal (ESC/POS)
// yazıcıya basmak için PDF sayfalarını 203 dpi resme çevirir.
//
// Yazı tipleri: Windows'ta şablonlardaki gerçek yazı tipleri (Arial, Arial Narrow, Arial Black, Book Antiqua)
// sistemden okunur — BarTender çıktısıyla aynı görünüm. Bulunamazsa (Android) gömülü DejaVu Sans /
// DejaVu Sans Condensed. ₺ gibi eksik harfler için DejaVu yedek yazı tipidir.

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../cekirdek/etiket/raf_etiket_sablonlari.dart';

const _mm = PdfPageFormat.mm;

/// Barkod türü: geçerli EAN-13 / EAN-8 / UPC-A ise o, değilse Code128 (boşsa / basılamazsa null).
pw.Barcode? rafBarkodTuru(String s) {
  if (s.isEmpty) return null;
  final e13 = pw.Barcode.ean13();
  if (s.length == 13 && e13.isValid(s)) return e13;
  final e8 = pw.Barcode.ean8();
  if (s.length == 8 && e8.isValid(s)) return e8;
  final upc = pw.Barcode.upcA();
  if (s.length == 12 && upc.isValid(s)) return upc;
  final c = pw.Barcode.code128();
  return c.isValid(s) ? c : null;
}

// ───────────────────────── Yazı tipleri ─────────────────────────

class _Yazi {
  final pw.Font font;
  final TtfParser p;
  _Yazi(ByteData b) : font = pw.Font.ttf(b), p = TtfParser(b);

  /// Harfin genişliği (em); yazı tipinde yoksa -1.
  double harf(int r) {
    final g = p.charToGlyphIndexMap[r];
    if (g == null || g == 0) return -1;
    return p.glyphInfoMap[g]?.advanceWidth ?? 0;
  }

  double get ascent => p.ascent / p.unitsPerEm;
  double get descent => -p.descent / p.unitsPerEm;
}

/// Etiket yazı tipleri; aynı zamanda yerleşim için ölçer.
class RafEtiketYazilari implements YaziOlcer {
  final Map<(YaziTipi, bool), _Yazi> _y;
  final _Yazi _yedekNormal, _yedekKalin;

  /// Windows yazı tiplerinin hepsi bulundu mu.
  final bool sistemYazisi;
  RafEtiketYazilari._(this._y, this._yedekNormal, this._yedekKalin, this.sistemYazisi);

  static RafEtiketYazilari? _onbellek;

  static const _windows = {
    (YaziTipi.arial, false): 'arial.ttf',
    (YaziTipi.arial, true): 'arialbd.ttf',
    (YaziTipi.arialNarrow, false): 'ARIALN.TTF',
    (YaziTipi.arialNarrow, true): 'ARIALNB.TTF',
    (YaziTipi.arialBlack, false): 'ariblk.ttf',
    (YaziTipi.arialBlack, true): 'ariblk.ttf',
    (YaziTipi.antikva, false): 'BKANT.TTF',
    (YaziTipi.antikva, true): 'ANTQUAB.TTF',
  };

  static Future<RafEtiketYazilari> yukle({bool sistem = true}) async {
    if (sistem && _onbellek != null) return _onbellek!;
    Future<_Yazi> varlik(String ad) async => _Yazi(await rootBundle.load('assets/fonts/$ad'));
    final dn = await varlik('DejaVuSans.ttf');
    final db = await varlik('DejaVuSans-Bold.ttf');
    final y = <(YaziTipi, bool), _Yazi>{};
    if (sistem && !kIsWeb && Platform.isWindows) {
      final kl = '${Platform.environment['WINDIR'] ?? r'C:\Windows'}\\Fonts';
      for (final e in _windows.entries) {
        try {
          final f = File('$kl\\${e.value}');
          if (await f.exists()) y[e.key] = _Yazi(ByteData.sublistView(await f.readAsBytes()));
        } catch (e) {
          debugPrint('Raf etiketi yazı tipi okunamadı: $e'); // bozuk yazı tipi → DejaVu
        }
      }
    }
    // Windows yazı tipi yoksa: dar yazı için DejaVu Condensed, diğerleri DejaVu Sans
    if (!y.containsKey((YaziTipi.arialNarrow, false))) y[(YaziTipi.arialNarrow, false)] = await varlik('DejaVuSansCondensed.ttf');
    if (!y.containsKey((YaziTipi.arialNarrow, true))) y[(YaziTipi.arialNarrow, true)] = await varlik('DejaVuSansCondensed-Bold.ttf');
    final s = RafEtiketYazilari._(y, dn, db, _windows.keys.every((k) => y.containsKey(k)) && !kIsWeb && Platform.isWindows);
    if (sistem) _onbellek = s;
    return s;
  }

  _Yazi _sec(YaziTipi t, bool kalin) => _y[(t, kalin)] ?? (kalin || t == YaziTipi.arialBlack ? _yedekKalin : _yedekNormal);
  _Yazi _yedek(bool kalin) => kalin ? _yedekKalin : _yedekNormal;

  pw.TextStyle stil(YaziTipi t, bool kalin, double punto, {bool altiCizili = false}) => pw.TextStyle(
        font: _sec(t, kalin).font,
        fontSize: punto,
        fontFallback: [_yedek(kalin).font],
        decoration: altiCizili ? pw.TextDecoration.underline : null,
        decorationThickness: altiCizili ? 1.6 : null,
      );

  @override
  double genislik(String s, YaziTipi t, bool kalin) {
    final a = _sec(t, kalin), y = _yedek(kalin);
    var w = 0.0;
    for (final r in s.runes) {
      final h = a.harf(r);
      w += h >= 0 ? h : math.max(0, y.harf(r));
    }
    return w;
  }

  @override
  double ascent(YaziTipi t, bool kalin) => _sec(t, kalin).ascent;
  @override
  double descent(YaziTipi t, bool kalin) => _sec(t, kalin).descent;
}

// ───────────────────────── PDF ─────────────────────────

enum RafEtiketKagidi { rulo, a4 }

class RafEtiketPdfServisi {
  RafEtiketPdfServisi._();

  static const _a4Kenar = 8.0, _a4Ara = 2.0;

  /// A4'e kaç sütun × satır etiket sığar.
  static (int, int) a4Dizilim(EtiketSablonu s) => (
        math.max(1, ((210 - 2 * _a4Kenar + _a4Ara) / (s.genislik + _a4Ara)).floor()),
        math.max(1, ((297 - 2 * _a4Kenar + _a4Ara) / (s.yukseklik + _a4Ara)).floor()),
      );

  /// Etiket PDF'i. [liste] zaten adet kadar çoğaltılmış olmalı.
  static Future<Uint8List> pdf(
    List<EtiketVeri> liste,
    EtiketSablonu s, {
    RafEtiketKagidi kagit = RafEtiketKagidi.rulo,
    String mensei = 'Türkiye',
    String firma = '',
    DateTime? bugun,
    RafEtiketYazilari? yazilar,
    double dpi = varsayilanDpi, // yazıcı çözünürlüğü: barkod çubukları noktalarına oturur
  }) async {
    final y = yazilar ?? await RafEtiketYazilari.yukle();
    final logo = pw.MemoryImage((await rootBundle.load('assets/images/yerli_uretim.png')).buffer.asUint8List());
    final doc = pw.Document(title: 'Raf etiketleri', author: firma);
    final etiketler = [for (final v in liste) yerlesim(s, v, olcer: y, mensei: mensei, firma: firma, bugun: bugun, dpi: dpi)];

    if (etiketler.isEmpty) {
      doc.addPage(pw.Page(build: (_) => pw.Center(child: pw.Text('Basılacak etiket yok', style: y.stil(YaziTipi.arial, false, 12)))));
    } else if (kagit == RafEtiketKagidi.rulo) {
      // Sayfa, yazıcı noktasının tam katı (80 mm @203 dpi = 639,37 → 639 nokta = 79,95 mm): resme çevirirken
      // (Printing.raster sayfayı tam sayı piksele keser) ölçek tam 1 nokta = 1 piksel olur, çubuk kenarları kaymaz.
      double tam(double mm) => (mm * dpi / 25.4).floorToDouble() * 72 / dpi;
      final f = PdfPageFormat(tam(s.genislik), tam(s.yukseklik));
      for (final c in etiketler) {
        doc.addPage(pw.Page(pageFormat: f, build: (_) => _etiket(s, c, y, logo)));
      }
    } else {
      final (sutun, satir) = a4Dizilim(s);
      final sayfada = sutun * satir;
      for (var i = 0; i < etiketler.length; i += sayfada) {
        final parca = etiketler.sublist(i, math.min(i + sayfada, etiketler.length));
        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4.copyWith(
              marginTop: _a4Kenar * _mm,
              marginBottom: _a4Kenar * _mm,
              marginLeft: _a4Kenar * _mm,
              marginRight: _a4Kenar * _mm,
            ),
            build: (_) => pw.Wrap(
              spacing: _a4Ara * _mm,
              runSpacing: _a4Ara * _mm,
              children: [for (final c in parca) _etiket(s, c, y, logo, kenar: true)],
            ),
          ),
        );
      }
    }
    return doc.save();
  }

  /// Barkod çubuklarının yerleşimi (mm): widget'ın sol kenarı, genişliği ve çubukların başladığı yer.
  /// Barkod paketi rakamlar için çubukların soluna / sağına pay bırakıp kalan genişliği çubuklara böler; payları ölçüp
  /// widget'ı, her modül tam [BarkodCizimi.modul] ve ilk çubuk yazıcı noktasına oturacak biçimde boyutlandırırız
  /// (kesirli modül 1-2-3 noktalık düzensiz, silik çubuklar veriyordu).
  static ({double sol, double genislik, double cubukBasi, int modulSayisi}) barkodYeri(BarkodCizimi c, double yaziPt) {
    final kod = rafBarkodTuru(c.veri)!;
    const deneme = 1000.0; // pt
    final cubuklar = kod
        .make(c.veri, width: deneme, height: 100, drawText: true, fontHeight: yaziPt, textPadding: 0)
        .whereType<pw.BarcodeBar>()
        .where((b) => b.black)
        .toList();
    final ilk = cubuklar.first, son = cubuklar.last;
    final enInce = cubuklar.map((b) => b.width).reduce(math.min); // = 1 modül
    final solPay = ilk.left, sagPay = deneme - (son.left + son.width);
    final n = ((son.left + son.width - ilk.left) / enInce).round();
    final cubukG = n * c.modul;
    final cubukBasi = noktayaOturt(c.x + (c.genislik - cubukG) / 2, c.nokta);
    final solMm = solPay / _mm, sagMm = sagPay / _mm;
    return (sol: cubukBasi - solMm, genislik: solMm + cubukG + sagMm, cubukBasi: cubukBasi, modulSayisi: n);
  }

  static pw.Widget _barkod(BarkodCizimi c, RafEtiketYazilari y) {
    final stil = y.stil(YaziTipi.arial, c.oge.kalinYazi, c.oge.yaziPunto);
    final yer = barkodYeri(c, stil.fontSize!);
    return pw.Positioned(
      left: yer.sol * _mm,
      top: c.oge.y * _mm,
      child: pw.BarcodeWidget(
        barcode: rafBarkodTuru(c.veri)!,
        data: c.veri,
        width: yer.genislik * _mm,
        height: c.oge.h * _mm,
        drawText: true,
        textStyle: stil,
      ),
    );
  }

  /// PDF sayfalarını termal yazıcı için siyah-beyaz resme çevirir. [dpi], PDF'i üretirken verilenle aynı olmalı
  /// (barkod çubukları o çözünürlüğün noktalarına oturtulur).
  static Future<List<img.Image>> resimler(Uint8List pdf, {double dpi = varsayilanDpi}) async {
    final sonuc = <img.Image>[];
    await for (final sayfa in Printing.raster(pdf, dpi: dpi)) {
      final png = await sayfa.toPng();
      final r = img.decodePng(png);
      if (r == null) throw Exception('Etiket resmi oluşturulamadı');
      // saydam zemin beyaz olsun
      sonuc.add(img.compositeImage(img.Image(width: r.width, height: r.height)..clear(img.ColorRgb8(255, 255, 255)), r));
    }
    return sonuc;
  }

  /// Yazıyı sol kenarından yatayda [olcek] kadar genişletir / daraltır (BarTender'daki yazı genişliği).
  static pw.Widget _olcekli(double olcek, pw.Widget w) => (olcek - 1).abs() < 1e-6
      ? w
      : pw.Transform(transform: Matrix4.diagonal3Values(olcek, 1, 1), alignment: pw.Alignment.topLeft, child: w);

  static pw.Widget _etiket(EtiketSablonu s, List<Cizim> cizimler, RafEtiketYazilari y, pw.ImageProvider logo, {bool kenar = false}) {
    final w = s.genislik * _mm, h = s.yukseklik * _mm;
    final cizgiler = cizimler.whereType<CizgiCizimi>().toList();

    pw.Widget satirlar(YaziCizimi c) => pw.Stack(
          overflow: pw.Overflow.visible,
          children: [
            for (final st in c.satirlar)
              pw.Positioned(
                left: st.x * _mm,
                top: st.y * _mm,
                child: _olcekli(
                  st.olcek,
                  pw.Text(
                    st.metin,
                    maxLines: 1,
                    softWrap: false,
                    style: y.stil(c.oge.yazi, c.oge.kalin, st.punto, altiCizili: c.oge.altiCizili),
                  ),
                ),
              ),
          ],
        );

    // 90° döndürülmüş içerik: döndürülmemiş hâli (h × g) kutunun ortasına konur, merkez etrafında döndürülür
    // → (g × h) kutuyu tam doldurur; aşağıdan yukarı okunur.
    pw.Widget dikey(double x, double yy, double g, double hh, pw.Widget icerik) => pw.Positioned(
          left: (x + g / 2 - hh / 2) * _mm,
          top: (yy + hh / 2 - g / 2) * _mm,
          child: pw.Transform.rotate(
            angle: math.pi / 2,
            child: pw.SizedBox(width: hh * _mm, height: g * _mm, child: icerik),
          ),
        );

    pw.Widget ciz(Cizim c) => switch (c) {
          YaziCizimi(:final oge) when oge.dikey => dikey(oge.x, oge.y, oge.g, oge.h, satirlar(c)),
          YaziCizimi() => pw.Positioned(left: 0, top: 0, child: pw.SizedBox(width: w, height: h, child: satirlar(c))),
          BarkodCizimi() => _barkod(c, y),
          KutuCizimi(:final oge) => pw.Positioned(
              left: oge.x * _mm,
              top: oge.y * _mm,
              child: pw.Container(
                width: oge.g * _mm,
                height: oge.h * _mm,
                decoration: pw.BoxDecoration(border: pw.Border.all(width: oge.kalinlik * _mm)),
              ),
            ),
          LogoCizimi(:final oge) when oge.dikey => dikey(oge.x, oge.y, oge.g, oge.h, pw.Image(logo, fit: pw.BoxFit.contain)),
          LogoCizimi(:final oge) => pw.Positioned(
              left: oge.x * _mm,
              top: oge.y * _mm,
              child: pw.SizedBox(width: oge.g * _mm, height: oge.h * _mm, child: pw.Image(logo, fit: pw.BoxFit.contain)),
            ),
          CizgiCizimi() => pw.SizedBox(), // aşağıda tek CustomPaint ile
        };

    return pw.Container(
      width: w,
      height: h,
      decoration: kenar ? pw.BoxDecoration(border: pw.Border.all(width: 0.3, color: PdfColors.grey400)) : null,
      child: pw.Stack(
        overflow: pw.Overflow.clip,
        children: [
          for (final c in cizimler) ciz(c),
          if (cizgiler.isNotEmpty)
            pw.Positioned(
              left: 0,
              top: 0,
              child: pw.CustomPaint(
                size: PdfPoint(w, h),
                painter: (g, boy) {
                  g.setStrokeColor(PdfColors.black);
                  for (final l in cizgiler) {
                    g
                      ..setLineWidth(l.kalinlik * _mm)
                      ..moveTo(l.x1 * _mm, boy.y - l.y1 * _mm)
                      ..lineTo(l.x2 * _mm, boy.y - l.y2 * _mm)
                      ..strokePath();
                  }
                },
              ),
            ),
        ],
      ),
    );
  }
}
