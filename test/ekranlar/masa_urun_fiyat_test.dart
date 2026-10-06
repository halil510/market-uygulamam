// Masa ürün kartı: promosyonlu fiyat adisyona girecek fiyatla aynı kuralla hesaplanır.
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/modeller/promosyon_model.dart';
import 'package:market_plus/modeller/urun_model.dart';
import 'package:market_plus/servisler/urun_fiyat_hesaplayici.dart';

void main() {
  final urun = const UrunModel(urunAdi: 'Süt', satisFiyati: 100);
  test('promosyon yoksa liste fiyatı', () {
    expect(UrunFiyatHesaplayici.hesapla(urun, 1, null), 100);
  });
  test('geçerli %10 promosyon → 90', () {
    final p = const PromosyonModel(urunId: 1, promosyonAdi: 'x', iskontoOran: 10);
    expect(UrunFiyatHesaplayici.hesapla(urun, 1, [p]), 90);
  });
  test('miktar eşiği sağlanmıyorsa indirim yok', () {
    final p = const PromosyonModel(urunId: 1, promosyonAdi: 'x', iskontoOran: 10, minMiktar: 3);
    expect(UrunFiyatHesaplayici.hesapla(urun, 1, [p]), 100);
    expect(UrunFiyatHesaplayici.hesapla(urun, 3, [p]), 90);
  });
}
