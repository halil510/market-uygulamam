// test/servisler/utc_damga_test.dart
//
// Buluta giden last_updated damgası her zaman GERÇEK UTC olmalı. Bulut
// kontrolünde (2026-09-28) SQLite CURRENT_TIMESTAMP ile yazılmış damgaların
// (satislar/cari/masa…) bulutta 3 saat GERİDE olduğu görüldü: dilimsiz UTC
// metni yerel saat sanılıp bir kez daha UTC'ye çevriliyordu. Geride kalan
// damga, diğer kasaların "Buluttan Al" filigranının gerisinde kalıp
// ATLANABİLİR.
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/servisler/kolon_haritalama.dart';

void main() {
  group('KolonHaritalama.utcDamga', () {
    test('SQLite CURRENT_TIMESTAMP biçimi (boşluklu) zaten UTC — kaydırılmaz', () {
      expect(KolonHaritalama.utcDamga('2026-09-28 09:26:48'), '2026-09-28T09:26:48.000Z');
    });

    test('SQLite biçimi kesirli saniyeyle de UTC sayılır', () {
      expect(KolonHaritalama.utcDamga('2026-09-28 09:26:48.5'), '2026-09-28T09:26:48.500Z');
    });

    test("Dart'ın dilimsiz yerel damgası ('T' ayraçlı) yerel saat olarak UTC'ye çevrilir", () {
      final yerel = DateTime(2026, 9, 28, 12, 26, 48);
      expect(KolonHaritalama.utcDamga(yerel.toIso8601String()),
          yerel.toUtc().toIso8601String());
    });

    test('Zaten UTC (Z) olan damga değişmez', () {
      expect(KolonHaritalama.utcDamga('2026-09-28T09:26:48.000Z'), '2026-09-28T09:26:48.000Z');
    });

    test('DateTime nesnesi UTC metne çevrilir; null → null', () {
      final t = DateTime.utc(2026, 9, 28, 9, 26, 48);
      expect(KolonHaritalama.utcDamga(t), '2026-09-28T09:26:48.000Z');
      expect(KolonHaritalama.utcDamga(null), isNull);
    });
  });
}
