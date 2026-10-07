// test/servisler/masa_adisyon_servisi_test.dart
//
// Masa detay ekranından ayrılan adisyon numarası kuralı (2026-10-07 refactor).
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/servisler/masa/masa_adisyon_servisi.dart';

void main() {
  test('adisyon numarası yalnız harf, rakam ve tire içerir', () {
    final no = MasaAdisyonServisi.adisyonNo(DateTime.fromMillisecondsSinceEpoch(1760000000000));
    expect(no, 'ADY-1760000000000');
    expect(RegExp(r'^[a-zA-Z0-9-]+$').hasMatch(no), isTrue);
  });
}
