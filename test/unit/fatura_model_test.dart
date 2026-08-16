import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/modeller/fatura_model.dart';

void main() {
  group('FaturaModel', () {
    test('odendi getter - odemeDurumu "odendi" iken true', () {
      final f = FaturaModel(tarih: DateTime.now(), odemeDurumu: 'odendi');
      expect(f.odendi, isTrue);
    });

    test('odendi getter - "beklemede" iken false', () {
      final f = FaturaModel(tarih: DateTime.now(), odemeDurumu: 'beklemede');
      expect(f.odendi, isFalse);
    });

    test('eFaturaGonderildi getter doğru çalışır', () {
      final f = FaturaModel(tarih: DateTime.now(), eFaturaDurum: 'gonderildi');
      expect(f.eFaturaGonderildi, isTrue);
    });

    test('vadesiGecti - vade tarihi geçmişte ve kalan tutar var -> true', () {
      final f = FaturaModel(
        tarih: DateTime(2020, 1, 1),
        vadeTarihi: DateTime(2020, 1, 15),
        kalanTutar: 500,
      );
      expect(f.vadesiGecti, isTrue);
    });

    test('vadesiGecti - vade tarihi yoksa false', () {
      final f = FaturaModel(tarih: DateTime.now(), kalanTutar: 500);
      expect(f.vadesiGecti, isFalse);
    });

    test('varsayılan faturaTipi Satış', () {
      final f = FaturaModel(tarih: DateTime.now());
      expect(f.faturaTipi, equals('Satış'));
      expect(f.durum, equals('aktif'));
      expect(f.detaylar, isEmpty);
    });
  });

  group('FaturaDetayModel', () {
    test('toplamTutar alanı doğru taşınır', () {
      const d = FaturaDetayModel(
        urunAdi: 'Test Ürün',
        miktar: 2,
        birimFiyat: 50,
        iskontoOrani: 0,
        iskontoTutari: 0,
        kdvOrani: 20,
        kdvTutari: 20,
        araToplam: 100,
        toplamTutar: 120,
      );
      expect(d.toplamTutar, equals(120));
      expect(d.urunAdi, equals('Test Ürün'));
    });
  });
}
