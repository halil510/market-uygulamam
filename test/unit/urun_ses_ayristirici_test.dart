// test/unit/urun_ses_ayristirici_test.dart
//
// Türkçe konuşma sayıları ve ürün formu sesli komut ayrıştırıcısı.
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/servisler/ai/tr_sayi_ayristirici.dart';
import 'package:market_plus/servisler/ai/urun_ses_ayristirici.dart';

void main() {
  group('TrSayi', () {
    final vakalar = <String, double>{
      '25,50': 25.5,
      '25.50': 25.5,
      '1.250,75': 1250.75,
      '1.250': 1250,
      '1250': 1250,
      '%18': 18,
      'yirmi beş': 25,
      'yüz elli': 150,
      'yüz': 100,
      'bin': 1000,
      'bin iki yüz': 1200,
      'on iki bin beş yüz': 12500,
      'iki buçuk': 2.5,
      'bir buçuk': 1.5,
      '25 buçuk': 25.5,
      'yarım': 0.5,
      'çeyrek': 0.25,
      'yirmi beş lira elli': 25.5,
      'on lira elli kuruş': 10.5,
      '25 lira 5 kuruş': 25.05,
      '25 lira': 25,
      'yirmi beş virgül elli': 25.5,
      'üç virgül beş': 3.5,
      '25 virgül 5': 25.5,
      '3 bin 500': 3500,
      '2 milyon': 2000000,
      "40'a": 40,
      'yüzde yirmi': 20,
      'sıfır': 0,
    };
    vakalar.forEach((metin, beklenen) {
      test('"$metin" → $beklenen', () {
        expect(TrSayi.ilkSayi(metin), closeTo(beklenen, 0.0001));
      });
    });

    test('ardışık birler tek sayı sayılmaz (bir iki)', () {
      expect(TrSayi.tumSayilar('bir iki'), [1, 2]);
    });

    test('"35 lira 50 adet" → 50 kuruş değil adet', () {
      expect(TrSayi.tumSayilar('35 lira 50 adet'), [35, 50]);
    });

    test('basamak dizisi (barkod diktesi)', () {
      expect(TrSayi.basamakDizisi(['sekiz', 'altı', 'dokuz', 'sıfır', '123'], 0), '8690123');
    });

    test('Türkçe büyük I/İ normalizasyonu', () {
      expect(TrSayi.normalize('ÜRÜN İSMİ IŞIK'), 'ürün ismi ışık');
    });
  });

  group('UrunSesAyristirici', () {
    UrunSesSonuc a(String s) => UrunSesAyristirici.ayristir(s);

    test('klasik rakamlı komut', () {
      final r = a('ürün adı çikolata alış fiyat 25,50 satış fiyat 35 stok 100');
      expect(r.alanlar['urunAdi'], 'Çikolata');
      expect(r.alanlar['alisFiyat'], 25.5);
      expect(r.alanlar['satisFiyati'], 35);
      expect(r.alanlar['stok'], 100);
      expect(r.anlasilmayan, isEmpty);
    });

    test('tek cümlede yazıyla çok alan + kaydet', () {
      final r = a('ülker çikolatalı gofret alış fiyatı yirmi beş buçuk satış otuz beş '
          'kdv yüzde on stok yüz minimum stok on koli içi on iki raf a üç kaydet');
      expect(r.alanlar['urunAdi'], 'Ülker Çikolatalı Gofret');
      expect(r.alanlar['alisFiyat'], 25.5);
      expect(r.alanlar['satisFiyati'], 35);
      expect(r.alanlar['alisKdvOran'], 10);
      expect(r.alanlar['kdvOran'], 10);
      expect(r.alanlar['stok'], 100);
      expect(r.alanlar['minimumStok'], 10);
      expect(r.alanlar['koliIciMiktar'], 12);
      expect(r.alanlar['rafNo'], 'A3');
      expect(r.eylemler, contains('kaydet'));
      expect(r.anlasilmayan, isEmpty);
    });

    test('birim + lira/kuruş', () {
      final r = a('süt birim litre satış 32 lira 50');
      expect(r.alanlar['urunAdi'], 'Süt');
      expect(r.alanlar['birim'], 'LİTRE');
      expect(r.alanlar['satisFiyati'], 32.5);
    });

    test('barkod, kategori ve çok kelimeli marka', () {
      final r = a('barkod 8690504012345 kategori içecek marka coca cola');
      expect(r.alanlar['barkod'], '8690504012345');
      expect(r.alanlar['anaGrup'], 'İçecek');
      expect(r.alanlar['marka'], 'Coca Cola');
    });

    test('barkod yazıyla dikte edilir', () {
      final r = a('barkod sekiz altı dokuz sıfır sıfır sıfır bir iki üç');
      expect(r.alanlar['barkod'], '869000123');
    });

    test('kilo ile satılır: birim KG ve ada karışmaz', () {
      final r = a('domates kilo ile satılır satış 40');
      expect(r.alanlar['urunAdi'], 'Domates');
      expect(r.alanlar['birim'], 'KG');
      expect(r.alanlar['satisBirimiTipi'], 'kg');
      expect(r.alanlar['satisFiyati'], 40);
    });

    test('genel KDV hem alış hem satışa; özel KDV ayrı', () {
      var r = a('alış 20 satış 30 kdv 8');
      expect(r.alanlar['alisKdvOran'], 8);
      expect(r.alanlar['kdvOran'], 8);
      r = a('alış kdv 10 satış kdv 20');
      expect(r.alanlar['alisKdvOran'], 10);
      expect(r.alanlar['kdvOran'], 20);
    });

    test('geçersiz KDV oranı reddedilir', () {
      final r = a('kdv yüzde yirmi beş');
      expect(r.alanlar.containsKey('kdvOran'), isFalse);
      expect(r.anlasilmayan, isNotEmpty);
    });

    test('KDV dahil alış ayrı alan', () {
      final r = a('alış kdv dahil 30');
      expect(r.alanlar['alisFiyatKdvDahil'], 30);
      expect(r.alanlar.containsKey('alisFiyat'), isFalse);
    });

    test('"yüzde 10 kdv" ters kalıbı ada karışmaz', () {
      final r = a('yüzde 10 kdv alış 20');
      expect(r.alanlar['kdvOran'], 10);
      expect(r.alanlar['alisFiyat'], 20);
      expect(r.alanlar.containsKey('urunAdi'), isFalse);
    });

    test('indirim oranı ve sınır', () {
      expect(a('indirim yüzde 5').alanlar['indirimOrani'], 5);
      expect(a('indirim 150').alanlar.containsKey('indirimOrani'), isFalse);
    });

    test('toptan fiyat, koli içi, koli birimi', () {
      final r = a('toptan fiyat 28 koli içi 24 koli birimi paket');
      expect(r.alanlar['toptanFiyat'], 28);
      expect(r.alanlar['koliIciMiktar'], 24);
      expect(r.alanlar['koliBirimAdi'], 'Paket');
    });

    test('eylemler: barkod üret + ad', () {
      final r = a('barkod üret ürün adı su satış 5');
      expect(r.eylemler, contains('barkodUret'));
      expect(r.alanlar['urunAdi'], 'Su');
      expect(r.alanlar['satisFiyati'], 5);
      expect(r.alanlar.containsKey('barkod'), isFalse);
    });

    test('grup öner / marka öner yalnız eylem', () {
      final r = a('grup öner marka öner');
      expect(r.eylemler, containsAll(['grupOner', 'markaOner']));
      expect(r.alanlar, isEmpty);
    });

    test('pasif ve lot takibi', () {
      var r = a('ürün adı kalem pasif');
      expect(r.alanlar['aktif'], false);
      expect(r.alanlar['urunAdi'], 'Kalem');
      r = a('lot takibi yok');
      expect(r.alanlar['lotTakibi'], false);
      r = a('süt lot takibi açık satış 30');
      expect(r.alanlar['lotTakibi'], true);
      expect(r.alanlar['urunAdi'], 'Süt');
    });

    test('"N adet" stok olarak anlaşılır', () {
      var r = a('alış 25 satış 35 100 adet');
      expect(r.alanlar['stok'], 100);
      expect(r.alanlar['satisFiyati'], 35);
      r = a('süt 100 adet alış 20');
      expect(r.alanlar['stok'], 100);
      expect(r.alanlar['urunAdi'], 'Süt');
      r = a('satış 35 lira 50 adet');
      expect(r.alanlar['satisFiyati'], 35);
      expect(r.alanlar['stok'], 50);
    });

    test('"X adında ürün ekle" kalıbı', () {
      final r = a('çikolata adında ürün ekle satış 10');
      expect(r.alanlar['urunAdi'], 'Çikolata');
      expect(r.alanlar['satisFiyati'], 10);
    });

    test('stok / minimum / maksimum', () {
      final r = a('stok 100 minimum 10 maksimum 500');
      expect(r.alanlar['stok'], 100);
      expect(r.alanlar['minimumStok'], 10);
      expect(r.alanlar['maksimumStok'], 500);
    });

    test('düzeltme cümleleri: ek ve fiil toleransı', () {
      expect(a("satış fiyatını 40'a çıkar").alanlar['satisFiyati'], 40);
      expect(a('stoğu elli olsun').alanlar['stok'], 50);
      expect(a('alış fiyatı otuz lira yap').alanlar['alisFiyat'], 30);
    });

    test('raf numarası ve ürün kodu', () {
      expect(a('raf b iki').alanlar['rafNo'], 'B2');
      expect(a('ürün kodu abc 123').alanlar['kod'], 'ABC123');
    });

    test('kategori / alt kategori ayrı', () {
      final r = a('ürün adı çay marka çaykur ana grup içecek alt grup sıcak içecek');
      expect(r.alanlar['urunAdi'], 'Çay');
      expect(r.alanlar['marka'], 'Çaykur');
      expect(r.alanlar['anaGrup'], 'İçecek');
      expect(r.alanlar['altGrup'], 'Sıcak İçecek');
    });

    test('lira + kuruş', () {
      final r = a('alış fiyat 25 lira 50 kuruş satış 35 lira');
      expect(r.alanlar['alisFiyat'], 25.5);
      expect(r.alanlar['satisFiyati'], 35);
    });

    test('anlaşılmayan: sayısız fiyat', () {
      final r = a('satış fiyatı');
      expect(r.alanlar.containsKey('satisFiyati'), isFalse);
      expect(r.anlasilmayan, isNotEmpty);
    });

    test('kısa fiyat söyleyişi: "kırk dokuz doksan" = 49,90', () {
      var r = a('satış fiyatı kırk dokuz doksan');
      expect(r.alanlar['satisFiyati'], closeTo(49.9, 0.001));
      r = a('alış 35 50 satış 49 90');
      expect(r.alanlar['alisFiyat'], closeTo(35.5, 0.001));
      expect(r.alanlar['satisFiyati'], closeTo(49.9, 0.001));
      // ardından adet geliyorsa kuruş değil stok
      r = a('satış 35 50 adet');
      expect(r.alanlar['satisFiyati'], 35);
      expect(r.alanlar['stok'], 50);
    });

    test('lira+kuruş yazıyla ve virgüllü rakam', () {
      expect(a('alış fiyatı yirmi beş lira yetmiş beş kuruş').alanlar['alisFiyat'], closeTo(25.75, 0.001));
      expect(a('satış 1.250,75').alanlar['satisFiyati'], closeTo(1250.75, 0.001));
      expect(a('satış bin iki yüz elli').alanlar['satisFiyati'], 1250);
    });

    test('ASR virgül/noktalama ve büyük harf toleransı', () {
      final r = a('Ürün adı: Süt, Alış fiyatı: 25,50. Satış fiyatı: 35! Stok: 100');
      expect(r.alanlar['urunAdi'], 'Süt');
      expect(r.alanlar['alisFiyat'], 25.5);
      expect(r.alanlar['satisFiyati'], 35);
      expect(r.alanlar['stok'], 100);
    });

    test('kdv oranı doğal söyleyişler', () {
      expect(a('yüzde 10 kdv').alanlar['kdvOran'], 10);
      expect(a('kdv %20').alanlar['kdvOran'], 20);
      expect(a('kdv oranı yüzde sıfır').alanlar['kdvOran'], 0);
      expect(a('kdv yüzde bir').alanlar['kdvOran'], 1);
    });

    test('boş / anlamsız metin', () {
      expect(a('').bos, isTrue);
      expect(a('   ').bos, isTrue);
    });

    test('özet satırları okunur', () {
      final s = a('satış 35 stok 100').ozetSatirlari();
      expect(s, containsAll(['Satış fiyatı: 35', 'Stok: 100']));
    });
  });
}
