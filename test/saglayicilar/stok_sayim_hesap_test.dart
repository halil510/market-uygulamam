// test/saglayicilar/stok_sayim_hesap_test.dart
//
// KOMPLE UYGULAMA DERİN ANALİZİNDE bulunan, kanıtlanmış veri kaybı:
// çok şubeli kurulumda Stok Sayımı ekranı, kullanıcının SADECE aktif
// şubede saydığı miktarı (sayilan) doğrudan urunler.stok'un (TÜM
// şubelerin TOPLAMI) yeni değeri olarak StokDeposu.stokDuzelt()'e
// gönderiyordu. Somut senaryo: Ürün X — Şube A'da 15, Şube B'de 5,
// toplam 20. Şube B'de fiziksel sayım yapılıp "5" girildiğinde (fark
// yok sanılarak), eski kodla toplam stok 5'e düşüyor — Şube A'nın 15
// birimi sessizce sistemden siliniyordu.
//
// Bu test, StokSayimHesap.yeniToplamHesapla()'nın doğru YENİ TOPLAM'ı
// (mevcut toplam - eski şube payı + yeni şube sayımı) ürettiğini, tek
// şubeli/şube seçilmemiş kurulumda ise eski davranışın (girilen değer
// doğrudan yeni toplam) BİREBİR korunduğunu doğrular.
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/saglayicilar/riverpod/stok_sayim_provider.dart';

void main() {
  group('StokSayimHesap.yeniToplamHesapla', () {
    test('çok şubeli: sadece aktif şubenin payı değişir, diğer şubenin '
        'stoğu korunur', () {
      // Şube A=15, Şube B=5, toplam=20. Şube B'de fiziksel sayım "5"
      // bulundu (değişiklik yok).
      final yeniToplam = StokSayimHesap.yeniToplamHesapla(
          toplamStok: 20, subeStok: 5, sayilan: 5);
      expect(yeniToplam, equals(20),
          reason: 'Şube B\'nin sayımı değişmediyse toplam da değişmemeli '
              '(eski kodla yanlışlıkla 5\'e düşüyordu, Şube A\'nın 15 '
              'birimini siliyordu).');
    });

    test('çok şubeli: aktif şubede sayım artınca SADECE fark toplama eklenir', () {
      // Şube A=15, Şube B=5, toplam=20. Şube B'de gerçekte 8 bulundu (+3).
      final yeniToplam = StokSayimHesap.yeniToplamHesapla(
          toplamStok: 20, subeStok: 5, sayilan: 8);
      expect(yeniToplam, equals(23));
    });

    test('çok şubeli: aktif şubede sayım azalınca SADECE fark toplamdan düşer', () {
      // Şube A=15, Şube B=5, toplam=20. Şube B'de gerçekte 2 bulundu (-3).
      final yeniToplam = StokSayimHesap.yeniToplamHesapla(
          toplamStok: 20, subeStok: 5, sayilan: 2);
      expect(yeniToplam, equals(17));
    });

    test('tek şubeli / şube seçilmemiş: eski davranış BİREBİR korunuyor '
        '(girilen değer doğrudan yeni toplam)', () {
      final yeniToplam = StokSayimHesap.yeniToplamHesapla(
          toplamStok: 20, subeStok: null, sayilan: 7);
      expect(yeniToplam, equals(7));
    });
  });
}
