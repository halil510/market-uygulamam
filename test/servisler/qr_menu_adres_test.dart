// test/servisler/qr_menu_adres_test.dart
//
// Derin analiz 2026-10-07 (A2): QR menüsünün yerel IP seçimi ve adres üretimi.
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/servisler/masa/qr_menu_adresi.dart';
import 'package:market_plus/servisler/masa/qr_menu_sunucu_servisi.dart';
import 'package:shared_preferences/shared_preferences.dart';

({String ad, List<String> adresler}) _a(String ad, String adres) =>
    (ad: ad, adresler: [adres]);

void main() {
  group('enIyiYerelIp', () {
    test('WiFi kapalıyken mobil veri (rmnet 10.x) IP\'si SEÇİLMEZ', () {
      expect(QrMenuSunucuServisi.enIyiYerelIp([_a('rmnet_data0', '10.45.12.7')]), isNull);
    });

    test('WiFi ve mobil veri birlikteyken WiFi seçilir', () {
      expect(
        QrMenuSunucuServisi.enIyiYerelIp([
          _a('rmnet_data0', '10.45.12.7'),
          _a('wlan0', '192.168.1.34'),
        ]),
        '192.168.1.34',
      );
    });

    test('Windows: sanal Hyper-V/WSL arayüzü yerine Wi-Fi seçilir', () {
      expect(
        QrMenuSunucuServisi.enIyiYerelIp([
          _a('vEthernet (WSL)', '172.20.80.1'),
          _a('Wi-Fi', '10.0.0.12'),
        ]),
        '10.0.0.12',
      );
    });

    test('İngilizce Windows kablolu ağ adı ("Local Area Connection") elenmez', () {
      expect(
        QrMenuSunucuServisi.enIyiYerelIp([_a('Local Area Connection', '192.168.0.5')]),
        '192.168.0.5',
      );
    });

    test('loopback, link-local ve genel IP\'ler seçilmez', () {
      expect(
        QrMenuSunucuServisi.enIyiYerelIp([
          _a('lo', '127.0.0.1'),
          _a('wlan0', '169.254.3.3'),
          _a('eth0', '85.10.1.2'),
        ]),
        isNull,
      );
    });

    test('adı bilinmeyen arayüzde özel aralık önceliği: 192.168 > 10. > 172.16-31', () {
      expect(
        QrMenuSunucuServisi.enIyiYerelIp([
          _a('x1', '172.16.0.9'),
          _a('x2', '10.1.1.1'),
          _a('x3', '192.168.5.5'),
        ]),
        '192.168.5.5',
      );
      expect(QrMenuSunucuServisi.enIyiYerelIp([_a('x', '172.32.0.1')]), isNull,
          reason: '172.32 özel aralıkta değil');
    });
  });

  group('QrMenuAdresi', () {
    test('bulut adresi tanımlıysa masa parametresi doğru ayraçla eklenir', () async {
      SharedPreferences.setMockInitialValues(
          {QrMenuAdresi.bulutUrlAnahtari: ' https://menu.ornek.com/?isletme=5 '});
      final adres = await QrMenuAdresi.coz();
      expect(adres, isNotNull);
      expect(adres!.bulut, isTrue);
      expect(adres.masaUrl(3), 'https://menu.ornek.com/?isletme=5&masa=3');

      SharedPreferences.setMockInitialValues(
          {QrMenuAdresi.bulutUrlAnahtari: 'https://menu.ornek.com'});
      expect((await QrMenuAdresi.coz())!.masaUrl(7), 'https://menu.ornek.com?masa=7');
    });

    test('yerel URL biçimi', () {
      expect(QrMenuSunucuServisi.yerelMasaUrl('192.168.1.2', 4),
          'http://192.168.1.2:${QrMenuSunucuServisi.port}/menu/4');
    });
  });
}
