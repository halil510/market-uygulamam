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

    // Kendi-keşif turu bulgusu: showDatePicker saat bilgisi olmadan
    // (00:00:00) bir tarih döndürüyor — bitiş GÜNÜNÜN TAMAMI (o günün
    // herhangi bir saatinde) hâlâ geçerli sayılmalı, sadece bitiş
    // gününden SONRAKİ gün geçersiz olmalı.
    test('geçerli - bitiş GÜNÜNÜN İÇİNDE (saat ne olursa olsun)', () {
      final bugun = DateTime.now();
      final p = PromosyonModel(
        urunId: 1, promosyonAdi: 'Test', aktif: true,
        bitisTarihi: DateTime(bugun.year, bugun.month, bugun.day), // 00:00:00
      );
      expect(p.gecerli, isTrue,
          reason: 'bitiş tarihi BUGÜNSE, günün tamamında geçerli olmalı');
    });

    test('geçersiz - bitiş gününden BİR SONRAKİ gün', () {
      final dun = DateTime.now().subtract(const Duration(days: 1));
      final p = PromosyonModel(
        urunId: 1, promosyonAdi: 'Test', aktif: true,
        bitisTarihi: DateTime(dun.year, dun.month, dun.day),
      );
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
