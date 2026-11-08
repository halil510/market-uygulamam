// test/unit/tarih_aralik_sql_test.dart
//
// TarihUtils.aralikSql / sonrasiSql / oncesiSql — rapor tarih koşulunun
// tek biçimi (CLAUDE.md §4.6).
//
// Faz D (2026-11-08): `datetime(tarih) BETWEEN …` tek başına index
// kullanamıyordu (sütun fonksiyona sarılınca SQLite tüm tabloyu tarar).
// Koşulun ÖNÜNE, ham sütun üzerinde gün payı bırakan bir ön süzgeç
// eklendi; asıl `datetime()` koşulu AYNEN duruyor. Aşağıdaki testler
// (1) eski koşulun SQL'de birebir korunduğunu, (2) farklı biçimlerde
// yazılmış tarihlerle eski/yeni koşulun AYNI satırları döndüğünü ve
// (3) satislar sorgusunun artık index ile arandığını doğrular.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/cekirdek/utils/tarih_utils.dart';
import '../helper/test_initializer.dart';

const _eskiAralik = 'datetime(tarih) BETWEEN datetime(?) AND datetime(?)';

void main() {
  test('üretilen SQL eski koşulu birebir içerir, önüne gün paylı ön süzgeç ekler', () {
    final sql = TarihUtils.aralikSql(
        's.tarih', DateTime(2026, 11, 6), DateTime(2026, 11, 6, 23, 59, 59));
    expect(sql, contains('datetime(s.tarih) BETWEEN datetime(?) AND datetime(?)'));
    expect(sql, contains("s.tarih >= '2026-11-05'"));
    expect(sql, contains("s.tarih < '2026-11-08'"));
    expect('?'.allMatches(sql).length, 2, reason: 'parametre sayısı değişmemeli');

    // Ay/yıl sınırı: takvim aritmetiği doğru kayar.
    final yilBasi = TarihUtils.aralikSql('tarih', DateTime(2026, 1, 1), DateTime(2026, 12, 31));
    expect(yilBasi, contains("tarih >= '2025-12-31'"));
    expect(yilBasi, contains("tarih < '2027-01-02'"));

    expect(TarihUtils.sonrasiSql('tarih', null), 'datetime(tarih) >= datetime(?)');
    expect(TarihUtils.oncesiSql('tarih', null), 'datetime(tarih) <= datetime(?)');
  });

  group('ön süzgeç sonucu değiştirmez (eski koşulla aynı satırlar)', () {
    late Database db;
    setUp(() async => db = await TestVeritabani.olustur());
    tearDown(() => db.close());

    // Yerelde gerçekten görülen biçimler: Dart'ın yerel ISO'su ('T'),
    // SQLite CURRENT_TIMESTAMP (boşluklu), buluttan dönen TIMESTAMPTZ
    // (+00:00 / Z), yalnız tarih, mikro saniyeli ve bozuk metin.
    const ornekler = <String?>[
      '2026-11-05T23:59:59.999999',
      '2026-11-06T00:00:00.000',
      '2026-11-06T00:30:00.000',
      '2026-11-06 12:00:00',
      '2026-11-06T23:59:59.000',
      '2026-11-06T23:59:59.999',
      '2026-11-07T00:00:00.000',
      '2026-11-07T00:00:01.000',
      '2026-11-06T22:00:00+00:00',
      '2026-11-06T22:00:00Z',
      '2026-11-06T22:00:00.123+00:00',
      '2026-11-07T01:00:00+03:00', // datetime() → 2026-11-06 22:00:00
      '2026-11-05T22:00:00-03:00', // datetime() → 2026-11-06 01:00:00
      '2026-11-06',
      '2026-11-07',
      '2025-11-06T10:00:00.000',
      '2026-12-01T10:00:00.000',
      'bozuk',
      '06.11.2026',
    ];

    setUp(() async {
      for (final t in ornekler) {
        await db.insert('kasa_hareketleri', {'hareket_tipi': 'Satış', 'tutar': 1, 'tarih': t});
      }
    });

    Future<List<int>> idler(String kosul, List<Object?> args) async {
      final rows = await db.rawQuery(
          'SELECT id FROM kasa_hareketleri WHERE $kosul ORDER BY id', args);
      return [for (final r in rows) r['id'] as int];
    }

    final araliklar = <(DateTime, DateTime)>[
      (DateTime(2026, 11, 6), DateTime(2026, 11, 6, 23, 59, 59, 999)),
      (DateTime(2026, 11, 6), DateTime(2026, 11, 6, 23, 59, 59)),
      (DateTime(2026, 11, 6, 12), DateTime(2026, 11, 7)),
      (DateTime(2026, 11, 1), DateTime(2026, 11, 30, 23, 59, 59)),
      (DateTime(2026, 1, 1), DateTime(2026, 12, 31, 23, 59, 59)),
      (DateTime(2026, 11, 7), DateTime(2026, 11, 6)), // ters aralık → boş
      (DateTime(2026, 11, 6, 22), DateTime(2026, 11, 6, 22)),
    ];

    test('aralikSql', () async {
      for (final (bas, bit) in araliklar) {
        final args = [bas.toIso8601String(), bit.toIso8601String()];
        expect(await idler(TarihUtils.aralikSql('tarih', bas, bit), args),
            await idler(_eskiAralik, args),
            reason: '$bas – $bit');
      }
    });

    test('sonrasiSql / oncesiSql', () async {
      for (final (bas, bit) in araliklar) {
        final b = [bas.toIso8601String()];
        expect(await idler(TarihUtils.sonrasiSql('tarih', bas), b),
            await idler('datetime(tarih) >= datetime(?)', b),
            reason: '>= $bas');
        final e = [bit.toIso8601String()];
        expect(await idler(TarihUtils.oncesiSql('tarih', bit), e),
            await idler('datetime(tarih) <= datetime(?)', e),
            reason: '<= $bit');
      }
    });

    test('gece 00:30 ve 23:59 kaydı o günün raporunda, ertesi gün 00:00:01 dışında', () async {
      final bas = DateTime(2026, 11, 6);
      final bit = DateTime(2026, 11, 6, 23, 59, 59, 999);
      final rows = await db.rawQuery(
          'SELECT tarih FROM kasa_hareketleri WHERE ${TarihUtils.aralikSql('tarih', bas, bit)}',
          [bas.toIso8601String(), bit.toIso8601String()]);
      final tarihler = rows.map((r) => r['tarih']).toSet();
      expect(tarihler, contains('2026-11-06T00:30:00.000'));
      expect(tarihler, contains('2026-11-06T23:59:59.999'));
      expect(tarihler, isNot(contains('2026-11-07T00:00:01.000')));
      expect(tarihler, isNot(contains('2026-11-05T23:59:59.999999')));
    });
  });

  group('index kullanımı (EXPLAIN QUERY PLAN)', () {
    late Database db;
    setUp(() async => db = await TestVeritabani.olustur());
    tearDown(() => db.close());

    Future<String> plan(String sql, List<Object?> args) async {
      final rows = await db.rawQuery('EXPLAIN QUERY PLAN $sql', args);
      return rows.map((r) => r['detail']).join(' | ');
    }

    final bas = DateTime(2026, 11, 6);
    final bit = DateTime(2026, 11, 6, 23, 59, 59);
    final args = [bas.toIso8601String(), bit.toIso8601String()];

    test('eski koşul tarih indexini kullanamıyordu (referans)', () async {
      final p = await plan('SELECT COUNT(*) FROM satislar WHERE $_eskiAralik '
          'AND iptal = 0 AND is_deleted = 0 AND sync_cakisma_kopyasi = 0', args);
      expect(p, isNot(contains('tarih>?')), reason: p);
    });

    for (final (tablo, ek) in [
      ('satislar', 'AND iptal = 0 AND is_deleted = 0 AND sync_cakisma_kopyasi = 0'),
      ('kasa_hareketleri', 'AND deleted_at IS NULL'),
      ('giderler', 'AND deleted_at IS NULL'),
      ('stok_hareket', ''),
      ('banka_hareketler', ''),
    ]) {
      test('$tablo tarih aralığı index ile aranır', () async {
        final p = await plan(
            'SELECT COUNT(*) FROM $tablo WHERE ${TarihUtils.aralikSql('tarih', bas, bit)} $ek',
            args);
        expect(p, contains('SEARCH $tablo USING'), reason: p);
        expect(p, contains('tarih>?'), reason: p);
      });
    }
  });
}
