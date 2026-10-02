// "İADE ALMA.xlsx" örnek dosyası (hatalar/PROGRAM İÇİN) ile içe alma testi.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/servisler/excel_servisi.dart';

void main() {
  test('İADE ALMA örnek dosyası okunur: kod/barkod/miktar/KDV dahil fiyat', () async {
    final dosya = File('hatalar/PROGRAM İÇİN/İADE ALMA.xlsx');
    if (!dosya.existsSync()) return; // örnek dosya yoksa atla
    final satirlar = await ExcelServisi().iadeExcelIceAl(await dosya.readAsBytes());
    expect(satirlar.length, 1);
    final s = satirlar.first;
    expect(s['kod'], '100020');
    expect(s['barkod'], '100020');
    expect(s['urun_adi'], 'PIDE EKMEK');
    expect(s['miktar'], 1);
    expect(s['birim_fiyat'], 20); // 'Kdv li fiyat' (KDV dahil, indirim sonrası)
  });
}
