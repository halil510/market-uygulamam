// test/veri/sync_cakisma_deposu_test.dart
//
// SyncCakismaDeposu'nun gerçek üretim şemasıyla (TestVeritabani) temel
// CRUD ve çözüm akışlarını doğrular. Depo, Veritabani() singleton'ı
// üzerinden çalıştığı için burada tabloya doğrudan (gerçek şemayla
// oluşturulmuş) db üzerinden yazıp okuyarak aynı SQL'i/şemayı doğruluyoruz.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/modeller/sync_cakisma_model.dart';
import '../helper/test_initializer.dart';

void main() {
  late Database db;

  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  group('sync_cakismalar şeması', () {
    test('tablo gerçek şemada oluşuyor', () async {
      final tablolar = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='sync_cakismalar'");
      expect(tablolar, isNotEmpty);
    });

    test('bir çakışma kaydı eklenip okunabiliyor', () async {
      final model = SyncCakismaModel(
        tablo: 'urunler',
        kayitGlobalId: 'g1',
        alanFarklari: {'fiyat': {'yerel': 125, 'gelen': 129}},
        yerelKayit: {'id': 1, 'fiyat': 125},
        gelenKayit: {'fiyat': 129},
        tarih: DateTime.now(),
      );
      final id = await db.insert('sync_cakismalar', model.toMap()..remove('id'));

      final rows = await db.query('sync_cakismalar', where: 'id = ?', whereArgs: [id]);
      expect(rows, hasLength(1));
      final okunan = SyncCakismaModel.fromMap(rows.first);
      expect(okunan.tablo, equals('urunler'));
      expect(okunan.cozuldu, isFalse);
      expect(okunan.alanFarklari['fiyat'], equals({'yerel': 125, 'gelen': 129}));
    });

    test('çözülmüş kayıt cozuldu=1 ile işaretlenebiliyor', () async {
      final id = await db.insert('sync_cakismalar', SyncCakismaModel(
        tablo: 'urunler', kayitGlobalId: 'g1',
        alanFarklari: {'fiyat': {'yerel': 125, 'gelen': 129}},
        tarih: DateTime.now(),
      ).toMap()..remove('id'));

      await db.update('sync_cakismalar', {
        'cozuldu': 1, 'cozum_tipi': 'yerel', 'cozen_kullanici': 'test',
        'cozum_tarihi': DateTime.now().toIso8601String(),
      }, where: 'id = ?', whereArgs: [id]);

      final rows = await db.query('sync_cakismalar', where: 'id = ?', whereArgs: [id]);
      expect(rows.first['cozuldu'], equals(1));
      expect(rows.first['cozum_tipi'], equals('yerel'));
    });

    test('cozuldu index ile sadece çözülmemişler filtrelenebiliyor', () async {
      await db.insert('sync_cakismalar', SyncCakismaModel(
        tablo: 'urunler', alanFarklari: {'a': 1}, tarih: DateTime.now(), cozuldu: false,
      ).toMap()..remove('id'));
      await db.insert('sync_cakismalar', SyncCakismaModel(
        tablo: 'urunler', alanFarklari: {'a': 1}, tarih: DateTime.now(), cozuldu: true,
      ).toMap()..remove('id'));

      final cozulmemisler = await db.query('sync_cakismalar', where: 'cozuldu = 0');
      expect(cozulmemisler, hasLength(1));
    });
  });
}
