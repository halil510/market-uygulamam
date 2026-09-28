// test/servisler/otomatik_bulut_cekme_test.dart
//
// Otomatik buluttan çekme (kullanıcı isteği 2026-09-28): aralık/geri çekilme
// hesabı, ayar kaydı ve bulut yapılandırılmamışken hiç çekme yapılmaması.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:market_plus/servisler/bulut/bulut_manager.dart';
import 'package:market_plus/servisler/bulut/otomatik_bulut_cekme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Bekleme süresi', () {
    test('Hata yokken ayarlanan aralık kullanılır', () {
      expect(OtomatikBulutCekme.beklemeHesapla(60, 0), const Duration(seconds: 60));
      expect(OtomatikBulutCekme.beklemeHesapla(30, 0), const Duration(seconds: 30));
    });

    test('Ardışık hatada aralık katlanır', () {
      expect(OtomatikBulutCekme.beklemeHesapla(30, 1), const Duration(seconds: 60));
      expect(OtomatikBulutCekme.beklemeHesapla(30, 2), const Duration(seconds: 120));
    });

    test('Geri çekilme en fazla 5 dakika', () {
      expect(OtomatikBulutCekme.beklemeHesapla(60, 3), const Duration(minutes: 5));
      expect(OtomatikBulutCekme.beklemeHesapla(60, 50), const Duration(minutes: 5));
      expect(OtomatikBulutCekme.beklemeHesapla(300, 1), const Duration(minutes: 5));
    });
  });

  group('Ayar', () {
    test('Varsayılan 60 saniye; seçilen aralık kaydedilir, 0 = kapalı', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await OtomatikBulutCekme.aralikOku(), 60);
      await OtomatikBulutCekme().aralikAyarla(120);
      expect(await OtomatikBulutCekme.aralikOku(), 120);
      await OtomatikBulutCekme().aralikAyarla(0);
      expect(await OtomatikBulutCekme.aralikOku(), 0);
      expect(OtomatikBulutCekme.secenekler, contains(0));
    });
  });

  test('Bulut yapılandırılmamışken çekme yapılmaz (ağa hiç çıkılmaz)', () async {
    BulutManager().durum.value = BulutDurum.yapilandirilmamis;
    expect(await OtomatikBulutCekme().simdiCek(), isNull);
    expect(OtomatikBulutCekme().sonKontrol.value, isNull);
  });
}
