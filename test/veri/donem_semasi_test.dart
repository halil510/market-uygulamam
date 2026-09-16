// test/veri/donem_semasi_test.dart
//
// Yıl Sonu Devir / Dönem Kapatma / Arşivleme sistemi — FAZ 1 (2026-09-16,
// kullanıcı onaylı mimari plan raporu). Depo sınıfları (DonemDeposu,
// DevirCheckpointDeposu) Veritabani() singleton'ı üzerinden çalıştığı
// için (diğer depo testlerinde olduğu gibi, bkz.
// vardiya_nakit_mutabakat_test.dart yorumu) burada ŞEMANIN KENDİSİ —
// tablo varlığı + UNIQUE kısıtlarının tasarlandığı gibi davranması —
// gerçek şema üzerinde doğrulanıyor.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import '../helper/test_initializer.dart';

void main() {
  late Database db;
  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  group('Yıl Sonu Devir şeması — tablolar oluşuyor', () {
    for (final tablo in [
      'donemler',
      'donem_sube_durumlari',
      'devir_checkpoint',
      'stok_kapanis_snapshot',
      'cari_kapanis_snapshot',
      'kasa_kapanis_snapshot',
      'banka_kapanis_snapshot',
    ]) {
      test('$tablo tablosu mevcut ve sorgulanabilir', () async {
        final rows = await db.query(tablo);
        expect(rows, isEmpty); // taze DB'de boş ama hata vermeden dönmeli
      });
    }
  });

  group('donemler — UNIQUE(donem_yili)', () {
    test('aynı yıl iki kez eklenemez', () async {
      await db.insert('donemler', {
        'donem_yili': 2026,
        'baslangic_tarihi': '2026-01-01',
        'bitis_tarihi': '2026-12-31',
      });
      expect(
        () => db.insert('donemler', {
          'donem_yili': 2026,
          'baslangic_tarihi': '2026-01-01',
          'bitis_tarihi': '2026-12-31',
        }),
        throwsA(anything),
      );
    });

    test('varsayılan durum OPEN, alt-durumlar bekliyor', () async {
      final id = await db.insert('donemler', {
        'donem_yili': 2027,
        'baslangic_tarihi': '2027-01-01',
        'bitis_tarihi': '2027-12-31',
      });
      final rows = await db.query('donemler', where: 'id = ?', whereArgs: [id]);
      expect(rows.first['durum'], 'OPEN');
      expect(rows.first['backup_durumu'], 'bekliyor');
      expect(rows.first['arsiv_durumu'], 'bekliyor');
      expect(rows.first['devir_durumu'], 'bekliyor');
    });
  });

  group('donem_sube_durumlari — UNIQUE(donem_id, sube_id)', () {
    test('aynı (donem_id, sube_id) çifti iki kez eklenemez', () async {
      final donemId = await db.insert('donemler', {
        'donem_yili': 2026,
        'baslangic_tarihi': '2026-01-01',
        'bitis_tarihi': '2026-12-31',
      });
      await db.insert('donem_sube_durumlari', {'donem_id': donemId, 'sube_id': 1});
      expect(
        () => db.insert('donem_sube_durumlari', {'donem_id': donemId, 'sube_id': 1}),
        throwsA(anything),
      );
      // Farklı şube — sorun olmamalı
      await db.insert('donem_sube_durumlari', {'donem_id': donemId, 'sube_id': 2});
      final rows = await db.query('donem_sube_durumlari', where: 'donem_id = ?', whereArgs: [donemId]);
      expect(rows, hasLength(2));
    });
  });

  group('devir_checkpoint — UNIQUE(kaynak,hedef,sube) ile 0-sentinel', () {
    test('sube_id=0 (şirket geneli) ile aynı kombinasyon iki kez eklenemez', () async {
      // 🔴 Bu test, donem_semasi.dart baş yorumunda açıklanan tasarım
      // kararını doğrular: sube_id NULL olsaydı SQLite UNIQUE kısıtı bu
      // ikinci INSERT'i ENGELLEMEZDİ (NULL != NULL). 0 sentinel ile
      // güvenilir şekilde engelleniyor.
      await db.insert('devir_checkpoint', {
        'devir_id': 'd-1',
        'kaynak_donem_id': 1,
        'hedef_donem_id': 2,
        'sube_id': 0,
      });
      expect(
        () => db.insert('devir_checkpoint', {
          'devir_id': 'd-2',
          'kaynak_donem_id': 1,
          'hedef_donem_id': 2,
          'sube_id': 0,
        }),
        throwsA(anything),
      );
    });

    test('devir_id UNIQUE — aynı devir_id iki farklı satırda olamaz', () async {
      await db.insert('devir_checkpoint', {
        'devir_id': 'd-tekil',
        'kaynak_donem_id': 1,
        'hedef_donem_id': 2,
        'sube_id': 1,
      });
      expect(
        () => db.insert('devir_checkpoint', {
          'devir_id': 'd-tekil',
          'kaynak_donem_id': 1,
          'hedef_donem_id': 2,
          'sube_id': 2, // farklı şube ama AYNI devir_id
        }),
        throwsA(anything),
      );
    });

    test('varsayılan durum INIT, mevcut_faz 0', () async {
      final id = await db.insert('devir_checkpoint', {
        'devir_id': 'd-3',
        'kaynak_donem_id': 1,
        'hedef_donem_id': 2,
        'sube_id': 1,
      });
      final rows = await db.query('devir_checkpoint', where: 'id = ?', whereArgs: [id]);
      expect(rows.first['durum'], 'INIT');
      expect(rows.first['mevcut_faz'], 0);
    });
  });

  group('Kapanış snapshot tabloları — UNIQUE kısıtları', () {
    test('stok_kapanis_snapshot: UNIQUE(donem_id, sube_id, urun_id)', () async {
      await db.insert('stok_kapanis_snapshot',
          {'devir_id': 'd-1', 'donem_id': 1, 'sube_id': 1, 'urun_id': 100, 'miktar': 50});
      expect(
        () => db.insert('stok_kapanis_snapshot',
            {'devir_id': 'd-1', 'donem_id': 1, 'sube_id': 1, 'urun_id': 100, 'miktar': 999}),
        throwsA(anything),
      );
    });

    test('cari_kapanis_snapshot: UNIQUE(donem_id, cari_id)', () async {
      await db.insert('cari_kapanis_snapshot', {'devir_id': 'd-1', 'donem_id': 1, 'cari_id': 5, 'bakiye': 1000});
      expect(
        () => db.insert('cari_kapanis_snapshot', {'devir_id': 'd-1', 'donem_id': 1, 'cari_id': 5, 'bakiye': 0}),
        throwsA(anything),
      );
    });

    test('kasa_kapanis_snapshot: UNIQUE(donem_id, sube_id)', () async {
      await db.insert('kasa_kapanis_snapshot', {'devir_id': 'd-1', 'donem_id': 1, 'sube_id': 1, 'bakiye': 500});
      expect(
        () => db.insert('kasa_kapanis_snapshot', {'devir_id': 'd-1', 'donem_id': 1, 'sube_id': 1, 'bakiye': 0}),
        throwsA(anything),
      );
    });

    test('banka_kapanis_snapshot: UNIQUE(donem_id, banka_hesap_id)', () async {
      await db.insert('banka_kapanis_snapshot',
          {'devir_id': 'd-1', 'donem_id': 1, 'banka_hesap_id': 7, 'bakiye': 250});
      expect(
        () => db.insert('banka_kapanis_snapshot',
            {'devir_id': 'd-1', 'donem_id': 1, 'banka_hesap_id': 7, 'bakiye': 0}),
        throwsA(anything),
      );
    });
  });
}
