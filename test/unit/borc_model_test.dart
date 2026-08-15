import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/modeller/borc_model.dart';

void main() {
  group('BorcModel', () {
    test('kalanTutar doğru hesaplanır', () {
      final b = BorcModel(
        baslik: 'Elektrik Faturası',
        tur: 'fatura',
        tutar: 1000,
        odenenTutar: 400,
        kesimTarihi: DateTime(2026, 1, 1),
        sonOdemeTarihi: DateTime(2026, 1, 15),
      );
      expect(b.kalanTutar, equals(600));
    });

    test('odemeOrani yüzde hesabı', () {
      final b = BorcModel(
        baslik: 'Kira',
        tur: 'kira',
        tutar: 2000,
        odenenTutar: 500,
        kesimTarihi: DateTime(2026, 1, 1),
        sonOdemeTarihi: DateTime(2026, 1, 15),
      );
      expect(b.odemeOrani, closeTo(25.0, 0.1));
    });

    test('odemeOrani tutar 0 iken hata vermez', () {
      final b = BorcModel(
        baslik: 'Test',
        tur: 'diger',
        tutar: 0,
        kesimTarihi: DateTime(2026, 1, 1),
        sonOdemeTarihi: DateTime(2026, 1, 15),
      );
      expect(b.odemeOrani, equals(0));
    });

    test('vadesiGecti - geçmiş tarih ve ödenmemiş -> true', () {
      final b = BorcModel(
        baslik: 'Eski Borç',
        tur: 'fatura',
        tutar: 100,
        kesimTarihi: DateTime(2020, 1, 1),
        sonOdemeTarihi: DateTime(2020, 1, 15),
        odendi: false,
      );
      expect(b.vadesiGecti, isTrue);
    });

    test('vadesiGecti - geçmiş tarih ama ödenmiş -> false', () {
      final b = BorcModel(
        baslik: 'Eski Borç Ödendi',
        tur: 'fatura',
        tutar: 100,
        kesimTarihi: DateTime(2020, 1, 1),
        sonOdemeTarihi: DateTime(2020, 1, 15),
        odendi: true,
      );
      expect(b.vadesiGecti, isFalse);
    });

    test('kritik - 3 günden az kalan ve ödenmemiş -> true', () {
      final yarin = DateTime.now().add(const Duration(days: 2));
      final b = BorcModel(
        baslik: 'Yaklaşan Borç',
        tur: 'vergi',
        tutar: 500,
        kesimTarihi: DateTime.now(),
        sonOdemeTarihi: yarin,
        odendi: false,
      );
      expect(b.kritik, isTrue);
    });

    test('kritik - uzak tarih -> false', () {
      final uzakTarih = DateTime.now().add(const Duration(days: 30));
      final b = BorcModel(
        baslik: 'Uzak Borç',
        tur: 'vergi',
        tutar: 500,
        kesimTarihi: DateTime.now(),
        sonOdemeTarihi: uzakTarih,
        odendi: false,
      );
      expect(b.kritik, isFalse);
    });

    test('varsayılan değerler doğru', () {
      final b = BorcModel(
        baslik: 'Test',
        tur: 'diger',
        tutar: 100,
        kesimTarihi: DateTime(2026, 1, 1),
        sonOdemeTarihi: DateTime(2026, 1, 15),
      );
      expect(b.taksitSayisi, equals(1));
      expect(b.odenenTaksit, equals(0));
      expect(b.odendi, isFalse);
      expect(b.oncelik, equals(2));
    });
  });
}
