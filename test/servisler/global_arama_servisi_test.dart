// test/servisler/global_arama_servisi_test.dart
//
// erp_roadmap_yeni_ekranlar.md madde 23 — Global Arama. GlobalAramaServisi
// Veritabani() singleton'ı üzerinden çalıştığı için (diğer depo
// testlerinde olduğu gibi) burada AYNI SQL gerçek şema üzerinde
// doğrulanıyor.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import '../helper/test_initializer.dart';

Future<List<Map<String, Object?>>> _urunAra(Database db, String q) => db.rawQuery(
    '''SELECT id, urun_adi, barkod FROM urunler
       WHERE (urun_adi LIKE ? OR barkod LIKE ? OR kod LIKE ?) AND is_deleted = 0
       ORDER BY urun_adi ASC LIMIT 6''',
    ['%$q%', '%$q%', '%$q%']);

Future<List<Map<String, Object?>>> _cariAra(Database db, String q) => db.rawQuery(
    '''SELECT id, unvan FROM cari
       WHERE (unvan LIKE ? OR cari_kodu LIKE ? OR telefon LIKE ? OR vergi_no LIKE ?)
         AND is_deleted = 0 AND aktif = 1
       ORDER BY unvan ASC LIMIT 6''',
    ['%$q%', '%$q%', '%$q%', '%$q%']);

Future<List<Map<String, Object?>>> _satisAra(Database db, String q) => db.rawQuery(
    '''SELECT id, fis_no, iptal FROM satislar
       WHERE fis_no LIKE ? AND is_deleted = 0
       ORDER BY tarih DESC LIMIT 6''',
    ['%$q%']);

Future<List<Map<String, Object?>>> _faturaAra(Database db, String q) => db.rawQuery(
    '''SELECT id, fatura_no FROM faturalar
       WHERE fatura_no LIKE ? AND durum != 'silindi'
       ORDER BY tarih DESC LIMIT 6''',
    ['%$q%']);

Future<List<Map<String, Object?>>> _masaAra(Database db, String q) => db.rawQuery(
    '''SELECT id, ad FROM masalar
       WHERE ad LIKE ? AND is_deleted = 0
       ORDER BY ad ASC LIMIT 6''',
    ['%$q%']);

void main() {
  late Database db;
  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  group('GlobalAramaServisi.ara SQL mantığı', () {
    test('ürün adı/barkod eşleşmesi bulur, silinmişi hariç tutar', () async {
      await TestVeritabani.ornekUrunEkle(db, urunAdi: 'Coca Cola 1L', barkod: '8691234567890');
      final silinmisId = await TestVeritabani.ornekUrunEkle(db, urunAdi: 'Coca Cola 2.5L');
      await db.update('urunler', {'is_deleted': 1}, where: 'id=?', whereArgs: [silinmisId]);

      final r1 = await _urunAra(db, 'Coca');
      expect(r1.length, 1);
      expect(r1.first['urun_adi'], 'Coca Cola 1L');

      final r2 = await _urunAra(db, '8691234567890');
      expect(r2.length, 1);
    });

    test('cari unvan/telefon eşleşmesi bulur, pasif/silinmiş hariç tutar', () async {
      final aktifId = await TestVeritabani.ornekCariEkle(db, unvan: 'Ahmet Yılmaz Market');
      await db.update('cari', {'telefon': '05321112233'}, where: 'id=?', whereArgs: [aktifId]);
      final pasifId = await TestVeritabani.ornekCariEkle(db, unvan: 'Ahmet Pasif Market');
      await db.update('cari', {'aktif': 0}, where: 'id=?', whereArgs: [pasifId]);

      final r = await _cariAra(db, 'Ahmet');
      expect(r.length, 1);
      expect(r.first['unvan'], 'Ahmet Yılmaz Market');

      final rTel = await _cariAra(db, '05321112233');
      expect(rTel.length, 1);
    });

    test('satış fiş no eşleşmesi bulur, iptal edilmiş de dahil (ayrı işaretlenir)', () async {
      await db.insert('satislar', {'fis_no': 'FIS-1001', 'iptal': 0, 'is_deleted': 0});
      await db.insert('satislar', {'fis_no': 'FIS-1002', 'iptal': 1, 'is_deleted': 0});

      final r = await _satisAra(db, 'FIS-100');
      expect(r.length, 2);
      final iptalOlan = r.firstWhere((e) => e['fis_no'] == 'FIS-1002');
      expect(iptalOlan['iptal'], 1);
    });

    test('fatura no eşleşmesi bulur, silinmiş durumundakini hariç tutar', () async {
      await db.insert('faturalar', {'fatura_no': 'FT-2001', 'durum': 'aktif'});
      await db.insert('faturalar', {'fatura_no': 'FT-2002', 'durum': 'silindi'});

      final r = await _faturaAra(db, 'FT-200');
      expect(r.length, 1);
      expect(r.first['fatura_no'], 'FT-2001');
    });

    test('masa adı eşleşmesi bulur, silinmişi hariç tutar', () async {
      await db.insert('masalar', {'ad': 'Masa 5', 'kategori': 'Salon'});
      final silinenId = await db.insert('masalar', {'ad': 'Masa 15', 'kategori': 'Salon'});
      await db.update('masalar', {'is_deleted': 1}, where: 'id=?', whereArgs: [silinenId]);

      final r = await _masaAra(db, 'Masa 1');
      // "Masa 15" silindi, "Masa 1" için sadece bunlar eşleşirdi ama
      // silinen hariç tutulduğundan sonuç boş olmalı.
      expect(r, isEmpty);

      final r2 = await _masaAra(db, 'Masa 5');
      expect(r2.length, 1);
    });
  });
}
