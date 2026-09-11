// test/servisler/giris_deneme_sayaci_test.dart
//
// Derin analizde bulundu: brute-force koruması önceden sadece widget
// state'inde (bellekte) vardı, uygulama yeniden başlatılınca sıfırlanıyordu.
// Bu test, artık SharedPreferences'ta kalıcı tutulan GirisDenemeSayaci'nin
// doğru sayıp doğru kilitlediğini doğrular.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:market_plus/servisler/giris_deneme_sayaci.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GirisDenemeSayaci sayaci;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sayaci = const GirisDenemeSayaci(
      maxDeneme: 3,
      kilitSuresi: Duration(seconds: 30),
    );
  });

  group('GirisDenemeSayaci', () {
    test('yeni kullanıcı kilitli değildir', () async {
      expect(await sayaci.kalanKilitSaniyesi('ali'), isNull);
    });

    test('eşik altındaki başarısız denemeler kilitlemez', () async {
      expect(await sayaci.basarisizDenemeKaydet('ali'), isFalse);
      expect(await sayaci.basarisizDenemeKaydet('ali'), isFalse);
      expect(await sayaci.kalanKilitSaniyesi('ali'), isNull);
    });

    test('eşiğe ulaşınca kilitlenir', () async {
      expect(await sayaci.basarisizDenemeKaydet('ali'), isFalse); // 1
      expect(await sayaci.basarisizDenemeKaydet('ali'), isFalse); // 2
      expect(await sayaci.basarisizDenemeKaydet('ali'), isTrue);  // 3 = eşik

      final kalan = await sayaci.kalanKilitSaniyesi('ali');
      expect(kalan, isNotNull);
      expect(kalan, greaterThan(0));
      expect(kalan, lessThanOrEqualTo(30));
    });

    test('farklı kullanıcıların sayaçları birbirinden bağımsızdır', () async {
      await sayaci.basarisizDenemeKaydet('ali');
      await sayaci.basarisizDenemeKaydet('ali');
      await sayaci.basarisizDenemeKaydet('ali'); // ali kilitlendi

      expect(await sayaci.kalanKilitSaniyesi('ali'), isNotNull);
      expect(await sayaci.kalanKilitSaniyesi('veli'), isNull,
          reason: 'veli hiç yanlış deneme yapmadı, kilitli olmamalı');
    });

    test('temizle() sayacı ve kilidi sıfırlar (başarılı giriş sonrası)', () async {
      await sayaci.basarisizDenemeKaydet('ali');
      await sayaci.basarisizDenemeKaydet('ali');
      await sayaci.temizle('ali');

      // Temizlendiği için tekrar 2 deneme daha yapılabilmeli (3'e ulaşmadan)
      expect(await sayaci.basarisizDenemeKaydet('ali'), isFalse);
      expect(await sayaci.kalanKilitSaniyesi('ali'), isNull);
    });

    test('kilit süresi dolunca otomatik açılır', () async {
      final kisaSayac = GirisDenemeSayaci(
        maxDeneme: 1,
        kilitSuresi: const Duration(milliseconds: 50),
      );
      expect(await kisaSayac.basarisizDenemeKaydet('ali'), isTrue);
      expect(await kisaSayac.kalanKilitSaniyesi('ali'), isNotNull);

      await Future.delayed(const Duration(milliseconds: 100));

      expect(await kisaSayac.kalanKilitSaniyesi('ali'), isNull,
          reason: 'Kilit süresi dolduğu için serbest kalmalı');
    });
  });
}
