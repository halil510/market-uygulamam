// test/veri/sync_cakisma_tespit_test.dart
//
// Sync Çakışmaları özelliğinin (protokol §12) çekirdek fark-tespit
// mantığını test eder — Veritabani.supaKayitlariGuncelle() içinde, bir
// kaydın gelen (buluttan) sürümüyle üzerine yazılmadan ÖNCE çağrılır.
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/veri/database/sync_cakisma_tespit.dart';

void main() {
  group('SyncCakismaTespit.farklariBul', () {
    test('aynı veri, sadece last_updated farklıysa çakışma YOK', () {
      final yerel = {'id': 1, 'global_id': 'g1', 'ad': 'Ürün', 'fiyat': 100,
        'last_updated': '2026-01-01T10:00:00'};
      final gelen = {'global_id': 'g1', 'ad': 'Ürün', 'fiyat': 100,
        'last_updated': '2026-01-01T10:00:05'};

      expect(SyncCakismaTespit.farklariBul(yerel, gelen), isEmpty);
    });

    test('gerçek fiyat farkı varsa çakışma tespit edilir', () {
      final yerel = {'id': 1, 'global_id': 'g1', 'ad': 'Ürün', 'fiyat': 125,
        'last_updated': '2026-01-01T10:00:00'};
      final gelen = {'global_id': 'g1', 'ad': 'Ürün', 'fiyat': 129,
        'last_updated': '2026-01-01T10:00:03'};

      final farklar = SyncCakismaTespit.farklariBul(yerel, gelen);
      expect(farklar, contains('fiyat'));
      expect(farklar['fiyat'], equals({'yerel': 125, 'gelen': 129}));
      expect(farklar.containsKey('ad'), isFalse,
          reason: 'ad aynı olduğu için farklar listesinde OLMAMALI');
    });

    test('int/double aynı değer yanlış pozitif üretmez', () {
      final yerel = {'id': 1, 'global_id': 'g1', 'fiyat': 100,
        'last_updated': '2026-01-01T10:00:00'};
      final gelen = {'global_id': 'g1', 'fiyat': 100.0,
        'last_updated': '2026-01-01T10:00:03'};

      expect(SyncCakismaTespit.farklariBul(yerel, gelen), isEmpty);
    });

    test('birden fazla alan farklıysa hepsi raporlanır', () {
      final yerel = {'id': 1, 'global_id': 'g1', 'ad': 'A', 'fiyat': 100, 'stok': 10,
        'last_updated': '2026-01-01T10:00:00'};
      final gelen = {'global_id': 'g1', 'ad': 'B', 'fiyat': 200, 'stok': 10,
        'last_updated': '2026-01-01T10:00:03'};

      final farklar = SyncCakismaTespit.farklariBul(yerel, gelen);
      expect(farklar.keys.toSet(), equals({'ad', 'fiyat'}));
    });

    test('null vs değer farkı yakalanır', () {
      final yerel = {'id': 1, 'global_id': 'g1', 'aciklama': null,
        'last_updated': '2026-01-01T10:00:00'};
      final gelen = {'global_id': 'g1', 'aciklama': 'not eklendi',
        'last_updated': '2026-01-01T10:00:03'};

      final farklar = SyncCakismaTespit.farklariBul(yerel, gelen);
      expect(farklar, contains('aciklama'));
    });
  });
}
