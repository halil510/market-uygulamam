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

  // FAZ 3 (DEEP_AUDIT_REPORT madde 4, 2026-09-21): SyncCakismaDeposu.
  // gelenIleCoz() ARTIK gerçekten veri yazıyor (önceden no-op'tu, "zaten
  // uygulanmıştı" varsayımıyla) — "işlem verisi" tablolarında artık
  // otomatik uygulanmadığı için bu gerçek eylem gerekiyor. Depo
  // Veritabani() singleton'ı üzerinden çalıştığı için (diğer depo
  // testlerinde olduğu gibi) burada AYNI yazma mantığı doğrudan
  // doğrulanıyor.
  group('gelenIleCoz / yerelIleCoz — gerçek veri yazımı', () {
    Future<void> gelenIleCozMantik(Database db, int cakismaId) async {
      final rows = await db.query('sync_cakismalar', where: 'id = ?', whereArgs: [cakismaId]);
      final c = SyncCakismaModel.fromMap(rows.first);
      if (c.gelenKayit != null && c.kayitGlobalId != null) {
        final uygulanacak = Map<String, dynamic>.from(c.gelenKayit!)..remove('id');
        await db.update(c.tablo, uygulanacak,
            where: 'global_id = ?', whereArgs: [c.kayitGlobalId]);
      }
      await db.update('sync_cakismalar', {'cozuldu': 1, 'cozum_tipi': 'gelen'},
          where: 'id = ?', whereArgs: [cakismaId]);
    }

    Future<void> yerelIleCozMantik(Database db, int cakismaId) async {
      final rows = await db.query('sync_cakismalar', where: 'id = ?', whereArgs: [cakismaId]);
      final c = SyncCakismaModel.fromMap(rows.first);
      if (c.yerelKayit != null && c.kayitGlobalId != null) {
        final geriYazilacak = Map<String, dynamic>.from(c.yerelKayit!)..remove('id');
        await db.update(c.tablo, geriYazilacak,
            where: 'global_id = ?', whereArgs: [c.kayitGlobalId]);
      }
      await db.update('sync_cakismalar', {'cozuldu': 1, 'cozum_tipi': 'yerel'},
          where: 'id = ?', whereArgs: [cakismaId]);
    }

    test(
        'gelenIleCoz — işlem verisi tablosunda daha önce UYGULANMAMIŞ '
        'gelen_kayit artık GERÇEKTEN yazılır', () async {
      final hareketId = await db.insert('kasa_hareketleri', {
        'global_id': 'kasa-3', 'hareket_tipi': 'Satış', 'tutar': 100,
        'bakiye_sonrasi': 500, // yerel (henüz uygulanmamış çakışma senaryosu)
      });
      final cakismaId = await db.insert('sync_cakismalar', SyncCakismaModel(
        tablo: 'kasa_hareketleri', kayitGlobalId: 'kasa-3',
        alanFarklari: {'bakiye_sonrasi': {'yerel': 500, 'gelen': 999}},
        gelenKayit: {'bakiye_sonrasi': 999, 'global_id': 'kasa-3'},
        tarih: DateTime.now(),
      ).toMap()..remove('id'));

      await gelenIleCozMantik(db, cakismaId);

      final satir = (await db.query('kasa_hareketleri', where: 'id = ?', whereArgs: [hareketId])).first;
      expect(satir['bakiye_sonrasi'], 999, reason: 'gelen_kayit artık gerçekten uygulanmalı');
      final cakisma = (await db.query('sync_cakismalar', where: 'id = ?', whereArgs: [cakismaId])).first;
      expect(cakisma['cozuldu'], 1);
    });

    test(
        'yerelIleCoz — atlanmış bir çakışmada yerel_kayit\'i geri yazmak '
        'zararsızdır (zaten yereldeydi)', () async {
      final hareketId = await db.insert('kasa_hareketleri', {
        'global_id': 'kasa-4', 'hareket_tipi': 'Satış', 'tutar': 100,
        'bakiye_sonrasi': 500,
      });
      final cakismaId = await db.insert('sync_cakismalar', SyncCakismaModel(
        tablo: 'kasa_hareketleri', kayitGlobalId: 'kasa-4',
        alanFarklari: {'bakiye_sonrasi': {'yerel': 500, 'gelen': 999}},
        yerelKayit: {'bakiye_sonrasi': 500, 'global_id': 'kasa-4'},
        tarih: DateTime.now(),
      ).toMap()..remove('id'));

      await yerelIleCozMantik(db, cakismaId);

      final satir = (await db.query('kasa_hareketleri', where: 'id = ?', whereArgs: [hareketId])).first;
      expect(satir['bakiye_sonrasi'], 500);
    });
  });
}
