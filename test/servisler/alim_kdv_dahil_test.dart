import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/servisler/alim_islem_servisi.dart';

void main() {
  test('alım kalem tutarı KDV dahil hesaplanır', () {
    const k = AlimKalemGirdi(
        urunId: 1, miktar: 10, alisFiyat: 60, kdvOran: 20);
    expect(k.kdvDahilToplam, 720.0);
  });

  test('KDV oranı verilmezse eski davranış (KDV\'siz) korunur', () {
    const k = AlimKalemGirdi(urunId: 1, miktar: 3, alisFiyat: 10.5);
    expect(k.kdvDahilToplam, 31.5);
  });

  test('yuvarlama: 3 x 3,33 %10 = 10,99', () {
    const k = AlimKalemGirdi(
        urunId: 1, miktar: 3, alisFiyat: 3.33, kdvOran: 10);
    expect(k.kdvDahilToplam, 10.99);
  });
}
