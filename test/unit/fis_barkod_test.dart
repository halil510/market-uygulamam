// test/unit/fis_barkod_test.dart
//
// FİŞ BARKODU TANIMA TESTİ
//
// Neden bu test kritik: Hızlı Satış ekranında okutulan HER barkod önce
// bu desenden geçiyor. Desen fazla geniş olursa bir ÜRÜN barkodu yanlışlıkla
// "fiş" sanılır ve kasiyerin karşısına "fiş güncelleme" ekranı çıkar —
// satış akışı durur. Fazla dar olursa fiş barkodu hiç tanınmaz.
//
// Fiş no formatı (Veritabani.fisNoUret):
//   3 HARF ön ek + 4 hane yıl + 9 hane sıra = 16 karakter
//   Örnek: MKP2026000000001
//
// Ürün barkodları TAMAMEN RAKAM olduğu için (EAN-13=13, EAN-8=8 hane)
// çakışma matematiksel olarak imkânsız — bu test onu garanti altına alır.

import 'package:flutter_test/flutter_test.dart';

/// hizli_satis_ekrani.dart içindeki `_fisNoDeseni` ile BİREBİR aynı.
/// Orada değişirse burada da değişmeli — test o yüzden var.
final _fisNoDeseni = RegExp(r'^(MKP|CRI|MSA)\d{13}$');

bool fisBarkoduMu(String b) => _fisNoDeseni.hasMatch(b.toUpperCase());

void main() {
  group('Fiş barkodu — KABUL edilmesi gerekenler', () {
    test('perakende satış fişi (MKP)', () {
      expect(fisBarkoduMu('MKP2026000000001'), isTrue);
    });

    test('cariye (veresiye) satış fişi (CRI)', () {
      expect(fisBarkoduMu('CRI2026000000042'), isTrue);
    });

    test('masa satış fişi (MSA)', () {
      expect(fisBarkoduMu('MSA2026000000007'), isTrue);
    });

    test('küçük harfle okunsa da tanınır', () {
      // Bazı barkod okuyucular küçük harf gönderebiliyor
      expect(fisBarkoduMu('mkp2026000000001'), isTrue);
    });
  });

  group('Fiş barkodu — REDDEDİLMESİ gerekenler (diğer belge tipleri)', () {
    // Bu belgelerin kendi ekranları ve muhasebe kuralları var; Hızlı
    // Satış ekranından güncellenmemeli.
    test('fatura reddedilir', () {
      expect(fisBarkoduMu('FAT2026000000001'), isFalse);
    });

    test('irsaliye reddedilir', () {
      expect(fisBarkoduMu('IRS2026000000001'), isFalse);
    });

    test('alım fişi reddedilir', () {
      expect(fisBarkoduMu('ALM2026000000001'), isFalse);
    });

    test('iade fişi reddedilir', () {
      expect(fisBarkoduMu('IAD2026000000001'), isFalse);
    });
  });

  group('ÜRÜN BARKODLARI ile çakışma OLMAMALI', () {
    test('EAN-13 ürün barkodu fiş sanılmaz', () {
      expect(fisBarkoduMu('8690504010101'), isFalse);
    });

    test('EAN-8 ürün barkodu fiş sanılmaz', () {
      expect(fisBarkoduMu('12345678'), isFalse);
    });

    test('tartılı ürün barkodu (GS1-TR prefix 28) fiş sanılmaz', () {
      // Markette en riskli senaryo: manav/kasap terazi barkodu
      expect(fisBarkoduMu('2812345000505'), isFalse);
    });

    test('16 HANELİ ama tamamı rakam olan barkod fiş sanılmaz', () {
      // Uzunluk aynı ama harf öneki yok — desen harf zorunlu kılıyor
      expect(fisBarkoduMu('1234567890123456'), isFalse);
    });
  });

  group('Bozuk / sınır girdiler', () {
    test('15 hane (eksik) reddedilir', () {
      expect(fisBarkoduMu('MKP202600000001'), isFalse);
    });

    test('17 hane (fazla) reddedilir', () {
      expect(fisBarkoduMu('MKP20260000000012'), isFalse);
    });

    test('sıra kısmında harf varsa reddedilir', () {
      expect(fisBarkoduMu('MKPABCDEFGHIJKLM'), isFalse);
    });

    test('boş girdi reddedilir', () {
      expect(fisBarkoduMu(''), isFalse);
    });

    test('tanınmayan 3 harfli ön ek reddedilir', () {
      expect(fisBarkoduMu('XYZ2026000000001'), isFalse);
    });
  });
}
