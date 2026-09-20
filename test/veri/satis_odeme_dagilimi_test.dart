// test/veri/satis_odeme_dagilimi_test.dart
//
// Kullanıcı bulgusu (2026-09-20): Satış Detayı'ndaki "Ödeme Yöntemi"
// alanı Karma ödemede sadece düz "Karma" yazıyordu, hangi yöntemden ne
// kadar ödendiği görünmüyordu. SatisDeposu.odemeDagilimiGetir() ile
// AYNI SQL, SatisDeposu Veritabani() singleton'ına bağımlı olduğundan
// (projenin yerleşik test deseni) gerçek şema üzerinde doğrulanıyor.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import '../helper/test_initializer.dart';

Future<List<Map<String, dynamic>>> _odemeDagilimiGetir(Database db, int satisId) async {
  final sonuc = <Map<String, dynamic>>[];

  final kasaRows = await db.rawQuery('''
    SELECT odeme_yontemi, COALESCE(SUM(tutar), 0) AS tutar
    FROM kasa_hareketleri
    WHERE referans_id = ? AND referans_turu = 'satis' AND deleted_at IS NULL
    GROUP BY odeme_yontemi
  ''', [satisId]);
  for (final r in kasaRows) {
    final tutar = (r['tutar'] as num?)?.toDouble() ?? 0;
    if (tutar <= 0.005) continue;
    sonuc.add({'yontem': r['odeme_yontemi'] as String? ?? '—', 'tutar': tutar});
  }

  final cariRows = await db.rawQuery('''
    SELECT COALESCE(SUM(borc), 0) AS tutar
    FROM cari_hareket
    WHERE fis_id = ? AND fis_tipi = 'Satış' AND alacak = 0 AND borc > 0 AND is_deleted = 0
  ''', [satisId]);
  final cariTutar = (cariRows.first['tutar'] as num?)?.toDouble() ?? 0;
  if (cariTutar > 0.005) {
    sonuc.add({'yontem': 'Cari', 'tutar': cariTutar});
  }

  return sonuc;
}

void main() {
  late Database db;
  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  test('Karma (Nakit+Kart) satış — her yöntem kendi tutarıyla ayrı satır döner', () async {
    const satisId = 1;
    await db.insert('kasa_hareketleri', {
      'hareket_tipi': 'Satış', 'tutar': 50, 'odeme_yontemi': 'Nakit',
      'referans_id': satisId, 'referans_turu': 'satis', 'tarih': DateTime(2026, 9, 20).toIso8601String(),
    });
    await db.insert('kasa_hareketleri', {
      'hareket_tipi': 'Satış', 'tutar': 30, 'odeme_yontemi': 'Kredi Kartı',
      'referans_id': satisId, 'referans_turu': 'satis', 'tarih': DateTime(2026, 9, 20).toIso8601String(),
    });

    final dagilim = await _odemeDagilimiGetir(db, satisId);

    expect(dagilim, hasLength(2));
    final map = {for (final d in dagilim) d['yontem']: d['tutar']};
    expect(map['Nakit'], 50.0);
    expect(map['Kredi Kartı'], 30.0);
  });

  test('Karma (Nakit+Cari) satış — Cari payı gerçek borç satırından (self-cancelling HARİÇ)', () async {
    const satisId = 2;
    await db.insert('kasa_hareketleri', {
      'hareket_tipi': 'Satış', 'tutar': 50, 'odeme_yontemi': 'Nakit',
      'referans_id': satisId, 'referans_turu': 'satis', 'tarih': DateTime(2026, 9, 20).toIso8601String(),
    });
    // gerçek Cari borcu
    await db.insert('cari_hareket', {
      'cari_id': 1, 'fis_tipi': 'Satış', 'fis_id': satisId, 'fis_no': 'F2',
      'borc': 50, 'alacak': 0, 'odeme_turu': 'Cari', 'tarih': DateTime(2026, 9, 20).toIso8601String(),
    });
    // bakiyeyi etkilemeyen bilgi satırı — dağılıma DAHİL EDİLMEMELİ
    await db.insert('cari_hareket', {
      'cari_id': 1, 'fis_tipi': 'Satış', 'fis_id': satisId, 'fis_no': 'F2',
      'borc': 50, 'alacak': 50, 'odeme_turu': 'Nakit', 'tarih': DateTime(2026, 9, 20).toIso8601String(),
    });

    final dagilim = await _odemeDagilimiGetir(db, satisId);

    expect(dagilim, hasLength(2));
    final map = {for (final d in dagilim) d['yontem']: d['tutar']};
    expect(map['Nakit'], 50.0);
    expect(map['Cari'], 50.0, reason: 'sadece gerçek borç satırından gelmeli, self-cancelling satır SAYILMAMALI');
  });

  test('tek yöntemli (Karma olmayan) Nakit satış — tek elemanlı liste döner', () async {
    const satisId = 3;
    await db.insert('kasa_hareketleri', {
      'hareket_tipi': 'Satış', 'tutar': 100, 'odeme_yontemi': 'Nakit',
      'referans_id': satisId, 'referans_turu': 'satis', 'tarih': DateTime(2026, 9, 20).toIso8601String(),
    });

    final dagilim = await _odemeDagilimiGetir(db, satisId);

    expect(dagilim, hasLength(1));
    expect(dagilim.first['yontem'], 'Nakit');
    expect(dagilim.first['tutar'], 100.0);
  });

  test('sadece Cari (veresiye) satış — dağılım tek "Cari" satırı döner', () async {
    const satisId = 4;
    await db.insert('cari_hareket', {
      'cari_id': 1, 'fis_tipi': 'Satış', 'fis_id': satisId, 'fis_no': 'F4',
      'borc': 100, 'alacak': 0, 'odeme_turu': 'Cari', 'tarih': DateTime(2026, 9, 20).toIso8601String(),
    });

    final dagilim = await _odemeDagilimiGetir(db, satisId);

    expect(dagilim, hasLength(1));
    expect(dagilim.first['yontem'], 'Cari');
    expect(dagilim.first['tutar'], 100.0);
  });

  test('silinmiş (deleted_at dolu) kasa hareketi dağılıma dahil edilmez', () async {
    const satisId = 5;
    await db.insert('kasa_hareketleri', {
      'hareket_tipi': 'Satış', 'tutar': 100, 'odeme_yontemi': 'Nakit',
      'referans_id': satisId, 'referans_turu': 'satis',
      'tarih': DateTime(2026, 9, 20).toIso8601String(),
      'deleted_at': DateTime.now().toIso8601String(),
    });

    final dagilim = await _odemeDagilimiGetir(db, satisId);

    expect(dagilim, isEmpty);
  });

  test('başka bir satışın hareketleri karışmaz (referans_id filtresi)', () async {
    await db.insert('kasa_hareketleri', {
      'hareket_tipi': 'Satış', 'tutar': 999, 'odeme_yontemi': 'Nakit',
      'referans_id': 777, 'referans_turu': 'satis', 'tarih': DateTime(2026, 9, 20).toIso8601String(),
    });

    final dagilim = await _odemeDagilimiGetir(db, 6);

    expect(dagilim, isEmpty);
  });
}
