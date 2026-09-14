// test/servisler/ai_anlayici_test.dart
//
// Kullanıcı bulgusu — "ai chat düzgün yapmıyor, cari ismi veriyorum
// bana sipariş önerileri diyor": AiIntent.oneri (Sipariş Önerileri)
// tetikleyicileri arasında bağımsız/tek başına "öner" kelimesi vardı.
// "Öner" gerçek, yaygın bir Türk soyadı — bu, "cari" kelimesi hiç
// geçmeyen, sadece müşteri adı "Öner" (veya bu 4 harfi içeren HERHANGİ
// bir isim) olan HER soruyu yanlışlıkla Sipariş Önerileri'ne
// yönlendiriyordu.
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/servisler/ai/ai_anlayici.dart';
import 'package:market_plus/servisler/ai/ai_modeller.dart';

void main() {
  group('AiAnlayici.anla — "öner" içeren isimler yanlış yakalanmaz', () {
    test('sadece "Öner" soyadı geçen bir soru artık Sipariş Önerileri '
        'sayılmaz', () {
      expect(AiAnlayici.anla('Öner').intent, isNot(equals(AiIntent.oneri)));
    });

    test('"Öner ne kadar borçlu" cari sorgusu doğru tanınır (öner değil)', () {
      final soru = AiAnlayici.anla('Öner ne kadar borçlu');
      expect(soru.intent, equals(AiIntent.cariBorc));
    });

    test('"Önerşan Ticaret" gibi "öner" alt dizesi barındıran bir isim '
        'de Sipariş Önerileri\'ne kaçırılmaz', () {
      expect(AiAnlayici.anla('Önerşan Ticaret').intent,
          isNot(equals(AiIntent.oneri)));
    });
  });

  group('AiAnlayici.anla — asıl "sipariş öner" niyeti hâlâ çalışıyor', () {
    test('"sipariş öner" kalıbı Sipariş Önerileri olarak tanınmaya devam eder', () {
      expect(AiAnlayici.anla('sipariş öner').intent, equals(AiIntent.oneri));
    });

    test('"ne sipariş vermeliyim" kalıbı Sipariş Önerileri olarak tanınır', () {
      expect(AiAnlayici.anla('ne sipariş vermeliyim').intent,
          equals(AiIntent.oneri));
    });
  });
}
