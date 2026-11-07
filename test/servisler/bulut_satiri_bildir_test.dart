// test/servisler/bulut_satiri_bildir_test.dart
//
// BulutManager.satiriBildir — "satırı id ile taze oku → buluta bildir"
// üçlemesinin tek kaynağı (CLAUDE.md §4.1). 140 çağrı yeri buna geçti;
// davranışın eski elle yazılmış desenle birebir aynı kaldığını korur:
//  - Satır DB'den TAZE okunur (bellekteki eski değer değil),
//  - id null / satır yok → kuyruğa hiçbir şey yazılmaz.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/servisler/bulut/bulut_manager.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

Future<List<Map<String, dynamic>>> _kuyruk(Database db, String tablo) =>
    db.query('sync_queue', where: 'tablo_adi = ?', whereArgs: [tablo]);

/// upsert() kuyruğa yazmayı arka planda yapar — [beklenen] satır görünene
/// (ya da süre dolana) kadar bekler.
Future<List<Map<String, dynamic>>> _kuyrukBekle(Database db, String tablo,
    {required int beklenen}) async {
  var satirlar = <Map<String, dynamic>>[];
  for (var i = 0; i < 40; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 25));
    satirlar = await _kuyruk(db, tablo);
    if (satirlar.length >= beklenen && beklenen > 0) break;
  }
  return satirlar;
}

void main() {
  late Database db;
  late int urunId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await TestVeritabani.olustur();
    Veritabani.testVeritabani = db;
    urunId = await TestVeritabani.ornekUrunEkle(db);
    // Kurulumdan kalan kuyruk satırları testleri karıştırmasın.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await db.delete('sync_queue');
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    BulutManager().testIcinSifirla();
    Veritabani.testVeritabani = null;
    await db.close();
  });

  test('satır DB\'den taze okunup kuyruğa yazılır', () async {
    await db.update('urunler', {'urun_adi': 'Taze Ad'},
        where: 'id = ?', whereArgs: [urunId]);

    await BulutManager().satiriBildir(db, 'urunler', urunId);

    final kuyruk = await _kuyrukBekle(db, 'urunler', beklenen: 1);
    expect(kuyruk, hasLength(1));
    final veri = jsonDecode(kuyruk.first['veri_json'] as String) as Map;
    expect(veri['urun_adi'], 'Taze Ad');
    expect(kuyruk.first['islem_tipi'], 'UPSERT');
  });

  test('id null ise hiçbir şey bildirilmez', () async {
    await BulutManager().satiriBildir(db, 'urunler', null);
    expect(await _kuyrukBekle(db, 'urunler', beklenen: 0), isEmpty);
  });

  test('olmayan satır için hiçbir şey bildirilmez', () async {
    await BulutManager().satiriBildir(db, 'urunler', 999999);
    expect(await _kuyrukBekle(db, 'urunler', beklenen: 0), isEmpty);
  });
}
