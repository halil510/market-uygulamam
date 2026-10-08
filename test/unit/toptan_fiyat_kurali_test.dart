// test/unit/toptan_fiyat_kurali_test.dart
//
// Kullanıcı kararı 2026-10-08: ürün toptan fiyatı grup iskontosundan ÖNCE;
// Hızlı Satış sepeti bayi seçilince Toptan Satış ile AYNI kuralı kullanır
// (bulgu: toptan fiyatı 107 olan ürün Hızlı Satış'ta bayiye 120'den satıldı).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/modeller/cari_model.dart';
import 'package:market_plus/modeller/fiyat_grubu_model.dart';
import 'package:market_plus/modeller/fiyat_kademesi_model.dart';
import 'package:market_plus/modeller/urun_model.dart';
import 'package:market_plus/saglayicilar/riverpod/sepet_provider.dart';
import 'package:market_plus/servisler/fiyat_hesaplama_servisi.dart';

UrunModel _urun({double toptan = 107}) => UrunModel(
      urunAdi: 'Makaron',
      satisFiyati: 120,
      toptanFiyat: toptan,
      birimAdi: 'Adet',
      kdvOran: '20',
      stok: 10,
    );

const _bayi = CariModel(id: 7, unvan: 'Bayi', musteriTipi: 'Bayi', fiyatGrubuId: 3);
const _perakende = CariModel(id: 8, unvan: 'Müşteri');
const _grup = FiyatGrubuModel(id: 3, ad: 'bayi gurubu', varsayilanIskontoOrani: 10);

void main() {
  group('kural sırası', () {
    double f({UrunModel? u, CariModel? c = _bayi, double miktar = 1,
            List<FiyatKademesiModel> kademeler = const [], double? ozel}) =>
        FiyatHesaplamaServisi.kuralUygula(
          urun: u ?? _urun(), cari: c, miktar: miktar,
          kademeler: kademeler, grupOzelFiyat: ozel, grup: _grup,
        ).birimFiyat;

    test('perakende müşteri / müşteri yok → perakende', () {
      expect(f(c: _perakende), 120);
      expect(f(c: null), 120);
    });
    test('ürün toptan fiyatı grup iskontosundan önce (107, 108 değil)', () {
      expect(f(), 107);
    });
    test('toptan fiyatı yoksa grup iskontosu (%10 → 108)', () {
      expect(f(u: _urun(toptan: 0)), closeTo(108, 0.001));
    });
    test('gruba özel ürün fiyatı toptan fiyatından önce', () {
      expect(f(ozel: 100), 100);
    });
    test('miktar kademesi en önce', () {
      final k = [const FiyatKademesiModel(urunId: 1, minMiktar: 10, fiyat: 95)];
      expect(f(kademeler: k, ozel: 100, miktar: 12), 95);
      expect(f(kademeler: k, ozel: 100, miktar: 5), 100);
    });
  });

  group('Hızlı Satış sepeti', () {
    late ProviderContainer c;
    setUp(() => c = ProviderContainer());
    tearDown(() => c.dispose());

    test('bayi seçilince fiyat toptana, perakendeye dönünce 120\'ye döner', () {
      final n = c.read(sepetProvider.notifier);
      n.ekle(_urun());
      expect(c.read(sepetProvider).kalemler.first.birimFiyat, 120);
      n.musteriSec(_bayi);
      expect(c.read(sepetProvider).kalemler.first.birimFiyat, 107);
      n.musteriSec(_perakende);
      expect(c.read(sepetProvider).kalemler.first.birimFiyat, 120);
    });

    test('bayi seçiliyken eklenen ürün toptan fiyattan gelir', () {
      final n = c.read(sepetProvider.notifier);
      n.musteriSec(_bayi);
      n.ekle(_urun());
      expect(c.read(sepetProvider).kalemler.first.birimFiyat, 107);
    });

    test('bayi fiyatı indirim sayılmaz; ek indirim bayi fiyatına göre', () {
      final n = c.read(sepetProvider.notifier);
      n.musteriSec(_bayi);
      n.ekle(_urun(), miktar: 2);
      var k = c.read(sepetProvider).kalemler.first;
      expect(k.listeFiyat, 107);
      expect(k.toplamIndirim, 0); // ekranda/kayıtta 13 TL "indirim" yok
      expect(c.read(sepetProvider).genelToplam, 214);
      // F6 %5: liste fiyatından (107) hesaplanır → 101,65; 114'e çıkmaz.
      n.fiyatGuncelle(0, k.listeFiyat * 0.95);
      k = c.read(sepetProvider).kalemler.first;
      expect(k.birimFiyat, closeTo(101.65, 0.001));
      expect(k.toplamIndirim, closeTo(10.70, 0.01));
      expect(c.read(sepetProvider).genelToplam, closeTo(203.30, 0.001));
    });

    test('perakendeye dönünce liste fiyatı yine etiket fiyatı', () {
      final n = c.read(sepetProvider.notifier);
      n.musteriSec(_bayi);
      n.ekle(_urun());
      n.musteriSec(null);
      final k = c.read(sepetProvider).kalemler.first;
      expect(k.birimFiyat, 120);
      expect(k.listeFiyat, 120);
      expect(k.bazFiyat, isNull);
    });

    test('ödeme öncesi bekleyen fiyat güncellemesi yoksa hemen döner', () async {
      final n = c.read(sepetProvider.notifier);
      n.musteriSec(_bayi);
      n.ekle(_urun());
      await n.fiyatlarHazir();
      expect(c.read(sepetProvider).kalemler.first.birimFiyat, 107);
    });

    test('elle değiştirilen fiyat müşteri değişince korunur', () {
      final n = c.read(sepetProvider.notifier);
      n.ekle(_urun());
      n.fiyatGuncelle(0, 99);
      n.musteriSec(_bayi);
      expect(c.read(sepetProvider).kalemler.first.birimFiyat, 99);
    });
  });
}
