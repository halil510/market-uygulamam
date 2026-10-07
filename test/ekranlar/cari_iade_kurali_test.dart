// test/ekranlar/cari_iade_kurali_test.dart
//
// İade ekranından ayrılan iş kuralı (2026-10-07 refactor): cari tipine göre
// iade türü, stok yönü, fiyat kilidi, açıklama ve fiyat önizlemesi.
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/ekranlar/satis/iade/cari_iade_kurali.dart';
import 'package:market_plus/modeller/cari_model.dart';
import 'package:market_plus/modeller/urun_model.dart';

CariModel _cari(String cariTipi, {String musteriTipi = 'Perakende', int? id = 1}) => CariModel(
      id: id,
      unvan: 'Test',
      cariTipi: cariTipi,
      musteriTipi: musteriTipi,
    );

void main() {
  group('CariIadeTuru.belirle', () {
    test('cari yoksa veya kayıtsızsa müşteri', () {
      expect(CariIadeTuru.belirle(null), CariIadeTuru.musteri);
      expect(CariIadeTuru.belirle(_cari('Tedarikçi', id: null)), CariIadeTuru.musteri);
    });

    test('saf tedarikçi → tedarikçi; "Hem Müşteri Hem Tedarikçi" → müşteri', () {
      expect(CariIadeTuru.belirle(_cari('Tedarikçi')), CariIadeTuru.tedarikci);
      expect(CariIadeTuru.belirle(_cari('Hem Müşteri Hem Tedarikçi')), CariIadeTuru.musteri);
    });

    test('Bayi/Toptan müşteri tipli müşteri → bayi; perakende müşteri → müşteri', () {
      expect(CariIadeTuru.belirle(_cari('Müşteri', musteriTipi: 'Bayi')), CariIadeTuru.bayi);
      expect(CariIadeTuru.belirle(_cari('Müşteri', musteriTipi: 'Toptan')), CariIadeTuru.bayi);
      expect(CariIadeTuru.belirle(_cari('Müşteri')), CariIadeTuru.musteri);
    });
  });

  test('stok yönü ve fiyat kilidi', () {
    expect(CariIadeTuru.tedarikci.stokAzalir, isTrue);
    expect(CariIadeTuru.bayi.stokAzalir, isFalse);
    expect(CariIadeTuru.musteri.stokAzalir, isFalse);
    expect(CariIadeTuru.musteri.fiyatKuralli, isFalse);
    expect(CariIadeTuru.tedarikci.fiyatKuralli, isTrue);
    expect(CariIadeTuru.bayi.fiyatKuralli, isTrue);
  });

  test('açıklama: müşteride yok, tedarikçi/bayide cari adıyla', () {
    final c = _cari('Tedarikçi');
    expect(CariIadeTuru.musteri.fiyatAciklamasi(c), isNull);
    expect(CariIadeTuru.tedarikci.fiyatAciklamasi(c), contains('son alış maliyeti'));
    expect(CariIadeTuru.bayi.fiyatAciklamasi(c), contains('bayiye özel'));
  });

  test('önizleme fiyatı: müşteri → satış fiyatı, tedarikçi → KDV dahil maliyet', () async {
    const urun = UrunModel(
      id: 1,
      urunAdi: 'Ürün',
      satisFiyati: 150,
      alisFiyat: 100,
      alisKdvOran: 20,
    );
    expect(await CariIadeTuru.musteri.onizlemeFiyati(urun, miktar: 1), 150);
    expect(await CariIadeTuru.tedarikci.onizlemeFiyati(urun, miktar: 1), 120);
  });
}
