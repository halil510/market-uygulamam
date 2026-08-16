import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/modeller/banka_model.dart';

void main() {
  group('BankaModel', () {
    test('fromMap null güvenli', () {
      final m = <String, dynamic>{'ad': 'Ziraat Bankası'};
      final b = BankaModel.fromMap(m);
      expect(b.ad, equals('Ziraat Bankası'));
      expect(b.kod, isNull);
      expect(b.aktif, isTrue);
    });

    test('fromMap aktif=0 doğru okunur', () {
      final m = <String, dynamic>{'ad': 'Pasif Banka', 'aktif': 0};
      final b = BankaModel.fromMap(m);
      expect(b.aktif, isFalse);
    });

    test('varsayılan constructor aktif=true', () {
      const b = BankaModel(ad: 'İş Bankası');
      expect(b.aktif, isTrue);
      expect(b.id, isNull);
    });

    test('tüm alanlar fromMap ile doğru eşleşir', () {
      final m = <String, dynamic>{
        'id': 5,
        'ad': 'Garanti BBVA',
        'kod': 'GARAN',
        'tel': '0850 222 00 00',
        'email': 'info@garanti.com',
        'aktif': 1,
      };
      final b = BankaModel.fromMap(m);
      expect(b.id, equals(5));
      expect(b.ad, equals('Garanti BBVA'));
      expect(b.kod, equals('GARAN'));
      expect(b.tel, equals('0850 222 00 00'));
      expect(b.email, equals('info@garanti.com'));
    });
  });
}
