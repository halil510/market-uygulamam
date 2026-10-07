// test/servisler/bulut_cekim_sutun_filtresi_test.dart
//
// Canlı bulgu (2026-10-08): supabase_tam_sema.sql Bölüm H bulut tablolarına
// sunucu_zamani ekleyince hiçbir cihaz buluttan kayıt alamadı — çekimdeki
// "yerelde olmayan sütunu at" filtresi bir tip hatası yüzünden HİÇ
// çalışmıyordu ve yazım "no such column" ile düşüyordu.
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/servisler/supabase_sync_servisi.dart';
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

  test('yerel sütun listesi gerçekten okunur (boş küme dönmez)', () async {
    final k = await SupabaseSyncServisi.yerelKolonlarTest(db, 'satislar');
    expect(k, containsAll(['id', 'global_id', 'fis_no']));
    expect(k, isNot(contains('sunucu_zamani')));
    final z = await SupabaseSyncServisi.yerelZorunluKolonlarTest(db, 'satis_kalem');
    expect(z, isNotEmpty);
  });

  test('ekleme: bulut fazlası sütun yazımı düşürmez', () async {
    await Veritabani().supaKayitlariEkle('kasa_hareketleri', [
      {'global_id': 'KH-SZ', 'hareket_tipi': 'Satış', 'tutar': 10,
        'sunucu_zamani': '2026-10-07T22:00:00+00:00'},
    ]);
    expect(await db.query('kasa_hareketleri', where: "global_id = 'KH-SZ'"), hasLength(1));
  });

  test('güncelleme: bulut fazlası sütun yazımı düşürmez', () async {
    await db.insert('kasa_hareketleri',
        {'global_id': 'KH-SZ2', 'hareket_tipi': 'Satış', 'tutar': 10,
          'last_updated': '2026-10-01T00:00:00Z'});
    await Veritabani().supaKayitlariGuncelle('kasa_hareketleri', [
      {'global_id': 'KH-SZ2', 'tutar': 20, 'last_updated': '2026-10-07T22:00:00Z',
        'sunucu_zamani': '2026-10-07T22:00:01+00:00'},
    ]);
    final r = (await db.query('kasa_hareketleri', where: "global_id = 'KH-SZ2'")).first;
    expect(r['tutar'], 20);
  });
}
