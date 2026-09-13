// test/servisler/onay_merkezi_servisi_test.dart
//
// FAZ 9 — Onay Merkezi (bildirim tipi): eşik kontrolü saf fonksiyonu +
// onay_talepleri tablosunun gerçek şema üzerinde doğrulanması.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/servisler/onay_merkezi_servisi.dart';
import '../helper/test_initializer.dart';

void main() {
  group('onayEsikiAsildiMi', () {
    test('eşik <= 0 ise kontrol devre dışıdır (limitKontrolEt ile aynı konvansiyon)', () {
      expect(onayEsikiAsildiMi(1000000, 0), isFalse);
      expect(onayEsikiAsildiMi(1000000, -5), isFalse);
    });

    test('tutar eşiğin altındaysa aşım yoktur', () {
      expect(onayEsikiAsildiMi(499, 500), isFalse);
    });

    test('tutar eşiğe eşit veya üstündeyse aşım vardır', () {
      expect(onayEsikiAsildiMi(500, 500), isTrue);
      expect(onayEsikiAsildiMi(501, 500), isTrue);
    });
  });

  group('OnayTuru kod/etiket eşlemesi', () {
    test('her tür benzersiz bir kod üretir (DB tarafında çakışma olmaz)', () {
      final kodlar = OnayTuru.values.map((t) => t.kod).toSet();
      expect(kodlar.length, OnayTuru.values.length);
    });
  });

  // onay_talepleri tablosunun gerçek şema üzerinde (migration +
  // fresh-install yolunun İKİSİNDE de) doğru oluştuğunu doğrular.
  group('onay_talepleri şema doğrulaması', () {
    late Database db;
    setUp(() async => db = await TestVeritabani.olustur());
    tearDown(() => db.close());

    test('tablo oluşuyor ve bir kayıt eklenip okunabiliyor', () async {
      await db.insert('onay_talepleri', {
        'global_id': 'g1',
        'tur': 'yuksek_iskonto',
        'referans_turu': 'satis',
        'referans_id': 5,
        'tutar': 25.0,
        'esik_tutar': 20.0,
        'aciklama': 'Test iskonto',
        'goruldu': 0,
        'is_deleted': 0,
      });

      final rows = await db.query('onay_talepleri');
      expect(rows.length, 1);
      expect(rows.first['tur'], 'yuksek_iskonto');
      expect(rows.first['goruldu'], 0);
    });

    test('goruldu=0 filtreli sorgu sadece görülmemişleri döner', () async {
      await db.insert('onay_talepleri', {
        'tur': 'yuksek_iade', 'tutar': 600.0, 'esik_tutar': 500.0,
        'goruldu': 0, 'is_deleted': 0,
      });
      await db.insert('onay_talepleri', {
        'tur': 'kasa_cikisi', 'tutar': 1200.0, 'esik_tutar': 1000.0,
        'goruldu': 1, 'is_deleted': 0,
      });

      final gorulmemisler = await db.query('onay_talepleri',
          where: 'is_deleted = 0 AND goruldu = 0');
      expect(gorulmemisler.length, 1);
      expect(gorulmemisler.first['tur'], 'yuksek_iade');
    });
  });
}
