import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/modeller/kredi_karti_model.dart';

void main() {
  group('KrediKartiModel.maskele — GÜVENLİK', () {
    // Bu testler, kredi kartı numarasının ASLA düz metin saklanmadığını
    // doğrular (bkz. DERIN_YOL_HARITASI.md madde A1). Herhangi bir
    // regresyon bu testleri kırar.

    test('16 haneli kart numarası sadece son 4 haneyi gösterir', () {
      final maskeli = KrediKartiModel.maskele('4111111111111234');
      expect(maskeli, equals('**** **** **** 1234'));
      expect(maskeli, isNot(contains('4111111111')));
    });

    test('boşluklu kart numarası doğru maskelenir', () {
      final maskeli = KrediKartiModel.maskele('4111 1111 1111 5678');
      expect(maskeli, equals('**** **** **** 5678'));
    });

    test('kısa/eksik numara güvenli şekilde işlenir', () {
      final maskeli = KrediKartiModel.maskele('12');
      expect(maskeli, equals('**** **** **** 12'));
    });

    test('boş string çökmeden işlenir', () {
      final maskeli = KrediKartiModel.maskele('');
      expect(maskeli, equals('**** **** **** ????'));
    });

    test('maskelenmiş sonuç asla orijinal tam numarayı içermez', () {
      const tamNumara = '5312345678901234';
      final maskeli = KrediKartiModel.maskele(tamNumara);
      // Sadece son 4 hane ('1234') görünür olmalı, geri kalanı asla
      expect(maskeli.contains('531234567890'), isFalse);
    });

    test('fromMap eski (göç etmemiş) kayıtları geriye dönük okuyabilir', () {
      // Migration öncesi bazı satırlarda hâlâ eski "kart_no" kolonu olabilir
      final m = <String, dynamic>{
        'banka_id': 1,
        'kart_adi': 'İş Bankası Kartım',
        'kart_no': '**** **** **** 9999', // eski kayıt
      };
      final k = KrediKartiModel.fromMap(m);
      expect(k.kartNoMaskeli, equals('**** **** **** 9999'));
    });

    test('fromMap yeni kolonu (kart_no_maskeli) önceliklendirir', () {
      final m = <String, dynamic>{
        'banka_id': 1,
        'kart_adi': 'Kart',
        'kart_no_maskeli': '**** **** **** 4242',
        'kart_no': '**** **** **** 9999', // artık kullanılmıyor
      };
      final k = KrediKartiModel.fromMap(m);
      expect(k.kartNoMaskeli, equals('**** **** **** 4242'));
    });

    test('toMap çıktısında "cvc" veya "kart_no" alanı ASLA olmaz', () {
      const k = KrediKartiModel(
        bankaId: 1,
        kartAdi: 'Test Kart',
        kartNoMaskeli: '**** **** **** 1111',
      );
      final map = k.toMap();
      expect(map.containsKey('cvc'), isFalse);
      expect(map.containsKey('kart_no'), isFalse);
      expect(map.containsKey('kart_no_maskeli'), isTrue);
    });
  });

  group('KrediKartiModel — genel alanlar', () {
    test('varsayılan değerler doğru', () {
      const k = KrediKartiModel(
        bankaId: 1,
        kartAdi: 'Test',
        kartNoMaskeli: '**** **** **** 0000',
      );
      expect(k.kartTipi, equals('Diğer'));
      expect(k.kartLimit, equals(0));
      expect(k.taksitSayisi, equals(1));
      expect(k.aktif, isTrue);
    });

    test('fromMap sayısal alanları güvenli çevirir', () {
      final m = <String, dynamic>{
        'banka_id': 2,
        'kart_adi': 'Kart',
        'kart_no_maskeli': '**** **** **** 4444',
        'kartlimit': 15000,
        'kullanilan_limit': 3200.5,
        'taksit_sayisi': 3,
      };
      final k = KrediKartiModel.fromMap(m);
      expect(k.kartLimit, equals(15000.0));
      expect(k.kullanilanLimit, equals(3200.5));
      expect(k.taksitSayisi, equals(3));
    });
  });
}
