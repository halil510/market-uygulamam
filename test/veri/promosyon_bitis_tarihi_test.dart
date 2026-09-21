// test/veri/promosyon_bitis_tarihi_test.dart
//
// Kendi-keşif turu bulgusu: PromosyonDeposu.urunPromosyonlari()'ndeki
// SQL 'bitis_tarihi >= şimdiki_zaman' string karşılaştırması, bitis_tarihi
// saat bilgisi olmadan (00:00:00) saklandığı için bitiş GÜNÜNÜN
// BAŞLAMASIYLA promosyonu anında "süresi dolmuş" sayıyordu (aynı hata
// sınıfı PromosyonModel.gecerli'de de vardı, orada da düzeltildi).
//
// PromosyonDeposu.urunPromosyonlari() Veritabani() singleton'ı üzerinden
// çalıştığı için (diğer depo testlerindeki AYNI gerekçe), burada
// BİREBİR AYNI SQL gerçek şema üzerinde bir in-memory veritabanı
// içinde doğrudan çalıştırılıyor.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import '../helper/test_initializer.dart';

void main() {
  late Database db;
  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  Future<int> _promosyonEkle(int urunId, DateTime? bitis) => db.insert('promosyonlar', {
        'urun_id': urunId,
        'promosyon_adi': 'Test Promosyon',
        'iskonto_oran': 10,
        'min_miktar': 1,
        'bitis_tarihi': bitis?.toIso8601String(),
        'aktif': 1,
      });

  test('bitiş tarihi BUGÜNSE (saat 00:00:00 olarak saklansa bile) '
      'urunPromosyonlari hâlâ döner', () async {
    final urunId = await TestVeritabani.ornekUrunEkle(db);
    final bugunGunBasi =
        DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    await _promosyonEkle(urunId, bugunGunBasi);

    final now = DateTime.now().toIso8601String();
    final rows = await db.rawQuery(
      'SELECT p.* FROM promosyonlar p '
      'WHERE p.urun_id = ? AND p.aktif = 1 AND p.deleted_at IS NULL '
      'AND (DATE(p.bitis_tarihi) >= DATE(?)) '
      'ORDER BY p.iskonto_oran DESC',
      [urunId, now],
    );

    expect(rows.length, 1,
        reason: 'bitiş tarihi bugünse, günün HERHANGİ bir saatinde hâlâ dönmeli');
  });

  test('bitiş tarihi DÜNSE artık dönmez', () async {
    final urunId = await TestVeritabani.ornekUrunEkle(db);
    final dun = DateTime.now().subtract(const Duration(days: 1));
    await _promosyonEkle(urunId, DateTime(dun.year, dun.month, dun.day));

    final now = DateTime.now().toIso8601String();
    final rows = await db.rawQuery(
      'SELECT p.* FROM promosyonlar p '
      'WHERE p.urun_id = ? AND p.aktif = 1 AND p.deleted_at IS NULL '
      'AND (DATE(p.bitis_tarihi) >= DATE(?)) '
      'ORDER BY p.iskonto_oran DESC',
      [urunId, now],
    );

    expect(rows, isEmpty);
  });
}
