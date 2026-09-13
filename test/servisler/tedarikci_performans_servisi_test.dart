// test/servisler/tedarikci_performans_servisi_test.dart
//
// FAZ 8 — Tedarikçi Performansı: sınıflandırma ve sıralama kuralının
// saf-fonksiyon seviyesinde doğrulanması (bkz.
// lib/servisler/tedarikci_performans_servisi.dart).
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/servisler/tedarikci_performans_servisi.dart';
import '../helper/test_initializer.dart';

TedarikciPerformansGirdi _girdi({
  int teslimAlinan = 0,
  int iptalEdilen = 0,
  int bekleyen = 0,
  double? ortSure,
  double ortTutar = 0,
}) =>
    TedarikciPerformansGirdi(
      tedarikciId: 1,
      tedarikciAdi: 'Test Tedarikçi',
      toplamSiparis: teslimAlinan + iptalEdilen + bekleyen,
      teslimAlinan: teslimAlinan,
      iptalEdilen: iptalEdilen,
      bekleyen: bekleyen,
      ortalamaTeslimSuresiGun: ortSure,
      ortalamaSiparisTutari: ortTutar,
    );

void main() {
  group('tedarikciPerformansiHesapla', () {
    test('hiç sonuçlanmış sipariş yoksa (hepsi beklemede) → Veri Yok', () {
      final s = tedarikciPerformansiHesapla(_girdi(bekleyen: 5));
      expect(s.sinif, TedarikciPerformansSinifi.veriYok);
      expect(s.tamamlanmaOrani, isNull);
    });

    test('tamamlanma oranı >= %90 → İyi', () {
      final s = tedarikciPerformansiHesapla(_girdi(teslimAlinan: 9, iptalEdilen: 1));
      expect(s.tamamlanmaOrani, 0.9);
      expect(s.sinif, TedarikciPerformansSinifi.iyi);
    });

    test('tamamlanma oranı %60-89 → Normal', () {
      final s = tedarikciPerformansiHesapla(_girdi(teslimAlinan: 6, iptalEdilen: 4));
      expect(s.tamamlanmaOrani, 0.6);
      expect(s.sinif, TedarikciPerformansSinifi.normal);
    });

    test('tamamlanma oranı %60 altı → Zayıf', () {
      final s = tedarikciPerformansiHesapla(_girdi(teslimAlinan: 3, iptalEdilen: 7));
      expect(s.tamamlanmaOrani, 0.3);
      expect(s.sinif, TedarikciPerformansSinifi.zayif);
    });

    test('beklemede siparişler tamamlanma oranı paydasına GİRMEZ', () {
      final s = tedarikciPerformansiHesapla(
          _girdi(teslimAlinan: 9, iptalEdilen: 1, bekleyen: 100));
      expect(s.tamamlanmaOrani, 0.9);
      expect(s.sinif, TedarikciPerformansSinifi.iyi);
    });
  });

  group('tedarikciPerformansListesiHesapla sıralama', () {
    test('Zayıf → Normal → İyi → Veri Yok sırasıyla listelenir', () {
      final girdiler = [
        TedarikciPerformansGirdi(
            tedarikciId: 1, tedarikciAdi: 'İyi Tedarikçi', toplamSiparis: 10,
            teslimAlinan: 10, iptalEdilen: 0, bekleyen: 0,
            ortalamaTeslimSuresiGun: 3, ortalamaSiparisTutari: 500),
        TedarikciPerformansGirdi(
            tedarikciId: 2, tedarikciAdi: 'Veri Yok Tedarikçi', toplamSiparis: 2,
            teslimAlinan: 0, iptalEdilen: 0, bekleyen: 2,
            ortalamaTeslimSuresiGun: null, ortalamaSiparisTutari: 0),
        TedarikciPerformansGirdi(
            tedarikciId: 3, tedarikciAdi: 'Zayıf Tedarikçi', toplamSiparis: 10,
            teslimAlinan: 2, iptalEdilen: 8, bekleyen: 0,
            ortalamaTeslimSuresiGun: null, ortalamaSiparisTutari: 300),
      ];
      final sonuc = tedarikciPerformansListesiHesapla(girdiler);
      expect(sonuc.map((s) => s.tedarikciAdi).toList(),
          ['Zayıf Tedarikçi', 'İyi Tedarikçi', 'Veri Yok Tedarikçi']);
    });
  });

  // TedarikciPerformansServisi.analizGetir Veritabani() singleton'ı
  // üzerinden çalıştığı için burada AYNI SQL gerçek şema üzerinde
  // doğrulanıyor.
  group('analizGetir SQL (şema doğrulaması)', () {
    late Database db;
    setUp(() async => db = await TestVeritabani.olustur());
    tearDown(() => db.close());

    test('durum bazlı sayım ve ortalama teslim süresi doğru hesaplanır', () async {
      final tedarikciId = await TestVeritabani.ornekCariEkle(db,
          unvan: 'Ülker Dağıtım', cariTipi: 'Tedarikçi');
      await db.insert('tedarikci_siparisler', {
        'cari_id': tedarikciId, 'siparis_no': 'SIP-1',
        'siparis_tarihi': '2026-09-01 10:00:00',
        'teslim_tarihi': '2026-09-03 10:00:00',
        'toplam_tutar': 1000, 'durum': 'teslim_alindi', 'is_deleted': 0,
      });
      await db.insert('tedarikci_siparisler', {
        'cari_id': tedarikciId, 'siparis_no': 'SIP-2',
        'siparis_tarihi': '2026-09-05 10:00:00',
        'toplam_tutar': 500, 'durum': 'iptal', 'is_deleted': 0,
      });
      await db.insert('tedarikci_siparisler', {
        'cari_id': tedarikciId, 'siparis_no': 'SIP-3',
        'siparis_tarihi': '2026-09-10 10:00:00',
        'toplam_tutar': 750, 'durum': 'beklemede', 'is_deleted': 0,
      });

      final rows = await db.rawQuery('''
        SELECT c.id AS tedarikci_id, c.unvan AS tedarikci_adi,
          COUNT(*) AS toplam,
          SUM(CASE WHEN t.durum = 'teslim_alindi' THEN 1 ELSE 0 END) AS teslim_alinan,
          SUM(CASE WHEN t.durum = 'iptal' THEN 1 ELSE 0 END) AS iptal_edilen,
          SUM(CASE WHEN t.durum = 'beklemede' THEN 1 ELSE 0 END) AS bekleyen,
          AVG(CASE WHEN t.durum = 'teslim_alindi' AND t.teslim_tarihi IS NOT NULL
                THEN julianday(t.teslim_tarihi) - julianday(t.siparis_tarihi) END) AS ort_sure,
          AVG(t.toplam_tutar) AS ort_tutar
        FROM tedarikci_siparisler t
        JOIN cari c ON c.id = t.cari_id
        WHERE t.is_deleted = 0
        GROUP BY t.cari_id
      ''');

      expect(rows.length, 1);
      final r = rows.first;
      expect(r['tedarikci_adi'], 'Ülker Dağıtım');
      expect(r['toplam'], 3);
      expect(r['teslim_alinan'], 1);
      expect(r['iptal_edilen'], 1);
      expect(r['bekleyen'], 1);
      expect((r['ort_sure'] as num).toDouble(), 2.0);
      expect((r['ort_tutar'] as num).toDouble(), closeTo(750, 0.01));
    });
  });
}
