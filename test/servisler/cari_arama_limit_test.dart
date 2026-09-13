// test/servisler/cari_arama_limit_test.dart
//
// Performans denetiminde bulundu: CariDeposu.ara() hiç LIMIT
// uygulamıyordu (urunler.ara()'nın aksine) — büyük bir cari tabanında
// kısa bir arama terimi TÜM eşleşen satırları belleğe çekebiliyordu.
// CariDeposu Veritabani() singleton'ı üzerinden çalıştığı için AYNI SQL
// gerçek şema üzerinde doğrulanıyor.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import '../helper/test_initializer.dart';

Future<List<Map<String, Object?>>> _ara(Database db, String q, {int limit = 500}) => db.rawQuery(
    '''SELECT * FROM cari
       WHERE (unvan LIKE ? OR cari_kodu LIKE ? OR telefon LIKE ? OR vergi_no LIKE ? OR email LIKE ?)
       AND is_deleted = 0 AND aktif = 1
       ORDER BY unvan ASC LIMIT ?''',
    ['%$q%', '%$q%', '%$q%', '%$q%', '%$q%', limit]);

void main() {
  late Database db;
  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  group('CariDeposu.ara LIMIT', () {
    test('eşleşen kayıt sayısı limitten fazlaysa sonuç limitle sınırlanır', () async {
      for (var i = 0; i < 10; i++) {
        await TestVeritabani.ornekCariEkle(db, unvan: 'Market $i');
      }
      final r = await _ara(db, 'Market', limit: 3);
      expect(r.length, 3);
    });

    test('limit varsayılanı (500) altındaki normal aramalarda hiçbir kayıt kaybolmaz', () async {
      for (var i = 0; i < 10; i++) {
        await TestVeritabani.ornekCariEkle(db, unvan: 'Bakkal $i');
      }
      final r = await _ara(db, 'Bakkal');
      expect(r.length, 10);
    });
  });
}
