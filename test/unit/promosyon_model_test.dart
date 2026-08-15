import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/modeller/promosyon_model.dart';

void main() {
  group('PromosyonModel', () {
    test('gecerli - aktif', () {
      final p = PromosyonModel(
        urunId: 1, promosyonAdi: 'Test',
        aktif: true,
        baslangicTarihi: DateTime.now().subtract(const Duration(days: 1)),
        bitisTarihi: DateTime.now().add(const Duration(days: 1)),
      );
      expect(p.gecerli, isTrue);
    });

    test('geçersiz - süresi dolmuş', () {
      final p = PromosyonModel(
        urunId: 1, promosyonAdi: 'Test',
        aktif: true,
        bitisTarihi: DateTime.now().subtract(const Duration(days: 1)),
      );
      expect(p.gecerli, isFalse);
    });

    test('geçersiz - pasif', () {
      final p = PromosyonModel(urunId: 1, promosyonAdi: 'Test', aktif: false);
      expect(p.gecerli, isFalse);
    });

    test('copyWith', () {
      final p = PromosyonModel(urunId: 1, promosyonAdi: 'Test', iskontoOran: 10);
      final p2 = p.copyWith(iskontoOran: 20, aktif: false);
      expect(p2.iskontoOran, equals(20));
      expect(p2.aktif, isFalse);
      expect(p2.urunId, equals(1)); // değişmemeli
    });
  });
}
