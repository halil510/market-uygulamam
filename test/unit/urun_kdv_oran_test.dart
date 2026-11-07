// test/unit/urun_kdv_oran_test.dart
//
// UrunModel.kdvOranCoz / kdvOranSayi — KDV oranı metninden sayıya TEK
// kaynak. Regresyon: 20 yerde `double.tryParse(kdvOran) ?? X` vardı, X
// bazı yerde 18 bazı yerde 0'dı → oranı boş kalmış ürün satışta %18, raf
// etiketinde/ZPL'de %0 ile hesaplanıyordu (aynı ürün, iki farklı fiyat).
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/modeller/urun_model.dart';

UrunModel _urun(String kdv) => UrunModel(urunAdi: 'Test', kdvOran: kdv);

void main() {
  group('UrunModel.kdvOranCoz', () {
    test('geçerli metin oranları', () {
      expect(UrunModel.kdvOranCoz('18'), 18);
      expect(UrunModel.kdvOranCoz('10'), 10);
      expect(UrunModel.kdvOranCoz('1'), 1);
      expect(UrunModel.kdvOranCoz('0'), 0);
    });

    test('yüzde işareti, virgüllü ondalık ve boşluk', () {
      expect(UrunModel.kdvOranCoz('%18'), 18);
      expect(UrunModel.kdvOranCoz('8,5'), 8.5);
      expect(UrunModel.kdvOranCoz(' 20 '), 20);
    });

    test('DB\'den gelen ham değerler (REAL/TEXT)', () {
      expect(UrunModel.kdvOranCoz(18.0), 18);
      expect(UrunModel.kdvOranCoz(10), 10);
    });

    test('boş / null / geçersiz → HER YERDE aynı varsayılan (%18)', () {
      expect(UrunModel.kdvOranCoz(null), UrunModel.varsayilanKdvOrani);
      expect(UrunModel.kdvOranCoz(''), UrunModel.varsayilanKdvOrani);
      expect(UrunModel.kdvOranCoz('abc'), UrunModel.varsayilanKdvOrani);
      expect(UrunModel.varsayilanKdvOrani, 18);
    });

    test('%0 KDV\'li ürün varsayılana DÜŞMEZ (0 geçerli bir oran)', () {
      expect(_urun('0').kdvOranSayi, 0);
    });
  });

  test('kdvOranSayi getter kdvOranCoz ile aynı sonucu verir', () {
    expect(_urun('10').kdvOranSayi, 10);
    expect(_urun('').kdvOranSayi, 18);
  });
}
