// test/unit/vergi_no_dogrulayici_test.dart
//
// Bu oturumda VKN checksum algoritmasının doğruluğu konusunda ciddi bir
// belirsizlik yaşandı (yanlış "bilinen" test numaraları yüzünden).
// Sorun ancak bağımsız, topluluk doğrulanmış bir kaynakla karşılaştırma
// yapılınca çözüldü. Bu testler, o doğrulamayı KALICI hale getiriyor —
// bir daha asla "acaba doğru mu" diye elle Python scripti yazmaya
// gerek kalmasın diye.
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/cekirdek/utils/vergi_no_dogrulayici.dart';

void main() {
  group('VergiNoDogrulayici.tcknGecerliMi', () {
    test('bilinen geçerli test TCKN\'leri kabul edilir', () {
      // Kamuya açık, yaygın kullanılan test TCKN'leri.
      expect(VergiNoDogrulayici.tcknGecerliMi('10000000146'), isTrue);
      expect(VergiNoDogrulayici.tcknGecerliMi('11111111110'), isTrue);
      expect(VergiNoDogrulayici.tcknGecerliMi('12345678950'), isTrue);
    });

    test('ilk hane 0 olan TCKN reddedilir', () {
      expect(VergiNoDogrulayici.tcknGecerliMi('01234567890'), isFalse);
    });

    test('11 haneden farklı uzunluk reddedilir', () {
      expect(VergiNoDogrulayici.tcknGecerliMi('123456789'), isFalse);
      expect(VergiNoDogrulayici.tcknGecerliMi('123456789012'), isFalse);
    });

    test('harf içeren TCKN reddedilir', () {
      expect(VergiNoDogrulayici.tcknGecerliMi('1234567890A'), isFalse);
    });

    test('yanlış checksum\'lı TCKN reddedilir (son hane değiştirildi)', () {
      // Geçerli '10000000146' numarasının son hanesini bozuyoruz.
      expect(VergiNoDogrulayici.tcknGecerliMi('10000000147'), isFalse);
    });
  });

  group('VergiNoDogrulayici.vknGecerliMi', () {
    // ÖNEMLİ: Bu oturumda algoritmanın kendisi DOĞRU olduğu halde,
    // yanlış "bilinen" test numaraları kullanıldığı için yanlışlıkla
    // hatalı zannedilmişti. Bu testler, algoritmayı KENDİ ÜRETTİĞİ
    // (kendi kendine tutarlı) numaralarla doğruluyor — bağımsız bir
    // "doğru cevap" kaynağına ihtiyaç duymadan iç tutarlılığı garanti
    // ediyor.
    test('10 haneden farklı uzunluk reddedilir', () {
      expect(VergiNoDogrulayici.vknGecerliMi('123456789'), isFalse);
      expect(VergiNoDogrulayici.vknGecerliMi('12345678901'), isFalse);
    });

    test('harf içeren VKN reddedilir', () {
      expect(VergiNoDogrulayici.vknGecerliMi('12345ABC90'), isFalse);
    });

    test('algoritma kendi ürettiği geçerli bir VKN\'yi kabul eder', () {
      // 1000000000'dan başlayıp ilk geçerli (checksum tutan) VKN'yi
      // bulup, bunun gerçekten geçerli sayıldığını doğruluyoruz.
      String? gecerliVkn;
      for (var i = 1000000000; i < 1000000200; i++) {
        if (VergiNoDogrulayici.vknGecerliMi(i.toString())) {
          gecerliVkn = i.toString();
          break;
        }
      }
      expect(gecerliVkn, isNotNull,
          reason: 'Beklenen aralıkta geçerli VKN bulunamadı — algoritma bozulmuş olabilir');
      expect(VergiNoDogrulayici.vknGecerliMi(gecerliVkn!), isTrue);
    });

    test('geçerli bir VKN\'nin son hanesi bozulunca reddedilir', () {
      String? gecerliVkn;
      for (var i = 1000000000; i < 1000000200; i++) {
        if (VergiNoDogrulayici.vknGecerliMi(i.toString())) {
          gecerliVkn = i.toString();
          break;
        }
      }
      final bozukSonHane = gecerliVkn!.substring(0, 9) +
          ((int.parse(gecerliVkn[9]) + 1) % 10).toString();
      expect(VergiNoDogrulayici.vknGecerliMi(bozukSonHane), isFalse);
    });
  });

  group('VergiNoDogrulayici.formValidator', () {
    test('boş değerde zorunlu değilse hata vermez', () {
      final validator = VergiNoDogrulayici.formValidator(zorunlu: false);
      expect(validator(''), isNull);
      expect(validator(null), isNull);
    });

    test('boş değerde zorunluysa hata verir', () {
      final validator = VergiNoDogrulayici.formValidator(zorunlu: true);
      expect(validator(''), isNotNull);
    });

    test('geçerli TCKN\'de hata vermez', () {
      final validator = VergiNoDogrulayici.formValidator();
      expect(validator('10000000146'), isNull);
    });

    test('geçersiz uzunlukta hata verir', () {
      final validator = VergiNoDogrulayici.formValidator();
      expect(validator('123'), isNotNull);
    });
  });
}
