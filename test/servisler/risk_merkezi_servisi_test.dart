// test/servisler/risk_merkezi_servisi_test.dart
//
// FAZ 11 — Risk Merkezi: seviye sınıflandırma saf fonksiyonu + şema
// doğrulaması (bkz. lib/servisler/risk_merkezi_servisi.dart). Eşikler
// cari_detay_ekrani.dart'taki risk rozetiyle AYNI olmalı (%60/%90).
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/servisler/risk_merkezi_servisi.dart';
import '../helper/test_initializer.dart';

void main() {
  group('riskSeviyesiHesapla', () {
    test('%90 ve üzeri → Kritik', () {
      expect(riskSeviyesiHesapla(0.9), RiskSeviyesi.kritik);
      expect(riskSeviyesiHesapla(1.5), RiskSeviyesi.kritik);
    });

    test('%60-89 → Dikkat', () {
      expect(riskSeviyesiHesapla(0.6), RiskSeviyesi.dikkat);
      expect(riskSeviyesiHesapla(0.89), RiskSeviyesi.dikkat);
    });

    test('%60 altı → İyi', () {
      expect(riskSeviyesiHesapla(0.0), RiskSeviyesi.iyi);
      expect(riskSeviyesiHesapla(0.59), RiskSeviyesi.iyi);
    });
  });

  // RiskMerkeziServisi.analizGetir Veritabani() singleton'ı üzerinden
  // çalıştığı için burada AYNI SQL gerçek şema üzerinde doğrulanıyor.
  group('analizGetir SQL (şema doğrulaması)', () {
    late Database db;
    setUp(() async => db = await TestVeritabani.olustur());
    tearDown(() => db.close());

    test('sadece limit_tutari>0 olan Müşteri tipi cariler döner', () async {
      await TestVeritabani.ornekCariEkle(db, unvan: 'Limitli Müşteri', cariTipi: 'Müşteri');
      await db.update('cari', {'limit_tutari': 1000, 'bakiye': 800},
          where: 'unvan = ?', whereArgs: ['Limitli Müşteri']);

      await TestVeritabani.ornekCariEkle(db, unvan: 'Limitsiz Müşteri', cariTipi: 'Müşteri');
      // limit_tutari varsayılan 0 — dahil edilmemeli.

      await TestVeritabani.ornekCariEkle(db, unvan: 'Sadece Tedarikçi', cariTipi: 'Tedarikçi');
      await db.update('cari', {'limit_tutari': 5000},
          where: 'unvan = ?', whereArgs: ['Sadece Tedarikçi']);

      final rows = await db.rawQuery('''
        SELECT id, unvan, bakiye, limit_tutari FROM cari
        WHERE is_deleted = 0 AND aktif = 1
          AND cari_tipi LIKE '%Müşteri%' AND limit_tutari > 0
      ''');

      expect(rows.length, 1);
      expect(rows.first['unvan'], 'Limitli Müşteri');
      expect(rows.first['bakiye'], 800);
    });
  });
}
