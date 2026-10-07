// test/veri/supa_kayit_ekle_id_koru_test.dart
//
// Bulut Veri Güvenliği Raporu (2026-10-07), Bulgu 13 — "yeni" sanılan
// kayıt yerelde zaten varsa REPLACE onu silip YENİ id ile ekliyordu;
// çocuk kayıtlar eski id'de yetim kalıyordu. Artık yerel id korunur.
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import 'package:sqflite/sqflite.dart';
import '../helper/test_initializer.dart';

void main() {
  late Database db;

  setUp(() async {
    db = await TestVeritabani.olustur();
    Veritabani.testVeritabani = db;
  });
  tearDown(() async {
    Veritabani.testVeritabani = null;
    await db.close();
  });

  test('aynı global_id yerelde varsa id korunarak güncellenir', () async {
    final id = await db.insert('kasa_hareketleri',
        {'global_id': 'KH-1', 'hareket_tipi': 'Satış', 'tutar': 100});
    await Veritabani().supaKayitlariEkle('kasa_hareketleri', [
      {'global_id': 'KH-1', 'hareket_tipi': 'Satış', 'tutar': 150,
        'last_updated': '2026-10-07T10:00:00Z'},
    ]);
    final satirlar = await db.query('kasa_hareketleri', where: "global_id = 'KH-1'");
    expect(satirlar, hasLength(1));
    expect(satirlar.first['id'], id, reason: 'yerel id değişmemeli');
    expect(satirlar.first['tutar'], 150);
  });

  test('gerçekten yeni kayıt eklenir', () async {
    await Veritabani().supaKayitlariEkle('kasa_hareketleri', [
      {'global_id': 'KH-2', 'hareket_tipi': 'Satış', 'tutar': 75},
    ]);
    expect(await db.query('kasa_hareketleri', where: "global_id = 'KH-2'"), hasLength(1));
  });
}
