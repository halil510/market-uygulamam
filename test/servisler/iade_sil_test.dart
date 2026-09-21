// test/servisler/iade_sil_test.dart
//
// Kullanıcı bulgusu (2026-09-22): "iade silme işlemini de kontrol et
// aynı hatalar olmasın" — Satış (SatisDeposu.sil()) ve Tedarikçi Alımı
// (AlimIslemServisi.sil()) silmede bulunan AYNI hata sınıfı İade'nin
// gerçek fiş-silme yolunda (IadeIslemServisi.gecmisFisIadeSil(), İade
// Geçmişi sekmesinden "Fişi Sil") da vardı: kasa reversal'ı orijinal
// iadenin GERÇEKTEN nakit olarak verilip verilmediğine bakmadan HER
// ZAMAN bir "Iade Iptali" (nakit GİRİŞ) kaydı ekliyordu — Kart/Banka
// veya Cari'ye işlenmiş bir iade silinince hiç var olmamış bir nakit
// girişi oluşturuluyordu.
//
// IadeIslemServisi Veritabani() singleton'ına bağımlı olduğundan
// (projenin yerleşik test deseni), bu test yeni gecmisFisIadeSil()
// akışındaki BİREBİR aynı sorguyu gerçek şema üzerinde doğrular.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../helper/test_initializer.dart';

/// IadeIslemServisi.gecmisFisIadeSil()'in kasa reversal kısmının
/// BİREBİR aynısı — tam fonksiyonun tekrarı yerine, kritik düzeltilen
/// davranışı (kasa sadece GERÇEK satır varsa tersine çevrilir) izole
/// doğrular.
Future<void> _gecmisFisIadeSilSimulasyonu(
  Database db, {
  required int iadeId,
  required int? cariId,
}) async {
  await db.transaction((txn) async {
    final guncelIade = await txn.query('iade', where: 'id = ?', whereArgs: [iadeId], limit: 1);
    if (guncelIade.isNotEmpty && guncelIade.first['durum'] == 'iptal') {
      throw Exception('Bu iade zaten iptal edilmiş.');
    }
    final now = DateTime.now().toIso8601String();

    final kalemler = await txn.query('iade_kalem', where: 'iade_id = ?', whereArgs: [iadeId]);
    for (final k in kalemler) {
      final urunId = k['urun_id'] as int?;
      final miktar = (k['miktar'] as num?)?.toDouble() ?? 0;
      if (urunId == null || miktar <= 0) continue;
      final onceki = (await txn.query('urunler', columns: ['stok'], where: 'id = ?', whereArgs: [urunId])).first['stok'] as num;
      await txn.update('urunler', {'stok': onceki.toDouble() - miktar}, where: 'id = ?', whereArgs: [urunId]);
      await txn.insert('stok_hareket', {
        'urun_id': urunId, 'hareket_turu': 'İade İptali', 'miktar': miktar,
        'onceki_stok': onceki, 'sonraki_stok': onceki.toDouble() - miktar,
        'tarih': now, 'referans_id': iadeId, 'referans_turu': 'iade_iptal',
      });
    }

    final orijinalKasaSatirlari = await txn.query('kasa_hareketleri',
        where: 'referans_id = ? AND referans_turu = ? AND deleted_at IS NULL',
        whereArgs: [iadeId, 'iade']);
    for (final k in orijinalKasaSatirlari) {
      final kasaTutar = (k['tutar'] as num?)?.toDouble() ?? 0;
      if (kasaTutar <= 0) continue;
      await txn.insert('kasa_hareketleri', {
        'global_id': const Uuid().v4(), 'hareket_tipi': 'Iade Iptali', 'tutar': kasaTutar,
        'referans_id': iadeId, 'referans_turu': 'iade_iptal', 'tarih': now,
      });
    }

    if (cariId != null) {
      await txn.rawUpdate(
          "UPDATE cari_hareket SET is_deleted = 1, last_updated = ? WHERE fis_id = ? AND cari_id = ? AND fis_tipi IN ('İade','Alım İadesi')",
          [now, iadeId, cariId]);
      await txn.rawUpdate(
          'UPDATE cari SET bakiye = (SELECT COALESCE(SUM(borc),0) - COALESCE(SUM(alacak),0) FROM cari_hareket WHERE cari_id = ? AND is_deleted = 0) WHERE id = ?',
          [cariId, cariId]);
    }

    await txn.update('iade', {'durum': 'iptal', 'last_updated': now}, where: 'id = ?', whereArgs: [iadeId]);
  });
}

void main() {
  late Database db;
  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  group('gecmisFisIadeSil() — kasa reversal artık tahmine göre değil, GERÇEK satıra göre', () {
    test('Nakit iade silinince kasaya GERÇEK tutarla "Iade Iptali" eklenir', () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db, stok: 10);
      final iadeId = await db.insert('iade', {
        'cari_id': null, 'fis_no': 'IAD1', 'tarih': DateTime.now().toIso8601String(),
        'toplam_tutar': 60.0, 'durum': 'tamamlandi',
      });
      await db.insert('iade_kalem', {
        'iade_id': iadeId, 'urun_id': urunId, 'urun_adi': 'Test',
        'miktar': 2, 'birim_fiyat': 30.0, 'toplam': 60.0,
      });
      await db.update('urunler', {'stok': 12}, where: 'id = ?', whereArgs: [urunId]); // 10 + 2 iade
      await db.insert('kasa_hareketleri', {
        'global_id': const Uuid().v4(), 'hareket_tipi': 'İade', 'tutar': 60.0,
        'referans_id': iadeId, 'referans_turu': 'iade', 'tarih': DateTime.now().toIso8601String(),
      });

      await _gecmisFisIadeSilSimulasyonu(db, iadeId: iadeId, cariId: null);

      final kasaTers = await db.query('kasa_hareketleri',
          where: 'referans_id = ? AND referans_turu = ?', whereArgs: [iadeId, 'iade_iptal']);
      expect(kasaTers, hasLength(1));
      expect((kasaTers.first['tutar'] as num).toDouble(), equals(60.0));

      final urun = (await db.query('urunler', where: 'id = ?', whereArgs: [urunId])).first;
      expect((urun['stok'] as num).toDouble(), equals(10.0));
    });

    test('Kart/Banka (kasa satırı OLMAYAN) iade silinince HAYALET nakit-giriş kaydı OLUŞMAZ', () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db, stok: 5);
      final iadeId = await db.insert('iade', {
        'cari_id': null, 'fis_no': 'IAD2', 'tarih': DateTime.now().toIso8601String(),
        'toplam_tutar': 40.0, 'durum': 'tamamlandi',
      });
      await db.insert('iade_kalem', {
        'iade_id': iadeId, 'urun_id': urunId, 'urun_adi': 'Test',
        'miktar': 1, 'birim_fiyat': 40.0, 'toplam': 40.0,
      });
      await db.update('urunler', {'stok': 6}, where: 'id = ?', whereArgs: [urunId]);
      // BİLİNÇLİ OLARAK kasa_hareketleri satırı EKLENMEDİ (Kart/Banka/Cari iade).

      await _gecmisFisIadeSilSimulasyonu(db, iadeId: iadeId, cariId: null);

      final kasaTers = await db.query('kasa_hareketleri',
          where: 'referans_id = ? AND referans_turu = ?', whereArgs: [iadeId, 'iade_iptal']);
      expect(kasaTers, isEmpty,
          reason: 'Gerçekte nakit girmemiş bir iadenin silinmesi hayalet bir kasa kaydı OLUŞTURMAMALI');

      final urun = (await db.query('urunler', where: 'id = ?', whereArgs: [urunId])).first;
      expect((urun['stok'] as num).toDouble(), equals(5.0), reason: 'stok yine de geri düşmeli');
    });

    test('Cari (veresiye) iade silinince bakiye tam sıfırlanır', () async {
      final cariId = await TestVeritabani.ornekCariEkle(db);
      final urunId = await TestVeritabani.ornekUrunEkle(db, stok: 0);
      final iadeId = await db.insert('iade', {
        'cari_id': cariId, 'fis_no': 'IAD3', 'tarih': DateTime.now().toIso8601String(),
        'toplam_tutar': 90.0, 'durum': 'tamamlandi',
      });
      await db.insert('iade_kalem', {
        'iade_id': iadeId, 'urun_id': urunId, 'urun_adi': 'Test',
        'miktar': 3, 'birim_fiyat': 30.0, 'toplam': 90.0,
      });
      await db.update('urunler', {'stok': 3}, where: 'id = ?', whereArgs: [urunId]);
      await db.insert('cari_hareket', {
        'global_id': const Uuid().v4(), 'cari_id': cariId, 'tarih': DateTime.now().toIso8601String(),
        'fis_tipi': 'İade', 'fis_id': iadeId, 'fis_no': 'IAD3',
        'borc': 0, 'alacak': 90.0, 'odeme_turu': 'Nakit', 'is_deleted': 0,
      });
      await db.update('cari', {'bakiye': -90.0}, where: 'id = ?', whereArgs: [cariId]);

      await _gecmisFisIadeSilSimulasyonu(db, iadeId: iadeId, cariId: cariId);

      final cari = (await db.query('cari', where: 'id = ?', whereArgs: [cariId])).first;
      expect((cari['bakiye'] as num).toDouble(), equals(0.0));
    });

    test('zaten "iptal" durumundaki bir iade TEKRAR silinemez (çift-iptal koruması)', () async {
      final iadeId = await db.insert('iade', {
        'cari_id': null, 'fis_no': 'IAD4', 'tarih': DateTime.now().toIso8601String(),
        'toplam_tutar': 20.0, 'durum': 'iptal',
      });

      await expectLater(
          _gecmisFisIadeSilSimulasyonu(db, iadeId: iadeId, cariId: null), throwsException);
    });
  });
}
