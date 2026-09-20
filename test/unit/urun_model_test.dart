import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/modeller/urun_model.dart';

void main() {
  group('UrunModel', () {
    test('karOrani hesabı', () {
      final u = UrunModel(
        urunAdi: 'Test', alisFiyat: 80, satisFiyati: 100,
        birimAdi: 'Adet', kdvOran: '20',
      );
      expect(u.karOrani, closeTo(25.0, 0.1)); // (100-80)/80*100
    });

    test('kritikStok false - minimum 0', () {
      final u = UrunModel(
        urunAdi: 'Test', stok: 5, minimumStok: 0,
        birimAdi: 'Adet', kdvOran: '20',
      );
      expect(u.kritikStok, isFalse);
    });

    test('kritikStok true', () {
      final u = UrunModel(
        urunAdi: 'Test', stok: 2, minimumStok: 5,
        birimAdi: 'Adet', kdvOran: '20',
      );
      expect(u.kritikStok, isTrue);
    });

    test('indirimliFiyat', () {
      final u = UrunModel(
        urunAdi: 'Test', satisFiyati: 100,
        indirimliFiyatKayitli: 80,
        birimAdi: 'Adet', kdvOran: '20',
      );
      expect(u.indirimliFiyat, equals(80));
    });

    test('fromMap null güvenli', () {
      final map = <String, dynamic>{
        'urun_adi': 'Test',
        'satis_fiyati': 100.0,
        'birim_adi': 'Adet',
        'kdv_oran': '20',
      };
      final u = UrunModel.fromMap(map);
      expect(u.urunAdi, equals('Test'));
      expect(u.stok, equals(0.0));
      expect(u.aktif, isTrue);
    });

    test('copyWith', () {
      final u = UrunModel(
        urunAdi: 'Test', satisFiyati: 100,
        birimAdi: 'Adet', kdvOran: '20',
      );
      final u2 = u.copyWith(satisFiyati: 120, aktif: false);
      expect(u2.satisFiyati, equals(120));
      expect(u2.aktif, isFalse);
      expect(u2.urunAdi, equals('Test'));
    });

    // 🔴 DÜZELTME (Madde 20 — Model Tutarlılığı denetimi, 2026-09-20):
    // plu/pluKartBoyut copyWith'in ne parametre listesinde ne de
    // constructor çağrısında YOKTU — ilgisiz bir alanı değiştiren HER
    // copyWith() çağrısı bu iki alanı sessizce sıfırlıyordu.
    test('copyWith ilgisiz bir alanı değiştirirken plu/pluKartBoyut KORUNUR '
        '(önceden sessizce 0/2\'ye sıfırlanıyordu)', () {
      final u = UrunModel(
        urunAdi: 'PLU Ürünü', satisFiyati: 100,
        birimAdi: 'Adet', kdvOran: '20',
        plu: 1, pluKartBoyut: 3,
      );
      final u2 = u.copyWith(satisFiyati: 120);
      expect(u2.plu, equals(1));
      expect(u2.pluKartBoyut, equals(3));
    });

    test('copyWith ile plu/pluKartBoyut doğrudan da güncellenebilir', () {
      final u = UrunModel(
        urunAdi: 'Test', satisFiyati: 100,
        birimAdi: 'Adet', kdvOran: '20',
        plu: 0, pluKartBoyut: 2,
      );
      final u2 = u.copyWith(plu: 1, pluKartBoyut: 1);
      expect(u2.plu, equals(1));
      expect(u2.pluKartBoyut, equals(1));
    });
  });
}
