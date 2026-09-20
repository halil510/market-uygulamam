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

  // Madde 34 (Barkod/POS) denetimi, 2026-09-20: gs1128Coz() önceden
  // yazılmıştı ama HİÇBİR YERDEN çağrılmıyordu (ölü kod) — artık
  // hizli_satis_ekrani_barkod.dart'ta gerçek GS1-128 tarama akışında
  // kullanılıyor. Bu testler o fonksiyonun DOĞRU parse ettiğini
  // doğruluyor (daha önce hiç test edilmemişti).
  group('BarkodServisi.gs1128Coz — GS1-128 Application Identifier ayrıştırma', () {
    test('sabit uzunluklu AI(01) GTIN doğru ayıklanır', () {
      final sonuc = BarkodServisi.gs1128Coz('(01)08691234567890');
      expect(sonuc['AI_01'], equals('08691234567890'));
    });

    test('AI(01) GTIN + AI(17) SKT + değişken uzunluklu AI(10) LOT birlikte doğru ayrıştırılır', () {
      final sonuc = BarkodServisi.gs1128Coz('(01)08691234567890(17)261231(10)LOT123');
      expect(sonuc['AI_01'], equals('08691234567890'));
      expect(sonuc['AI_17'], equals('261231'));
      expect(sonuc['AI_10'], equals('LOT123'));
    });

    test('parantezsiz (ham GS1-128 tarayıcı çıktısı) da aynı şekilde çözülür', () {
      // '(01)08691234567890(17)261231(10)LOT123' ile AYNI veri, sadece
      // parantezler kaldırılmış hali (bazı tarayıcılar FNC1'i böyle iletir).
      final sonuc = BarkodServisi.gs1128Coz('01086912345678901726123110LOT123');
      expect(sonuc['AI_01'], equals('08691234567890'));
      expect(sonuc['AI_17'], equals('261231'));
      expect(sonuc['AI_10'], equals('LOT123'));
    });

    test('14 haneli GTIN, baştaki dolgu sıfırı çıkarılınca geçerli bir EAN-13 (Türkiye prefix) olur '
        '— hizli_satis_ekrani_barkod.dart\'taki arama kademesinin dayandığı varsayım', () {
      final sonuc = BarkodServisi.gs1128Coz('(01)08691234567890');
      final gtin = sonuc['AI_01']!;
      expect(gtin.length, 14);
      final ean13Adayi = gtin.substring(1);
      expect(ean13Adayi, equals('8691234567890'));
      expect(BarkodServisi.barkodTurunuBul(ean13Adayi), equals(BarkodTuru.ean13Turkiye));
    });
  });
}
