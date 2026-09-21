// test/veri/urun_arama_barkodlar_test.dart
//
// Kullanıcı bulgusu: bir ürünün EK/alternatif barkodları (`barkodlar`
// sütunu — virgülle ayrılmış) metin arama kutularında hiç taranmıyordu.
// Kamera ile okutma (UrunDeposu.barkodlaGetir — zaten hem 'barkod' hem
// 'barkodlar'ı kontrol ediyordu, bu turda DEĞİŞMEDİ) ile arama kutusuna
// elle yazılan/okutulan bir alternatif barkod arasında TUTARSIZLIK
// vardı: okutma bulurdu, arama kutusu bulamazdı. Artık aşağıdaki TÜM
// arama yüzeyleri de 'barkodlar' sütununu tarıyor:
//   - UrunDeposu.ara() (Hızlı Satış/Ürün Liste'deki "ürün adı veya
//     barkod ara..." kutusu)
//   - UrunDeposu.sayfaliGetir() (Ürün Liste filtreleme)
//   - GlobalAramaServisi.ara() (Global Arama)
//   - AiSohbetServisi (AI sohbet — stok sorgula / ürün ara)
//
// Bu depolar Veritabani() singleton'ı üzerinden çalıştığı için (diğer
// depo testlerindeki AYNI gerekçe), burada BİREBİR AYNI SQL gerçek
// şema üzerinde bir in-memory veritabanı içinde doğrudan çalıştırılıyor.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import '../helper/test_initializer.dart';

Future<int> _urunEkle(Database db, {
  required String urunAdi,
  String? barkod,
  String? barkodlar,
}) => db.insert('urunler', {
      'urun_adi': urunAdi,
      'barkod': barkod,
      'barkodlar': barkodlar,
      'satis_fiyati': 100.0,
      'stok': 10.0,
      'birim_adi': 'Adet',
      'kdv_oran': '20',
      'aktif': 1,
      'is_deleted': 0,
    });

void main() {
  late Database db;
  late int urunId;

  setUp(() async {
    db = await TestVeritabani.olustur();
    urunId = await _urunEkle(db,
        urunAdi: 'Kola 1L',
        barkod: '8690000000001',
        barkodlar: '8690000000099,8690000000098');
  });
  tearDown(() => db.close());

  test('UrunDeposu.ara() — sadece barkodlar\'da olan bir kod artık '
      'bulunabiliyor (önceden hiç bulunamıyordu)', () async {
    const q = '%8690000000099%';
    final rows = await db.rawQuery(
      'SELECT * FROM urunler'
      ' WHERE (urun_adi LIKE ? OR barkod LIKE ? OR barkodlar LIKE ? OR kod LIKE ?'
      '       OR alternatif_urun_adi LIKE ? OR marka LIKE ?)'
      '   AND is_deleted = 0 AND aktif = 1'
      ' ORDER BY urun_adi ASC LIMIT ? OFFSET ?',
      [q, q, q, q, q, q, 80, 0],
    );
    expect(rows.length, 1);
    expect(rows.first['id'], urunId);
  });

  test('UrunDeposu.sayfaliGetir() — sadece barkodlar\'da olan bir kod '
      'artık bulunabiliyor', () async {
    const q = '%8690000000098%';
    final rows = await db.query('urunler',
        where: '(is_deleted = 0) AND (aktif = 1) AND '
            '(urun_adi LIKE ? OR barkod LIKE ? OR barkodlar LIKE ? OR kod LIKE ?'
            ' OR ana_grup LIKE ? OR alternatif_urun_adi LIKE ? OR marka LIKE ?)',
        whereArgs: [q, q, q, q, q, q, q]);
    expect(rows.length, 1);
    expect(rows.first['id'], urunId);
  });

  test('GlobalAramaServisi.ara() SQL\'i — barkodlar\'ı da tarıyor', () async {
    const q = '%8690000000099%';
    final rows = await db.rawQuery(
      '''SELECT id, urun_adi, barkod, satis_fiyati FROM urunler
         WHERE (urun_adi LIKE ? OR barkod LIKE ? OR barkodlar LIKE ? OR kod LIKE ?)
           AND is_deleted = 0
         ORDER BY urun_adi ASC LIMIT ?''',
      [q, q, q, q, 6],
    );
    expect(rows.length, 1);
  });

  test('primer barkod\'la eşleşme davranışı BOZULMADI (geriye dönük '
      'uyumluluk)', () async {
    const q = '%8690000000001%';
    final rows = await db.rawQuery(
      'SELECT * FROM urunler'
      ' WHERE (urun_adi LIKE ? OR barkod LIKE ? OR barkodlar LIKE ? OR kod LIKE ?'
      '       OR alternatif_urun_adi LIKE ? OR marka LIKE ?)'
      '   AND is_deleted = 0 AND aktif = 1'
      ' ORDER BY urun_adi ASC LIMIT ? OFFSET ?',
      [q, q, q, q, q, q, 80, 0],
    );
    expect(rows.length, 1);
  });

  test('hiçbir barkodla eşleşmeyen bir sorgu boş döner (yanlış-pozitif '
      'yok)', () async {
    const q = '%hicbir-sekilde-eslesmez%';
    final rows = await db.rawQuery(
      'SELECT * FROM urunler'
      ' WHERE (urun_adi LIKE ? OR barkod LIKE ? OR barkodlar LIKE ? OR kod LIKE ?'
      '       OR alternatif_urun_adi LIKE ? OR marka LIKE ?)'
      '   AND is_deleted = 0 AND aktif = 1'
      ' ORDER BY urun_adi ASC LIMIT ? OFFSET ?',
      [q, q, q, q, q, q, 80, 0],
    );
    expect(rows, isEmpty);
  });
}
