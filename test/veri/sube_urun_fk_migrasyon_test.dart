// test/veri/sube_urun_fk_migrasyon_test.dart
//
// Kullanıcı bulgusu ("tam ERP oldu mu, başka hata var mı" denetimi,
// 2026-09-22): 'sube_urun' (şube bazlı stok payı) tablosunda hiç
// FOREIGN KEY yoktu. MigrasyonYonetici._v73denV74e() bunu standart
// SQLite "yeniden oluştur" deseniyle (rename → FK'lı yeni tablo →
// sadece geçerli satırları kopyala → eskiyi sil) düzeltiyor.
//
// Bu test GERÇEK MigrasyonYonetici.guncelle(db, 73, 74) çağrısını,
// elle kurulmuş bir "v73 öncesi" (FK'sız) sube_urun tablosuna karşı
// çalıştırır — hem geçerli hem YETİM (var olmayan ürüne/şubeye işaret
// eden) satır içeren gerçekçi bir senaryoyla.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:market_plus/veri/database/migrasyon_yonetici.dart';

Future<Database> _v73OncesiDbOlustur() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final db = await openDatabase(inMemoryDatabasePath, version: 1);

  // FK hedefleri — testin amacına yetecek minimal kolonlarla.
  await db.execute('CREATE TABLE urunler (id INTEGER PRIMARY KEY AUTOINCREMENT, urun_adi TEXT)');
  await db.execute('CREATE TABLE subeler (id INTEGER PRIMARY KEY AUTOINCREMENT, sube_adi TEXT)');

  // v73 ÖNCESİ gerçek şema: composite PK dışında hiçbir FK yok.
  await db.execute('''
    CREATE TABLE sube_urun (
      global_id TEXT,
      urun_id INTEGER NOT NULL, sube_id INTEGER NOT NULL,
      stok REAL NOT NULL DEFAULT 0, rezerve_stok REAL NOT NULL DEFAULT 0,
      kritik_stok REAL DEFAULT 0, satis_fiyati REAL, alis_fiyati REAL,
      raf_kodu TEXT, son_guncelleme DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      last_updated DATETIME,
      PRIMARY KEY (urun_id, sube_id)
    )
  ''');
  return db;
}

void main() {
  late Database db;
  tearDown(() => db.close());

  test('sube_urun FK migrasyonu (v73→v74) — geçerli satır korunur, yetim satır sessizce atlanır, FK aktif olur',
      () async {
    db = await _v73OncesiDbOlustur();

    final urunId = await db.insert('urunler', {'urun_adi': 'Gerçek Ürün'});
    final subeId = await db.insert('subeler', {'sube_adi': 'Merkez'});

    // Geçerli satır — hem urun hem sube gerçekten var.
    await db.insert('sube_urun', {
      'global_id': 'g1', 'urun_id': urunId, 'sube_id': subeId,
      'stok': 42.0, 'raf_kodu': 'A-1',
    });
    // YETİM satır — urun_id 9999 hiç var olmayan bir ürüne işaret ediyor
    // (ör. üründen kalıntı, ya da bozuk bir senkron kaydı).
    await db.insert('sube_urun', {
      'global_id': 'g2', 'urun_id': 9999, 'sube_id': subeId, 'stok': 5.0,
    });

    await MigrasyonYonetici.guncelle(db, 73, 74);

    // 1) Geçerli satır aynen korundu.
    final satirlar = await db.query('sube_urun');
    expect(satirlar, hasLength(1),
        reason: 'Sadece hem ürünü hem şubesi var olan satır kalmalı, yetim satır atlanmalı');
    expect(satirlar.first['urun_id'], equals(urunId));
    expect((satirlar.first['stok'] as num).toDouble(), equals(42.0));
    expect(satirlar.first['raf_kodu'], equals('A-1'));

    // 2) FK artık gerçekten tanımlı.
    final fkListesi = await db.rawQuery("PRAGMA foreign_key_list('sube_urun')");
    expect(fkListesi.length, equals(2),
        reason: 'urun_id ve sube_id için birer FOREIGN KEY tanımlı olmalı');

    // 3) PRAGMA foreign_key_check hiçbir ihlal bulmamalı.
    await db.execute('PRAGMA foreign_keys = ON');
    final ihlaller = await db.rawQuery('PRAGMA foreign_key_check');
    expect(ihlaller, isEmpty);

    // 4) İndeksler hâlâ mevcut (performans regresyonu yok).
    final indeksler = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='sube_urun'");
    final indeksAdlari = indeksler.map((r) => r['name']).toSet();
    expect(indeksAdlari, containsAll(['idx_sube_urun_urun', 'idx_sube_urun_sube']));
  });

  test('migrasyon sonrası artık gerçek bir hard-delete otomatik CASCADE ile temizleniyor', () async {
    db = await _v73OncesiDbOlustur();
    final urunId = await db.insert('urunler', {'urun_adi': 'Silinecek Ürün'});
    final subeId = await db.insert('subeler', {'sube_adi': 'Merkez'});
    await db.insert('sube_urun', {'urun_id': urunId, 'sube_id': subeId, 'stok': 10.0});

    await MigrasyonYonetici.guncelle(db, 73, 74);
    await db.execute('PRAGMA foreign_keys = ON');

    await db.delete('urunler', where: 'id = ?', whereArgs: [urunId]);

    final kalanlar = await db.query('sube_urun', where: 'urun_id = ?', whereArgs: [urunId]);
    expect(kalanlar, isEmpty,
        reason: 'ON DELETE CASCADE artık ürün silinince ilişkili sube_urun satırını da temizlemeli');
  });
}
