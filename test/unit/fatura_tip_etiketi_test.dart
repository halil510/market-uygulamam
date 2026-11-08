// test/unit/fatura_tip_etiketi_test.dart
//
// Regresyon (2026-11-08, masaüstü taraması): Fatura Ekle formu tipi ASCII
// ('Alis') kaydediyor, Fatura Listesi'nin Gelen/Giden süzgeci ise yalnız
// 'Alış'/'Alış Faturası' tanıyordu → elle kesilen alış faturaları GİDEN
// listesinde görünüyordu. Ekranda da "Satis/Alis" yazıyordu.
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/modeller/fatura_model.dart';

FaturaModel _f(String? tip) => FaturaModel(tarih: DateTime(2026, 11, 8), faturaTipi: tip);

void main() {
  test('alış faturası Fatura Ekle\'nin ASCII değeriyle de alış sayılır', () {
    expect(_f('Alis').alisMi, isTrue);
    expect(_f('Alış').alisMi, isTrue);
    expect(_f('Alış Faturası').alisMi, isTrue);
    expect(_f('Satis').alisMi, isFalse);
    expect(_f('Satış').alisMi, isFalse);
    expect(_f('Iade').alisMi, isFalse);
    expect(_f(null).alisMi, isFalse);
  });

  test('tip etiketi Türkçe gösterilir, bilinmeyen tip aynen kalır', () {
    expect(FaturaModel.tipEtiketi('Satis'), 'Satış');
    expect(FaturaModel.tipEtiketi('Alis'), 'Alış');
    expect(FaturaModel.tipEtiketi('Iade'), 'İade');
    expect(FaturaModel.tipEtiketi('Proforma'), 'Proforma');
    expect(FaturaModel.tipEtiketi('Satış'), 'Satış');
    expect(FaturaModel.tipEtiketi('e-Arşiv'), 'e-Arşiv');
    expect(FaturaModel.tipEtiketi('Satis').toUpperCase(), 'SATIŞ');
  });
}
