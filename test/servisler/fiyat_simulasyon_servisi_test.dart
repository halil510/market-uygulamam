// test/servisler/fiyat_simulasyon_servisi_test.dart
//
// FAZ 11 — Fiyat Simülasyonu: saf hesaplama fonksiyonunun doğrulanması
// (bkz. lib/servisler/fiyat_simulasyon_servisi.dart). Bu bir ÖNİZLEME
// aracıdır — hiçbir tabloya yazmaz, bu test sadece matematiği doğrular.
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/servisler/fiyat_simulasyon_servisi.dart';

void main() {
  group('fiyatSimulasyonuHesapla', () {
    test('kâr oranı UrunModel.karOrani ile AYNI konvansiyonu kullanır (markup: kâr/alış)', () {
      // Alış 80, satış 100 → kâr 20, oran = 20/80*100 = %25.
      final s = fiyatSimulasyonuHesapla(alisFiyat: 80, eskiFiyat: 100, yeniFiyat: 100);
      expect(s.eskiKarOrani, 25.0);
      expect(s.yeniKarOrani, 25.0);
    });

    test('fiyat artışında birim kâr ve kâr oranı artar', () {
      final s = fiyatSimulasyonuHesapla(alisFiyat: 80, eskiFiyat: 100, yeniFiyat: 120);
      expect(s.eskiBirimKar, 20.0);
      expect(s.yeniBirimKar, 40.0);
      expect(s.yeniKarOrani, 50.0);
    });

    test('alış fiyatı 0 ise kâr oranı 0 döner (sıfıra bölme yok)', () {
      final s = fiyatSimulasyonuHesapla(alisFiyat: 0, eskiFiyat: 100, yeniFiyat: 120);
      expect(s.eskiKarOrani, 0.0);
      expect(s.yeniKarOrani, 0.0);
    });

    test('aylık satılan miktar verilmezse aylık tahmini kâr farkı null döner', () {
      final s = fiyatSimulasyonuHesapla(alisFiyat: 80, eskiFiyat: 100, yeniFiyat: 120);
      expect(s.aylikTahminiKarFarki, isNull);
    });

    test('aylık satılan miktar verilirse kâr farkı miktarla çarpılır', () {
      // Birim kâr farkı: 40-20=20. Aylık 50 adet satılıyorsa → 1000.
      final s = fiyatSimulasyonuHesapla(
          alisFiyat: 80, eskiFiyat: 100, yeniFiyat: 120, aylikSatilanMiktar: 50);
      expect(s.aylikTahminiKarFarki, 1000.0);
    });

    test('fiyat düşürülürse aylık kâr farkı negatif olur', () {
      final s = fiyatSimulasyonuHesapla(
          alisFiyat: 80, eskiFiyat: 100, yeniFiyat: 90, aylikSatilanMiktar: 50);
      expect(s.aylikTahminiKarFarki, -500.0);
    });
  });
}
