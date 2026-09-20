// test/veri/vardiya_onay_test.dart
//
// Madde 12 denetimi (Kasa Kapanış — Müdür Onayı, 2026-09-16, kullanıcı
// onaylı UX: "Anında PIN onayı"). VardiyaDeposu Veritabani() singleton'ı
// üzerinden çalıştığı için (projenin yerleşik test deseni), kapat()'ın
// güncelleme mantığı gerçek şema üzerinde (TestVeritabani — migrasyon
// v68→v69 ile BİREBİR aynı fresh-install şeması) doğrulanıyor.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import '../helper/test_initializer.dart';

/// VardiyaDeposu.kapat() ile BİREBİR aynı UPDATE mantığı.
Future<void> _kapat(
  Database db, {
  required int vardiyaId,
  required double sayim,
  required double fark,
  int? onaylayanKullaniciId,
}) async {
  final now = DateTime.now().toIso8601String();
  await db.update(
      'vardiyalar',
      {
        'kapanis_tarihi': now,
        'kapanis_kasasi': sayim,
        'bitis_bakiye': sayim,
        'nakit_sayim': sayim,
        'fark': fark,
        'durum': 'kapali',
        'last_updated': now,
        if (onaylayanKullaniciId != null) ...{
          'onaylayan_kullanici_id': onaylayanKullaniciId,
          'onaylanma_tarihi': now,
        },
      },
      where: 'id = ?',
      whereArgs: [vardiyaId]);
}

Future<List<Map<String, Object?>>> _gecmisVardiyalarGetir(Database db) {
  return db.rawQuery(
      'SELECT v.*, k.ad_soyad, o.ad_soyad AS onaylayan_adi FROM vardiyalar v '
      'LEFT JOIN kullanicilar k ON v.kullanici_id = k.id '
      'LEFT JOIN kullanicilar o ON v.onaylayan_kullanici_id = o.id '
      'WHERE v.kapanis_tarihi IS NOT NULL ORDER BY v.id DESC');
}

void main() {
  late Database db;
  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  Future<int> kullaniciEkle(String adSoyad, String rol) {
    return db.insert('kullanicilar', {
      'kullanici_adi': adSoyad.toLowerCase().replaceAll(' ', '_'),
      'sifre_hash': 'x', 'ad_soyad': adSoyad, 'rol': rol, 'aktif': 1,
    });
  }

  Future<int> vardiyaAc(int kullaniciId) {
    return db.insert('vardiyalar', {
      'kullanici_id': kullaniciId,
      'acilis_tarihi': DateTime(2026, 9, 20, 9, 0).toIso8601String(),
      'acilis_kasasi': 0, 'baslangic_bakiye': 0, 'durum': 'acik',
    });
  }

  test('vardiyalar şeması onaylayan_kullanici_id/onaylanma_tarihi içerir '
      '(migrasyon v68→v69 ile fresh-install BİREBİR aynı olmalı)', () async {
    final kolonlar = await db.rawQuery("PRAGMA table_info('vardiyalar')");
    final adlar = kolonlar.map((k) => k['name']).toSet();
    expect(adlar.contains('onaylayan_kullanici_id'), isTrue);
    expect(adlar.contains('onaylanma_tarihi'), isTrue);
  });

  group('kapat() — Müdür Onayı alanları', () {
    test('onaylayanKullaniciId verilirse onaylayan_kullanici_id + onaylanma_tarihi yazılır', () async {
      final kasiyerId = await kullaniciEkle('Ayşe Kasiyer', 'kasiyer');
      final muduId = await kullaniciEkle('Mehmet Müdür', 'mudur');
      final vardiyaId = await vardiyaAc(kasiyerId);

      await _kapat(db, vardiyaId: vardiyaId, sayim: 100, fark: 0, onaylayanKullaniciId: muduId);

      final satir = (await db.query('vardiyalar', where: 'id = ?', whereArgs: [vardiyaId])).first;
      expect(satir['onaylayan_kullanici_id'], muduId);
      expect(satir['onaylanma_tarihi'], isNotNull);
      expect(satir['durum'], 'kapali');
    });

    test('onaylayanKullaniciId verilmezse (Müdür kendi vardiyasını kapatır) alanlar null kalır', () async {
      final muduId = await kullaniciEkle('Mehmet Müdür', 'mudur');
      final vardiyaId = await vardiyaAc(muduId);

      await _kapat(db, vardiyaId: vardiyaId, sayim: 100, fark: 0);

      final satir = (await db.query('vardiyalar', where: 'id = ?', whereArgs: [vardiyaId])).first;
      expect(satir['onaylayan_kullanici_id'], isNull);
      expect(satir['onaylanma_tarihi'], isNull);
    });

    test('gecmisVardiyalarGetir onaylayan_adi\'yı doğru JOIN eder', () async {
      final kasiyerId = await kullaniciEkle('Ayşe Kasiyer', 'kasiyer');
      final muduId = await kullaniciEkle('Mehmet Müdür', 'mudur');
      final vardiyaId = await vardiyaAc(kasiyerId);
      await _kapat(db, vardiyaId: vardiyaId, sayim: 100, fark: 0, onaylayanKullaniciId: muduId);

      final gecmis = await _gecmisVardiyalarGetir(db);
      expect(gecmis, hasLength(1));
      expect(gecmis.first['ad_soyad'], 'Ayşe Kasiyer');
      expect(gecmis.first['onaylayan_adi'], 'Mehmet Müdür');
    });

    test('onaysız kapanan vardiyalarda onaylayan_adi null döner (LEFT JOIN)', () async {
      final muduId = await kullaniciEkle('Mehmet Müdür', 'mudur');
      final vardiyaId = await vardiyaAc(muduId);
      await _kapat(db, vardiyaId: vardiyaId, sayim: 100, fark: 0);

      final gecmis = await _gecmisVardiyalarGetir(db);
      expect(gecmis, hasLength(1));
      expect(gecmis.first['onaylayan_adi'], isNull);
    });
  });
}
