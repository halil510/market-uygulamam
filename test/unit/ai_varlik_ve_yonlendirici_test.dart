// test/unit/ai_varlik_ve_yonlendirici_test.dart
//
// Ek çözme (ürün/cari adı adayları) ve Gemini araç çağrısının güvenli eşlemesi.
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/servisler/ai/eylem/ai_eylem_modeli.dart';
import 'package:market_plus/servisler/ai/eylem/ai_eylem_yonlendirici.dart';
import 'package:market_plus/servisler/ai/eylem/ai_varlik_arama.dart';

void main() {
  group('AiVarlikArama.adaylar', () {
    final vakalar = <String, String>{
      'kolanın': 'kola',
      'ekmeğe': 'ekmek',
      'sütten': 'süt',
      'çayın': 'çay',
      'kitabı': 'kitap',
      'suyun': 'su',
      'ağacın': 'ağaç',
    };
    vakalar.forEach((girdi, beklenen) {
      test('"$girdi" → "$beklenen" adayı içerir', () {
        expect(AiVarlikArama.adaylar(girdi), contains(beklenen));
      });
    });

    test('en uzun aday ilk gelir, tekrar yok', () {
      final a = AiVarlikArama.adaylar('kolanın');
      expect(a.first, 'kolanın');
      expect(a.toSet().length, a.length);
    });

    test('çok kelimeli adda yalnız SON kelimenin eki atılır', () {
      final a = AiVarlikArama.adaylar('ülker çikolatalı gofretin');
      expect(a, contains('ülker çikolatalı gofret'));
      expect(a.every((x) => x.startsWith('ülker çikolatalı')), isTrue);
    });

    test('uydurma sözcük iki harfli köke indirgenip yanlış eşleşmez', () {
      final a = AiVarlikArama.adaylar('xyzabc');
      expect(a.any((x) => x.length < 3), isFalse);
    });

    test('anahtar: Türkçe duyarsız karşılaştırma', () {
      expect(AiVarlikArama.anahtar('ÇİKOLATA'), AiVarlikArama.anahtar('cikolata'));
      expect(AiVarlikArama.anahtar('Süt'), 'sut');
    });
  });

  group('AiEylemYonlendirici.komutaCevir (Gemini çıktısı doğrulaması)', () {
    test('fiyat: islem/alan eşlemesi', () {
      final k = AiEylemYonlendirici.komutaCevir('urun_fiyat_guncelle',
          {'urun_adi': 'kola', 'alan': 'alis', 'islem': 'yuzde_artir', 'deger': 10});
      expect(k?.tur, AiEylemTuru.fiyatGuncelle);
      expect(k?.fiyatAlani, 'alisFiyat');
      expect(k?.islem, 'yuzdeArtir');
      expect(k?.deger, 10);
    });

    test('alan belirtilmezse satış', () {
      final k = AiEylemYonlendirici.komutaCevir(
          'urun_fiyat_guncelle', {'urun_adi': 'kola', 'islem': 'ayarla', 'deger': 35});
      expect(k?.fiyatAlani, 'satisFiyati');
    });

    test('eksik/negatif/geçersiz argüman → null (işlem YAPILMAZ)', () {
      expect(AiEylemYonlendirici.komutaCevir('urun_fiyat_guncelle', {'urun_adi': 'kola'}), isNull);
      expect(
          AiEylemYonlendirici.komutaCevir(
              'urun_fiyat_guncelle', {'urun_adi': 'k', 'islem': 'ayarla', 'deger': -5}),
          isNull);
      expect(
          AiEylemYonlendirici.komutaCevir(
              'urun_fiyat_guncelle', {'urun_adi': 'k', 'islem': 'bilinmeyen', 'deger': 5}),
          isNull);
      expect(AiEylemYonlendirici.komutaCevir('urun_stok_duzenle', {'urun_adi': 'k', 'islem': 'artir', 'miktar': 'çok'}), isNull);
      expect(AiEylemYonlendirici.komutaCevir('gider_ekle', {'tutar': 0}), isNull);
      expect(AiEylemYonlendirici.komutaCevir('olmayan_arac', {'x': 1}), isNull);
      expect(AiEylemYonlendirici.komutaCevir('urun_durum_degistir', {'urun_adi': 'k', 'aktif': 'evet'}), isNull);
    });

    test('stok, durum, gider, tahsilat, cari', () {
      var k = AiEylemYonlendirici.komutaCevir(
          'urun_stok_duzenle', {'urun_adi': 'süt', 'islem': 'artir', 'miktar': 3, 'birim': 'Koli'});
      expect(k?.birim, 'koli');
      k = AiEylemYonlendirici.komutaCevir('urun_durum_degistir', {'urun_adi': 'süt', 'aktif': false});
      expect(k?.aktif, false);
      k = AiEylemYonlendirici.komutaCevir('gider_ekle', {'tutar': 500, 'kategori': 'kira'});
      expect(k?.metin, 'kira');
      expect(k?.odemeTuru, 'Nakit');
      k = AiEylemYonlendirici.komutaCevir(
          'cari_tahsilat_odeme', {'cari_adi': 'Ali', 'tutar': 250, 'islem': 'tahsilat', 'odeme_turu': 'havale'});
      expect(k?.islemTipi, 'Tahsilat');
      expect(k?.odemeTuru, 'Havale');
      k = AiEylemYonlendirici.komutaCevir('cari_ekle', {'unvan': 'Atlas', 'tip': 'tedarikci'});
      expect(k?.islemTipi, 'Tedarikçi');
    });

    test('ürün ekle: model çıktısı doğrulamadan geçer (geçersiz KDV elenir)', () {
      final k = AiEylemYonlendirici.komutaCevir('urun_ekle', {
        'urun_adi': 'Gofret',
        'satis_fiyati': 10,
        'alis_fiyati': 6,
        'kdv_orani': 33, // geçersiz
        'stok': 50,
        'kategori': 'atıştırmalık',
      });
      expect(k?.tur, AiEylemTuru.urunEkle);
      expect(k?.urunAlanlari?['satisFiyati'], 10);
      expect(k?.urunAlanlari?['stok'], 50);
      expect(k?.urunAlanlari?.containsKey('kdvOran'), isFalse);
      expect(k?.uyarilar, isNotEmpty);
      expect(k?.urunAlanlari?['anaGrup'], 'Atıştırmalık');
    });
  });

  group('eylemIpucuVar kapısı (gereksiz API çağrısını önler)', () {
    test('işlem gibi görünenler', () {
      for (final s in ['bu kolayı 40 liraya yapalım', 'depoya 3 koli süt ekle', 'kira 500 yaz']) {
        expect(AiEylemYonlendirici.eylemIpucuVar(s), isTrue, reason: s);
      }
    });
    test('okuma/soru/sohbet', () {
      for (final s in ['merhaba', 'bugün ciro ne kadar', 'ürün nasıl eklenir', 'kasa durumu', 'stok nedir']) {
        expect(AiEylemYonlendirici.eylemIpucuVar(s), isFalse, reason: s);
      }
    });
  });
}
