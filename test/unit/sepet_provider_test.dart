import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:market_plus/saglayicilar/riverpod/sepet_provider.dart';
import 'package:market_plus/modeller/urun_model.dart';

UrunModel _testUrun({int id = 1, double fiyat = 100.0}) => UrunModel(
  urunAdi: 'Test Ürün $id',
  satisFiyati: fiyat,
  birimAdi: 'Adet',
  kdvOran: '20',
  stok: 50,
);

void main() {
  group('Sepet', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });
    tearDown(() => container.dispose());

    Sepet notifier() => container.read(sepetProvider.notifier);
    SepetDurum durum() => container.read(sepetProvider);

    test('başlangıçta boş', () {
      expect(durum().bos, isTrue);
      expect(durum().kalemSayisi, equals(0));
    });

    test('ürün ekle', () {
      notifier().ekle(_testUrun());
      expect(durum().kalemSayisi, equals(1));
      expect(durum().genelToplam, equals(100.0));
    });

    test('aynı ürün tekrar eklenince miktar artar', () {
      final u = _testUrun();
      notifier().ekle(u);
      notifier().ekle(u);
      expect(durum().kalemSayisi, equals(1));
      expect(durum().genelToplam, equals(200.0));
    });

    test('miktar güncelle', () {
      notifier().ekle(_testUrun());
      notifier().miktarGuncelle(0, 5.0);
      expect(durum().genelToplam, equals(500.0));
    });

    test('miktar 0 → kalem silinir', () {
      notifier().ekle(_testUrun());
      notifier().miktarGuncelle(0, 0);
      expect(durum().bos, isTrue);
    });

    test('iskonto uygulanır', () {
      notifier().ekle(_testUrun());
      notifier().iskontoGuncelle(10); // %10
      expect(durum().genelToplam, closeTo(90.0, 0.01));
    });

    test('temizle', () {
      notifier().ekle(_testUrun());
      notifier().temizle();
      expect(durum().bos, isTrue);
    });

    test('sil', () {
      notifier().ekle(_testUrun(id: 1));
      notifier().ekle(_testUrun(id: 2));
      notifier().sil(0);
      expect(durum().kalemSayisi, equals(1));
    });
  });
}
