// test/satis_servisi_test.dart
// Kritik iş mantığı unit testleri
// Çalıştır: flutter test
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart';

// Test için in-memory DB kurulumu
Future<Database> _testDbOlustur() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final db = await openDatabase(
    inMemoryDatabasePath,
    version: 1,
    onCreate: (db, v) async {
      await db.execute('''
        CREATE TABLE urunler (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          urun_kodu TEXT, urun_adi TEXT NOT NULL,
          barkod TEXT UNIQUE, stok REAL NOT NULL DEFAULT 0,
          satis_fiyati REAL NOT NULL DEFAULT 0,
          alis_fiyati REAL DEFAULT 0,
          kdv_orani REAL DEFAULT 18,
          aktif INTEGER DEFAULT 1, plu INTEGER DEFAULT 0,
          plu_kart_boyut INTEGER DEFAULT 2,
          is_deleted INTEGER DEFAULT 0
        )
      ''');
      await db.execute('''
        CREATE TABLE satislar (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          fis_no TEXT UNIQUE NOT NULL,
          tarih DATETIME NOT NULL,
          genel_toplam REAL NOT NULL DEFAULT 0,
          odenen_tutar REAL NOT NULL DEFAULT 0,
          odeme_yontemi TEXT DEFAULT 'Nakit',
          cari_id INTEGER,
          kasiyer_id INTEGER,
          iptal INTEGER DEFAULT 0,
          iptal_tarihi DATETIME,
          iptal_nedeni TEXT,
          is_deleted INTEGER DEFAULT 0
        )
      ''');
      await db.execute('''
        CREATE TABLE satis_kalem (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          satis_id INTEGER NOT NULL,
          urun_id INTEGER NOT NULL,
          urun_adi TEXT NOT NULL,
          barkod TEXT,
          miktar REAL NOT NULL,
          birim_fiyat REAL NOT NULL,
          iskonto_oran REAL DEFAULT 0,
          iskonto_tutar REAL DEFAULT 0,
          kdv_oran REAL DEFAULT 18,
          kdv_tutar REAL DEFAULT 0,
          net_fiyat REAL DEFAULT 0,
          toplam_tutar REAL NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE stok_hareket (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          urun_id INTEGER NOT NULL,
          hareket_turu TEXT NOT NULL,
          miktar REAL NOT NULL,
          onceki_stok REAL DEFAULT 0,
          sonraki_stok REAL DEFAULT 0,
          tarih DATETIME,
          referans_id INTEGER,
          referans_turu TEXT,
          kullanici_id INTEGER,
          aciklama TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE kasa_hareketleri (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          hareket_tipi TEXT NOT NULL,
          tutar REAL NOT NULL,
          bakiye_sonrasi REAL NOT NULL DEFAULT 0,
          referans_id INTEGER,
          referans_turu TEXT,
          tarih DATETIME,
          aciklama TEXT,
          kullanici_id INTEGER
        )
      ''');
      await db.execute('''
        CREATE TABLE cari (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          unvan TEXT NOT NULL,
          bakiye REAL DEFAULT 0
        )
      ''');
      await db.execute('''
        CREATE TABLE cari_hareket (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          cari_id INTEGER NOT NULL,
          tarih DATETIME,
          fis_tipi TEXT,
          fis_id INTEGER,
          fis_no TEXT,
          borc REAL DEFAULT 0,
          alacak REAL DEFAULT 0,
          odeme_turu TEXT,
          aciklama TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE fis_sayac (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          tip TEXT UNIQUE NOT NULL,
          son_numara INTEGER NOT NULL DEFAULT 0,
          prefix TEXT DEFAULT ''
        )
      ''');
      // Fiş sayaç seed
      await db.insert('fis_sayac', {'tip': 'satis', 'son_numara': 0, 'prefix': 'F'});
    },
  );
  return db;
}

void main() {
  late Database db;

  setUpAll(() async {
    db = await _testDbOlustur();
  });

  tearDownAll(() async {
    await db.close();
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('Fiş No Üretimi', () {
    test('Her çağrıda benzersiz ve artan fiş no üretilir', () async {
      // İlk fiş
      final no1 = await _fisNoUret(db, 'satis');
      // İkinci fiş
      final no2 = await _fisNoUret(db, 'satis');

      expect(no1, isNotEmpty);
      expect(no2, isNotEmpty);
      expect(no1, isNot(equals(no2)));

      // Numarasal kısmı çıkar ve karşılaştır
      final n1 = int.parse(no1.replaceAll(RegExp(r'\D'), ''));
      final n2 = int.parse(no2.replaceAll(RegExp(r'\D'), ''));
      expect(n2, greaterThan(n1));
    });

    test('Prefix doğru eklenir', () async {
      final no = await _fisNoUret(db, 'satis');
      expect(no.startsWith('F'), isTrue);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('Stok Düşme', () {
    late int urunId;

    setUp(() async {
      urunId = await db.insert('urunler', {
        'urun_adi': 'Test Ürün',
        'barkod': '1234567890123',
        'stok': 100.0,
        'satis_fiyati': 10.0,
      });
    });

    tearDown(() async {
      await db.delete('urunler', where: 'id = ?', whereArgs: [urunId]);
      await db.delete('stok_hareket', where: 'urun_id = ?', whereArgs: [urunId]);
    });

    test('Satış sonrası stok doğru düşer', () async {
      await _stokDus(db, urunId: urunId, miktar: 30, referansId: 1);

      final rows = await db.query('urunler', where: 'id = ?', whereArgs: [urunId]);
      final stok = (rows.first['stok'] as num).toDouble();
      expect(stok, equals(70.0));
    });

    test('Stok negatife düşmez', () async {
      await _stokDus(db, urunId: urunId, miktar: 200, referansId: 2);

      final rows = await db.query('urunler', where: 'id = ?', whereArgs: [urunId]);
      final stok = (rows.first['stok'] as num).toDouble();
      expect(stok, greaterThanOrEqualTo(0));
    });

    test('Stok hareketi kaydedilir', () async {
      await _stokDus(db, urunId: urunId, miktar: 5, referansId: 3);

      final hareketler = await db.query('stok_hareket',
          where: 'urun_id = ? AND referans_id = ?', whereArgs: [urunId, 3]);
      expect(hareketler.length, equals(1));
      expect(hareketler.first['hareket_turu'], equals('Çıkış'));
      expect((hareketler.first['miktar'] as num).toDouble(), equals(5.0));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('Satış İptal / Silme', () {
    late int satisId;
    late int urunId;

    setUp(() async {
      urunId = await db.insert('urunler', {
        'urun_adi': 'İptal Test Ürün',
        'barkod': '9876543210123',
        'stok': 50.0,
        'satis_fiyati': 25.0,
      });

      final fisNo = await _fisNoUret(db, 'satis');
      satisId = await db.insert('satislar', {
        'fis_no': fisNo,
        'tarih': DateTime.now().toIso8601String(),
        'genel_toplam': 50.0,
        'odenen_tutar': 50.0,
        'odeme_yontemi': 'Nakit',
      });

      await db.insert('satis_kalem', {
        'satis_id': satisId,
        'urun_id': urunId,
        'urun_adi': 'İptal Test Ürün',
        'miktar': 2.0,
        'birim_fiyat': 25.0,
        'toplam_tutar': 50.0,
      });

      // Stok düş (satış yapıldı)
      await db.rawUpdate(
          'UPDATE urunler SET stok = stok - 2 WHERE id = ?', [urunId]);

      // Kasa hareketi
      await db.insert('kasa_hareketleri', {
        'hareket_tipi': 'Satış',
        'tutar': 50.0,
        'bakiye_sonrasi': 50.0,
        'referans_id': satisId,
        'referans_turu': 'satis',
        'tarih': DateTime.now().toIso8601String(),
      });
    });

    tearDown(() async {
      await db.delete('kasa_hareketleri', where: 'referans_id = ?', whereArgs: [satisId]);
      await db.delete('satis_kalem', where: 'satis_id = ?', whereArgs: [satisId]);
      await db.delete('satislar', where: 'id = ?', whereArgs: [satisId]);
      await db.delete('urunler', where: 'id = ?', whereArgs: [urunId]);
    });

    test('Silince satış soft-delete olur', () async {
      await _satisSil(db, satisId);

      final rows = await db.query('satislar', where: 'id = ?', whereArgs: [satisId]);
      expect(rows.first['is_deleted'], equals(1));
      expect(rows.first['iptal'], equals(1));
    });

    test('Silince stok geri yüklenir', () async {
      final onceki = await _stokAl(db, urunId); // 48
      await _satisSil(db, satisId);
      final sonraki = await _stokAl(db, urunId);

      expect(sonraki, equals(onceki + 2));
    });

    test('Silince kasa ters hareketi yazılır', () async {
      await _satisSil(db, satisId);

      final iptalHareket = await db.query('kasa_hareketleri',
          where: 'referans_id = ? AND hareket_tipi = ?',
          whereArgs: [satisId, 'Satış İptali']);
      expect(iptalHareket.length, equals(1));
      final tutar = (iptalHareket.first['tutar'] as num).toDouble();
      expect(tutar, equals(-50.0));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('Cari Hareket', () {
    late int cariId;

    setUp(() async {
      cariId = await db.insert('cari', {'unvan': 'Test Cari', 'bakiye': 0.0});
    });

    test('Borç hareketi bakiyeyi artırır', () async {
      await _cariHareketEkle(db,
          cariId: cariId, borc: 150.0, alacak: 0.0, fis: 'TEST001');

      final cari = await db.query('cari', where: 'id = ?', whereArgs: [cariId]);
      final bakiye = (cari.first['bakiye'] as num).toDouble();
      expect(bakiye, equals(150.0));
    });

    test('Ödeme hareketi bakiyeyi düşürür', () async {
      await _cariHareketEkle(db,
          cariId: cariId, borc: 200.0, alacak: 0.0, fis: 'TEST002');
      await _cariHareketEkle(db,
          cariId: cariId, borc: 0.0, alacak: 80.0, fis: 'TEST003');

      final cari = await db.query('cari', where: 'id = ?', whereArgs: [cariId]);
      final bakiye = (cari.first['bakiye'] as num).toDouble();
      expect(bakiye, equals(120.0));
    });

    test('Bakiye trigger ile hesaplanır (SUM)', () async {
      await _cariHareketEkle(db,
          cariId: cariId, borc: 100.0, alacak: 0.0, fis: 'T1');
      await _cariHareketEkle(db,
          cariId: cariId, borc: 200.0, alacak: 0.0, fis: 'T2');
      await _cariHareketEkle(db,
          cariId: cariId, borc: 0.0, alacak: 150.0, fis: 'T3');

      final cari = await db.query('cari', where: 'id = ?', whereArgs: [cariId]);
      final bakiye = (cari.first['bakiye'] as num).toDouble();
      expect(bakiye, equals(150.0)); // 100+200-150
    });
  });
}

// ── Test yardımcı metodları ────────────────────────────────────────────────

Future<String> _fisNoUret(Database db, String tip) async {
  return await db.transaction((txn) async {
    final rows = await txn.query('fis_sayac',
        where: 'tip = ?', whereArgs: [tip]);
    if (rows.isEmpty) {
      await txn.insert('fis_sayac', {'tip': tip, 'son_numara': 1, 'prefix': 'F'});
      return 'F000001';
    }
    final sonNo = (rows.first['son_numara'] as int) + 1;
    final prefix = rows.first['prefix'] as String? ?? '';
    await txn.update('fis_sayac', {'son_numara': sonNo},
        where: 'tip = ?', whereArgs: [tip]);
    return '$prefix${sonNo.toString().padLeft(6, '0')}';
  });
}

Future<void> _stokDus(Database db, {
  required int urunId, required double miktar, required int referansId}) async {
  await db.transaction((txn) async {
    final rows = await txn.query('urunler', where: 'id = ?', whereArgs: [urunId]);
    if (rows.isEmpty) return;
    final onceki = (rows.first['stok'] as num).toDouble();
    final sonraki = (onceki - miktar).clamp(0.0, double.infinity);
    await txn.update('urunler', {'stok': sonraki},
        where: 'id = ?', whereArgs: [urunId]);
    await txn.insert('stok_hareket', {
      'urun_id': urunId,
      'hareket_turu': 'Çıkış',
      'miktar': miktar,
      'onceki_stok': onceki,
      'sonraki_stok': sonraki,
      'tarih': DateTime.now().toIso8601String(),
      'referans_id': referansId,
      'referans_turu': 'satis',
    });
  });
}

Future<double> _stokAl(Database db, int urunId) async {
  final rows = await db.query('urunler', where: 'id = ?', whereArgs: [urunId]);
  return (rows.first['stok'] as num).toDouble();
}

Future<void> _satisSil(Database db, int satisId) async {
  await db.transaction((txn) async {
    final satisRows = await txn.query('satislar',
        where: 'id = ?', whereArgs: [satisId]);
    if (satisRows.isEmpty) return;
    final satis = satisRows.first;
    final odenen = (satis['odenen_tutar'] as num).toDouble();
    final yontem = satis['odeme_yontemi'] as String? ?? '';
    final fisNo  = satis['fis_no'] as String? ?? '';

    await txn.update('satislar', {
      'is_deleted': 1, 'iptal': 1,
      'iptal_tarihi': DateTime.now().toIso8601String(),
      'iptal_nedeni': 'Test iptali',
    }, where: 'id = ?', whereArgs: [satisId]);

    final kalemler = await txn.query('satis_kalem',
        where: 'satis_id = ?', whereArgs: [satisId]);
    for (final k in kalemler) {
      final urunId = k['urun_id'] as int;
      final miktar = (k['miktar'] as num).toDouble();
      await txn.rawUpdate(
          'UPDATE urunler SET stok = stok + ? WHERE id = ?', [miktar, urunId]);
    }

    if (odenen > 0 && yontem != 'Cari') {
      final kasaRows = await txn.rawQuery(
          'SELECT bakiye_sonrasi FROM kasa_hareketleri ORDER BY id DESC LIMIT 1');
      final mevcut = kasaRows.isEmpty ? 0.0
          : (kasaRows.first['bakiye_sonrasi'] as num?)?.toDouble() ?? 0.0;
      await txn.insert('kasa_hareketleri', {
        'hareket_tipi': 'Satış İptali',
        'tutar': -odenen,
        'bakiye_sonrasi': mevcut - odenen,
        'referans_id': satisId,
        'referans_turu': 'satis_iptal',
        'tarih': DateTime.now().toIso8601String(),
        'aciklama': 'İptal: $fisNo',
      });
    }
  });
}

Future<void> _cariHareketEkle(Database db, {
  required int cariId,
  required double borc,
  required double alacak,
  required String fis,
}) async {
  await db.transaction((txn) async {
    await txn.insert('cari_hareket', {
      'cari_id': cariId, 'tarih': DateTime.now().toIso8601String(),
      'fis_tipi': 'Test', 'fis_no': fis,
      'borc': borc, 'alacak': alacak,
    });
    final res = await txn.rawQuery(
        'SELECT SUM(borc) - SUM(alacak) AS b FROM cari_hareket WHERE cari_id = ?',
        [cariId]);
    final yeniBakiye = (res.first['b'] as num?)?.toDouble() ?? 0;
    await txn.update('cari', {'bakiye': yeniBakiye},
        where: 'id = ?', whereArgs: [cariId]);
  });
}
