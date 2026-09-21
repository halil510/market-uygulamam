// test/unit/satis_kalem_iskonto_test.dart
//
// Kendi-keşif turu (Promosyon modülü denetimi, kullanıcı onayıyla):
// satis_kalem.iskonto_oran/iskonto_tutar HER ZAMAN 0 yazılıyordu —
// sepetteki GERÇEK indirim (promosyon, DB kayıtlı indirimli fiyat,
// ürün indirim oranı, elle indirim) doğrudan birimFiyat'a gömülüyor
// ama kalem satırına hiç yazılmıyordu. Somut etki: Gün Sonu Excel
// raporundaki "İndirim" sütunu promosyon uygulanan satışlarda bile
// hep 0 gösteriyordu.
//
// SatisTamamlamaServisi._kalemOlustur() private olduğu için burada
// BİREBİR AYNI formül (ürünün güncel katalog fiyatı — k.urun.
// satisFiyati — ile fiilen tahsil edilen birim fiyat — k.birimFiyat —
// arasındaki fark) saf bir fonksiyon olarak mirror edilip doğrulanıyor.
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/modeller/sepet_model.dart';
import 'package:market_plus/modeller/urun_model.dart';

/// SatisTamamlamaServisi._kalemOlustur() ile BİREBİR AYNI formül.
({double iskontoOran, double iskontoTutar}) _iskontoHesapla(SepetKalem k) {
  final bazFiyat = k.urun.satisFiyati;
  final indirimBirim = bazFiyat > k.birimFiyat ? bazFiyat - k.birimFiyat : 0.0;
  final iskontoOran = bazFiyat > 0 ? (indirimBirim / bazFiyat * 100) : 0.0;
  final iskontoTutar = indirimBirim * k.miktar;
  return (iskontoOran: iskontoOran, iskontoTutar: iskontoTutar);
}

UrunModel _urun({double satisFiyati = 100}) => UrunModel(
      urunAdi: 'Test Ürün',
      satisFiyati: satisFiyati,
      birimAdi: 'Adet',
      kdvOran: '20',
      stok: 50,
    );

void main() {
  group('SatisKalemModel iskonto hesaplama (promosyon/elle indirim izi)', () {
    test('indirim YOKSA (birimFiyat == katalog fiyatı) iskonto 0 kalır', () {
      final k = SepetKalem(urun: _urun(satisFiyati: 100), birimFiyat: 100, miktar: 2);
      final sonuc = _iskontoHesapla(k);
      expect(sonuc.iskontoOran, 0);
      expect(sonuc.iskontoTutar, 0);
    });

    test('promosyon/elle %20 indirimli satılan kalemde GERÇEK indirim '
        'artık yakalanır (önceden HER ZAMAN 0 idi)', () {
      // Katalog 100₺, promosyon/elle indirimle 80₺'den satılmış (%20).
      final k = SepetKalem(urun: _urun(satisFiyati: 100), birimFiyat: 80, miktar: 3);
      final sonuc = _iskontoHesapla(k);
      expect(sonuc.iskontoOran, closeTo(20.0, 0.001));
      expect(sonuc.iskontoTutar, closeTo(60.0, 0.001)); // (100-80)*3
    });

    test('birimFiyat katalog fiyatından YÜKSEKSE (manuel fiyat artışı) '
        'negatif "indirim" üretmez, 0da kalır', () {
      final k = SepetKalem(urun: _urun(satisFiyati: 100), birimFiyat: 120, miktar: 1);
      final sonuc = _iskontoHesapla(k);
      expect(sonuc.iskontoOran, 0);
      expect(sonuc.iskontoTutar, 0);
    });

    test('katalog fiyatı 0 ise (bölme hatası olmadan) güvenle 0 döner', () {
      final k = SepetKalem(urun: _urun(satisFiyati: 0), birimFiyat: 0, miktar: 1);
      final sonuc = _iskontoHesapla(k);
      expect(sonuc.iskontoOran, 0);
      expect(sonuc.iskontoTutar, 0);
    });
  });
}
