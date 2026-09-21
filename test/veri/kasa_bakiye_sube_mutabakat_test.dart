// test/veri/kasa_bakiye_sube_mutabakat_test.dart
//
// FAZ 1 — DEEP_AUDIT_REPORT_2026-09-20.md madde 2 ("[HIGH] Çok şubeli
// kasa mutabakat düzeltmesi şube karıştırıyor"):
// KasaDeposu.hareketSil() / bakiyeMutabakatYap() / bakiyeUyumsuzlukSayisi()
// ÖNCEDEN 'bakiye_sonrasi' zincirini TÜM şubelerin hareketlerini TEK bir
// sırada karıştırarak yeniden hesaplıyordu — "düzelt" aksiyonu aslında
// farklı şubelerin bakiyelerini birbirine karıştırarak veriyi BOZUYORDU.
// Düzeltme: her şube (ve sube_id NULL olan eski kayıtlar) KENDİ bağımsız
// zincirinde, sıfırdan yeniden hesaplanıyor.
//
// KasaDeposu bu üç metodda Veritabani() singleton'ı (_d) üzerinden
// çalıştığı için — diğer depo testlerinde olduğu gibi (bkz.
// vardiya_nakit_mutabakat_test.dart'taki AYNI gerekçe) — burada
// kasa_deposu.dart'taki DÜZELTİLMİŞ algoritma BİREBİR AYNI SQL/mantıkla,
// gerçek şema üzerinde bir in-memory veritabanında doğrudan doğrulanıyor.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import '../helper/test_initializer.dart';

const _girisler = {
  'Satış', 'Tahsilat', 'AçılışKasa', 'Giriş', 'Virman Giriş',
  'Iade Iptali', 'İade İptali', 'Ödeme Girişi', 'Gider İptali',
};

/// KasaDeposu.bakiyeMutabakatYap() ile BİREBİR AYNI (düzeltilmiş) mantık.
Future<int> _bakiyeMutabakatYap(Database db) async {
  final now = DateTime.now().toIso8601String();
  var duzeltilen = 0;
  await db.transaction((txn) async {
    final subeRows = await txn.rawQuery(
        'SELECT DISTINCT sube_id FROM kasa_hareketleri WHERE deleted_at IS NULL');
    for (final sr in subeRows) {
      final subeId = sr['sube_id'] as int?;
      final rows = subeId != null
          ? await txn.query('kasa_hareketleri',
              where: 'deleted_at IS NULL AND sube_id = ?',
              whereArgs: [subeId],
              orderBy: 'tarih ASC, id ASC')
          : await txn.query('kasa_hareketleri',
              where: 'deleted_at IS NULL AND sube_id IS NULL',
              orderBy: 'tarih ASC, id ASC');
      double bakiye = 0;
      for (final r in rows) {
        final tip = r['hareket_tipi'] as String? ?? '';
        final tutar = (r['tutar'] as num?)?.toDouble() ?? 0;
        bakiye = _girisler.contains(tip) ? bakiye + tutar : bakiye - tutar;
        final mevcut = (r['bakiye_sonrasi'] as num?)?.toDouble();
        if (mevcut == null || (mevcut - bakiye).abs() > 0.01) {
          await txn.update('kasa_hareketleri',
              {'bakiye_sonrasi': bakiye, 'last_updated': now},
              where: 'id = ?', whereArgs: [r['id']]);
          duzeltilen++;
        }
      }
    }
  });
  return duzeltilen;
}

/// KasaDeposu.hareketSil() ile BİREBİR AYNI (düzeltilmiş) yeniden
/// hesaplama bloğu — silme sonrası.
Future<void> _hareketSil(Database db, int id) async {
  final now = DateTime.now().toIso8601String();
  await db.transaction((txn) async {
    await txn.update(
        'kasa_hareketleri', {'deleted_at': now, 'last_updated': now},
        where: 'id = ?', whereArgs: [id]);
    final subeRows = await txn.rawQuery(
        'SELECT DISTINCT sube_id FROM kasa_hareketleri WHERE deleted_at IS NULL');
    for (final sr in subeRows) {
      final subeId = sr['sube_id'] as int?;
      final rows = subeId != null
          ? await txn.query('kasa_hareketleri',
              where: 'deleted_at IS NULL AND sube_id = ?',
              whereArgs: [subeId],
              orderBy: 'tarih ASC, id ASC')
          : await txn.query('kasa_hareketleri',
              where: 'deleted_at IS NULL AND sube_id IS NULL',
              orderBy: 'tarih ASC, id ASC');
      double bakiye = 0;
      for (final r in rows) {
        final tip = r['hareket_tipi'] as String? ?? '';
        final tutar = (r['tutar'] as num?)?.toDouble() ?? 0;
        bakiye = _girisler.contains(tip) ? bakiye + tutar : bakiye - tutar;
        await txn.update('kasa_hareketleri',
            {'bakiye_sonrasi': bakiye, 'last_updated': now},
            where: 'id = ?', whereArgs: [r['id']]);
      }
    }
  });
}

Future<double?> _bakiyeSonrasi(Database db, int id) async {
  final rows = await db.query('kasa_hareketleri',
      columns: ['bakiye_sonrasi'], where: 'id = ?', whereArgs: [id]);
  return (rows.first['bakiye_sonrasi'] as num?)?.toDouble();
}

void main() {
  late Database db;
  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  group('KasaDeposu şube bazlı bakiye mutabakatı (Madde 2 regresyonu)', () {
    test(
        'bakiyeMutabakatYap — 2 şubenin hareketleri interleaved eklenince '
        'BİRBİRİNE KARIŞMADAN, her şube kendi bağımsız zincirinde hesaplanır',
        () async {
      final t0 = DateTime(2026, 9, 21, 9, 0);
      // Interleaved id sırası: Şube1(+100), Şube2(+50), Şube1(+30) —
      // eski (buggy) kod TEK zincirde 100 → 150 → 180 üretirdi.
      final id1 = await db.insert('kasa_hareketleri', {
        'hareket_tipi': 'Satış', 'tutar': 100, 'sube_id': 1,
        'tarih': t0.toIso8601String(),
      });
      final id2 = await db.insert('kasa_hareketleri', {
        'hareket_tipi': 'Satış', 'tutar': 50, 'sube_id': 2,
        'tarih': t0.add(const Duration(minutes: 1)).toIso8601String(),
      });
      final id3 = await db.insert('kasa_hareketleri', {
        'hareket_tipi': 'Tahsilat', 'tutar': 30, 'sube_id': 1,
        'tarih': t0.add(const Duration(minutes: 2)).toIso8601String(),
      });

      final duzeltilen = await _bakiyeMutabakatYap(db);
      expect(duzeltilen, 3);

      // Şube 1 KENDİ zincirinde: 100 → 130 (Şube 2'nin 50'si karışmıyor).
      expect(await _bakiyeSonrasi(db, id1), 100);
      expect(await _bakiyeSonrasi(db, id3), 130);
      // Şube 2 KENDİ zincirinde: sadece 50.
      expect(await _bakiyeSonrasi(db, id2), 50);
    });

    test(
        'hareketSil — Şube 2 hareketi silinince Şube 1 zinciri ETKİLENMEZ',
        () async {
      final t0 = DateTime(2026, 9, 21, 9, 0);
      final id1 = await db.insert('kasa_hareketleri', {
        'hareket_tipi': 'Satış', 'tutar': 100, 'sube_id': 1,
        'tarih': t0.toIso8601String(), 'bakiye_sonrasi': 100,
      });
      final id2 = await db.insert('kasa_hareketleri', {
        'hareket_tipi': 'Satış', 'tutar': 50, 'sube_id': 2,
        'tarih': t0.add(const Duration(minutes: 1)).toIso8601String(),
        'bakiye_sonrasi': 50,
      });
      final id3 = await db.insert('kasa_hareketleri', {
        'hareket_tipi': 'Tahsilat', 'tutar': 30, 'sube_id': 1,
        'tarih': t0.add(const Duration(minutes: 2)).toIso8601String(),
        'bakiye_sonrasi': 130,
      });

      await _hareketSil(db, id2);

      // Şube 1 zinciri Şube 2'deki silme işleminden ETKİLENMEMELİ.
      expect(await _bakiyeSonrasi(db, id1), 100);
      expect(await _bakiyeSonrasi(db, id3), 130);
    });

    test(
        'sube_id NULL olan eski kayıtlar KENDİ ayrı grubunda hesaplanır, '
        'şube 1 ile karışmaz', () async {
      final t0 = DateTime(2026, 9, 21, 9, 0);
      final idNull = await db.insert('kasa_hareketleri', {
        'hareket_tipi': 'Satış', 'tutar': 20, 'sube_id': null,
        'tarih': t0.toIso8601String(),
      });
      final id1 = await db.insert('kasa_hareketleri', {
        'hareket_tipi': 'Satış', 'tutar': 100, 'sube_id': 1,
        'tarih': t0.add(const Duration(minutes: 1)).toIso8601String(),
      });

      await _bakiyeMutabakatYap(db);

      expect(await _bakiyeSonrasi(db, idNull), 20);
      expect(await _bakiyeSonrasi(db, id1), 100);
    });
  });
}
