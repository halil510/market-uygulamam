// test/unit/ai_eylem_ayristirici_test.dart
//
// Asistanın işlem komutlarını anlaması + OKUMA sorularını işlem SAYMAMASI.
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/servisler/ai/eylem/ai_eylem_ayristirici.dart';
import 'package:market_plus/servisler/ai/eylem/ai_eylem_modeli.dart';

void main() {
  AiEylemKomutu? a(String s) => AiEylemAyristirici.ayristir(s);

  group('Fiyat güncelle', () {
    test('mutlak fiyat (ek ve fiil çeşitleri)', () {
      for (final s in [
        'kolanın satış fiyatını 35 yap',
        'kola fiyatı 35 olsun',
        'kolanın fiyatını otuz beş lira yap',
        'kolanın fiyatını 35 liraya güncelle',
      ]) {
        final c = a(s);
        expect(c?.tur, AiEylemTuru.fiyatGuncelle, reason: s);
        expect(c?.islem, 'ayarla', reason: s);
        expect(c?.deger, 35, reason: s);
        expect(c?.fiyatAlani, 'satisFiyati', reason: s);
        expect(c?.urunMetni, startsWith('kola'), reason: s);
      }
    });

    test("40'a çıkar → ayarla (artış miktarı değil)", () {
      final c = a("süt fiyatını 40'a çıkar");
      expect(c?.islem, 'ayarla');
      expect(c?.deger, 40);
    });

    test('yüzde zam / indirim', () {
      var c = a('ekmeğe yüzde 10 zam yap');
      expect(c?.islem, 'yuzdeArtir');
      expect(c?.deger, 10);
      expect(c?.urunMetni, 'ekmeğe');
      c = a('ekmeğe %10 indirim yap');
      expect(c?.islem, 'yuzdeAzalt');
      c = a('sütün fiyatını yüzde yirmi düşür');
      expect(c?.islem, 'yuzdeAzalt');
      expect(c?.deger, 20);
    });

    test('tutar zam / indirim', () {
      var c = a('çaya 5 lira zam yap');
      expect(c?.islem, 'artir');
      expect(c?.deger, 5);
      c = a('çayın fiyatını 2 lira düşür');
      expect(c?.islem, 'azalt');
      expect(c?.deger, 2);
    });

    test('alış ve toptan fiyat alanı', () {
      expect(a('sütün alış fiyatını 28 yap')?.fiyatAlani, 'alisFiyat');
      expect(a('sütün toptan fiyatını 30 yap')?.fiyatAlani, 'toptanFiyat');
    });
  });

  group('Stok düzenle', () {
    test('ekle / artır', () {
      var c = a('süte 50 adet stok ekle');
      expect(c?.tur, AiEylemTuru.stokDuzenle);
      expect(c?.islem, 'artir');
      expect(c?.deger, 50);
      expect(c?.birim, 'adet');
      expect(c?.urunMetni, 'süte');
      c = a('ekmeğin stoğunu elli artır');
      expect(c?.islem, 'artir');
      expect(c?.deger, 50);
    });

    test('ayarla / sıfırla', () {
      var c = a('ekmeğin stoğunu 100 yap');
      expect(c?.islem, 'ayarla');
      expect(c?.deger, 100);
      c = a('kola stoğunu sıfırla');
      expect(c?.islem, 'ayarla');
      expect(c?.deger, 0);
    });

    test('azalt / düş', () {
      var c = a('sütten stoktan 5 düş');
      expect(c?.islem, 'azalt');
      expect(c?.deger, 5);
      c = a('çay stok 3 azalt');
      expect(c?.islem, 'azalt');
    });

    test('birimli doğal cümle: koli', () {
      final c = a('20 koli kola ekle');
      expect(c?.tur, AiEylemTuru.stokDuzenle);
      expect(c?.birim, 'koli');
      expect(c?.deger, 20);
      expect(c?.urunMetni, 'kola');
    });
  });

  group('Ürün ekle', () {
    test('fiyat alanlarıyla', () {
      final c = a('ülker çikolatalı gofret ekle alış 6 satış 10 stok 50');
      expect(c?.tur, AiEylemTuru.urunEkle);
      expect(c?.urunAlanlari?['urunAdi'], 'Ülker Çikolatalı Gofret');
      expect(c?.urunAlanlari?['alisFiyat'], 6);
      expect(c?.urunAlanlari?['satisFiyati'], 10);
      expect(c?.urunAlanlari?['stok'], 50);
    });

    test('"yeni ürün ekle" + yazıyla', () {
      final c = a('yeni ürün ekle su satış fiyatı beş lira kdv yüzde bir');
      expect(c?.tur, AiEylemTuru.urunEkle);
      expect(c?.urunAlanlari?['urunAdi'], 'Su');
      expect(c?.urunAlanlari?['satisFiyati'], 5);
    });

    test('stok ekleme ürün eklemeyle karışmaz', () {
      expect(a('süt stok 50 ekle')?.tur, AiEylemTuru.stokDuzenle);
    });
  });

  group('Pasif / aktif', () {
    test('pasife al', () {
      final c = a('kolayı pasife al');
      expect(c?.tur, AiEylemTuru.urunDurum);
      expect(c?.aktif, false);
      expect(c?.urunMetni, 'kolayı');
    });
    test('satıştan kaldır', () {
      final c = a('eski sabunu satıştan kaldır');
      expect(c?.aktif, false);
    });
    test('aktife al', () {
      expect(a('sabunu aktife al')?.aktif, true);
    });
  });

  group('Gider', () {
    test('kira gideri', () {
      final c = a('kira gideri 15000 ekle');
      expect(c?.tur, AiEylemTuru.giderEkle);
      expect(c?.deger, 15000);
      expect(c?.metin, 'kira');
      expect(c?.odemeTuru, 'Nakit');
    });
    test('fatura yazıyla', () {
      final c = a('elektrik faturası iki bin beş yüz gider yaz');
      expect(c?.tur, AiEylemTuru.giderEkle);
      expect(c?.deger, 2500);
      expect(c?.metin, 'elektrik faturası');
    });
  });

  group('Tahsilat / ödeme', () {
    test('tahsilat al', () {
      final c = a("Ali Yılmaz'dan 500 lira tahsilat al");
      expect(c?.tur, AiEylemTuru.tahsilatOdeme);
      expect(c?.islemTipi, 'Tahsilat');
      expect(c?.deger, 500);
      expect(c?.cariMetni, 'ali yılmaz');
    });
    test('ödeme yap', () {
      final c = a("Atlas Toptan'a 5000 lira ödeme yap");
      expect(c?.islemTipi, 'Odeme');
      expect(c?.deger, 5000);
      expect(c?.cariMetni, 'atlas toptan');
    });
    test('ödeme aldım = tahsilat', () {
      final c = a('Mehmet Demir 250 lira ödeme aldım');
      expect(c?.islemTipi, 'Tahsilat');
    });
    test('havale/kart türü ayıklanır', () {
      expect(a('Ali Yılmaz 500 lira havale tahsilat al')?.odemeTuru, 'Havale');
      expect(a('Ali Yılmaz 500 lira kartla tahsilat al')?.odemeTuru, 'Kredi Kartı');
    });
  });

  group('Cari ekle', () {
    test('yeni müşteri + telefon', () {
      final c = a('yeni müşteri ayşe demir 05321234567');
      expect(c?.tur, AiEylemTuru.cariEkle);
      expect(c?.metin, 'Ayşe Demir');
      expect(c?.telefon, '05321234567');
      expect(c?.islemTipi, 'Müşteri');
    });
    test('tedarikçi ekle', () {
      final c = a('atlas gıda tedarikçi ekle');
      expect(c?.tur, AiEylemTuru.cariEkle);
      expect(c?.islemTipi, 'Tedarikçi');
    });
    test('adsız "cari ekle" işlem değil (gezinmeye kalır)', () {
      expect(a('cari ekle'), isNull);
    });
  });

  group('OKUMA soruları işlem SAYILMAZ', () {
    const sorular = [
      'bugünkü ciro ne kadar',
      'kasada ne kadar para var',
      'kritik stoklar',
      'kolanın fiyatı kaç',
      'kolanın stoğu kaç',
      'stok durumu',
      'en çok satan 10 ürün',
      'ürün nasıl eklenir',
      'gider raporu',
      'bu ay giderler ne kadar',
      'ödeme yöntemi dağılımı son 7 gün',
      'tahsilat özeti bu hafta',
      'borçlu müşteriler',
      'ürün listesi',
      'merhaba',
      'fiyat sorgula süt',
      'zam gelen ürünler hangileri',
      'ürün eklemek istiyorum nasıl yaparım',
      'stok 50 altındaki ürünler',
      'cari listesi',
    ];
    for (final s in sorular) {
      test('"$s"', () => expect(a(s), isNull));
    }
  });
}
