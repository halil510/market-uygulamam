import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/cekirdek/utils/hata_utils.dart';

void main() {
  test('UNIQUE ihlali anlaşılır Türkçe olur, ham metin sızmaz', () {
    final m = kullaniciyaHataMetni(Exception(
        'DatabaseException(SqliteException(2067): UNIQUE constraint failed: urunler.barkod)'));
    expect(m, contains('zaten mevcut'));
    expect(m, isNot(contains('SqliteException')));
  });

  test('FOREIGN KEY ve NOT NULL çevrilir', () {
    expect(kullaniciyaHataMetni('SqliteException(787): FOREIGN KEY constraint failed'),
        contains('ilişkili'));
    expect(kullaniciyaHataMetni('SqliteException(1299): NOT NULL constraint failed: cari.unvan'),
        contains('Zorunlu'));
  });

  test('tip/aralık hataları genel mesaja döner', () {
    expect(kullaniciyaHataMetni("type 'Null' is not a subtype of type 'int'"),
        contains('Beklenmeyen'));
    expect(kullaniciyaHataMetni(RangeError('x')), contains('Beklenmeyen'));
  });

  test('ön metin korunur, iş mantığı mesajı bozulmaz', () {
    expect(
        bildirimMetniniSadelestir(
            'Kayıt başarısız: FormatException: Invalid number'),
        startsWith('Kayıt başarısız: '));
    expect(kullaniciyaHataMetni(Exception('Bu sipariş zaten teslim alınmış.')),
        'Bu sipariş zaten teslim alınmış.');
    expect(bildirimMetniniSadelestir('Stok yetersiz'), 'Stok yetersiz');
  });
}
