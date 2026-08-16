import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/modeller/gider_model.dart';

void main() {
  group('GiderModel', () {
    test('fromMap tam sayı tutarı double çevirir', () {
      final m = <String, dynamic>{
        'kategori_id': 1,
        'kategori_adi': 'Kira',
        'tutar': 1500, // int olarak geliyor (SQLite)
        'tarih': '2026-01-15T00:00:00.000',
      };
      final g = GiderModel.fromMap(m);
      expect(g.tutar, equals(1500.0));
      expect(g.tutar, isA<double>());
    });

    test('fromMap ondalıklı tutarı korur', () {
      final m = <String, dynamic>{
        'kategori_id': 2,
        'tutar': 249.90,
        'tarih': '2026-01-15T00:00:00.000',
      };
      final g = GiderModel.fromMap(m);
      expect(g.tutar, equals(249.90));
    });

    test('geçersiz tarih güvenli şekilde şimdiki zamana düşer', () {
      final m = <String, dynamic>{
        'kategori_id': 1,
        'tutar': 100.0,
        'tarih': 'gecersiz-tarih',
      };
      final g = GiderModel.fromMap(m);
      expect(g.tarih, isA<DateTime>());
    });

    test('varsayılan ödeme yöntemi Nakit', () {
      final g = GiderModel(
        kategoriId: 1,
        tutar: 100,
        tarih: DateTime(2026, 1, 1),
      );
      expect(g.odemeYontemi, equals('Nakit'));
    });

    test('copyWith sadece belirtilen alanı değiştirir', () {
      final g = GiderModel(
        kategoriId: 1,
        kategoriAdi: 'Kira',
        tutar: 1000,
        tarih: DateTime(2026, 1, 1),
      );
      final g2 = g.copyWith(tutar: 1200);
      expect(g2.tutar, equals(1200));
      expect(g2.kategoriAdi, equals('Kira'));
      expect(g2.kategoriId, equals(1));
    });
  });
}
