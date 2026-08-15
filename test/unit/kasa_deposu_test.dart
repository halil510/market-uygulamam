import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/modeller/kasa_hareket_model.dart';

void main() {
  group('KasaHareketModel', () {
    test('Giriş tipi - tutar pozitif', () {
      final h = KasaHareketModel(
        hareketTipi: 'Tahsilat',
        tutar: 100.0,
        tarih: DateTime.now(),
      );
      expect(h.tutar, 100.0);
      expect(h.hareketTipi, 'Tahsilat');
    });

    test('copyWith çalışır', () {
      final h = KasaHareketModel(
        hareketTipi: 'Satış',
        tutar: 50.0,
        tarih: DateTime.now(),
      );
      final h2 = h.copyWith(tutar: 75.0);
      expect(h2.tutar, 75.0);
      expect(h2.hareketTipi, 'Satış');
    });

    test('fromMap round-trip', () {
      final now = DateTime.now();
      final map = <String, dynamic>{
        'hareket_tipi': 'Gider',
        'tutar': 200.0,
        'tarih': now.toIso8601String(),
      };
      final h = KasaHareketModel.fromMap(map);
      expect(h.hareketTipi, 'Gider');
      expect(h.tutar, 200.0);
    });
  });
}
