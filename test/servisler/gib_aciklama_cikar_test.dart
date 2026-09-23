// test/servisler/gib_aciklama_cikar_test.dart
//
// gibAciklamaCikar() — GİB/entegratör durum yanıtından red sebebi vb.
// açıklamayı çıkarır. Önceden yalnızca `status` okunuyor, sebep atılıyordu.
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/servisler/gib/gib_tipleri.dart';

void main() {
  group('gibAciklamaCikar', () {
    test('reason alanını döndürür', () {
      expect(gibAciklamaCikar({'status': 'REJECTED', 'reason': 'VKN hatalı'}), 'VKN hatalı');
    });

    test('reason yoksa message kullanılır', () {
      expect(gibAciklamaCikar({'status': 'REJECTED', 'message': 'Şema hatası'}), 'Şema hatası');
    });

    test('reason, message\'dan önceliklidir', () {
      expect(
          gibAciklamaCikar({'status': 'x', 'message': 'genel', 'reason': 'özel'}), 'özel');
    });

    test('iç içe error.message desteklenir', () {
      expect(
          gibAciklamaCikar({'status': 'REJECTED', 'error': {'message': 'Mükerrer ETTN'}}),
          'Mükerrer ETTN');
    });

    test('durum kodunun kendisini açıklama saymaz', () {
      expect(gibAciklamaCikar({'status': 'REJECTED', 'message': 'rejected'}), isNull);
    });

    test('boş/eksik alanlarda null döner', () {
      expect(gibAciklamaCikar(null), isNull);
      expect(gibAciklamaCikar({'status': 'APPROVED'}), isNull);
      expect(gibAciklamaCikar({'status': 'REJECTED', 'reason': '   '}), isNull);
    });
  });
}
