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
//
// 2026-11-06 (test güvenilirliği, Kademe 1): bu test ÖNCEDEN odemeYap()'ın
// adımlarını kopyalayan bir simülasyon çağırıyordu — üretim kodu bozulsa
// bile yeşil kalırdı. Artık GERÇEK BorcOdemeIslemServisi().odemeYap()
// çağrılıyor. Atomiklik testi, son adımın (gider kaydı) yazacağı tabloyu
// düşürerek gerçek transaction'ın gerçekten geri alındığını doğrular.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/modeller/borc_model.dart';
import 'package:market_plus/servisler/borc_odeme_islem_servisi.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

/// GERÇEK BorcOdemeIslemServisi().odemeYap() — Nakit dalı. Borç güncel
/// haliyle DB'den okunur (ekrandaki gibi). [ortasindaPatlat]: gider
/// adımının yazacağı tablo düşürülür → transaction son adımda patlar.
Future<void> _nakitOdeme(
  Database db, {
  required int borcId,
  required double tutar,
  bool ortasindaPatlat = false,
}) async {
  final borc = BorcModel.fromMap(
      (await db.query('borclar', where: 'id = ?', whereArgs: [borcId])).first);
  if (ortasindaPatlat) await db.execute('DROP TABLE giderler');
  await BorcOdemeIslemServisi()
      .odemeYap(borc: borc, tutar: tutar, odemeYontemi: 'Nakit');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (_) async => null);
    SharedPreferences.setMockInitialValues({});
    db = await TestVeritabani.olustur();
    Veritabani.testVeritabani = db;
  });
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    Veritabani.testVeritabani = null;
    await db.close();
  });

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

      await _nakitOdeme(db, borcId: borcId, tutar: 200);

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
      await _nakitOdeme(db, borcId: borcId, tutar: 300);

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
        _nakitOdeme(db, borcId: borcId, tutar: 200, ortasindaPatlat: true),
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
      await _nakitOdeme(db, borcId: borcId, tutar: 200);
      await _nakitOdeme(db, borcId: borcId, tutar: 300);

      final odemeler = await db.query('borc_odemeler', where: 'borc_id = ?', whereArgs: [borcId]);
      expect(odemeler.length, equals(2));

      final borc = (await db.query('borclar', where: 'id = ?', whereArgs: [borcId])).first;
      expect((borc['odenen_tutar'] as num).toDouble(), equals(500.0));
      expect(borc['odendi'], equals(1));
    });
  });
}
