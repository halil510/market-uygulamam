// test/servisler/bulut/sync_backoff_test.dart
//
// MASTER ERP DEEP AUDIT — Madde 5 (Sync Network & Backoff Motoru)
// sertleştirmesinin test kapsamı. BulutManager._isle()'ın exponential
// backoff kararlarını verdiği SAF (DB/network'ten bağımsız) mantık.
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/servisler/bulut/sync_backoff.dart';

void main() {
  group('backoffSuresiSaniyeHesapla', () {
    test('ilk deneme (0) için hiç bekleme yok', () {
      expect(backoffSuresiSaniyeHesapla(0), 0);
    });

    test('her denemede süre İKİYE KATLANIR', () {
      expect(backoffSuresiSaniyeHesapla(1), 20); // 10 * 2^1
      expect(backoffSuresiSaniyeHesapla(2), 40); // 10 * 2^2
      expect(backoffSuresiSaniyeHesapla(3), 80); // 10 * 2^3
      expect(backoffSuresiSaniyeHesapla(4), 160);
    });

    test('30 dakikada (1800sn) TAVANLANIR — sonsuza kadar büyümez', () {
      expect(backoffSuresiSaniyeHesapla(10), 1800);
      expect(backoffSuresiSaniyeHesapla(20), 1800);
      expect(backoffSuresiSaniyeHesapla(1000), 1800);
    });

    test('negatif deneme sayısı da 0 gibi davranır (savunma amaçlı)', () {
      expect(backoffSuresiSaniyeHesapla(-1), 0);
    });
  });

  group('syncSatiriSimdiDenenebilirMi', () {
    test('deneme_sayisi=0 (hiç denenmemiş) her zaman denenebilir', () {
      final satir = {'deneme_sayisi': 0, 'son_deneme': null};
      expect(syncSatiriSimdiDenenebilirMi(satir), isTrue);
    });

    test('son_deneme kaydı yoksa (null) — belirsizlikte dene, atlama', () {
      final satir = {'deneme_sayisi': 3, 'son_deneme': null};
      expect(syncSatiriSimdiDenenebilirMi(satir), isTrue);
    });

    test('son_deneme ayrıştırılamıyorsa — belirsizlikte dene, atlama', () {
      final satir = {'deneme_sayisi': 3, 'son_deneme': 'bozuk-tarih'};
      expect(syncSatiriSimdiDenenebilirMi(satir), isTrue);
    });

    test('backoff penceresi DOLMADIYSA denenmez', () {
      final simdi = DateTime(2026, 1, 1, 12, 0, 0);
      final sonDeneme = simdi.subtract(const Duration(seconds: 5));
      // deneme_sayisi=1 → 20sn beklemeli, sadece 5sn geçti
      final satir = {
        'deneme_sayisi': 1,
        'son_deneme': sonDeneme.toIso8601String(),
      };
      expect(syncSatiriSimdiDenenebilirMi(satir, simdi: simdi), isFalse);
    });

    test('backoff penceresi TAM DOLUNCA denenebilir', () {
      final simdi = DateTime(2026, 1, 1, 12, 0, 0);
      final sonDeneme = simdi.subtract(const Duration(seconds: 20));
      // deneme_sayisi=1 → 20sn beklemeli, tam 20sn geçti
      final satir = {
        'deneme_sayisi': 1,
        'son_deneme': sonDeneme.toIso8601String(),
      };
      expect(syncSatiriSimdiDenenebilirMi(satir, simdi: simdi), isTrue);
    });

    test('backoff penceresi ÇOK AŞILMIŞSA (uzun süre kapalı kalmış '
        'uygulama) yine denenebilir', () {
      final simdi = DateTime(2026, 1, 1, 12, 0, 0);
      final sonDeneme = simdi.subtract(const Duration(days: 3));
      final satir = {
        'deneme_sayisi': 5,
        'son_deneme': sonDeneme.toIso8601String(),
      };
      expect(syncSatiriSimdiDenenebilirMi(satir, simdi: simdi), isTrue);
    });

    test('yüksek deneme sayısında (tavanlanmış backoff) pencere '
        'doğru hesaplanır', () {
      final simdi = DateTime(2026, 1, 1, 12, 0, 0);
      // deneme_sayisi=20 → tavan 1800sn — 1799sn'de henüz değil
      final henuzDegil = simdi.subtract(const Duration(seconds: 1799));
      expect(
        syncSatiriSimdiDenenebilirMi(
          {'deneme_sayisi': 20, 'son_deneme': henuzDegil.toIso8601String()},
          simdi: simdi,
        ),
        isFalse,
      );
      final tamZamani = simdi.subtract(const Duration(seconds: 1800));
      expect(
        syncSatiriSimdiDenenebilirMi(
          {'deneme_sayisi': 20, 'son_deneme': tamZamani.toIso8601String()},
          simdi: simdi,
        ),
        isTrue,
      );
    });
  });
}
