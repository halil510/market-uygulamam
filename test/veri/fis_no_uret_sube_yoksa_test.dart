// test/veri/fis_no_uret_sube_yoksa_test.dart
//
// Kullanıcı bulgusu (ekran görüntüsü, 2026-09-21): Hızlı Satış'tan
// normal VEYA cariye satış yapılırken
//   DatabaseException(FOREIGN KEY constraint failed (code 787
//   SQLITE_CONSTRAINT_FOREIGNKEY[787]))
//   sql 'INSERT INTO fis_seri(sube_id, fis_tipi, son_fis_no)
//   VALUES(?, ?, ?)' args [1, satis, 1]
// hatası alınıyordu — subeler tablosunda id=1'e sahip bir şube yokken
// fisNoUret() körü körüne sube_id=1 ile fis_seri'ye INSERT deniyordu,
// FK ihlaliyle patlayıp kullanıcıyı satış yapamaz hale getiriyordu.
//
// Veritabani.fisNoUret() Veritabani() singleton'ı üzerinden çalıştığı
// için (bkz. diğer depo testlerindeki AYNI gerekçe), burada onun YENİ
// eklenen _gecerliSubeIdGetir() + fis_seri mantığı BİREBİR AYNI sırayla
// gerçek şema üzerinde bir in-memory veritabanı içinde doğrudan
// çağrılıyor.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import '../helper/test_initializer.dart';

/// Veritabani._gecerliSubeIdGetir() ile BİREBİR AYNI mantık.
Future<int> _gecerliSubeIdGetir(Database db, int istenenSubeId) async {
  final istenen = await db.query('subeler',
      columns: ['id'], where: 'id = ?', whereArgs: [istenenSubeId], limit: 1);
  if (istenen.isNotEmpty) return istenenSubeId;

  final ilkSube =
      await db.query('subeler', columns: ['id'], orderBy: 'id', limit: 1);
  if (ilkSube.isNotEmpty) return ilkSube.first['id'] as int;

  final yeniId = await db.insert(
      'subeler', {'sube_kodu': 'MERKEZ', 'sube_adi': 'Merkez Şube'},
      conflictAlgorithm: ConflictAlgorithm.ignore);
  if (yeniId > 0) return yeniId;

  final tekrar =
      await db.query('subeler', columns: ['id'], orderBy: 'id', limit: 1);
  return tekrar.isNotEmpty ? tekrar.first['id'] as int : istenenSubeId;
}

/// Veritabani.fisNoUret() ile BİREBİR AYNI (sadece _fisSeriBulutlaUyumla/
/// _fisSeriBulutaPushla — ağ/best-effort yan etkiler — çıkarılmış) sıra.
Future<String> _fisNoUret(Database db, String tip, {int subeId = 1}) async {
  final gecerliSubeId = await _gecerliSubeIdGetir(db, subeId);
  late final int yeniNo;
  return await db.transaction((txn) async {
    final result = await txn.rawQuery(
      'SELECT son_fis_no FROM fis_seri WHERE sube_id = ? AND fis_tipi = ?',
      [gecerliSubeId, tip],
    );
    final sonNo = result.isNotEmpty ? (result.first['son_fis_no'] as int) : 0;
    yeniNo = sonNo + 1;
    if (result.isEmpty) {
      await txn.rawInsert(
        'INSERT INTO fis_seri(sube_id, fis_tipi, son_fis_no) VALUES(?, ?, ?)',
        [gecerliSubeId, tip, yeniNo],
      );
    } else {
      await txn.rawUpdate(
        'UPDATE fis_seri SET son_fis_no = ? WHERE sube_id = ? AND fis_tipi = ?',
        [yeniNo, gecerliSubeId, tip],
      );
    }
    final prefix = tip == 'satis' ? 'MKP' : tip == 'cari_satis' ? 'CRI' : 'XXX';
    return '$prefix${DateTime.now().year}${yeniNo.toString().padLeft(9, '0')}';
  });
}

void main() {
  late Database db;
  setUp(() async {
    db = await TestVeritabani.olustur();
    // Üretimde PRAGMA foreign_keys = ON (bkz. Veritabani._onConfigure) —
    // gerçek FK ihlalini doğrulayabilmek için test db'sinde de açılıyor.
    await db.execute('PRAGMA foreign_keys = ON');
  });
  tearDown(() => db.close());

  test(
      'subeler tablosu TAMAMEN BOŞKEN fisNoUret patlamaz — kendi kendini '
      'onarıp bir Merkez Şube oluşturur (önceden FK[787] fırlatıyordu)',
      () async {
    final subeSayisi =
        Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM subeler'));
    expect(subeSayisi, 0, reason: 'TestVeritabani seed verisi eklemiyor');

    final fisNo = await _fisNoUret(db, 'satis', subeId: 1);
    expect(fisNo, startsWith('MKP'));

    final subeler = await db.query('subeler');
    expect(subeler.length, 1,
        reason: 'subeler boşken kendi kendini onarıp bir şube oluşturmalı');
    expect(subeler.first['sube_kodu'], 'MERKEZ');
  });

  test('cari_satis tipi de aynı şekilde kendi kendini onarır', () async {
    final fisNo = await _fisNoUret(db, 'cari_satis', subeId: 1);
    expect(fisNo, startsWith('CRI'));
  });

  test('subeler tablosunda İSTENEN id yok ama BAŞKA bir şube VARSA, '
      'o şube kullanılır (yeni bir Merkez Şube DUPLICATE EDİLMEZ)', () async {
    final digerId = await db.insert(
        'subeler', {'sube_kodu': 'SB2', 'sube_adi': 'İkinci Şube'});

    await _fisNoUret(db, 'satis', subeId: 999); // var olmayan bir id istendi

    final fisSeriSatirlari = await db.query('fis_seri');
    expect(fisSeriSatirlari.length, 1);
    expect(fisSeriSatirlari.first['sube_id'], digerId);

    final subeSayisi =
        Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM subeler'));
    expect(subeSayisi, 1, reason: 'yeni bir şube OLUŞTURULMAMALI, var olan kullanılmalı');
  });

  test('şube gerçekten VARSA (normal/önceki davranış) hiçbir şey değişmez',
      () async {
    await db.insert('subeler', {'id': 1, 'sube_kodu': 'MERKEZ', 'sube_adi': 'Merkez Şube'});
    final fisNo1 = await _fisNoUret(db, 'satis', subeId: 1);
    final fisNo2 = await _fisNoUret(db, 'satis', subeId: 1);
    expect(fisNo1, isNot(fisNo2));

    final subeSayisi =
        Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM subeler'));
    expect(subeSayisi, 1);
  });
}
