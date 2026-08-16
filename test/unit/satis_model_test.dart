import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/modeller/satis_model.dart';

void main() {
  group('SatisModel', () {
    late SatisModel satis;

    setUp(() {
      satis = SatisModel(
        tarih: DateTime(2026, 6, 3),
        genelToplam: 90.0,
        odenenTutar: 100.0,
        fisNo: 'MKP2026000000001',
        fisTipi: 'Satış',
      );
    });

    test('kalanTutar - fazla ödendi', () {
      expect(satis.kalanTutar, equals(-10.0));
    });

    test('kalanTutar - ödenmedi', () {
      final s = SatisModel(
        tarih: DateTime.now(), genelToplam: 100.0, odenenTutar: 0.0);
      expect(s.kalanTutar, equals(100.0));
    });

    test('fromMap null güvenli', () {
      final map = <String, dynamic>{
        'tarih': '2026-06-03T10:00:00.000',
        'toplam_tutar': 100.0,
        'genel_toplam': 90.0,
        'odenen_tutar': 0.0,
        'fis_tipi': 'Satış',
      };
      final s = SatisModel.fromMap(map);
      expect(s.genelToplam, equals(90.0));
      expect(s.fisNo, isNull);
      expect(s.iptal, isFalse);
    });

    test('toMap id içermez (null id)', () {
      final map = satis.toMap();
      expect(map.containsKey('id'), isFalse);
    });

    test('copyWith', () {
      final s2 = satis.copyWith(aciklama: 'Test');
      expect(s2.aciklama, equals('Test'));
      expect(s2.genelToplam, equals(satis.genelToplam));
    });
  });
}
