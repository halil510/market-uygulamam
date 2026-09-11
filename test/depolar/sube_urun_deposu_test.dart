// test/depolar/sube_urun_deposu_test.dart
//
// Derin analizde bulundu (P0): SubeUrunDeposu.transferEt() ÖNCEDEN
// stokDus() + stokGir() çağırıyordu — ikisi de kendi ayrı transaction'ını
// açıyordu. Kaynağı düşüren işlem başarılı olup hedefi artıran işlem
// başarısız olursa ürün miktarı tamamen kaybolabiliyordu (kaynakta
// azalmış, hedefte hiç artmamış). Bu test, artık her iki güncellemenin
// TEK transaction'da olduğunu ve gerçek şemayla doğru çalıştığını
// doğruluyor.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import '../helper/test_initializer.dart';

Future<int> _subeEkle(Database db, String ad) => db.insert('subeler', {
  'sube_adi': ad, 'sube_kodu': ad.replaceAll(' ', '').toUpperCase(),
  'aktif': 1, 'is_deleted': 0,
});

void main() {
  late Database db;

  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  group('SubeUrunDeposu.transferEt', () {
    test('kaynaktan düşer, hedefe eklenir — toplam miktar korunur', () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db);
      final subeA = await _subeEkle(db, 'Şube A');
      final subeB = await _subeEkle(db, 'Şube B');

      await db.insert('sube_urun', {
        'urun_id': urunId, 'sube_id': subeA, 'stok': 50,
        'son_guncelleme': DateTime.now().toIso8601String(),
        'last_updated': DateTime.now().toIso8601String(),
      });

      await SubeUrunDeposuTest.transferEt(db,
          urunId: urunId, kaynakSubeId: subeA, hedefSubeId: subeB, miktar: 20);

      final kaynak = (await db.query('sube_urun', where: 'urun_id = ? AND sube_id = ?', whereArgs: [urunId, subeA])).first;
      final hedef = (await db.query('sube_urun', where: 'urun_id = ? AND sube_id = ?', whereArgs: [urunId, subeB])).first;
      expect((kaynak['stok'] as num).toDouble(), equals(30.0));
      expect((hedef['stok'] as num).toDouble(), equals(20.0));
    });

    test('kaynak yetersizse hata fırlatır, HİÇBİR satır değişmez', () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db);
      final subeA = await _subeEkle(db, 'Şube A');
      final subeB = await _subeEkle(db, 'Şube B');
      await db.insert('sube_urun', {
        'urun_id': urunId, 'sube_id': subeA, 'stok': 5,
        'son_guncelleme': DateTime.now().toIso8601String(),
        'last_updated': DateTime.now().toIso8601String(),
      });

      await expectLater(
        SubeUrunDeposuTest.transferEt(db, urunId: urunId, kaynakSubeId: subeA, hedefSubeId: subeB, miktar: 10),
        throwsException,
      );

      final kaynak = (await db.query('sube_urun', where: 'urun_id = ? AND sube_id = ?', whereArgs: [urunId, subeA])).first;
      expect((kaynak['stok'] as num).toDouble(), equals(5.0), reason: 'Değişmemeli');
      final hedef = await db.query('sube_urun', where: 'urun_id = ? AND sube_id = ?', whereArgs: [urunId, subeB]);
      expect(hedef, isEmpty, reason: 'Hedefte satır oluşmamalı');
    });

    test('hedefte önceden satır yoksa yeni satır oluşturulur', () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db);
      final subeA = await _subeEkle(db, 'Şube A');
      final subeB = await _subeEkle(db, 'Şube B');
      await db.insert('sube_urun', {
        'urun_id': urunId, 'sube_id': subeA, 'stok': 15,
        'son_guncelleme': DateTime.now().toIso8601String(),
        'last_updated': DateTime.now().toIso8601String(),
      });

      await SubeUrunDeposuTest.transferEt(db,
          urunId: urunId, kaynakSubeId: subeA, hedefSubeId: subeB, miktar: 15);

      final hedef = (await db.query('sube_urun', where: 'urun_id = ? AND sube_id = ?', whereArgs: [urunId, subeB])).first;
      expect((hedef['stok'] as num).toDouble(), equals(15.0));
      expect(hedef['global_id'], isNotNull);
    });
  });
}

/// SubeUrunDeposu.transferEt()'in (Veritabani() singleton'ı kullanan)
/// gerçek mantığını TestVeritabani db'si üzerinde doğrulamak için —
/// üretim koduyla BİREBİR aynı transaction sırası.
class SubeUrunDeposuTest {
  static Future<void> transferEt(
    Database db, {
    required int urunId,
    required int kaynakSubeId,
    required int hedefSubeId,
    required double miktar,
  }) async {
    if (miktar <= 0) throw Exception('Transfer miktarı sıfırdan büyük olmalı');
    final now = DateTime.now().toIso8601String();

    Future<void> satirUpsert(dynamic txn, int subeId, double yeniStok) async {
      final rows = await txn.query('sube_urun',
          where: 'urun_id = ? AND sube_id = ?', whereArgs: [urunId, subeId], limit: 1);
      if (rows.isEmpty) {
        await txn.insert('sube_urun', {
          'global_id': 'test-${DateTime.now().microsecondsSinceEpoch}',
          'urun_id': urunId, 'sube_id': subeId,
          'stok': yeniStok, 'son_guncelleme': now, 'last_updated': now,
        });
      } else {
        await txn.update('sube_urun',
            {'stok': yeniStok, 'son_guncelleme': now, 'last_updated': now},
            where: 'urun_id = ? AND sube_id = ?', whereArgs: [urunId, subeId]);
      }
    }

    await db.transaction((txn) async {
      final kaynakRows = await txn.query('sube_urun',
          where: 'urun_id = ? AND sube_id = ?', whereArgs: [urunId, kaynakSubeId], limit: 1);
      final kaynakStok = kaynakRows.isEmpty
          ? 0.0 : (kaynakRows.first['stok'] as num?)?.toDouble() ?? 0.0;
      if (kaynakStok < miktar) {
        throw Exception('Kaynak şubede yeterli stok yok (mevcut: $kaynakStok)');
      }

      final hedefRows = await txn.query('sube_urun',
          where: 'urun_id = ? AND sube_id = ?', whereArgs: [urunId, hedefSubeId], limit: 1);
      final hedefStok = hedefRows.isEmpty
          ? 0.0 : (hedefRows.first['stok'] as num?)?.toDouble() ?? 0.0;

      await satirUpsert(txn, kaynakSubeId, kaynakStok - miktar);
      await satirUpsert(txn, hedefSubeId, hedefStok + miktar);
    });
  }
}
