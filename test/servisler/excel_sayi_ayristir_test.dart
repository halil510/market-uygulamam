import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/servisler/excel_servisi.dart';

void main() {
  test('Türkçe ve İngilizce sayı biçimleri', () {
    expect(excelSayiAyristir('1.234,50'), 1234.5);
    expect(excelSayiAyristir('1,234.50'), 1234.5);
    expect(excelSayiAyristir('1234,5'), 1234.5);
    expect(excelSayiAyristir('12.5'), 12.5);
    expect(excelSayiAyristir('1.234.567'), 1234567);
    expect(excelSayiAyristir('1,234,567'), 1234567);
    expect(excelSayiAyristir('₺12,5 TL'), 12.5);
    expect(excelSayiAyristir('-3,25'), -3.25);
    expect(excelSayiAyristir(7), 7.0);
    expect(excelSayiAyristir(2.75), 2.75);
  });
  test('boş / geçersiz null döner', () {
    expect(excelSayiAyristir(null), isNull);
    expect(excelSayiAyristir(''), isNull);
    expect(excelSayiAyristir('-'), isNull);
    expect(excelSayiAyristir('abc'), isNull);
  });
}
