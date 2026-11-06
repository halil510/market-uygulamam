// test/depolar/cari_bakiye_tazele_test.dart
//
// CariDeposu.bakiyeTazeleTxn — cari bakiyesinin TEK hesaplama yeri
// (CLAUDE.md §4.2, 2026-11-06; önceden 17 kopya SQL).
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/depolar/cari_deposu.dart';
import '../helper/test_initializer.dart';

void main() {
  late Database db;
  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  Future<Map<String, Object?>> cari(int id) async =>
      (await db.query('cari', where: 'id = ?', whereArgs: [id])).first;

  Future<void> hareket(int cariId, double borc, double alacak, {int silindi = 0}) =>
      db.insert('cari_hareket', {
        'cari_id': cariId, 'borc': borc, 'alacak': alacak, 'is_deleted': silindi,
        'fis_tipi': 'Test', 'tarih': DateTime.now().toIso8601String(),
      });

  test('bakiye = silinmemiş (borç − alacak), kuruşa yuvarlanmış', () async {
    final id = await TestVeritabani.ornekCariEkle(db);
    await hareket(id, 0.1, 0);
    await hareket(id, 0.2, 0);
    await hareket(id, 500, 0, silindi: 1);
    await hareket(id, 0, 0.05);
    await db.update('cari', {'bakiye': 999}, where: 'id = ?', whereArgs: [id]);

    await CariDeposu.bakiyeTazeleTxn(db, id);

    expect((await cari(id))['bakiye'], 0.25);
  });

  test('hareketi olmayan carinin bakiyesi 0 olur', () async {
    final id = await TestVeritabani.ornekCariEkle(db);
    await db.update('cari', {'bakiye': 42}, where: 'id = ?', whereArgs: [id]);
    await CariDeposu.bakiyeTazeleTxn(db, id);
    expect((await cari(id))['bakiye'], 0);
  });

  test('lastUpdated verilirse yazılır, verilmezse dokunulmaz', () async {
    final id = await TestVeritabani.ornekCariEkle(db);
    await db.update('cari', {'last_updated': 'ESKI'}, where: 'id = ?', whereArgs: [id]);

    await CariDeposu.bakiyeTazeleTxn(db, id);
    expect((await cari(id))['last_updated'], 'ESKI');

    await CariDeposu.bakiyeTazeleTxn(db, id, lastUpdated: '2026-11-06T10:00:00');
    expect((await cari(id))['last_updated'], '2026-11-06T10:00:00');
  });

  test('transaction içinde çalışır; null id hiçbir şey yapmaz', () async {
    final id = await TestVeritabani.ornekCariEkle(db);
    await db.transaction((txn) async {
      await txn.insert('cari_hareket', {
        'cari_id': id, 'borc': 70, 'alacak': 20, 'is_deleted': 0,
        'fis_tipi': 'Test', 'tarih': DateTime.now().toIso8601String(),
      });
      await CariDeposu.bakiyeTazeleTxn(txn, id);
      await CariDeposu.bakiyeTazeleTxn(txn, null);
    });
    expect((await cari(id))['bakiye'], 50);
  });
}
