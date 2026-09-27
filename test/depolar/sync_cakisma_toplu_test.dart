// test/depolar/sync_cakisma_toplu_test.dart
//
// Sync Çakışmaları — toplu çözüm (benimkini / buluttakini / manuel).
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/depolar/sync_cakisma_deposu.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

Future<int> _cakisma(Database db, String gid, {required String yerelAd, required String gelenAd}) =>
    db.insert('sync_cakismalar', {
      'tablo': 'urunler',
      'kayit_global_id': gid,
      'alan_farklari': jsonEncode({'urun_adi': {'yerel': yerelAd, 'gelen': gelenAd}}),
      'yerel_kayit': jsonEncode({'global_id': gid, 'urun_adi': yerelAd}),
      'gelen_kayit': jsonEncode({'global_id': gid, 'urun_adi': gelenAd}),
      'tarih': DateTime.now().toIso8601String(),
      'cozuldu': 0,
    });

Future<String> _ad(Database db, String gid) async =>
    (await db.query('urunler', where: 'global_id = ?', whereArgs: [gid])).first['urun_adi'] as String;

void main() {
  late Database db;
  late List<int> idler;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await TestVeritabani.olustur();
    Veritabani.testVeritabani = db;
    for (final g in ['u1', 'u2']) {
      final id = await TestVeritabani.ornekUrunEkle(db, urunAdi: 'Ara-$g', barkod: 'B-$g');
      await db.update('urunler', {'global_id': g}, where: 'id = ?', whereArgs: [id]);
    }
    idler = [
      await _cakisma(db, 'u1', yerelAd: 'Yerel-1', gelenAd: 'Bulut-1'),
      await _cakisma(db, 'u2', yerelAd: 'Yerel-2', gelenAd: 'Bulut-2'),
    ];
  });
  tearDown(() async {
    Veritabani.testVeritabani = null;
    await db.close();
  });

  test('toplu "buluttakini kullan" hepsine gelen değeri yazar ve kapatır', () async {
    expect(await SyncCakismaDeposu().topluCoz(idler, tip: 'gelen', kullanici: 't'), 2);
    expect(await _ad(db, 'u1'), 'Bulut-1');
    expect(await _ad(db, 'u2'), 'Bulut-2');
    expect(await SyncCakismaDeposu().cozulmemisSayisi(), 0);
  });

  test('toplu "benimkini kullan" hepsine yerel değeri yazar', () async {
    expect(await SyncCakismaDeposu().topluCoz(idler, tip: 'yerel', kullanici: 't'), 2);
    expect(await _ad(db, 'u1'), 'Yerel-1');
    expect(await _ad(db, 'u2'), 'Yerel-2');
    expect(await SyncCakismaDeposu().cozulmemisSayisi(), 0);
  });

  test('toplu "manuel" veriye dokunmadan kapatır', () async {
    expect(await SyncCakismaDeposu().topluCoz(idler, tip: 'manuel', kullanici: 't'), 2);
    expect(await _ad(db, 'u1'), 'Ara-u1');
    expect(await SyncCakismaDeposu().cozulmemisSayisi(), 0);
  });
}
