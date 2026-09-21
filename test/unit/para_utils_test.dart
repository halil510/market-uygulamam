import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/cekirdek/utils/para_utils.dart';

void main() {
  group('ParaUtils.formatla', () {
    test('sıfır', () => expect(ParaUtils.formatla(0), contains('0')));
    test('tam sayı', () => expect(ParaUtils.formatla(100), contains('100')));
    test('ondalık', () => expect(ParaUtils.formatla(99.99), contains('99')));
    test('negatif', () => expect(ParaUtils.formatla(-50), contains('50')));
    test('büyük sayı', () => expect(ParaUtils.formatla(1000000), isNotEmpty));
  });

  group('ParaUtils.kisaFisNo', () {
    test('GIB format dönüşümü', () {
      final sonuc = ParaUtils.kisaFisNo('MKP2026000000001');
      expect(sonuc, equals('MKP-000001'));
    });
    test('null güvenli', () {
      expect(ParaUtils.kisaFisNo(null), equals('FİŞ'));
    });
    test('boş string', () {
      expect(ParaUtils.kisaFisNo(''), equals('FİŞ'));
    });
    test('kısa format', () {
      expect(ParaUtils.kisaFisNo('FIS-001'), equals('FIS-001'));
    });
    // Kullanıcı bulgusu: Veritabani._cakismaKorumasiUygula()'nın çakışma
    // önleme eki ("-SYNC<hash>") önceden anlamsız bir 8 karakter kesmeye
    // (ör. "NC2ec87b") düşüyordu — artık okunabilir + işaretli.
    test('senkron çakışması eki (-SYNC) okunabilir hale getirilir', () {
      expect(ParaUtils.kisaFisNo('MKP2026000000003-SYNC2ec87b'),
          equals('MKP-000003 ⚠'));
    });
  });
}
