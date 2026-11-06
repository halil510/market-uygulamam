// test/servisler/iade_cari_gercek_etki_test.dart
//
// Kullanıcı bulgusu (2026-09-22 sabah): "iade edildiğinde cariden niye
// düşme olmuyor — müşteri ise borcu azalacak, tedarikçide de aynı".
// Bir önceki turda (2026-09-22, fad1724) İade'de cari seçimi HER ZAMAN
// bakiyeyi etkilemeyen (borc=alacak) salt-kayıt yapılacak şekilde
// değiştirilmişti — bu, çift-iade riskini ortadan kaldırdı AMA gerçekten
// "Veresiye/Cari'ye yaz" seçilen iadelerde bakiyeyi hiç düşürmüyordu.
//
// Düzeltme: İade Ödeme Yöntemi artık üç seçenekli ('Nakit' / 'Kart-Banka'
// / 'Cari') tek seçimli bir dropdown — 'Cari' seçilirse (para fiziksel
// verilmedi) bakiye GERÇEKTEN düzeltilir, 'Nakit'/'Kart' seçilirse (para
// zaten fiziksel verildi) cari sadece takip amaçlı nötr kayıt alır.
//
// 2026-11-06 (test güvenilirliği, Kademe 1): bu test ÖNCEDEN
// topluIadeKaydet()'in cari yazımını ve duzenlemeModuKalemEkle()'nin kasa
// koşulunu KOPYALAYAN yardımcılar çağırıyordu — üretim kodu bozulsa bile
// yeşil kalırdı. Artık GERÇEK IadeIslemServisi metotları çağrılıyor.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:market_plus/depolar/cari_deposu.dart';
import 'package:market_plus/depolar/urun_deposu.dart';
import 'package:market_plus/servisler/iade_islem_servisi.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

/// Cariye [birimFiyat]'tan 1 adet satış yazar (iade fiyat dayanağı —
/// gerçek akış fiyatı o carinin son satışından okur), sonra GERÇEK
/// topluIadeKaydet ile 1 adet iade alır.
Future<void> _topluIade(Database db, {
  required int cariId,
  required String odemeYontemi,
  required double birimFiyat,
}) async {
  final urunId = await TestVeritabani.ornekUrunEkle(db, satisFiyati: birimFiyat);
  final satisId = await db.insert('satislar', {
    'global_id': const Uuid().v4(),
    'fis_no': 'S-$urunId',
    'tarih': DateTime.now().toIso8601String(),
    'cari_id': cariId,
    'genel_toplam': birimFiyat,
    'odenen_tutar': birimFiyat,
    'odeme_yontemi': 'Nakit',
    'is_deleted': 0,
  });
  await db.insert('satis_kalem', {
    'global_id': const Uuid().v4(),
    'satis_id': satisId,
    'urun_id': urunId,
    'urun_adi': 'Test Ürün',
    'miktar': 1,
    'birim_fiyat': birimFiyat,
    'net_fiyat': birimFiyat,
    'toplam_tutar': birimFiyat,
  });
  final urun = (await UrunDeposu().idileGetir(urunId))!;
  final cari = (await CariDeposu().idileGetir(cariId))!;
  await IadeIslemServisi().topluIadeKaydet(
    kalemler: [IadeKalemGirdi(urun: urun, adet: 1)],
    odemeYontemi: odemeYontemi,
    kullaniciId: null,
    kullaniciAdi: 'Test',
    cari: cari,
  );
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

  group("İade — 'Cari' ödeme yöntemi bakiyeyi GERÇEKTEN etkiler", () {
    test('Müşteride 200 TL veresiye borcu varken 60 TL Cari iade edilirse borç 140\'a düşer',
        () async {
      final cariId = await TestVeritabani.ornekCariEkle(db);
      await db.insert('cari_hareket', {
        'global_id': const Uuid().v4(),
        'cari_id': cariId,
        'tarih': DateTime.now().toIso8601String(),
        'fis_tipi': 'Satış',
        'borc': 200.0,
        'alacak': 0.0,
        'odeme_turu': 'Cari',
      });
      await db.update('cari', {'bakiye': 200.0}, where: 'id = ?', whereArgs: [cariId]);

      await _topluIade(db, cariId: cariId, odemeYontemi: 'Cari', birimFiyat: 60.0);

      final cari = (await db.query('cari', where: 'id = ?', whereArgs: [cariId])).first;
      expect((cari['bakiye'] as num).toDouble(), equals(140.0),
          reason: 'Cari ödeme yöntemiyle iade edilirse müşterinin borcu GERÇEKTEN azalmalı');
    });

    test('Tedarikçiye borcumuz 500 TL iken 100 TL Cari iade edilirse borcumuz 400\'e düşer',
        () async {
      final cariId = await TestVeritabani.ornekCariEkle(db, cariTipi: 'Tedarikçi');
      await db.insert('cari_hareket', {
        'global_id': const Uuid().v4(),
        'cari_id': cariId,
        'tarih': DateTime.now().toIso8601String(),
        'fis_tipi': 'Alım',
        'borc': 0.0,
        'alacak': 500.0,
        'odeme_turu': 'Cari',
      });
      await db.update('cari', {'bakiye': -500.0}, where: 'id = ?', whereArgs: [cariId]);

      await _topluIade(db, cariId: cariId, odemeYontemi: 'Cari', birimFiyat: 100.0);

      final cari = (await db.query('cari', where: 'id = ?', whereArgs: [cariId])).first;
      expect((cari['bakiye'] as num).toDouble(), equals(-400.0),
          reason: 'Cari ödeme yöntemiyle tedarikçiye iade edilirse bizim borcumuz GERÇEKTEN azalmalı');
    });

    test('Nakit ödeme yöntemiyle iade edilip AYRICA cari seçilirse bakiye YİNE etkilenmez (çift iade önlenir)',
        () async {
      final cariId = await TestVeritabani.ornekCariEkle(db);
      await db.update('cari', {'bakiye': 0}, where: 'id = ?', whereArgs: [cariId]);

      await _topluIade(db, cariId: cariId, odemeYontemi: 'Nakit', birimFiyat: 60.0);

      final cari = (await db.query('cari', where: 'id = ?', whereArgs: [cariId])).first;
      expect((cari['bakiye'] as num).toDouble(), equals(0.0),
          reason: 'Nakit zaten elden verildiği için cari bakiyesi hiç etkilenmemeli');
    });
  });

  group(
      "İade Geçmişi düzenleme modunda kalem ekleme (duzenlemeModuKalemEkle) — kasa hareketi artık ödeme yöntemine göre",
      () {
    // GERÇEK IadeIslemServisi.duzenlemeModuKalemEkle() çağrılır: ÖNCEDEN
    // odemeYontemi ne olursa olsun koşulsuz kasa çıkışı yazıyordu — Kart/
    // Banka veya Cari seçilse bile kasadan gerçekte hiç çıkmamış bir tutar
    // düşülüyordu.
    Future<int> kalemEkle(Database db,
        {required String odemeYontemi, required double toplam}) async {
      final urunId = await TestVeritabani.ornekUrunEkle(db);
      final iadeId = await db.insert('iade', {
        'global_id': const Uuid().v4(),
        'fis_no': 'IAD-$urunId',
        'tarih': DateTime.now().toIso8601String(),
        'toplam_tutar': 0,
        'durum': 'tamamlandi',
      });
      await IadeIslemServisi().duzenlemeModuKalemEkle(
        iadeId: iadeId,
        urunId: urunId,
        urunAdi: 'Test Ürün',
        miktar: 1,
        fiyat: toplam,
        toplam: toplam,
        fisNo: 'IAD-$urunId',
        cariId: null,
        cariTipi: null,
        kullaniciId: null,
        kullaniciAdi: 'Test',
        odemeYontemi: odemeYontemi,
      );
      return iadeId;
    }

    test('Kart/Banka seçiliyken kalem eklenirse kasaya HİÇ hareket yazılmaz', () async {
      final iadeId = await kalemEkle(db, odemeYontemi: 'Kart/Banka', toplam: 75.0);
      final kasaSatirlari = await db.query('kasa_hareketleri',
          where: 'referans_id = ? AND referans_turu = ?', whereArgs: [iadeId, 'iade']);
      expect(kasaSatirlari, isEmpty,
          reason: 'Kart/Banka ile ödenen bir iade kalemi kasadan hiç nakit çıkarmamalı');
    });

    test('Cari seçiliyken kalem eklenirse kasaya HİÇ hareket yazılmaz', () async {
      final iadeId = await kalemEkle(db, odemeYontemi: 'Cari', toplam: 50.0);
      final kasaSatirlari = await db.query('kasa_hareketleri',
          where: 'referans_id = ? AND referans_turu = ?', whereArgs: [iadeId, 'iade']);
      expect(kasaSatirlari, isEmpty,
          reason: 'Cari\'ye yazılan bir iade kalemi kasadan hiç nakit çıkarmamalı');
    });

    test('Nakit seçiliyken kalem eklenirse kasaya GERÇEK tutar yazılır', () async {
      final iadeId = await kalemEkle(db, odemeYontemi: 'Nakit', toplam: 40.0);
      final kasaSatirlari = await db.query('kasa_hareketleri',
          where: 'referans_id = ? AND referans_turu = ?', whereArgs: [iadeId, 'iade']);
      expect(kasaSatirlari, hasLength(1));
      expect((kasaSatirlari.first['tutar'] as num).toDouble(), equals(40.0));
    });
  });
}
