// test/veri/donem_devir_snapshot_test.dart
//
// Yıl Sonu Devir motoru FAZ 3 (2026-09-16) — stok/kasa snapshot
// sorgularının SQL mantığı, DonemDevirServisi'ndekiyle BİREBİR aynı,
// gerçek şema üzerinde doğrulanıyor (Veritabani() singleton'ı
// kullanan sınıflar için bu projenin test deseni — bkz.
// vardiya_nakit_mutabakat_test.dart yorumu). Cari/banka snapshot
// fazları zaten test edilmiş CariDeposu/BankaHesapDeposu metodlarını
// çağırdığı için burada ayrıca test edilmiyor.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import '../helper/test_initializer.dart';

Future<List<Map<String, Object?>>> _stokSnapshotSatirlari(Database db, int subeId) {
  return db.rawQuery('''
    SELECT su.urun_id AS urun_id, su.stok AS miktar
    FROM sube_urun su
    JOIN urunler u ON u.id = su.urun_id
    WHERE su.sube_id = ? AND u.is_deleted = 0
  ''', [subeId]);
}

Future<double> _kasaBakiyeSonrasi(Database db, int subeId) async {
  final rows = await db.rawQuery(
    'SELECT bakiye_sonrasi FROM kasa_hareketleri '
    'WHERE deleted_at IS NULL AND sube_id = ? ORDER BY tarih DESC, id DESC LIMIT 1',
    [subeId],
  );
  return rows.isEmpty ? 0.0 : ((rows.first['bakiye_sonrasi'] as num?)?.toDouble() ?? 0.0);
}

void main() {
  late Database db;
  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  group('Stok snapshot sorgusu (FAZ 4)', () {
    test('sube_urun satırları urunler ile eşleşip döner', () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db, urunAdi: 'Kola');
      await db.insert('sube_urun', {'urun_id': urunId, 'sube_id': 1, 'stok': 42});

      final satirlar = await _stokSnapshotSatirlari(db, 1);
      expect(satirlar, hasLength(1));
      expect(satirlar.first['urun_id'], urunId);
      expect(satirlar.first['miktar'], 42);
    });

    test('is_deleted=1 olan ürün hariç tutulur', () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db, urunAdi: 'Silinmiş Ürün');
      await db.update('urunler', {'is_deleted': 1}, where: 'id = ?', whereArgs: [urunId]);
      await db.insert('sube_urun', {'urun_id': urunId, 'sube_id': 1, 'stok': 10});

      expect(await _stokSnapshotSatirlari(db, 1), isEmpty);
    });

    test('farklı şubenin sube_urun satırı dahil edilmez', () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db);
      await db.insert('sube_urun', {'urun_id': urunId, 'sube_id': 2, 'stok': 5});

      expect(await _stokSnapshotSatirlari(db, 1), isEmpty);
      expect(await _stokSnapshotSatirlari(db, 2), hasLength(1));
    });

    test('sube_urun satırı hiç olmayan ürün (bilinen sınırlama) dahil edilmez', () async {
      await TestVeritabani.ornekUrunEkle(db); // sube_urun'a hiç eklenmedi
      expect(await _stokSnapshotSatirlari(db, 1), isEmpty);
    });
  });

  group('Kasa bakiye_sonrasi sorgusu (FAZ 6 — şube parametreli)', () {
    test('doğru şubenin EN SON bakiye_sonrasi değeri döner', () async {
      await db.insert('kasa_hareketleri', {
        'hareket_tipi': 'Satış', 'tutar': 100, 'sube_id': 1,
        'tarih': DateTime(2026, 1, 1).toIso8601String(), 'bakiye_sonrasi': 100,
      });
      await db.insert('kasa_hareketleri', {
        'hareket_tipi': 'Satış', 'tutar': 50, 'sube_id': 1,
        'tarih': DateTime(2026, 1, 2).toIso8601String(), 'bakiye_sonrasi': 150,
      });
      expect(await _kasaBakiyeSonrasi(db, 1), 150.0);
    });

    test('AktifSubeServisi\'ne bakılmaksızın, İSTENEN şube doğru okunur (çok şubeli senaryo)', () async {
      await db.insert('kasa_hareketleri', {
        'hareket_tipi': 'Satış', 'tutar': 100, 'sube_id': 1,
        'tarih': DateTime(2026, 1, 1).toIso8601String(), 'bakiye_sonrasi': 100,
      });
      await db.insert('kasa_hareketleri', {
        'hareket_tipi': 'Satış', 'tutar': 999, 'sube_id': 2,
        'tarih': DateTime(2026, 1, 1).toIso8601String(), 'bakiye_sonrasi': 999,
      });
      // Devir Şube 1 için çalışıyor olsa bile (AktifSubeServisi Şube 2'yi
      // gösterse dahi) doğru şubenin bakiyesi dönmeli — bu senaryo tam
      // olarak KasaDeposu.guncelBakiye()'nin KULLANILMAMASININ sebebi.
      expect(await _kasaBakiyeSonrasi(db, 1), 100.0);
      expect(await _kasaBakiyeSonrasi(db, 2), 999.0);
    });

    test('deleted_at dolu hareket sayılmaz', () async {
      await db.insert('kasa_hareketleri', {
        'hareket_tipi': 'Satış', 'tutar': 100, 'sube_id': 1,
        'tarih': DateTime(2026, 1, 2).toIso8601String(), 'bakiye_sonrasi': 100,
        'deleted_at': DateTime(2026, 1, 3).toIso8601String(),
      });
      expect(await _kasaBakiyeSonrasi(db, 1), 0.0);
    });

    test('hiç hareket yoksa 0 döner', () async {
      expect(await _kasaBakiyeSonrasi(db, 1), 0.0);
    });
  });
}
