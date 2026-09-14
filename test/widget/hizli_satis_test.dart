import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:market_plus/saglayicilar/riverpod/sepet_provider.dart';
import 'package:market_plus/modeller/urun_model.dart';

void main() {
  group('Sepet Provider - Kritik İş Mantığı', () {
    late ProviderContainer container;
    setUp(() => container = ProviderContainer());
    tearDown(() => container.dispose());

    Sepet notifier() => container.read(sepetProvider.notifier);
    SepetDurum durum() => container.read(sepetProvider);

    test('Boş sepet', () {
      expect(durum().bos, isTrue);
      expect(durum().genelToplam, 0.0);
      expect(durum().kalemSayisi, 0);
    });

    test('Ürün ekle - toplam doğru', () {
      final urun = UrunModel(urunAdi: 'Ekmek', satisFiyati: 10, birimAdi: 'Adet', kdvOran: '1');
      notifier().ekle(urun);
      expect(durum().kalemSayisi, 1);
      expect(durum().genelToplam, 10.0);
    });

    test('Aynı ürün tekrar - miktar artar', () {
      final urun = UrunModel(urunAdi: 'Ekmek', satisFiyati: 10, birimAdi: 'Adet', kdvOran: '1');
      notifier().ekle(urun);
      notifier().ekle(urun);
      expect(durum().kalemSayisi, 1);
      expect(durum().genelToplam, 20.0);
    });

    test('İskonto uygulanır', () {
      final urun = UrunModel(urunAdi: 'Test', satisFiyati: 100, birimAdi: 'Adet', kdvOran: '20');
      notifier().ekle(urun);
      notifier().iskontoGuncelle(10); // %10
      expect(durum().genelToplam, closeTo(90.0, 0.01));
    });

    test('Miktar 0 → kalem silinir', () {
      final urun = UrunModel(urunAdi: 'Test', satisFiyati: 100, birimAdi: 'Adet', kdvOran: '20');
      notifier().ekle(urun);
      notifier().miktarGuncelle(0, 0);
      expect(durum().bos, isTrue);
    });

    test('Temizle', () {
      final urun = UrunModel(urunAdi: 'Test', satisFiyati: 100, birimAdi: 'Adet', kdvOran: '20');
      notifier().ekle(urun);
      notifier().temizle();
      expect(durum().bos, isTrue);
      expect(durum().musteri, isNull);
    });

    // 🔴 Regresyon testleri (hızlı satış derin analizi, 2026-09-14):
    // elle uygulanan bir indirim (fiyatGuncelle), aynı ürün tekrar
    // eklenince (barkod tekrar okutulunca) veya miktarı elle
    // değiştirilince ÖNCEDEN sessizce kayboluyordu — fiyat koşulsuz
    // _fiyatHesapla() ile yeniden hesaplanıyordu.
    test('Elle indirim uygulanmış kalem, AYNI ürün tekrar eklenince (barkod '
        'tekrar okutulunca) korunur — standart fiyata SIFIRLANMAZ', () {
      final urun = UrunModel(urunAdi: 'Test', satisFiyati: 100, birimAdi: 'Adet', kdvOran: '20');
      notifier().ekle(urun);
      notifier().fiyatGuncelle(0, 80); // kasiyer elle %20 indirim uyguladı
      expect(durum().kalemler.first.birimFiyat, 80.0);

      notifier().ekle(urun); // aynı ürün tekrar barkodla okutuldu (miktar 2 oldu)

      expect(durum().kalemSayisi, 1);
      expect(durum().kalemler.first.miktar, 2.0);
      expect(durum().kalemler.first.birimFiyat, 80.0,
          reason: 'elle uygulanan indirim miktar artışında kaybolmamalı');
      expect(durum().genelToplam, closeTo(160.0, 0.01));
    });

    test('Elle indirim uygulanmış kalemin miktarı elle değiştirilince '
        'indirim korunur', () {
      final urun = UrunModel(urunAdi: 'Test', satisFiyati: 100, birimAdi: 'Adet', kdvOran: '20');
      notifier().ekle(urun);
      notifier().fiyatGuncelle(0, 75);
      notifier().miktarGuncelle(0, 3); // kasiyer sepet kartından miktarı 3'e çıkardı

      expect(durum().kalemler.first.birimFiyat, 75.0,
          reason: 'elle uygulanan indirim, elle miktar değişiminde de kaybolmamalı');
      expect(durum().genelToplam, closeTo(225.0, 0.01));
    });

    test('HİÇ elle dokunulmamış bir kalemde miktar artışı fiyatı normal '
        'şekilde yeniden hesaplar (mevcut davranış bozulmadı)', () {
      final urun = UrunModel(urunAdi: 'Test', satisFiyati: 100, birimAdi: 'Adet', kdvOran: '20');
      notifier().ekle(urun);
      notifier().ekle(urun); // elle indirim YOK — normal birleşme

      expect(durum().kalemler.first.miktar, 2.0);
      expect(durum().kalemler.first.birimFiyat, 100.0);
      expect(durum().genelToplam, closeTo(200.0, 0.01));
    });
  });

  group('UI Widget Testleri', () {
    testWidgets('Scaffold oluşturulur', (tester) async {
      await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: Scaffold(body: Center(child: Text('Test'))))));
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('AppBar başlık gösterilir', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(appBar: AppBar(title: Text('MarketPlus')))));
      expect(find.text('MarketPlus'), findsOneWidget);
    });
  });
}
