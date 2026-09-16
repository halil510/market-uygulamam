import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:market_plus/saglayicilar/riverpod/sepet_provider.dart';
import 'package:market_plus/modeller/urun_model.dart';
import 'package:market_plus/modeller/sepet_model.dart';

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

  // Madde 21 — Para Hesaplamaları denetimi (2026-09-16): satisFiyati
  // GERÇEKTE KDV DAHİL saklanır (kullanıcı onayıyla doğrulandı). Bu
  // testler olmadan önce kdvTutar, toplamTutar'ı (zaten KDV dahil)
  // yanlışlıkla KDV oranıyla ÇARPARAK büyütüyordu (120 TL'lik, %20
  // KDV'li bir kalemde 24 TL gibi yanlış bir KDV payı üretiyordu) —
  // doğrusu tutarın İÇİNDEN bölerek ayıklamaktır (120 TL'nin içindeki
  // gerçek KDV payı 20 TL'dir, 100 TL net + 20 TL KDV = 120 TL).
  group('SepetKalem KDV kırılımı (satış fiyatı KDV DAHİL)', () {
    UrunModel urun({double fiyat = 120.0, String kdvOran = '20'}) => UrunModel(
      urunAdi: 'Test Ürün',
      satisFiyati: fiyat,
      birimAdi: 'Adet',
      kdvOran: kdvOran,
      stok: 50,
    );

    test('toplamTutar KDV dahildir — müşteriden tahsil edilen tutarın ta kendisi', () {
      final kalem = SepetKalem(urun: urun(fiyat: 120.0), miktar: 1);
      expect(kalem.toplamTutar, equals(120.0));
    });

    test('kdvTutar, toplamTutar İÇİNDEN ayıklanır (üzerine eklenmez)', () {
      final kalem = SepetKalem(urun: urun(fiyat: 120.0, kdvOran: '20'), miktar: 1);
      // Doğru: 120 - 120/1.20 = 20   (YANLIŞ olsaydı: 120*0.20 = 24)
      expect(kalem.kdvTutar, closeTo(20.0, 0.001));
    });

    test('kdvliToplamTutar her zaman toplamTutar\'a eşittir (çift KDV eklenmez)', () {
      final kalem = SepetKalem(urun: urun(fiyat: 120.0, kdvOran: '20'), miktar: 3);
      expect(kalem.kdvliToplamTutar, equals(kalem.toplamTutar));
    });

    test('miktar ve iskonto ile birlikte KDV payı doğru ayıklanır', () {
      // 2 adet, birim 120 TL, %10 iskonto → toplamTutar = 2*120*0.9 = 216
      final kalem = SepetKalem(
        urun: urun(fiyat: 120.0, kdvOran: '20'),
        miktar: 2,
        iskontoOran: 10,
      );
      expect(kalem.toplamTutar, closeTo(216.0, 0.001));
      // 216 - 216/1.20 = 36
      expect(kalem.kdvTutar, closeTo(36.0, 0.001));
    });

    test('SepetDurum.kdvToplam, genelToplam ÜZERİNE eklenmez', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(sepetProvider.notifier);
      notifier.ekle(urun(fiyat: 120.0, kdvOran: '20'));
      final durum = container.read(sepetProvider);
      expect(durum.araToplam, equals(120.0));
      expect(durum.kdvToplam, closeTo(20.0, 0.001));
      // Kritik: genelToplam zaten KDV dahil olduğundan kdvToplam eklenmez
      expect(durum.genelToplam, equals(120.0));
    });
  });
}
