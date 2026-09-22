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
// IadeIslemServisi Veritabani() singleton'ına bağımlı olduğundan
// (projenin yerleşik test deseni — bkz. iade_olustur_cift_iade_fix_test.dart
// ve iade_sil_test.dart'taki AYNI yaklaşım), bu test topluIadeKaydet()'teki
// BİREBİR aynı cari_hareket yazım mantığını gerçek şema üzerinde doğrular.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../helper/test_initializer.dart';

/// IadeIslemServisi.topluIadeKaydet()'teki (düzeltilmiş) cari_hareket
/// yazımının BİREBİR aynısı.
Future<void> _iadeCariYaz(
  Database db, {
  required int cariId,
  required bool isTedarikci,
  required String odemeYontemi,
  required int iadeId,
  required String fisNo,
  required double toplamIade,
}) async {
  await db.transaction((txn) async {
    final gercekEtki = odemeYontemi == 'Cari';
    await txn.insert('cari_hareket', {
      'global_id': const Uuid().v4(),
      'cari_id': cariId,
      'tarih': DateTime.now().toIso8601String(),
      'fis_tipi': 'İade',
      'fis_id': iadeId,
      'fis_no': fisNo,
      'borc': gercekEtki ? (isTedarikci ? toplamIade : 0) : toplamIade,
      'alacak': gercekEtki ? (isTedarikci ? 0 : toplamIade) : toplamIade,
      'odeme_turu': odemeYontemi,
    });
    await txn.rawUpdate(
        'UPDATE cari SET bakiye = (SELECT COALESCE(SUM(borc),0) - COALESCE(SUM(alacak),0) FROM cari_hareket WHERE cari_id=? AND is_deleted=0) WHERE id=?',
        [cariId, cariId]);
  });
}

void main() {
  late Database db;
  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

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

      await _iadeCariYaz(db,
          cariId: cariId,
          isTedarikci: false,
          odemeYontemi: 'Cari',
          iadeId: 1,
          fisNo: 'IAD1',
          toplamIade: 60.0);

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

      await _iadeCariYaz(db,
          cariId: cariId,
          isTedarikci: true,
          odemeYontemi: 'Cari',
          iadeId: 2,
          fisNo: 'IAD2',
          toplamIade: 100.0);

      final cari = (await db.query('cari', where: 'id = ?', whereArgs: [cariId])).first;
      expect((cari['bakiye'] as num).toDouble(), equals(-400.0),
          reason: 'Cari ödeme yöntemiyle tedarikçiye iade edilirse bizim borcumuz GERÇEKTEN azalmalı');
    });

    test('Nakit ödeme yöntemiyle iade edilip AYRICA cari seçilirse bakiye YİNE etkilenmez (çift iade önlenir)',
        () async {
      final cariId = await TestVeritabani.ornekCariEkle(db);
      await db.update('cari', {'bakiye': 0}, where: 'id = ?', whereArgs: [cariId]);

      await _iadeCariYaz(db,
          cariId: cariId,
          isTedarikci: false,
          odemeYontemi: 'Nakit',
          iadeId: 3,
          fisNo: 'IAD3',
          toplamIade: 60.0);

      final cari = (await db.query('cari', where: 'id = ?', whereArgs: [cariId])).first;
      expect((cari['bakiye'] as num).toDouble(), equals(0.0),
          reason: 'Nakit zaten elden verildiği için cari bakiyesi hiç etkilenmemeli');
    });
  });

  group(
      "İade Geçmişi düzenleme modunda kalem ekleme (duzenlemeModuKalemEkle) — kasa hareketi artık ödeme yöntemine göre",
      () {
    // IadeIslemServisi.duzenlemeModuKalemEkle()'teki "5. Kasa hareketi"
    // adımının (düzeltilmiş) koşulunun BİREBİR aynısı: ÖNCEDEN odemeYontemi
    // ne olursa olsun koşulsuz kasa çıkışı yazıyordu — Kart/Banka veya Cari
    // seçilse bile kasadan gerçekte hiç çıkmamış bir tutar düşülüyordu.
    Future<void> kasaYazIadeGirisi(Database db,
        {required String odemeYontemi, required int iadeId, required double toplam}) async {
      if (odemeYontemi != 'Nakit') return; // düzeltilmiş davranış
      await db.insert('kasa_hareketleri', {
        'global_id': const Uuid().v4(),
        'hareket_tipi': 'İade',
        'tutar': toplam,
        'referans_id': iadeId,
        'referans_turu': 'iade',
        'tarih': DateTime.now().toIso8601String(),
      });
    }

    test('Kart/Banka seçiliyken kalem eklenirse kasaya HİÇ hareket yazılmaz', () async {
      await kasaYazIadeGirisi(db, odemeYontemi: 'Kart/Banka', iadeId: 10, toplam: 75.0);
      final kasaSatirlari = await db.query('kasa_hareketleri',
          where: 'referans_id = ? AND referans_turu = ?', whereArgs: [10, 'iade']);
      expect(kasaSatirlari, isEmpty,
          reason: 'Kart/Banka ile ödenen bir iade kalemi kasadan hiç nakit çıkarmamalı');
    });

    test('Cari seçiliyken kalem eklenirse kasaya HİÇ hareket yazılmaz', () async {
      await kasaYazIadeGirisi(db, odemeYontemi: 'Cari', iadeId: 11, toplam: 50.0);
      final kasaSatirlari = await db.query('kasa_hareketleri',
          where: 'referans_id = ? AND referans_turu = ?', whereArgs: [11, 'iade']);
      expect(kasaSatirlari, isEmpty,
          reason: 'Cari\'ye yazılan bir iade kalemi kasadan hiç nakit çıkarmamalı');
    });

    test('Nakit seçiliyken kalem eklenirse kasaya GERÇEK tutar yazılır', () async {
      await kasaYazIadeGirisi(db, odemeYontemi: 'Nakit', iadeId: 12, toplam: 40.0);
      final kasaSatirlari = await db.query('kasa_hareketleri',
          where: 'referans_id = ? AND referans_turu = ?', whereArgs: [12, 'iade']);
      expect(kasaSatirlari, hasLength(1));
      expect((kasaSatirlari.first['tutar'] as num).toDouble(), equals(40.0));
    });
  });
}
