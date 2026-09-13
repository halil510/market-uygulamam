// test/servisler/fiyat_degisim_orani_test.dart
//
// FAZ 9 — Onay Merkezi "Fiyat Değişimi" akışında kullanılan yüzde
// hesaplama saf fonksiyonunun doğrulanması (bkz.
// lib/servisler/onay_merkezi_servisi.dart).
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/servisler/onay_merkezi_servisi.dart';

void main() {
  group('fiyatDegisimOraniHesapla', () {
    test('eski fiyat 0 veya altıysa null döner (ilk fiyat girişi, "değişim" sayılmaz)', () {
      expect(fiyatDegisimOraniHesapla(0, 50), isNull);
      expect(fiyatDegisimOraniHesapla(-5, 50), isNull);
    });

    test('fiyat artışında doğru yüzde hesaplanır', () {
      expect(fiyatDegisimOraniHesapla(100, 130), 30.0);
    });

    test('fiyat düşüşünde de MUTLAK yüzde döner (yön önemsiz, sadece büyüklük)', () {
      expect(fiyatDegisimOraniHesapla(100, 70), 30.0);
    });

    test('fiyat değişmemişse 0 döner', () {
      expect(fiyatDegisimOraniHesapla(100, 100), 0.0);
    });
  });
}
