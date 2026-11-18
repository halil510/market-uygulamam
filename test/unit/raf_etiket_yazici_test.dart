// test/unit/raf_etiket_yazici_test.dart
// Raf etiketi baskısı: barkod çubukları yazıcı noktasına oturur (silik / düzensiz çubuk yok), TSPL etiket yazıcısı
// komutları, ESC/POS'ta ölçeklenmeden sığma, Windows sürücüsü (GDI) ile basma.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart' show PaperSize;
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/cekirdek/etiket/raf_etiket_sablonlari.dart';
import 'package:market_plus/cekirdek/etiket/tspl.dart';
import 'package:market_plus/servisler/etiket_baski_servisi.dart' show fisDpi;
import 'package:market_plus/servisler/raf_etiket_pdf_servisi.dart';
import 'package:market_plus/servisler/windows_etiket_yazici.dart';

Uint8List _resim(int en, int boy, bool Function(int x, int y) siyah) {
  final p = Uint8List(en * boy * 4);
  for (var y = 0; y < boy; y++) {
    for (var x = 0; x < en; x++) {
      final i = (y * en + x) * 4;
      final v = siyah(x, y) ? 0 : 255;
      p[i] = v;
      p[i + 1] = v;
      p[i + 2] = v;
      p[i + 3] = 255;
    }
  }
  return p;
}

bool _tamKat(double v, double nokta) => (v / nokta - (v / nokta).round()).abs() < 1e-9;

void main() {
  group('barkod yazıcı noktasına oturur', () {
    const nokta = 25.4 / 203;

    test('barkodModulu: tam nokta katı, en az 2 nokta, kutuyu aşmaz', () {
      expect(barkodModulu(0.29, nokta) / nokta, closeTo(2, 1e-9));
      expect(barkodModulu(0.324, nokta) / nokta, closeTo(3, 1e-9));
      expect(barkodModulu(0.1, nokta) / nokta, closeTo(2, 1e-9));
      expect(barkodModulu(0.4, nokta, enFazla: 0.3) / nokta, closeTo(2, 1e-9));
      expect(barkodModulu(0.4, nokta, enFazla: 0.1), 0.1);
    });

    test('her şablonda EAN-13 çubukları noktalara oturur (203 ve 182 dpi)', () {
      const v = EtiketVeri(ad: 'ABC ÇAMASIR SUYU 4KG', fiyat: 100, barkod: '8690511183754');
      for (final dpi in [203.0, 182.0]) {
        final n = 25.4 / dpi;
        for (final s in sablonlar) {
          final b = yerlesim(s, v, olcer: const TahminiOlcer(), dpi: dpi).whereType<BarkodCizimi>().single;
          expect(_tamKat(b.modul, n), isTrue, reason: '${s.id} $dpi');
          expect(b.modul / n, greaterThanOrEqualTo(2 - 1e-9), reason: s.id);
          expect(b.genislik, lessThanOrEqualTo(b.oge.g + 1e-9), reason: s.id);
          final yer = RafEtiketPdfServisi.barkodYeri(b, b.oge.yaziPunto);
          expect(yer.modulSayisi, 95, reason: s.id);
          expect(_tamKat(yer.cubukBasi, n), isTrue, reason: s.id);
        }
      }
    });
  });

  test('ESC/POS: etiket fiş yazıcısının basım alanına ölçeklenmeden sığar', () {
    expect(fisDpi(80, PaperSize.mm80), 182); // 576 nokta → 80 mm
    expect((80 * fisDpi(80, PaperSize.mm80) / 25.4).floor(), lessThanOrEqualTo(576));
    expect(fisDpi(40, PaperSize.mm58), varsayilanDpi); // 40 mm zaten sığar
    expect((58 * fisDpi(58, PaperSize.mm58) / 25.4).floor(), lessThanOrEqualTo(384));
  });

  group('TSPL', () {
    test('tsplResim: siyah = 0 biti, genişlik 8\'e beyazla tamamlanır', () {
      final r = tsplResim(_resim(10, 2, (x, y) => x == 0 || (y == 1 && x == 9)), 10, 2);
      expect(r.satirBayt, 2);
      expect(r.veri, [0x7F, 0xFF, 0x7F, 0xBF]);
      expect(() => tsplResim(Uint8List(4), 2, 1), throwsArgumentError);
    });

    test('tsplIs: başlık, art arda aynı etiketler tek PRINT', () {
      final a = tsplResim(_resim(16, 2, (x, y) => x < 4), 16, 2);
      final b = tsplResim(_resim(16, 2, (x, y) => x > 10), 16, 2);
      final is_ = tsplIs([a, a, b], genislik: 80, uzunluk: 35, ayar: const TsplAyar(bosluk: 2, ters: true, koyuluk: 12));
      final m = latin1.decode(is_);
      expect(m, startsWith('SIZE 80 mm,35 mm\r\nGAP 2 mm,0 mm\r\nDIRECTION 1,0\r\nREFERENCE 0,0\r\nDENSITY 12\r\n'));
      expect(m, contains('PRINT 1,2\r\n'));
      expect(m, endsWith('PRINT 1,1\r\n'));
      expect('CLS\r\n'.allMatches(m).length, 2);
    });
  });

  test('Windows sürücüsü: sayfa sorgusu ve gerçek GDI işi (Microsoft Print to PDF)', () async {
    if (!Platform.isWindows) return;
    const y = 'Microsoft Print to PDF';
    final a4 = windowsSayfaSorgula(y, 210, 297);
    expect(a4.uyar(210, 297), isTrue, reason: '${a4.olcu} ${a4.aciklama}');
    expect(a4.dpi, greaterThan(0));
    expect(() => windowsSayfaSorgula('Böyle Bir Yazıcı Yok', 80, 35), throwsA(isA<WindowsYaziciHatasi>()));

    final dosya = '${Directory.systemTemp.createTempSync('rafwy').path}${Platform.pathSeparator}deneme.pdf';
    Stream<(Uint8List, int, int)> ciz(double dpi) async* {
      final en = (210 / 25.4 * dpi).round(), boy = (297 / 25.4 * dpi).round();
      yield (_resim(en, boy, (x, yy) => yy < 100), en, boy);
    }

    expect(await windowsResimBas(y, ciz, genislik: 210, uzunluk: 297, cikti: dosya), 1);
    for (var i = 0; i < 50 && !(File(dosya).existsSync() && File(dosya).lengthSync() > 0); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    expect(File(dosya).readAsStringSync(encoding: latin1), contains('/Type'));
  });

  // Microsoft'un sanal yazıcıları (PDF / XPS) RAW işi yok sayar; kurulu gerçek bir yazıcı sürücüsü gerekir.
  // İş dosyaya yönlendirildiği için kâğıda bir şey basılmaz.
  test('Windows RAW: veri sürücüden geçmeden aynen yazılır (gerçek sürücü → dosya)', () async {
    if (!Platform.isWindows) return;
    final r = await Process.run('powershell', [
      '-NoProfile',
      '-Command',
      "Get-Printer | Where-Object { \$_.DriverName -notmatch 'Microsoft|OneNote|Fax' } | Select-Object -First 1 -ExpandProperty Name"
    ]);
    final yazici = '${r.stdout}'.trim();
    if (yazici.isEmpty) {
      markTestSkipped('Gerçek sürücülü yazıcı kurulu değil');
      return;
    }
    final dosya = '${Directory.systemTemp.createTempSync('ham').path}${Platform.pathSeparator}ham.bin';
    final veri = Uint8List.fromList([...latin1.encode('SIZE 80 mm,35 mm\r\nCLS\r\n'), 0, 1, 2, 255, 13, 10]);
    windowsHamGonder(yazici, veri, cikti: dosya);
    for (var i = 0; i < 50 && !(File(dosya).existsSync() && File(dosya).lengthSync() >= veri.length); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    expect(File(dosya).readAsBytesSync(), veri);
    expect(() => windowsHamGonder('Böyle Bir Yazıcı Yok', veri), throwsA(isA<WindowsYaziciHatasi>()));
  });
}
