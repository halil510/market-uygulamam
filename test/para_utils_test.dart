// test/para_utils_test.dart
//
// PROJENİN İLK TESTİ.
//
// Neden buradan başlıyoruz: `ParaUtils.sayiCoz` uygulamadaki HER sayı
// girdisinin geçtiği tek nokta. Yanlış çalışırsa ürün fiyatları, iade
// tutarları, tahsilatlar, promosyon oranları — hepsi bozulur. Saf bir
// fonksiyon olduğu için Flutter'a hiç ihtiyaç duymadan test edilebilir.
//
// Çalıştırma:  flutter test test/para_utils_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/cekirdek/utils/para_utils.dart';

void main() {
  group('ParaUtils.sayiCoz — Türkçe ondalık ayırıcı', () {
    // ── ASIL HATA: Türkçe klavyede ondalık tuşu virgüldür ───────────────
    // Bu testler olmadan, double.tryParse('12,50') null döndürüyor ve
    // `?? 0` ile yutuluyordu → ürün fiyatı 0 kaydediliyordu.
    test('virgüllü ondalık doğru çözülür', () {
      expect(ParaUtils.sayiCoz('12,50'), 12.50);
      expect(ParaUtils.sayiCoz('0,01'), 0.01);
      expect(ParaUtils.sayiCoz('2,5'), 2.5);
      expect(ParaUtils.sayiCoz('149,99'), 149.99);
    });

    test('noktalı ondalık da çalışmaya devam eder', () {
      expect(ParaUtils.sayiCoz('12.50'), 12.50);
      expect(ParaUtils.sayiCoz('0.01'), 0.01);
    });

    test('tam sayılar', () {
      expect(ParaUtils.sayiCoz('12'), 12.0);
      expect(ParaUtils.sayiCoz('0'), 0.0);
      expect(ParaUtils.sayiCoz('100'), 100.0);
      expect(ParaUtils.sayiCoz('18'), 18.0); // KDV oranı
    });
  });

  group('ParaUtils.sayiCoz — binlik ayırıcı', () {
    test('Türkçe biçim: nokta binlik, virgül ondalık', () {
      expect(ParaUtils.sayiCoz('1.234,56'), 1234.56);
      expect(ParaUtils.sayiCoz('1.234.567,89'), 1234567.89);
      expect(ParaUtils.sayiCoz('10.000,00'), 10000.0);
    });

    test('İngilizce biçim: virgül binlik, nokta ondalık', () {
      expect(ParaUtils.sayiCoz('1,234.56'), 1234.56);
      expect(ParaUtils.sayiCoz('1,000,000.00'), 1000000.0);
    });

    test('KURAL: tek başına nokta ondalıktır, binlik DEĞİL', () {
      // "12.50" markette 12 lira 50 kuruştur, 12500 lira değil.
      // Bu bilinçli bir tercih — belirsizliği fiyat lehine çözüyoruz.
      expect(ParaUtils.sayiCoz('12.50'), 12.50);
      expect(ParaUtils.sayiCoz('12.5'), 12.5);
    });
  });

  group('ParaUtils.sayiCoz — kirli girdi', () {
    test('para simgesi temizlenir', () {
      expect(ParaUtils.sayiCoz('₺12,50'), 12.50);
      expect(ParaUtils.sayiCoz('₺ 1.500,00'), 1500.0);
      expect(ParaUtils.sayiCoz('\$12.50'), 12.50);
    });

    test('boşluklar temizlenir', () {
      expect(ParaUtils.sayiCoz('  12,50  '), 12.50);
      expect(ParaUtils.sayiCoz('1 234,56'), 1234.56);
    });

    test('yazım sırasındaki yarım girdi', () {
      // Kullanıcı "12," yazmışken onChange tetiklenir — çökmemeli
      expect(ParaUtils.sayiCoz('12,'), 12.0);
      expect(ParaUtils.sayiCoz('12.'), 12.0);
      expect(ParaUtils.sayiCoz(',5'), 0.5);
    });

    test('hatalı çoklu virgül — son parça ondalık sayılır', () {
      expect(ParaUtils.sayiCoz('12,5,3'), 12.53);
    });

    test('negatif değerler (iade, iskonto, virman)', () {
      expect(ParaUtils.sayiCoz('-5,25'), -5.25);
      expect(ParaUtils.sayiCoz('-1.234,56'), -1234.56);
    });
  });

  group('ParaUtils.sayiCoz — geçersiz girdi null döner', () {
    test('boş ve null', () {
      expect(ParaUtils.sayiCoz(null), isNull);
      expect(ParaUtils.sayiCoz(''), isNull);
      expect(ParaUtils.sayiCoz('   '), isNull);
    });

    test('sayı olmayan metin', () {
      expect(ParaUtils.sayiCoz('abc'), isNull);
      expect(ParaUtils.sayiCoz('12abc'), isNull);
      expect(ParaUtils.sayiCoz('₺'), isNull);
    });
  });

  group('ParaUtils.sayi — varsayılanlı sürüm', () {
    test('geçerli girdi çözülür', () {
      expect(ParaUtils.sayi('12,50'), 12.50);
    });

    test('geçersiz girdide varsayılan döner', () {
      expect(ParaUtils.sayi('abc'), 0);
      expect(ParaUtils.sayi(''), 0);
      expect(ParaUtils.sayi(null, varsayilan: 18), 18);
    });
  });

  group('ParaUtils.tamSayiCoz', () {
    test('tam sayıya yuvarlar', () {
      expect(ParaUtils.tamSayiCoz('12'), 12);
      expect(ParaUtils.tamSayiCoz('12,4'), 12);
      expect(ParaUtils.tamSayiCoz('12,6'), 13);
    });

    test('geçersizde null', () {
      expect(ParaUtils.tamSayiCoz('abc'), isNull);
      expect(ParaUtils.tamSayiCoz(null), isNull);
    });
  });

  group('GERİLEME TESTİ — format et, geri oku', () {
    // formatla() çıktısı sayiCoz() ile geri okunabilmeli.
    // Bu döngü kırılırsa "düzenle" ekranlarında değer bozulur.
    test('formatla → sayiCoz döngüsü değeri korur', () {
      for (final d in [0.0, 0.01, 12.5, 149.99, 1234.56, 1000000.0]) {
        final metin = ParaUtils.formatla(d);          // "₺1.234,56"
        final geri = ParaUtils.sayiCoz(metin);
        expect(geri, closeTo(d, 0.001),
            reason: '$d → "$metin" → $geri  (döngü bozuldu)');
      }
    });
  });

  group('ParaUtils — KDV hesapları (mevcut davranış korunuyor mu)', () {
    test('kdvHesapla', () {
      expect(ParaUtils.kdvHesapla(100, 20), closeTo(20, 0.001));
      expect(ParaUtils.kdvHesapla(100, 0), 0);
    });

    test('kdvDahilFiyat ve kdvHaricFiyat birbirinin tersi', () {
      const haric = 100.0;
      final dahil = ParaUtils.kdvDahilFiyat(haric, 20);
      expect(ParaUtils.kdvHaricFiyat(dahil, 20), closeTo(haric, 0.001));
    });

    // Madde 21 (2026-09-16): satış fiyatları projede KDV DAHİL saklanır
    // — kdvPayiCikar bu dahil tutarın içindeki KDV payını (üzerine
    // ekleyerek DEĞİL, içinden bölerek) çıkarır.
    test('kdvPayiCikar KDV dahil tutarın içindeki payı doğru ayıklar', () {
      // 120 TL KDV dahil, %20 KDV → net 100, KDV payı 20
      expect(ParaUtils.kdvPayiCikar(120, 20), closeTo(20.0, 0.001));
      expect(ParaUtils.kdvPayiCikar(100, 0), 0);
    });

    test('kdvPayiCikar, kdvHesapla ile KARIŞTIRILMAMALI (farklı sonuç verirler)', () {
      // kdvHesapla KDV HARİÇ bir tabana KDV üretir (100*0.20=20) — bu
      // örnekte tesadüfen kdvPayiCikar ile aynı çıkar çünkü 120'nin
      // içindeki pay da 20'dir; asıl fark taban farklı bir tutarda ortaya
      // çıkar: kdvHesapla(120,20)=24 (YANLIŞ, üzerine ekler) vs
      // kdvPayiCikar(120,20)=20 (DOĞRU, içinden ayıklar).
      expect(ParaUtils.kdvHesapla(120, 20), closeTo(24.0, 0.001));
      expect(ParaUtils.kdvPayiCikar(120, 20), closeTo(20.0, 0.001));
    });
  });
}
