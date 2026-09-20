// test/saglayicilar/dashboard_hesap_test.dart
//
// Madde 31 (Dashboard) denetimi, 2026-09-20 — DashboardHesap saf
// fonksiyonları (DB'den bağımsız, doğrudan test edilebilir).
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/saglayicilar/riverpod/dashboard_provider.dart';

void main() {
  group('DashboardHesap.alacakBorcAyir', () {
    test('pozitif bakiyeler alacağa, negatifler borca gider', () {
      final r = DashboardHesap.alacakBorcAyir([500, -200, 300, -100]);
      expect(r.alacak, 800.0);
      expect(r.borc, 300.0);
    });

    test('borç MUTLAK DEĞER olarak döner (eksi işaretsiz)', () {
      final r = DashboardHesap.alacakBorcAyir([-1500]);
      expect(r.borc, 1500.0, reason: 'negatif değil, pozitif bir tutar olarak gösterilmeli');
      expect(r.alacak, 0.0);
    });

    test('sıfır bakiye ne alacağa ne borca eklenir', () {
      final r = DashboardHesap.alacakBorcAyir([0, 100, -50, 0]);
      expect(r.alacak, 100.0);
      expect(r.borc, 50.0);
    });

    test('boş liste 0/0 döner', () {
      final r = DashboardHesap.alacakBorcAyir([]);
      expect(r.alacak, 0.0);
      expect(r.borc, 0.0);
    });

    test('net toplam (500) tek başına gizlediği detayı (2000 alacak - '
        '1500 borç) doğru ayırır — bu KPI\'nın eklenme SEBEBİ', () {
      final r = DashboardHesap.alacakBorcAyir([2000, -1500]);
      expect(r.alacak, 2000.0);
      expect(r.borc, 1500.0);
      expect(r.alacak - r.borc, 500.0, reason: 'net toplamla tutarlı olmalı');
    });
  });

  group('DashboardHesap.karHesapla', () {
    test('brüt kâr = ciro - maliyet, net kâr = brüt kâr - gider', () {
      final r = DashboardHesap.karHesapla(ciro: 1000, maliyet: 600, gider: 100);
      expect(r.brutKar, 400.0);
      expect(r.netKar, 300.0);
    });

    test('DÜZELTME: maliyet artık düşülüyor — önceden netKar = ciro - '
        'gider idi (maliyeti HİÇ saymıyordu, ciro neredeyse tamamen kâr '
        'gibi görünürdü)', () {
      final r = DashboardHesap.karHesapla(ciro: 1000, maliyet: 700, gider: 0);
      expect(r.netKar, 300.0,
          reason: 'önceki (bug\'lı) formülle bu 1000 dönerdi — 700 TL '
              'maliyeti hiç saymayıp tüm ciroyu kâr gösterirdi');
    });

    test('marj oranı ciro=0 iken sıfır döner (bölme hatası yok)', () {
      final r = DashboardHesap.karHesapla(ciro: 0, maliyet: 0, gider: 0);
      expect(r.marjOrani, 0.0);
    });

    test('marj oranı doğru yüzde hesaplar', () {
      final r = DashboardHesap.karHesapla(ciro: 200, maliyet: 150, gider: 0);
      expect(r.marjOrani, 25.0, reason: '(200-150)/200*100 = 25');
    });

    test('zarar durumunda netKar negatif olabilir', () {
      final r = DashboardHesap.karHesapla(ciro: 100, maliyet: 80, gider: 50);
      expect(r.netKar, -30.0);
    });
  });
}
