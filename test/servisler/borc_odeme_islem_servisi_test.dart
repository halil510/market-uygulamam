// test/servisler/borc_odeme_islem_servisi_test.dart
//
// Derin analizde bulunan iki P0 hatanın regresyon testi:
//  1) BorcOdemeIslemServisi.odemeYap() TEK bir ödeme için borc_odemeler
//     tablosuna İKİ kayıt oluşturuyordu (biri BorcDeposu.odemeYap'ın kendi
//     içinden 'Nakit' etiketiyle, biri servisin kendi doğru-yöntemli
//     kaydı). Artık BorcDeposu.odemeYapTxn(gecmisKaydet: false) ile bu
//     iç kayıt bastırılıyor — tek kayıt oluşmalı.
//  2) Borç güncellemesi + ödeme geçmişi + kasa/banka/kart hareketi + gider
//     kaydı ayrı ayrı awaited çağrılardı, ortak bir transaction'da değildi.
//     Bu test, gerçek üretim şemasıyla (TestVeritabani) depoların Txn
//     varyantlarını TEK transaction içinde çağırarak servisin şu anki
//     mantığını doğrular; adımlardan biri hata fırlatırsa TÜM transaction
//     geri alınmalı (hiçbir yarım kayıt kalmamalı).
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/depolar/borc_deposu.dart';
import 'package:market_plus/depolar/borc_odeme_deposu.dart';
import 'package:market_plus/depolar/kasa_deposu.dart';
import 'package:market_plus/depolar/gider_deposu.dart';
import 'package:market_plus/modeller/borc_odeme_model.dart';
import 'package:market_plus/modeller/kasa_hareket_model.dart';
import 'package:market_plus/modeller/gider_model.dart';
import '../helper/test_initializer.dart';

/// BorcOdemeIslemServisi.odemeYap()'ın nakit dalıyla BİREBİR aynı sırada
/// depo Txn metotlarını çağıran yardımcı — servis Veritabani() singleton'ı
/// üzerinden çalıştığı için testte doğrudan tekrar üretiliyor.
Future<void> _nakitOdemeSimule(
  Database db, {
  required int borcId,
  required double tutar,
  required String baslik,
  bool ortasindaPatlat = false,
}) async {
  final borcDepo = BorcDeposu();
  final odemeDepo = BorcOdemeDeposu();
  final kasaDepo = KasaDeposu();
  final giderDepo = GiderDeposu();

  await db.transaction((txn) async {
    await borcDepo.odemeYapTxn(txn, borcId, tutar, gecmisKaydet: false);

    await odemeDepo.ekleTxn(txn, BorcOdemeModel(
      borcId: borcId, tutar: tutar, tarih: DateTime.now(), odemeYontemi: 'Nakit',
    ));

    await kasaDepo.hareketEkleTxn(txn, KasaHareketModel(
      hareketTipi: 'Borç Ödemesi', tutar: tutar,
      referansId: borcId, referansTuru: 'borc_odeme',
      aciklama: '$baslik - Borç Ödemesi', tarih: DateTime.now(),
    ));

    if (ortasindaPatlat) {
      throw Exception('Simüle edilmiş hata — gider adımından önce');
    }

    final mevcutKategori = await txn.query('gider_kategoriler',
        where: 'ad = ?', whereArgs: ['Borç Ödemeleri'], limit: 1);
    final kategoriId = mevcutKategori.isNotEmpty
        ? mevcutKategori.first['id'] as int
        : await txn.insert('gider_kategoriler', {'ad': 'Borç Ödemeleri'});
    await giderDepo.ekleTxn(txn, GiderModel(
      kategoriId: kategoriId, kategoriAdi: 'Borç Ödemeleri', tutar: tutar,
      aciklama: baslik, tarih: DateTime.now(), odemeYontemi: 'Nakit',
    ));
  });
}

void main() {
  late Database db;

  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  Future<int> borcEkle({double tutar = 500}) => db.insert('borclar', {
    'baslik': 'Test Borç', 'tur': 'tedarikci', 'tutar': tutar,
    'odenen_tutar': 0, 'odendi': 0,
    'kesim_tarihi': DateTime.now().toIso8601String(),
    'son_odeme_tarihi': DateTime.now().toIso8601String(),
    'is_deleted': 0,
  });

  group('BorcOdemeIslemServisi akışı — atomiklik ve tekillik', () {
    test('tek ödeme, borc_odemeler tablosuna TEK kayıt oluşturur (çift kayıt regresyonu)', () async {
      final borcId = await borcEkle(tutar: 500);

      await _nakitOdemeSimule(db, borcId: borcId, tutar: 200, baslik: 'Test Borç');

      final odemeler = await db.query('borc_odemeler', where: 'borc_id = ?', whereArgs: [borcId]);
      expect(odemeler.length, equals(1),
          reason: 'Tek ödeme işlemi borc_odemeler tablosuna tam olarak 1 kayıt bırakmalı');
      expect(odemeler.first['odeme_yontemi'], equals('Nakit'));

      final borc = (await db.query('borclar', where: 'id = ?', whereArgs: [borcId])).first;
      expect((borc['odenen_tutar'] as num).toDouble(), equals(200.0));
      expect(borc['odendi'], equals(0));
    });

    test('kasa ve gider kaydı da aynı işlemde birlikte oluşur', () async {
      final borcId = await borcEkle(tutar: 300);
      await _nakitOdemeSimule(db, borcId: borcId, tutar: 300, baslik: 'Test Borç');

      final kasa = await db.query('kasa_hareketleri', where: 'referans_id = ? AND referans_turu = ?', whereArgs: [borcId, 'borc_odeme']);
      expect(kasa.length, equals(1));
      expect((kasa.first['tutar'] as num).toDouble(), equals(300.0));

      final giderler = await db.query('giderler');
      expect(giderler.length, equals(1));

      final borc = (await db.query('borclar', where: 'id = ?', whereArgs: [borcId])).first;
      expect(borc['odendi'], equals(1), reason: 'Tam tutar ödendiğinde borç kapanmalı');
    });

    test('adımlardan biri hata fırlatırsa TÜM işlem geri alınır (atomiklik)', () async {
      final borcId = await borcEkle(tutar: 500);

      await expectLater(
        _nakitOdemeSimule(db, borcId: borcId, tutar: 200, baslik: 'Test Borç', ortasindaPatlat: true),
        throwsException,
      );

      // Transaction geri alındığı için hiçbir yan etki kalıcı olmamalı.
      final borc = (await db.query('borclar', where: 'id = ?', whereArgs: [borcId])).first;
      expect((borc['odenen_tutar'] as num).toDouble(), equals(0.0),
          reason: 'Rollback sonrası borç güncellenmemiş olmalı');
      expect(await db.query('borc_odemeler', where: 'borc_id = ?', whereArgs: [borcId]), isEmpty);
      expect(await db.query('kasa_hareketleri', where: 'referans_id = ?', whereArgs: [borcId]), isEmpty);
    });

    test('birden fazla kısmi ödeme doğru şekilde birikir, borç tam ödenince kapanır', () async {
      final borcId = await borcEkle(tutar: 500);
      await _nakitOdemeSimule(db, borcId: borcId, tutar: 200, baslik: 'Test Borç');
      await _nakitOdemeSimule(db, borcId: borcId, tutar: 300, baslik: 'Test Borç');

      final odemeler = await db.query('borc_odemeler', where: 'borc_id = ?', whereArgs: [borcId]);
      expect(odemeler.length, equals(2));

      final borc = (await db.query('borclar', where: 'id = ?', whereArgs: [borcId])).first;
      expect((borc['odenen_tutar'] as num).toDouble(), equals(500.0));
      expect(borc['odendi'], equals(1));
    });
  });
}
