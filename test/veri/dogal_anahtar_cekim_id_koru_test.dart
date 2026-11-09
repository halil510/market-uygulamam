// test/veri/dogal_anahtar_cekim_id_koru_test.dart
//
// Derin denetim (2026-11-09) #17, yüksek: doğal anahtarlı tablolar
// (kategoriler/birimler/markalar/gider_kategoriler) buluttan her inişte
// REPLACE ile silinip yeni id alıyor, ürün/gider kategori bağı kopuyordu.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

void main() {
  late Database db;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await TestVeritabani.olustur();
    Veritabani.testVeritabani = db;
  });
  tearDown(() async {
    Veritabani.testVeritabani = null;
    await db.close();
  });

  test('buluttan inen kategori yerel id korunarak güncellenir, ürün bağı kopmaz', () async {
    final katId = await db.insert('kategoriler', {
      'ad': 'İçecek', 'last_updated': DateTime(2026, 11, 1).toIso8601String(),
    });
    final urun = await TestVeritabani.ornekUrunEkle(db);
    await db.update('urunler', {'kategori_id': katId}, where: 'id = ?', whereArgs: [urun]);

    await Veritabani().supaKayitlariEkle('kategoriler', [
      {'ad': 'İçecek', 'sira': 7, 'last_updated': DateTime(2026, 11, 9).toIso8601String()},
    ]);

    final kat = await db.query('kategoriler', where: 'ad = ?', whereArgs: ['İçecek']);
    expect(kat, hasLength(1));
    expect(kat.single['id'], katId, reason: 'önceden REPLACE yeni id veriyordu');
    expect(kat.single['sira'], 7);
    final u = (await db.query('urunler', where: 'id = ?', whereArgs: [urun])).first;
    expect(u['kategori_id'], katId);
  });

  test('yerel kayıt daha yeniyse buluttan gelen eski sürüm üzerine yazmaz', () async {
    await db.insert('kategoriler', {
      'ad': 'Atıştırmalık', 'sira': 1, 'last_updated': DateTime(2026, 11, 9).toIso8601String(),
    });
    await Veritabani().supaKayitlariEkle('kategoriler', [
      {'ad': 'Atıştırmalık', 'sira': 9, 'last_updated': DateTime(2026, 11, 1).toIso8601String()},
    ]);
    final kat = (await db.query('kategoriler', where: 'ad = ?', whereArgs: ['Atıştırmalık'])).single;
    expect(kat['sira'], 1);
  });

  test('yerelde olmayan kategori normal eklenir', () async {
    await Veritabani().supaKayitlariEkle('kategoriler', [
      {'ad': 'Yeni Kategori', 'last_updated': DateTime(2026, 11, 9).toIso8601String()},
    ]);
    expect(await db.query('kategoriler', where: 'ad = ?', whereArgs: ['Yeni Kategori']), hasLength(1));
  });
}
