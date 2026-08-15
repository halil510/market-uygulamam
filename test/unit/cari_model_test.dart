import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/modeller/cari_model.dart';

void main() {
  group('CariModel', () {
    test('fromMap temel', () {
      final m = <String, dynamic>{
        'unvan': 'Test Firma',
        'cari_tipi': 'Müşteri',
        'bakiye': 500.0,
      };
      final c = CariModel.fromMap(m);
      expect(c.unvan, equals('Test Firma'));
      expect(c.bakiye, equals(500.0));
      expect(c.aktif, isTrue);
    });

    test('toMap round-trip', () {
      final c = CariModel(
        unvan: 'Test', cariTipi: 'Tedarikçi',
        bakiye: -1000, limitTutari: 5000,
      );
      final map = c.toMap();
      expect(map['unvan'], equals('Test'));
      expect(map['cari_tipi'], equals('Tedarikçi'));
    });

    test('copyWith', () {
      final c = CariModel(unvan: 'A', cariTipi: 'Müşteri');
      final c2 = c.copyWith(bakiye: 999);
      expect(c2.bakiye, equals(999));
      expect(c2.unvan, equals('A'));
    });
  });
}
