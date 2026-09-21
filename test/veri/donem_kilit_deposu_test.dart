// test/veri/donem_kilit_deposu_test.dart
//
// Yıl Sonu Devir — çoklu cihaz kilidi (2026-09-21, FAZ 4). DonemKilit
// Deposu Veritabani() singleton'ı üzerinden çalıştığı için (diğer depo
// testlerinde olduğu gibi) burada AYNI kilit algoritması gerçek şema
// üzerinde bir in-memory veritabanında doğrudan doğrulanıyor.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import '../helper/test_initializer.dart';

/// DonemKilitDeposu.kilitAl() ile BİREBİR AYNI algoritma.
Future<bool> _kilitAl(Database db,
    {required int donemId,
    required int subeId,
    required String cihazId,
    Duration ttl = const Duration(minutes: 5),
    DateTime? simdi}) async {
  final now = simdi ?? DateTime.now();
  return db.transaction((txn) async {
    final mevcut = await txn.query('donem_kilit',
        where: 'donem_id = ? AND sube_id = ?', whereArgs: [donemId, subeId], limit: 1);
    if (mevcut.isEmpty) {
      await txn.insert('donem_kilit', {
        'donem_id': donemId, 'sube_id': subeId, 'cihaz_id': cihazId,
        'kilit_zamani': now.toIso8601String(), 'son_yenileme': now.toIso8601String(),
      });
      return true;
    }
    final satir = mevcut.first;
    final sahipCihaz = satir['cihaz_id'] as String?;
    final sonYenileme = DateTime.tryParse(satir['son_yenileme'] as String? ?? '');
    final taze = sonYenileme != null && now.difference(sonYenileme) < ttl;

    if (sahipCihaz == cihazId) {
      await txn.update('donem_kilit', {'son_yenileme': now.toIso8601String()},
          where: 'id = ?', whereArgs: [satir['id']]);
      return true;
    }
    if (taze) return false;
    await txn.update(
        'donem_kilit',
        {'cihaz_id': cihazId, 'kilit_zamani': now.toIso8601String(), 'son_yenileme': now.toIso8601String()},
        where: 'id = ?', whereArgs: [satir['id']]);
    return true;
  });
}

Future<void> _kilitBirak(Database db,
    {required int donemId, required int subeId, required String cihazId}) async {
  await db.delete('donem_kilit',
      where: 'donem_id = ? AND sube_id = ? AND cihaz_id = ?',
      whereArgs: [donemId, subeId, cihazId]);
}

void main() {
  late Database db;
  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  group('DonemKilitDeposu.kilitAl', () {
    test('hiç kilit yoksa yeni kilit alınır (true)', () async {
      final alindi =
          await _kilitAl(db, donemId: 1, subeId: 1, cihazId: 'cihaz-A');
      expect(alindi, isTrue);
      final rows = await db.query('donem_kilit');
      expect(rows, hasLength(1));
      expect(rows.first['cihaz_id'], 'cihaz-A');
    });

    test(
        'BAŞKA bir cihaz taze bir kilide sahipse ikinci cihaz REDDEDİLİR (false)',
        () async {
      final simdi = DateTime(2026, 9, 21, 10, 0);
      await _kilitAl(db, donemId: 1, subeId: 1, cihazId: 'cihaz-A', simdi: simdi);
      final ikinciCihaz = await _kilitAl(db,
          donemId: 1, subeId: 1, cihazId: 'cihaz-B',
          simdi: simdi.add(const Duration(seconds: 30)));
      expect(ikinciCihaz, isFalse);
    });

    test('AYNI cihaz kilidi tekrar alabilir (resumable devir, idempotent)',
        () async {
      final simdi = DateTime(2026, 9, 21, 10, 0);
      await _kilitAl(db, donemId: 1, subeId: 1, cihazId: 'cihaz-A', simdi: simdi);
      final tekrar = await _kilitAl(db,
          donemId: 1, subeId: 1, cihazId: 'cihaz-A',
          simdi: simdi.add(const Duration(minutes: 1)));
      expect(tekrar, isTrue);
      final rows = await db.query('donem_kilit');
      expect(rows, hasLength(1)); // ikinci satır oluşmadı
    });

    test(
        'TTL aşılmış (stale) kilit BAŞKA bir cihaz tarafından DEVRALINABİLİR',
        () async {
      final simdi = DateTime(2026, 9, 21, 10, 0);
      await _kilitAl(db, donemId: 1, subeId: 1, cihazId: 'cihaz-A', simdi: simdi);
      // 10 dakika sonra (varsayılan TTL 5 dk) — cihaz-A çökmüş kabul edilir.
      final devralan = await _kilitAl(db,
          donemId: 1, subeId: 1, cihazId: 'cihaz-B',
          simdi: simdi.add(const Duration(minutes: 10)));
      expect(devralan, isTrue);
      final rows = await db.query('donem_kilit');
      expect(rows, hasLength(1));
      expect(rows.first['cihaz_id'], 'cihaz-B');
    });

    test('farklı şubeler bağımsız kilitlenir (biri diğerini engellemez)',
        () async {
      final alinan1 = await _kilitAl(db, donemId: 1, subeId: 1, cihazId: 'cihaz-A');
      final alinan2 = await _kilitAl(db, donemId: 1, subeId: 2, cihazId: 'cihaz-B');
      expect(alinan1, isTrue);
      expect(alinan2, isTrue);
    });
  });

  group('DonemKilitDeposu.kilitBirak', () {
    test('kilit bırakılınca aynı dönem/şube için BAŞKA cihaz kilit alabilir',
        () async {
      await _kilitAl(db, donemId: 1, subeId: 1, cihazId: 'cihaz-A');
      await _kilitBirak(db, donemId: 1, subeId: 1, cihazId: 'cihaz-A');

      final rows = await db.query('donem_kilit');
      expect(rows, isEmpty);

      final yeniCihaz = await _kilitAl(db, donemId: 1, subeId: 1, cihazId: 'cihaz-B');
      expect(yeniCihaz, isTrue);
    });

    test('başka bir cihazın kilidi yanlışlıkla bırakılamaz', () async {
      await _kilitAl(db, donemId: 1, subeId: 1, cihazId: 'cihaz-A');
      await _kilitBirak(db, donemId: 1, subeId: 1, cihazId: 'cihaz-YANLIS');

      final rows = await db.query('donem_kilit');
      expect(rows, hasLength(1)); // hâlâ cihaz-A'da duruyor
      expect(rows.first['cihaz_id'], 'cihaz-A');
    });
  });
}

