// test/servisler/bulut/bulut_hata_siniflandirma_test.dart
//
// MASTER ERP DEEP AUDIT — Madde 5 sertleştirmesi: sunucudan dönen
// hataların "geçici" (yeniden denemeye değer) / "kalıcı" (validation/
// auth — yeniden denemek sonucu değiştirmez) sınıflandırması.
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/servisler/bulut/bulut_saglayici.dart';

void main() {
  group('bulutHataTuruBelirle', () {
    test('401 (kimlik doğrulama) KALICI sayılır', () {
      expect(bulutHataTuruBelirle(401), BulutHataTuru.kalici);
    });

    test('403 (yetki) KALICI sayılır', () {
      expect(bulutHataTuruBelirle(403), BulutHataTuru.kalici);
    });

    test('400/404/409/422 (validation/conflict) KALICI sayılır', () {
      for (final kod in [400, 404, 409, 422]) {
        expect(bulutHataTuruBelirle(kod), BulutHataTuru.kalici,
            reason: 'HTTP $kod kalıcı olmalı');
      }
    });

    test('5xx (sunucu hatası) GEÇİCİ sayılır', () {
      for (final kod in [500, 502, 503, 504]) {
        expect(bulutHataTuruBelirle(kod), BulutHataTuru.gecici,
            reason: 'HTTP $kod geçici olmalı');
      }
    });

    test('durum kodu yok (ağ hatası/zaman aşımı) GEÇİCİ sayılır', () {
      expect(bulutHataTuruBelirle(null), BulutHataTuru.gecici);
    });

    test('299 ve altı (2xx/3xx — normalde buraya hiç gelmemeli) '
        'güvenli tarafta GEÇİCİ sayılır', () {
      expect(bulutHataTuruBelirle(200), BulutHataTuru.gecici);
      expect(bulutHataTuruBelirle(301), BulutHataTuru.gecici);
    });
  });

  group('BulutIstekHatasi', () {
    test('.tur, statusKodu\'ndan doğru hesaplanır', () {
      const kalici = BulutIstekHatasi(401, 'yetkisiz');
      expect(kalici.tur, BulutHataTuru.kalici);

      const gecici = BulutIstekHatasi(503, 'sunucu meşgul');
      expect(gecici.tur, BulutHataTuru.gecici);

      const kodsuz = BulutIstekHatasi(null, 'bağlantı koptu');
      expect(kodsuz.tur, BulutHataTuru.gecici);
    });

    test('toString() durum kodunu okunabilir şekilde içerir', () {
      const hata = BulutIstekHatasi(422, 'geçersiz veri');
      expect(hata.toString(), contains('422'));
      expect(hata.toString(), contains('geçersiz veri'));
    });
  });

  group('BulutSonuc.tur', () {
    test('sonStatusKodu 4xx ise kalıcı', () {
      const sonuc = BulutSonuc(basarili: 0, hata: 5, sonStatusKodu: 401);
      expect(sonuc.tur, BulutHataTuru.kalici);
    });

    test('sonStatusKodu null (ağ hatası) ise geçici', () {
      const sonuc = BulutSonuc(basarili: 0, hata: 5);
      expect(sonuc.tur, BulutHataTuru.gecici);
    });

    test('tamam getter\'ı hata=0 iken true döner', () {
      const basarili = BulutSonuc(basarili: 10, hata: 0);
      expect(basarili.tamam, isTrue);
      const basarisiz = BulutSonuc(basarili: 5, hata: 1);
      expect(basarisiz.tamam, isFalse);
    });
  });
}
