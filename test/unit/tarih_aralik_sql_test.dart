// test/unit/tarih_aralik_sql_test.dart
//
// TarihUtils.aralikSql — rapor tarih aralığı koşulunun tek biçimi
// (CLAUDE.md §4.6, 2026-11-06; önceden 47 yerde elle yazılıydı).
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/cekirdek/utils/tarih_utils.dart';
import '../helper/test_initializer.dart';

void main() {
  test('üretilen SQL eski elle yazılmış biçimle birebir aynı', () {
    expect(TarihUtils.aralikSql('tarih'),
        'datetime(tarih) BETWEEN datetime(?) AND datetime(?)');
    expect(TarihUtils.aralikSql('s.tarih'),
        'datetime(s.tarih) BETWEEN datetime(?) AND datetime(?)');
  });

  group('yerel saatli kayıtlar gün aralığına doğru girer', () {
    late Database db;
    setUp(() async => db = await TestVeritabani.olustur());
    tearDown(() => db.close());

    test('gece 00:30 ve 23:59 kaydı o günün raporunda, ertesi gün 00:00 dışında', () async {
      for (final t in [
        DateTime(2026, 11, 6, 0, 30),
        DateTime(2026, 11, 6, 23, 59, 59),
        DateTime(2026, 11, 7, 0, 0, 1),
      ]) {
        await db.insert('kasa_hareketleri',
            {'hareket_tipi': 'Satış', 'tutar': 1, 'tarih': t.toIso8601String()});
      }
      final rows = await db.rawQuery(
          'SELECT COUNT(*) AS n FROM kasa_hareketleri WHERE ${TarihUtils.aralikSql('tarih')}',
          [DateTime(2026, 11, 6).toIso8601String(),
           DateTime(2026, 11, 6, 23, 59, 59, 999).toIso8601String()]);
      expect(rows.first['n'], 2);
    });
  });
}
