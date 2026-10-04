import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/servisler/excel_servisi.dart';

void main() {
  tarihTestleri();
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

void tarihTestleri() {
  test('tarih biçimleri', () {
    expect(excelTarihAyristir('2025-12-31'), DateTime(2025, 12, 31));
    expect(excelTarihAyristir('31.12.2025'), DateTime(2025, 12, 31));
    expect(excelTarihAyristir('5/3/2025 14:30'), DateTime(2025, 3, 5, 14, 30));
    expect(excelTarihAyristir('31.02.2025'), isNull);
    expect(excelTarihAyristir('abc'), isNull);
    expect(excelTarihAyristir(''), isNull);
  });
}
