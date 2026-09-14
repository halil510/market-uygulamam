// test/veri/biyometrik_kayit_test.dart
//
// Güvenlik düzeltmesi: parmak izi ile giriş ARTIK kullanıcının ham
// şifresini değil, cihaza özel rastgele bir tokenın tuzlu hash'ini
// saklıyor (bkz. BiyometrikDeposu, AuthServisi.girisYapBiyometrikToken).
// BiyometrikDeposu Veritabani() singleton'ı üzerinden çalıştığı için
// (diğer depo testlerinde olduğu gibi) burada AYNI SQL gerçek şema
// üzerinde doğrulanıyor.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/cekirdek/utils/sifre_hash.dart';
import 'package:market_plus/depolar/biyometrik_deposu.dart';
import '../helper/test_initializer.dart';

Future<void> _kaydet(Database db, int kullaniciId, String token) async {
  final tuz = SifreHash.tuzUret();
  final hash = SifreHash.hashleTuzlu(token, tuz);
  await db.insert(
    'biyometrik_kayitlar',
    {'kullanici_id': kullaniciId, 'token_hash': hash, 'tuz': tuz},
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

Future<bool> _dogrula(Database db, int kullaniciId, String token) async {
  final rows = await db.query('biyometrik_kayitlar',
      where: 'kullanici_id = ?', whereArgs: [kullaniciId]);
  if (rows.isEmpty) return false;
  final row = rows.first;
  return SifreHash.hashleTuzlu(token, row['tuz'] as String) ==
      row['token_hash'];
}

void main() {
  group('BiyometrikDeposu.tokenUret', () {
    test('yeterince uzun (256-bit) ve hex formatında', () {
      final token = BiyometrikDeposu.tokenUret();
      expect(token.length, equals(64));
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(token), isTrue);
    });

    test('her çağrıda farklı, rastgele bir token üretir', () {
      final t1 = BiyometrikDeposu.tokenUret();
      final t2 = BiyometrikDeposu.tokenUret();
      expect(t1, isNot(equals(t2)));
    });
  });

  late Database db;
  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  group('biyometrik_kayitlar şeması', () {
    test('tablo ve beklenen kolonlar mevcut', () async {
      final kolonlar = await db.rawQuery('PRAGMA table_info(biyometrik_kayitlar)');
      final adlar = kolonlar.map((k) => k['name'] as String).toSet();
      expect(adlar, containsAll(['kullanici_id', 'token_hash', 'tuz']));
    });

    test('şifre/PIN metni hiçbir kolonda düz olarak tutulmuyor', () async {
      final kolonlar = await db.rawQuery('PRAGMA table_info(biyometrik_kayitlar)');
      final adlar = kolonlar.map((k) => k['name'] as String).toSet();
      expect(adlar.contains('sifre'), isFalse);
      expect(adlar.contains('token'), isFalse); // sadece 'token_hash' olmalı
    });
  });

  group('Biyometrik token doğrulama', () {
    test('kayıtlı token doğru şekilde doğrulanır', () async {
      await _kaydet(db, 1, 'abc123token');
      expect(await _dogrula(db, 1, 'abc123token'), isTrue);
    });

    test('yanlış token reddedilir', () async {
      await _kaydet(db, 1, 'dogruToken');
      expect(await _dogrula(db, 1, 'yanlisToken'), isFalse);
    });

    test('kayıt yoksa doğrulama false döner (istisna fırlatmaz)', () async {
      expect(await _dogrula(db, 999, 'herhangiBirToken'), isFalse);
    });

    test('aynı kullanıcı için yeniden kaydetme eskisinin üzerine yazar (REPLACE)', () async {
      await _kaydet(db, 5, 'ilkToken');
      await _kaydet(db, 5, 'ikinciToken');

      expect(await _dogrula(db, 5, 'ilkToken'), isFalse);
      expect(await _dogrula(db, 5, 'ikinciToken'), isTrue);

      final rows = await db.query('biyometrik_kayitlar', where: 'kullanici_id = ?', whereArgs: [5]);
      expect(rows.length, equals(1));
    });

    test('farklı kullanıcıların tokenları birbirini etkilemez', () async {
      await _kaydet(db, 1, 'tokenA');
      await _kaydet(db, 2, 'tokenB');

      expect(await _dogrula(db, 1, 'tokenB'), isFalse);
      expect(await _dogrula(db, 2, 'tokenA'), isFalse);
      expect(await _dogrula(db, 1, 'tokenA'), isTrue);
      expect(await _dogrula(db, 2, 'tokenB'), isTrue);
    });
  });
}
