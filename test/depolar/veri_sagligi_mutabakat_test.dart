// test/depolar/veri_sagligi_mutabakat_test.dart
//
// Veri Sağlığı Merkezi'nin (protokol §13) dayandığı yeni mutabakat
// fonksiyonlarını (CariDeposu.bakiyeMutabakatYap, KasaDeposu
// .bakiyeMutabakatYap, BankaHesapDeposu.bakiyeMutabakatYap) gerçek
// şemayla doğrular. Bu depolar Veritabani() singleton'ı üzerinden
// çalıştığı için, üretim koduyla BİREBİR aynı SQL/algoritma burada
// TestVeritabani db'si üzerinde tekrar uygulanıyor (bu oturumda
// kurulan test deseniyle tutarlı).
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/modeller/kasa_hareket_model.dart';
import '../helper/test_initializer.dart';

// ── Cari bakiye mutabakatı (CariDeposu.bakiyeMutabakatYap ile aynı SQL) ──
Future<int> _cariBakiyeUyumsuzlukSayisi(Database db) async {
  final rows = await db.rawQuery('''
    SELECT COUNT(*) as n FROM cari c
    WHERE c.is_deleted = 0 AND ABS(c.bakiye - (
      SELECT COALESCE(SUM(borc), 0) - COALESCE(SUM(alacak), 0)
      FROM cari_hareket WHERE cari_id = c.id AND is_deleted = 0
    )) > 0.01
  ''');
  return (rows.first['n'] as int?) ?? 0;
}

Future<int> _cariBakiyeMutabakatYap(Database db) async {
  final uyumsuzlar = await db.rawQuery('''
    SELECT c.id FROM cari c
    WHERE c.is_deleted = 0 AND ABS(c.bakiye - (
      SELECT COALESCE(SUM(borc), 0) - COALESCE(SUM(alacak), 0)
      FROM cari_hareket WHERE cari_id = c.id AND is_deleted = 0
    )) > 0.01
  ''');
  final now = DateTime.now().toIso8601String();
  for (final r in uyumsuzlar) {
    // last_updated bump'ı da CariDeposu.bakiyeYenidenHesapla() ile AYNI
    // (bkz. o fonksiyondaki kök neden notu) — bu olmadan delta senkron
    // ("Hızlı Gönder") düzeltmeyi asla yakalayamaz.
    await db.rawUpdate('''
      UPDATE cari SET bakiye = (
        SELECT COALESCE(SUM(borc), 0) - COALESCE(SUM(alacak), 0)
        FROM cari_hareket WHERE cari_id = ? AND is_deleted = 0
      ), last_updated = ? WHERE id = ?
    ''', [r['id'], now, r['id']]);
  }
  return uyumsuzlar.length;
}

// ── Kasa bakiye mutabakatı (KasaDeposu.bakiyeMutabakatYap ile aynı algoritma) ──
Future<int> _kasaBakiyeMutabakatYap(Database db) async {
  final rows = await db.query('kasa_hareketleri', where: 'deleted_at IS NULL', orderBy: 'tarih ASC, id ASC');
  double bakiye = 0;
  var duzeltilen = 0;
  final girisler = KasaHareketModel.girisTipleri;
  for (final r in rows) {
    final tip = r['hareket_tipi'] as String? ?? '';
    final tutar = (r['tutar'] as num?)?.toDouble() ?? 0;
    bakiye = girisler.contains(tip) ? bakiye + tutar : bakiye - tutar;
    final mevcut = (r['bakiye_sonrasi'] as num?)?.toDouble();
    if (mevcut == null || (mevcut - bakiye).abs() > 0.01) {
      await db.update('kasa_hareketleri', {'bakiye_sonrasi': bakiye}, where: 'id = ?', whereArgs: [r['id']]);
      duzeltilen++;
    }
  }
  return duzeltilen;
}

// ── Banka bakiye mutabakatı (BankaHesapDeposu.bakiyeMutabakatYap ile aynı SQL) ──
const _uyumsuzHesaplarSql = '''
    SELECT h.id, (
      SELECT bh2.sonraki_bakiye FROM banka_hareketler bh2
      WHERE bh2.banka_hesap_id = h.id ORDER BY bh2.tarih DESC, bh2.id DESC LIMIT 1
    ) as dogru_bakiye
    FROM banka_hesaplar h
    WHERE h.aktif = 1
      AND EXISTS (SELECT 1 FROM banka_hareketler bh WHERE bh.banka_hesap_id = h.id)
      AND ABS(h.bakiye - (
        SELECT bh2.sonraki_bakiye FROM banka_hareketler bh2
        WHERE bh2.banka_hesap_id = h.id ORDER BY bh2.tarih DESC, bh2.id DESC LIMIT 1
      )) > 0.01
  ''';

Future<int> _bankaBakiyeMutabakatYap(Database db) async {
  final uyumsuzlar = await db.rawQuery(_uyumsuzHesaplarSql);
  final now = DateTime.now().toIso8601String();
  for (final r in uyumsuzlar) {
    final dogru = (r['dogru_bakiye'] as num?)?.toDouble() ?? 0;
    await db.update('banka_hesaplar', {'bakiye': dogru, 'last_updated': now},
        where: 'id = ?', whereArgs: [r['id']]);
  }
  return uyumsuzlar.length;
}

void main() {
  late Database db;

  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  group('Cari bakiye mutabakatı', () {
    test('bakiye zaten doğruysa uyumsuzluk sayısı 0', () async {
      final cariId = await TestVeritabani.ornekCariEkle(db);
      await db.insert('cari_hareket', {'cari_id': cariId, 'borc': 100, 'alacak': 0, 'is_deleted': 0, 'fis_tipi': 'Test', 'tarih': DateTime.now().toIso8601String()});
      await db.update('cari', {'bakiye': 100}, where: 'id = ?', whereArgs: [cariId]);

      expect(await _cariBakiyeUyumsuzlukSayisi(db), equals(0));
    });

    test('bakiye yanlışsa tespit edilir ve düzeltilince doğrulanır', () async {
      final cariId = await TestVeritabani.ornekCariEkle(db);
      await db.insert('cari_hareket', {'cari_id': cariId, 'borc': 500, 'alacak': 200, 'is_deleted': 0, 'fis_tipi': 'Test', 'tarih': DateTime.now().toIso8601String()});
      // Kasıtlı olarak yanlış bir bakiye yaz (gerçek değer 300 olmalı).
      await db.update('cari', {'bakiye': 999}, where: 'id = ?', whereArgs: [cariId]);

      expect(await _cariBakiyeUyumsuzlukSayisi(db), equals(1));

      final duzeltilen = await _cariBakiyeMutabakatYap(db);
      expect(duzeltilen, equals(1));

      final cari = (await db.query('cari', where: 'id = ?', whereArgs: [cariId])).first;
      expect((cari['bakiye'] as num).toDouble(), equals(300.0));
      expect(await _cariBakiyeUyumsuzlukSayisi(db), equals(0));
    });

    // 🔴 Regresyon testi (kullanıcı isteği — "veri sağlığı merkezine
    // düzgün bak"): ÖNCEDEN CariDeposu.bakiyeYenidenHesapla() (bu
    // fonksiyonun dayandığı GERÇEK kod) last_updated'ı hiç bümlemiyordu
    // — düzeltilen bakiye normal "Hızlı Gönder" (delta) senkronuyla
    // ASLA buluta/diğer cihazlara gitmiyordu.
    test('düzeltme sonrası last_updated bümlenir — delta senkron bunu '
        'yakalayabilsin diye', () async {
      final cariId = await TestVeritabani.ornekCariEkle(db);
      await db.update('cari', {'last_updated': '2020-01-01T00:00:00'},
          where: 'id = ?', whereArgs: [cariId]);
      await db.insert('cari_hareket', {'cari_id': cariId, 'borc': 500, 'alacak': 0, 'is_deleted': 0, 'fis_tipi': 'Test', 'tarih': DateTime.now().toIso8601String()});
      await db.update('cari', {'bakiye': 999, 'last_updated': '2020-01-01T00:00:00'}, where: 'id = ?', whereArgs: [cariId]);

      await _cariBakiyeMutabakatYap(db);

      final cari = (await db.query('cari', where: 'id = ?', whereArgs: [cariId])).first;
      expect(cari['last_updated'], isNot(equals('2020-01-01T00:00:00')),
          reason: 'düzeltme sonrası last_updated GÜNCEL olmalı, aksi halde '
              'delta senkron bu düzeltmeyi hiç görmez');
    });
  });

  group('Kasa bakiye mutabakatı', () {
    test('sırayla doğru hesaplanmış bakiye_sonrasi değerlerine dokunulmaz', () async {
      await db.insert('kasa_hareketleri', {'hareket_tipi': 'Satış', 'tutar': 100, 'bakiye_sonrasi': 100, 'tarih': '2026-01-01T10:00:00'});
      await db.insert('kasa_hareketleri', {'hareket_tipi': 'Gider', 'tutar': 30, 'bakiye_sonrasi': 70, 'tarih': '2026-01-01T11:00:00'});

      final duzeltilen = await _kasaBakiyeMutabakatYap(db);
      expect(duzeltilen, equals(0));
    });

    test('yanlış bakiye_sonrasi tespit edilip zincirleme düzeltilir', () async {
      await db.insert('kasa_hareketleri', {'hareket_tipi': 'Satış', 'tutar': 100, 'bakiye_sonrasi': 999, 'tarih': '2026-01-01T10:00:00'});
      await db.insert('kasa_hareketleri', {'hareket_tipi': 'Gider', 'tutar': 30, 'bakiye_sonrasi': 999, 'tarih': '2026-01-01T11:00:00'});

      final duzeltilen = await _kasaBakiyeMutabakatYap(db);
      expect(duzeltilen, equals(2));

      final rows = await db.query('kasa_hareketleri', orderBy: 'tarih ASC');
      expect((rows[0]['bakiye_sonrasi'] as num).toDouble(), equals(100.0));
      expect((rows[1]['bakiye_sonrasi'] as num).toDouble(), equals(70.0));
    });

    test('silinmiş (deleted_at dolu) hareketler hesaba katılmaz', () async {
      await db.insert('kasa_hareketleri', {'hareket_tipi': 'Satış', 'tutar': 100, 'bakiye_sonrasi': 100, 'tarih': '2026-01-01T10:00:00'});
      await db.insert('kasa_hareketleri', {
        'hareket_tipi': 'Satış', 'tutar': 500, 'bakiye_sonrasi': 600,
        'tarih': '2026-01-01T10:30:00', 'deleted_at': '2026-01-02T00:00:00',
      });
      await db.insert('kasa_hareketleri', {'hareket_tipi': 'Gider', 'tutar': 30, 'bakiye_sonrasi': 70, 'tarih': '2026-01-01T11:00:00'});

      final duzeltilen = await _kasaBakiyeMutabakatYap(db);
      expect(duzeltilen, equals(0), reason: 'Zaten doğru: silinmiş hareket hesaba katılmamalı');
    });
  });

  group('Banka bakiye mutabakatı', () {
    Future<int> hesapEkle(double bakiye) => db.insert('banka_hesaplar', {
      'banka_id': 1, 'hesap_adi': 'Test', 'hesap_no': '1', 'bakiye': bakiye, 'aktif': 1,
    });

    test('hareket yoksa uyumsuzluk sayılmaz (yeni açılmış hesap)', () async {
      await hesapEkle(500);
      expect(await db.rawQuery(_uyumsuzHesaplarSql), isEmpty);
    });

    test('bakiye son hareketin sonraki_bakiye değeriyle uyumluysa dokunulmaz', () async {
      final hesapId = await hesapEkle(70);
      await db.insert('banka_hareketler', {
        'banka_hesap_id': hesapId, 'islem_tipi': 'Gelen', 'tutar': 100,
        'onceki_bakiye': 0, 'sonraki_bakiye': 100, 'tarih': '2026-01-01T10:00:00',
      });
      await db.insert('banka_hareketler', {
        'banka_hesap_id': hesapId, 'islem_tipi': 'Giden', 'tutar': 30,
        'onceki_bakiye': 100, 'sonraki_bakiye': 70, 'tarih': '2026-01-01T11:00:00',
      });
      await db.update('banka_hesaplar', {'bakiye': 70}, where: 'id = ?', whereArgs: [hesapId]);

      expect(await _bankaBakiyeMutabakatYap(db), equals(0));
    });

    test('bakiye elle bozulmuşsa (hareketten sapmışsa) düzeltilir', () async {
      final hesapId = await hesapEkle(999); // yanlış — olması gereken 70
      await db.insert('banka_hareketler', {
        'banka_hesap_id': hesapId, 'islem_tipi': 'Gelen', 'tutar': 100,
        'onceki_bakiye': 0, 'sonraki_bakiye': 100, 'tarih': '2026-01-01T10:00:00',
      });
      await db.insert('banka_hareketler', {
        'banka_hesap_id': hesapId, 'islem_tipi': 'Giden', 'tutar': 30,
        'onceki_bakiye': 100, 'sonraki_bakiye': 70, 'tarih': '2026-01-01T11:00:00',
      });

      final duzeltilen = await _bankaBakiyeMutabakatYap(db);
      expect(duzeltilen, equals(1));

      final hesap = (await db.query('banka_hesaplar', where: 'id = ?', whereArgs: [hesapId])).first;
      expect((hesap['bakiye'] as num).toDouble(), equals(70.0));
    });

    // 🔴 Regresyon testi (bkz. Cari bölümündeki AYNI not) — banka
    // mutabakatı zaten last_updated bümlüyordu, ama bu davranışın
    // korunduğunu doğrulayan açık bir test yoktu.
    test('düzeltme sonrası last_updated bümlenir', () async {
      final hesapId = await hesapEkle(999);
      await db.update('banka_hesaplar', {'last_updated': '2020-01-01T00:00:00'},
          where: 'id = ?', whereArgs: [hesapId]);
      await db.insert('banka_hareketler', {
        'banka_hesap_id': hesapId, 'islem_tipi': 'Gelen', 'tutar': 100,
        'onceki_bakiye': 0, 'sonraki_bakiye': 100, 'tarih': '2026-01-01T10:00:00',
      });

      await _bankaBakiyeMutabakatYap(db);

      final hesap = (await db.query('banka_hesaplar', where: 'id = ?', whereArgs: [hesapId])).first;
      expect(hesap['last_updated'], isNot(equals('2020-01-01T00:00:00')));
    });
  });
}
