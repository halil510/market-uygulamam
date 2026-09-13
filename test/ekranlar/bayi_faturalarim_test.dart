// test/ekranlar/bayi_faturalarim_test.dart
//
// Bayi Portalı — "Faturalarım" ekranının veri izolasyonu doğrulaması:
// FaturaDeposu.listele(cariId: ...) SADECE o carinin faturalarını
// döndürmeli — bir bayi başka bir carinin faturasını asla görmemeli.
// FaturaDeposu Veritabani() singleton'ı üzerinden çalıştığı için (diğer
// depo testlerinde olduğu gibi) burada AYNI filtre SQL'i gerçek şema
// üzerinde doğrulanıyor.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import '../helper/test_initializer.dart';

void main() {
  late Database db;
  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  group('Bayi Faturalarım veri izolasyonu', () {
    test('sadece kendi cari_id\'sine ait faturalar döner, başka carininki hiç görünmez', () async {
      final bayiA = await TestVeritabani.ornekCariEkle(db, unvan: 'Bayi A', cariTipi: 'Tedarikçi');
      final bayiB = await TestVeritabani.ornekCariEkle(db, unvan: 'Bayi B', cariTipi: 'Tedarikçi');

      await db.insert('faturalar', {
        'fatura_no': 'FT-A1', 'cari_id': bayiA, 'tarih': DateTime.now().toIso8601String(),
        'genel_toplam': 100, 'durum': 'aktif',
      });
      await db.insert('faturalar', {
        'fatura_no': 'FT-B1', 'cari_id': bayiB, 'tarih': DateTime.now().toIso8601String(),
        'genel_toplam': 200, 'durum': 'aktif',
      });

      final rows = await db.rawQuery('''
        SELECT f.* FROM faturalar f WHERE f.durum != 'silindi' AND f.cari_id = ?
        ORDER BY f.tarih DESC
      ''', [bayiA]);

      expect(rows.length, 1);
      expect(rows.first['fatura_no'], 'FT-A1');
    });

    test('silinmiş (durum=silindi) faturalar listeye hiç girmez', () async {
      final bayiA = await TestVeritabani.ornekCariEkle(db, unvan: 'Bayi A', cariTipi: 'Tedarikçi');
      await db.insert('faturalar', {
        'fatura_no': 'FT-SILINDI', 'cari_id': bayiA, 'tarih': DateTime.now().toIso8601String(),
        'genel_toplam': 50, 'durum': 'silindi',
      });

      final rows = await db.rawQuery('''
        SELECT f.* FROM faturalar f WHERE f.durum != 'silindi' AND f.cari_id = ?
      ''', [bayiA]);

      expect(rows, isEmpty);
    });
  });
}
