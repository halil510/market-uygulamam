// test/unit/yardimci_fonksiyonlar_test.dart
//
// Kritik yardımcı fonksiyonların birim testleri (sayı girdisi çözme, KDV,
// fiş no kısaltma, vergi no, kullanıcıya hata metni, sayıyı yazıya çevirme,
// Excel formül enjeksiyonu koruması).
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/cekirdek/utils/excel_guvenlik_utils.dart';
import 'package:market_plus/cekirdek/utils/hata_utils.dart';
import 'package:market_plus/cekirdek/utils/para_utils.dart';
import 'package:market_plus/cekirdek/utils/sayi_yaziya_cevir.dart';
import 'package:market_plus/cekirdek/utils/vergi_no_dogrulayici.dart';

void main() {
  group('ParaUtils.sayiCoz — Türkçe/İngilizce sayı girdisi', () {
    test('Türkçe ondalık virgül', () => expect(ParaUtils.sayiCoz('12,50'), 12.5));
    test('İngilizce ondalık nokta', () => expect(ParaUtils.sayiCoz('12.50'), 12.5));
    test('Binlik ayraçlı Türkçe', () => expect(ParaUtils.sayiCoz('1.234,56'), 1234.56));
    test('Binlik ayraçlı İngilizce', () => expect(ParaUtils.sayiCoz('1,234.56'), 1234.56));
    test('Boş girdi → null', () {
      expect(ParaUtils.sayiCoz(''), null);
      expect(ParaUtils.sayiCoz(null), null);
    });
    test('Anlamsız girdi → null', () {
      expect(ParaUtils.sayiCoz('abc'), null);
      expect(ParaUtils.sayiCoz('---'), null);
    });
    test('Para simgesi temizlenir', () {
      expect(ParaUtils.sayiCoz('₺ 12,50'), 12.5);
      expect(ParaUtils.sayiCoz('\$99.99'), 99.99);
    });
    test('Negatif sayı', () => expect(ParaUtils.sayiCoz('-12,5'), -12.5));
    test('sayi() varsayılan döner', () {
      expect(ParaUtils.sayi('abc', varsayilan: 5), 5);
      expect(ParaUtils.sayi('12,5'), 12.5);
    });
    test('tamSayiCoz() yuvarlar', () {
      expect(ParaUtils.tamSayiCoz('12,7'), 13);
      expect(ParaUtils.tamSayiCoz('12,2'), 12);
    });
  });

  group('ParaUtils KDV hesaplamaları', () {
    test('kdvHesapla — hariç fiyattan KDV', () => expect(ParaUtils.kdvHesapla(100, 20), 20));
    test('kdvDahilFiyat', () => expect(ParaUtils.kdvDahilFiyat(100, 20), 120));
    test('kdvHaricFiyat', () => expect(ParaUtils.kdvHaricFiyat(120, 20), closeTo(100, 0.001)));
    test('kdvPayiCikar — dahil fiyattan KDV payı',
        () => expect(ParaUtils.kdvPayiCikar(120, 20), closeTo(20, 0.001)));
  });

  group('ParaUtils.kisaFisNo', () {
    test('SYNC kopyası işaretlenir', () {
      expect(ParaUtils.kisaFisNo('MKP2026000000001-SYNCabc123').contains('⚠'), true);
    });
    test('Boş → FİŞ', () {
      expect(ParaUtils.kisaFisNo(''), 'FİŞ');
      expect(ParaUtils.kisaFisNo(null), 'FİŞ');
    });
  });

  group('VergiNoDogrulayici', () {
    test('Geçersiz VKN uzunluk', () => expect(VergiNoDogrulayici.vknGecerliMi('123'), false));
    test('Geçersiz TCKN baş 0', () => expect(VergiNoDogrulayici.tcknGecerliMi('01234567890'), false));
    test('Geçerli TCKN', () => expect(VergiNoDogrulayici.tcknGecerliMi('10000000146'), true));
    test('Boş → geçerli (zorunlu değil)', () {
      expect(VergiNoDogrulayici.gecerliMi(''), true);
      expect(VergiNoDogrulayici.gecerliMi(null), true);
    });
    test('VKN yalnız biçim kontrolü', () {
      expect(VergiNoDogrulayici.vknFormatGecerliMi('1234567890'), true);
      expect(VergiNoDogrulayici.vknFormatGecerliMi('12345'), false);
    });
  });

  group('kullaniciyaHataMetni', () {
    test('Exception ön ekini kaldırır', () {
      expect(kullaniciyaHataMetni(Exception('Bu sipariş zaten teslim alınmış.')),
          'Bu sipariş zaten teslim alınmış.');
    });
    test('Diğer hataları olduğu gibi bırakır',
        () => expect(kullaniciyaHataMetni('Normal metin'), 'Normal metin'));
    test('Ham ağ hatası (Dio, HTTP 400) anlaşılır Türkçe metne çevrilir', () {
      final m = kullaniciyaHataMetni(
          'DioException [bad response]: This exception was thrown because the response '
          'has a status code of 400 and RequestOptions.validateStatus was configured');
      expect(m.contains('DioException'), false);
      expect(m.contains('400'), true);
    });
    test('Bağlantı yok (SocketException) → internet uyarısı', () {
      expect(kullaniciyaHataMetni('SocketException: Failed host lookup: evds2.tcmb.gov.tr'),
          contains('İnternet'));
    });
    test('Bildirim metni: ön metin korunur, ham kısım sadeleşir', () {
      final m = bildirimMetniniSadelestir(
          'TCMB listesi alınamadı: DioException [connection error]: SocketException');
      expect(m.startsWith('TCMB listesi alınamadı: '), true);
      expect(m.contains('DioException'), false);
    });
    test('Bildirim metni: ortadaki "Exception: " ön eki kalkar', () {
      expect(bildirimMetniniSadelestir('Kayıt hatası: Exception: Stok yetersiz'),
          'Kayıt hatası: Stok yetersiz');
    });
    test('Bildirim metni: hata içermeyen mesaj değişmez', () {
      expect(bildirimMetniniSadelestir('Cari seçin'), 'Cari seçin');
    });
  });

  group('Sayıyı yazıya çevirme (fatura "Yalnız …")', () {
    test('Sıfır', () => expect(sayiyiYaziyaCevir(0), 'Sıfır'));
    test('Tek basamak', () => expect(sayiyiYaziyaCevir(5), 'Beş'));
    test('Yuvarlak onlar', () => expect(sayiyiYaziyaCevir(50), 'Elli'));
    test('Yüz ("BirYüz" değil)', () => expect(sayiyiYaziyaCevir(100), 'Yüz'));
    test('Bin ("BirBin" değil)', () => expect(sayiyiYaziyaCevir(1000), 'Bin'));
    test('Karmaşık', () => expect(sayiyiYaziyaCevir(5079), 'BeşBinYetmişDokuz'));
    test('Tutar — kuruşsuz', () {
      final s = tutariYaziyaCevir(100.0);
      expect(s.contains('Yüz'), true);
      expect(s.contains('TL'), true);
    });
    test('Tutar — kuruşlu', () {
      final s = tutariYaziyaCevir(10.50);
      expect(s.contains('TL'), true);
      expect(s.contains('Kr'), true);
    });
  });

  group('Excel formül enjeksiyonu koruması', () {
    test('= ile başlayan formül engellenir',
        () => expect(excelIcinGuvenliMetin('=SUM(A1:A2)').startsWith("'"), true));
    test('+ ile başlayan', () => expect(excelIcinGuvenliMetin('+1').startsWith("'"), true));
    test('- ile başlayan', () => expect(excelIcinGuvenliMetin('-2').startsWith("'"), true));
    test('@ ile başlayan', () => expect(excelIcinGuvenliMetin('@cmd').startsWith("'"), true));
    test('Normal metin dokunulmaz', () => expect(excelIcinGuvenliMetin('Elma'), 'Elma'));
    test('Boş → boş', () {
      expect(excelIcinGuvenliMetin(''), '');
      expect(excelIcinGuvenliMetin(null), '');
    });
  });
}
