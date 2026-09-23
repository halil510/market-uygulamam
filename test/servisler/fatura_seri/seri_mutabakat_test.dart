// test/servisler/fatura_seri/seri_mutabakat_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/servisler/fatura_seri/seri_mutabakat_servisi.dart';

Map<String, dynamic> _blok(int bas, int bit, int siradaki,
        {String seri = 'HLF', int yil = 2026, String durum = 'aktif'}) =>
    {
      'seri': seri, 'yil': yil, 'blok_baslangic': bas, 'blok_bitis': bit,
      'siradaki': siradaki, 'durum': durum,
    };

Map<String, dynamic> _fatura(int sira, {String sy = 'HLF2026', bool silindi = false}) =>
    {'fatura_no': '$sy${sira.toString().padLeft(9, '0')}', 'deleted_at': silindi ? 'x' : null};

void main() {
  group('seriMutabakatHesapla', () {
    test('tüketilen her numaranın faturası varsa boşluk yok, kalan doğru', () {
      final r = seriMutabakatHesapla([_blok(1, 10, 4)], [_fatura(1), _fatura(2), _fatura(3)]);
      final b = r.bloklar.single;
      expect(b.kullanilan, 3);
      expect(b.bosluklar, isEmpty);
      expect(b.kalan, 7);
      expect(r.toplamBosluk, 0);
    });

    test('tüketilip faturası olmayan numara boşluk olarak raporlanır', () {
      final r = seriMutabakatHesapla([_blok(1, 10, 4)], [_fatura(1), _fatura(3)]);
      expect(r.bloklar.single.bosluklar, [2]);
      expect(r.bloklar.single.sorunlu, isTrue);
    });

    test('silinmiş fatura boşluk değil, ayrı sayılır', () {
      final r = seriMutabakatHesapla([_blok(1, 10, 3)], [_fatura(1), _fatura(2, silindi: true)]);
      final b = r.bloklar.single;
      expect(b.kullanilan, 1);
      expect(b.silinmis, [2]);
      expect(b.bosluklar, isEmpty);
    });

    test('tükenmiş blokta kalan 0', () {
      final r = seriMutabakatHesapla(
          [_blok(1, 2, 3, durum: 'tukendi')], [_fatura(1), _fatura(2)]);
      expect(r.bloklar.single.kalan, 0);
      expect(r.bloklar.single.kullanilan, 2);
    });

    test('bloğun ileri kısmına elle girilmiş fatura boşluk sayılmaz, blok içi sayılır', () {
      final r = seriMutabakatHesapla([_blok(1, 10, 2)], [_fatura(1), _fatura(8)]);
      expect(r.bloklar.single.bosluklar, isEmpty);
      expect(r.blokDisiFaturalar, isEmpty);
    });

    test('hiçbir bloğa düşmeyen fatura blok dışı listelenir; başka seri karışmaz', () {
      final r = seriMutabakatHesapla(
        [_blok(11, 20, 12)],
        [_fatura(11), _fatura(5), _fatura(5, sy: 'FTR2026'), {'fatura_no': 'SERBEST-1'}],
      );
      expect(r.blokDisiFaturalar, ['HLF2026000000005']);
    });
  });
}
