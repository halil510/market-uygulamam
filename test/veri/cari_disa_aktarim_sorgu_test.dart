// test/veri/cari_disa_aktarim_sorgu_test.dart
//
// CariDeposu.tumunuBorcAlacakAdresIle() (Excel dışa aktarım için, her
// carinin toplam borç/alacağını cari_hareket'ten SUM ile, varsayılan
// adresini cari_adres'ten getirir) Veritabani() singleton'ı üzerinden
// çalıştığı için, burada BİREBİR AYNI SQL gerçek şema üzerinde bir
// in-memory veritabanı içinde doğrudan çalıştırılıyor.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import '../helper/test_initializer.dart';

Future<List<Map<String, dynamic>>> _tumunuBorcAlacakAdresIle(Database db) => db.rawQuery('''
      SELECT c.*,
        COALESCE(h.toplam_borc, 0) AS toplam_borc,
        COALESCE(h.toplam_alacak, 0) AS toplam_alacak,
        ca.adres AS adres
      FROM cari c
      LEFT JOIN (
        SELECT cari_id, SUM(borc) AS toplam_borc, SUM(alacak) AS toplam_alacak
        FROM cari_hareket WHERE is_deleted = 0 GROUP BY cari_id
      ) h ON h.cari_id = c.id
      LEFT JOIN cari_adres ca ON ca.cari_id = c.id AND ca.varsayilan = 1
      WHERE c.is_deleted = 0
      ORDER BY c.unvan ASC
    ''');

void main() {
  late Database db;
  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  test('borç/alacak toplamları ve varsayılan adres doğru geliyor', () async {
    final cariId = await db.insert('cari', {
      'unvan': 'Hayrullah Şeran', 'cari_kodu': 'CARI0-3', 'cari_tipi': 'Müşteri',
      'bakiye': 24178.23, 'aktif': 1, 'is_deleted': 0,
    });
    await db.insert('cari_hareket', {
      'cari_id': cariId, 'tarih': DateTime.now().toIso8601String(),
      'fis_tipi': 'Satış', 'aciklama': '', 'borc': 100000.0, 'alacak': 80000.0, 'is_deleted': 0,
    });
    await db.insert('cari_hareket', {
      'cari_id': cariId, 'tarih': DateTime.now().toIso8601String(),
      'fis_tipi': 'Tahsilat', 'aciklama': '', 'borc': 81462.23, 'alacak': 77284.0, 'is_deleted': 0,
    });
    await db.insert('cari_adres', {
      'cari_id': cariId, 'adres_tipi': 'Fatura', 'adres': 'ADAMHARMANI', 'varsayilan': 1,
    });

    final satirlar = await _tumunuBorcAlacakAdresIle(db);
    expect(satirlar.length, 1);
    final s = satirlar.first;
    expect((s['toplam_borc'] as num).toDouble(), closeTo(181462.23, 0.01));
    expect((s['toplam_alacak'] as num).toDouble(), closeTo(157284.0, 0.01));
    expect(s['adres'], 'ADAMHARMANI');
  });

  test('hiç hareketi/adresi olmayan bir cari 0/null ile (hata vermeden) döner',
      () async {
    await db.insert('cari', {
      'unvan': 'Yeni Cari', 'cari_kodu': 'CARI0-99', 'cari_tipi': 'Müşteri',
      'bakiye': 0, 'aktif': 1, 'is_deleted': 0,
    });
    final satirlar = await _tumunuBorcAlacakAdresIle(db);
    expect(satirlar.length, 1);
    expect((satirlar.first['toplam_borc'] as num).toDouble(), 0.0);
    expect(satirlar.first['adres'], isNull);
  });

  test('silinmiş (is_deleted=1) cari listeye hiç dahil edilmez', () async {
    await db.insert('cari', {
      'unvan': 'Silinmiş', 'cari_kodu': 'CARI0-DEL', 'cari_tipi': 'Müşteri',
      'bakiye': 0, 'aktif': 1, 'is_deleted': 1,
    });
    final satirlar = await _tumunuBorcAlacakAdresIle(db);
    expect(satirlar, isEmpty);
  });
}
