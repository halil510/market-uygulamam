// test/veri/fis_yedek_kasa_no_test.dart
//
// Çoklu cihaz analizi (2026-11-08): bulut hiç bağlanmamış (terminal kaydı
// olmayan) iki cihaz aynı fiş numaralarını üretiyordu — WiFi aktarımında
// biri "-SYNC kopya" sayılıp Gün Sonu'ndan gizleniyordu. Artık terminalsiz
// cihaz, cihaz kimliğinden türetilen yedek kasa no'su (50–99) kullanır.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

void main() {
  group('fisYedekKasaNo', () {
    test('50–99 aralığında ve aynı cihaz için hep aynı', () {
      for (final id in ['cihaz_1791530174895', 'cihaz_1792684853498', 'cihaz_1', 'abc']) {
        final n = fisYedekKasaNo(id);
        expect(n, inInclusiveRange(50, 99));
        expect(fisYedekKasaNo(id), n);
      }
    });

    test('farklı kurulumlar farklı no alır (sahadaki üç cihaz)', () {
      final nolar = {
        fisYedekKasaNo('cihaz_1791530174895'),
        fisYedekKasaNo('cihaz_1791888051684'),
        fisYedekKasaNo('cihaz_1792684853498'),
      };
      expect(nolar, hasLength(3));
    });
  });

  group('fisNoUret — terminal kaydı yok', () {
    late Database db;
    setUp(() async {
      db = await TestVeritabani.olustur();
      Veritabani.testVeritabani = db;
    });
    tearDown(() async {
      Veritabani.testVeritabani = null;
      await db.close();
    });

    Future<String> uret(String cihazId, String tip) async {
      SharedPreferences.setMockInitialValues({'mp_cihaz_id': cihazId});
      return Veritabani().fisNoUret(tip);
    }

    test('iki bulutsuz cihazın satış fiş numaraları çakışmaz', () async {
      final a = await uret('cihaz_1791530174895', 'satis');
      await db.delete('fis_seri'); // ikinci cihaz: kendi sayacı sıfırdan
      final b = await uret('cihaz_1792684853498', 'satis');
      expect(a, hasLength(16));
      expect(b, hasLength(16));
      expect(a, isNot(b));
      final yil = DateTime.now().year;
      expect(a.substring(0, 7), 'MKP$yil');
      expect(int.parse(a.substring(7, 9)), fisYedekKasaNo('cihaz_1791530174895'));
    });

    test('fatura numarası kasa no almaz (GİB biçimi değişmedi)', () async {
      final f = await uret('cihaz_1791530174895', 'fatura');
      expect(f, 'FAT${DateTime.now().year}000000001');
    });
  });
}
