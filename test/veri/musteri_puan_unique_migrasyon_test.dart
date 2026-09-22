// test/veri/musteri_puan_unique_migrasyon_test.dart
//
// MigrasyonYonetici._v76denV77ye()'nin gerçek testi: musteri_puan.cari_id
// üzerinde UNIQUE index kuruluyor (PuanServisi.puanEkle()'nin ON
// CONFLICT(cari_id) hedefinin eksikliği düzeltiliyor) — ama önce, aynı
// cari_id'ye ait BİRDEN FAZLA satır varsa (gerçekte hiç olmaması gereken
// ama savunmacı davranılan bir durum) bunlar tek satıra birleştiriliyor.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:market_plus/veri/database/migrasyon_yonetici.dart';

Future<Database> _v76OncesiDbOlustur() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final db = await openDatabase(inMemoryDatabasePath, version: 1);
  await db.execute('CREATE TABLE cari (id INTEGER PRIMARY KEY AUTOINCREMENT, unvan TEXT)');
  // v76 öncesi gerçek şema: cari_id üzerinde HİÇBİR UNIQUE/PK kısıtı yok.
  await db.execute('''
    CREATE TABLE musteri_puan (
      id INTEGER PRIMARY KEY AUTOINCREMENT, global_id TEXT UNIQUE,
      cari_id INTEGER, toplam_puan REAL NOT NULL DEFAULT 0,
      kullanilan REAL NOT NULL DEFAULT 0, son_islem DATETIME, last_updated DATETIME
    )
  ''');
  return db;
}

void main() {
  late Database db;
  tearDown(() => db.close());

  test('migrasyon sonrası ON CONFLICT(cari_id) artık SQL hatası vermeden çalışır', () async {
    db = await _v76OncesiDbOlustur();
    final cariId = await db.insert('cari', {'unvan': 'Test'});

    await MigrasyonYonetici.guncelle(db, 76, 77);

    // Artık bu upsert (PuanServisi.puanEkle'nin BİREBİR aynısı) hata
    // fırlatmadan çalışmalı.
    await db.rawInsert('''
      INSERT INTO musteri_puan(cari_id, toplam_puan, kullanilan, son_islem)
      VALUES(?, ?, 0, datetime('now'))
      ON CONFLICT(cari_id) DO UPDATE SET toplam_puan = toplam_puan + excluded.toplam_puan
    ''', [cariId, 100.0]);
    await db.rawInsert('''
      INSERT INTO musteri_puan(cari_id, toplam_puan, kullanilan, son_islem)
      VALUES(?, ?, 0, datetime('now'))
      ON CONFLICT(cari_id) DO UPDATE SET toplam_puan = toplam_puan + excluded.toplam_puan
    ''', [cariId, 50.0]);

    final satirlar = await db.query('musteri_puan', where: 'cari_id = ?', whereArgs: [cariId]);
    expect(satirlar, hasLength(1), reason: 'ON CONFLICT sayesinde tek satırda BİRİKMELİ, çoğalmamalı');
    expect((satirlar.first['toplam_puan'] as num).toDouble(), equals(150.0));
  });

  test('migrasyon ÖNCESİNDEN kalmış mükerrer cari_id satırları tek satıra birleştirilir', () async {
    db = await _v76OncesiDbOlustur();
    final cariId = await db.insert('cari', {'unvan': 'Test'});
    // Gerçek üretimde asla olmaması gereken ama teorik olarak mümkün
    // (ör. bozuk bir manuel/senkron ekleme) mükerrer satır senaryosu.
    await db.insert('musteri_puan', {'cari_id': cariId, 'toplam_puan': 300.0, 'kullanilan': 50.0});
    await db.insert('musteri_puan', {'cari_id': cariId, 'toplam_puan': 100.0, 'kullanilan': 20.0});

    await MigrasyonYonetici.guncelle(db, 76, 77);

    final satirlar = await db.query('musteri_puan', where: 'cari_id = ?', whereArgs: [cariId]);
    expect(satirlar, hasLength(1), reason: 'Mükerrer satırlar birleştirilmeli');
    expect((satirlar.first['toplam_puan'] as num).toDouble(), equals(400.0),
        reason: 'Kazanılan puanlar TOPLANMALI, kaybolmamalı');
    expect((satirlar.first['kullanilan'] as num).toDouble(), equals(70.0));
  });
}
