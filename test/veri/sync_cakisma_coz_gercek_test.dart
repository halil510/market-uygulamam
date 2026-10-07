// test/veri/sync_cakisma_coz_gercek_test.dart
//
// Bulut Veri Güvenliği Raporu (2026-10-07), Bulgu 12 — gerçek
// SyncCakismaDeposu ile: bulutta olup yerelde olmayan sütun çözümü
// düşürmemeli; gelen kayıt yoksa "çözüldü" diye yalan söylenmemeli.
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/depolar/sync_cakisma_deposu.dart';
import 'package:market_plus/modeller/sync_cakisma_model.dart';
import 'package:market_plus/servisler/bulut/bulut_manager.dart';
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
    await Future<void>.delayed(const Duration(milliseconds: 200));
    BulutManager().testIcinSifirla();
    Veritabani.testVeritabani = null;
    await db.close();
  });

  Future<int> cakisma({Map<String, dynamic>? gelen, Map<String, dynamic>? yerel}) =>
      db.insert('sync_cakismalar', SyncCakismaModel(
        tablo: 'kasa_hareketleri', kayitGlobalId: 'kasa-9',
        alanFarklari: {'tutar': {'yerel': 100, 'gelen': 250}},
        gelenKayit: gelen, yerelKayit: yerel, tarih: DateTime.now(),
      ).toMap()..remove('id'));

  Future<Map<String, Object?>> hareket() async =>
      (await db.query('kasa_hareketleri', where: "global_id = 'kasa-9'")).first;

  Future<int?> cozuldu(int id) async =>
      (await db.query('sync_cakismalar', where: 'id = ?', whereArgs: [id])).first['cozuldu'] as int?;

  setUp(() async {
    await db.insert('kasa_hareketleri',
        {'global_id': 'kasa-9', 'hareket_tipi': 'Satış', 'tutar': 100});
  });

  test('gelen: bulutta olup yerelde olmayan sütun çözümü düşürmez', () async {
    final id = await cakisma(gelen: {
      'global_id': 'kasa-9', 'tutar': 250, 'sunucu_zamani': '2026-10-07T10:00:00Z', 'id': 77,
    });
    await SyncCakismaDeposu().gelenIleCoz(id, kullanici: 'test');
    expect((await hareket())['tutar'], 250);
    expect(await cozuldu(id), 1);
  });

  test('gelen kayıt yoksa hata verir, çakışma açık kalır', () async {
    final id = await cakisma();
    await expectLater(SyncCakismaDeposu().gelenIleCoz(id, kullanici: 'test'), throwsStateError);
    expect(await cozuldu(id), isNot(1));
    expect((await hareket())['tutar'], 100);
  });

  test('yerel: yabancı sütunlu eski kayıt da geri yazılabilir', () async {
    await db.update('kasa_hareketleri', {'tutar': 250}, where: "global_id = 'kasa-9'");
    final id = await cakisma(yerel: {'global_id': 'kasa-9', 'tutar': 100, 'sunucu_zamani': 'x'});
    await SyncCakismaDeposu().yerelIleCoz(id, kullanici: 'test');
    expect((await hareket())['tutar'], 100);
    expect(await cozuldu(id), 1);
  });
}
