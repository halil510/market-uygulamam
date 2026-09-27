// test/unit/etiket_yardimci_test.dart
// Etiket birim fiyatı (1 KG / 1 LT) ve ürün adı satır bölme (2026-09-28).
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/cekirdek/utils/etiket_yardimci.dart';
import 'package:market_plus/modeller/urun_model.dart';

UrunModel _u({String birim = 'Adet', double agirlik = 0}) =>
    UrunModel(urunAdi: 'Test', birimAdi: birim, agirlik: agirlik);

void main() {
  test('gram girilmiş üründe 1 kg fiyatı hesaplanır', () {
    expect(EtiketYardimci.birimFiyatMetni(_u(agirlik: 900), 65), '1 KG: 72,22 TL');
  });
  test('KG / LT birimli üründe fiyat zaten birim fiyattır', () {
    expect(EtiketYardimci.birimFiyatMetni(_u(birim: 'KG'), 120), '1 KG: 120,00 TL');
    expect(EtiketYardimci.birimFiyatMetni(_u(birim: 'Lt'), 40), '1 LT: 40,00 TL');
  });
  test('hesaplanamıyorsa null', () {
    expect(EtiketYardimci.birimFiyatMetni(_u(), 10), isNull);
  });
  test('ürün adı kelime sınırından bölünür', () {
    expect(EtiketYardimci.satirlaraBol('ABC ARAP SABUNU SIVI 900 G', 12),
        ['ABC ARAP', 'SABUNU SIVI']);
    expect(EtiketYardimci.satirlaraBol('KISA AD', 24), ['KISA AD']);
  });
}
