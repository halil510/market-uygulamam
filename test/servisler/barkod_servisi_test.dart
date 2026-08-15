import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/servisler/barkod_servisi.dart';

void main() {
  group('BarkodServisi.gecerliBarkodMu', () {
    test('boş barkod geçersiz', () {
      expect(BarkodServisi.gecerliBarkodMu(''), isFalse);
    });
    test('sadece rakam geçerli', () {
      expect(BarkodServisi.gecerliBarkodMu('8691234567890'), isTrue);
    });
    test('harf+rakam geçerli', () {
      expect(BarkodServisi.gecerliBarkodMu('ABC-123'), isTrue);
    });
    test('geçersiz özel karakter içeren barkod reddedilir', () {
      expect(BarkodServisi.gecerliBarkodMu('abc@#%'), isFalse);
    });
  });

  group('BarkodServisi.ean13Gecerli — GS1 kontrol basamağı', () {
    test('geçerli EAN-13 (Nivea test barkodu) doğrulanır', () {
      expect(BarkodServisi.ean13Gecerli('4006381333931'), isTrue);
    });
    test('yanlış kontrol basamaklı EAN-13 reddedilir', () {
      expect(BarkodServisi.ean13Gecerli('4006381333930'), isFalse);
    });
    test('13 haneden farklı uzunluk reddedilir', () {
      expect(BarkodServisi.ean13Gecerli('123456789'), isFalse);
    });
    test('harf içeren barkod reddedilir', () {
      expect(BarkodServisi.ean13Gecerli('400638133393A'), isFalse);
    });
  });

  group('BarkodServisi.ean8Gecerli', () {
    test('geçerli EAN-8 doğrulanır', () {
      expect(BarkodServisi.ean8Gecerli('40123455'), isTrue);
    });
    test('yanlış kontrol basamaklı EAN-8 reddedilir', () {
      expect(BarkodServisi.ean8Gecerli('40123456'), isFalse);
    });
    test('8 haneden farklı uzunluk reddedilir', () {
      expect(BarkodServisi.ean8Gecerli('4012345'), isFalse);
    });
  });

  group('BarkodServisi.itf14Gecerli', () {
    test('geçerli ITF-14 doğrulanır', () {
      expect(BarkodServisi.itf14Gecerli('10000000000007'), isTrue);
    });
    test('yanlış kontrol basamaklı ITF-14 reddedilir', () {
      expect(BarkodServisi.itf14Gecerli('10000000000008'), isFalse);
    });
  });

  group('BarkodServisi.barkodTurunuBul — tür tespiti', () {
    test('14 haneli sayısal -> itf14', () {
      expect(BarkodServisi.barkodTurunuBul('10000000000007'),
          equals(BarkodTuru.itf14));
    });
    test('868 ile başlayan geçerli EAN13 -> ean13Turkiye', () {
      expect(BarkodServisi.barkodTurunuBul('8681234567891'),
          equals(BarkodTuru.ean13Turkiye));
    });
    test('20-29 prefixli 13 haneli -> tartimEan13', () {
      expect(BarkodServisi.barkodTurunuBul('2112345012346'),
          equals(BarkodTuru.tartimEan13));
    });
    test('diğer 13 haneli -> ean13', () {
      expect(BarkodServisi.barkodTurunuBul('4006381333931'),
          equals(BarkodTuru.ean13));
    });
    test('8 haneli sayısal -> ean8', () {
      expect(BarkodServisi.barkodTurunuBul('40123455'),
          equals(BarkodTuru.ean8));
    });
    test('4-5 haneli sayısal -> plu', () {
      expect(BarkodServisi.barkodTurunuBul('1234'), equals(BarkodTuru.plu));
      expect(BarkodServisi.barkodTurunuBul('12345'), equals(BarkodTuru.plu));
    });
    test('boş barkod -> bilinmiyor', () {
      expect(BarkodServisi.barkodTurunuBul(''), equals(BarkodTuru.bilinmiyor));
    });
    test('20 haneden uzun alfanümerik -> qrDataMatrix', () {
      expect(
          BarkodServisi.barkodTurunuBul('ABCDEFGHIJKLMNOPQRSTUVWXYZ123456'),
          equals(BarkodTuru.qrDataMatrix));
    });
  });

  group('BarkodServisi.tartimBarkodCoz — GS1-TR tartım barkodu', () {
    test('geçerli tartım barkodu doğru çözülür', () {
      final sonuc = BarkodServisi.tartimBarkodCoz('2112345012346');
      expect(sonuc, isNotNull);
      expect(sonuc!.urunKodu, equals('12345'));
      expect(sonuc.miktarGram, equals(1234));
      expect(sonuc.miktarKg, closeTo(1.234, 0.001));
      expect(sonuc.prefix, equals(21));
    });

    test('prefix 20-29 dışındaysa null döner', () {
      // Aynı gövdeyi kullanıp geçerli bir 30 prefix + doğru checksum ile
      // deneyelim; prefix aralık dışı olduğu için sonuç null olmalı.
      final sonuc = BarkodServisi.tartimBarkodCoz('4006381333931'); // ean13, prefix 40
      expect(sonuc, isNull);
    });

    test('13 haneden farklı uzunlukta null döner', () {
      expect(BarkodServisi.tartimBarkodCoz('211234501234'), isNull);
    });

    test('geçersiz kontrol basamağıyla null döner', () {
      expect(BarkodServisi.tartimBarkodCoz('2112345012340'), isNull);
    });
  });
}
