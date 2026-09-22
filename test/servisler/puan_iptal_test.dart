// test/servisler/puan_iptal_test.dart
//
// Paralel fork denetimi (2026-09-22, "tam ERP" turu) YÜKSEK öncelikli
// bir bulgu buldu: satış tamamlanınca müşteri sadakat puanı kazanıyordu
// (PuanServisi.puanEkle), ama o satış İPTAL EDİLİP SİLİNİRSE
// (SatisDeposu.sil()) kazanılan puan hiç geri alınmıyordu — kasiyer
// satışı yanlışlıkla girip hemen silse bile puan bakiyesinde kalıcı
// olarak duruyordu.
//
// PuanServisi.puanIptalEt() bunu düzeltiyor: bu satışa ait TÜM
// puan_hareket satırlarını (kazanılan + varsa harcanan) bulup, HER
// BİRİNİ KENDİ YÖNÜNDE (toplam_puan / kullanilan) tersine çevirir,
// idempotent'tir (aynı satış için ikinci kez çağrılırsa no-op).
//
// PuanServisi Veritabani() singleton'ı üzerinden çalıştığı için (diğer
// depo/servis testlerinde olduğu gibi, bkz. virman_servisi_test.dart'
// taki AYNI gerekçe), bu test PuanServisi'nin BİREBİR aynı SQL
// mantığını (puanEkle/puanKullan/puanIptalEt) gerçek şema üzerinde bir
// in-memory veritabanı içinde doğrudan çalıştırır.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../helper/test_initializer.dart';

/// PuanServisi.puanEkle()'nin BİREBİR aynısı.
Future<void> _puanEkle(Database db,
    {required int cariId, required double tutar, required int satisId}) async {
  final kazanilanPuan = tutar.floorToDouble();
  if (kazanilanPuan <= 0) return;
  await db.transaction((txn) async {
    await txn.rawInsert('''
      INSERT INTO musteri_puan(cari_id, toplam_puan, kullanilan, son_islem, global_id)
      VALUES(?, ?, 0, datetime('now'), ?)
      ON CONFLICT(cari_id) DO UPDATE SET
        toplam_puan = toplam_puan + excluded.toplam_puan,
        son_islem   = excluded.son_islem
    ''', [cariId, kazanilanPuan, const Uuid().v4()]);
    await txn.insert('puan_hareket', {
      'global_id': const Uuid().v4(), 'cari_id': cariId, 'islem_tipi': 'Kazanıldı',
      'puan': kazanilanPuan, 'referans_id': satisId,
      'aciklama': 'Satış puanı ($tutar ₺)',
    });
  });
}

/// PuanServisi.puanKullan()'ın BİREBİR aynısı.
Future<void> _puanKullan(Database db,
    {required int cariId, required double istenenPuan, required int satisId}) async {
  final bakiye = await _puanBakiyesi(db, cariId);
  final kullanilanPuan = istenenPuan.clamp(0.0, bakiye);
  if (kullanilanPuan <= 0) return;
  await db.transaction((txn) async {
    await txn.rawUpdate(
        "UPDATE musteri_puan SET kullanilan = kullanilan + ?, son_islem = datetime('now') WHERE cari_id = ?",
        [kullanilanPuan, cariId]);
    await txn.insert('puan_hareket', {
      'global_id': const Uuid().v4(), 'cari_id': cariId, 'islem_tipi': 'Harcandı',
      'puan': -kullanilanPuan, 'referans_id': satisId, 'aciklama': 'Ödeme puanı kullanıldı',
    });
  });
}

Future<double> _puanBakiyesi(Database db, int cariId) async {
  final rows = await db.query('musteri_puan', where: 'cari_id = ?', whereArgs: [cariId]);
  if (rows.isEmpty) return 0;
  final toplam = (rows.first['toplam_puan'] as num?)?.toDouble() ?? 0;
  final kullanilan = (rows.first['kullanilan'] as num?)?.toDouble() ?? 0;
  return (toplam - kullanilan).clamp(0.0, double.infinity);
}

/// PuanServisi.puanIptalEt()'in BİREBİR aynısı.
Future<void> _puanIptalEt(Database db, {required int cariId, required int satisId}) async {
  await db.transaction((txn) async {
    final zatenIptal = await txn.query('puan_hareket',
        where: 'cari_id = ? AND referans_id = ? AND islem_tipi = ?',
        whereArgs: [cariId, satisId, 'İptal']);
    if (zatenIptal.isNotEmpty) return;

    final hareketler = await txn.query('puan_hareket',
        where: 'cari_id = ? AND referans_id = ? AND islem_tipi != ?',
        whereArgs: [cariId, satisId, 'İptal']);
    if (hareketler.isEmpty) return;

    double kazanilanToplam = 0, harcananToplam = 0;
    for (final h in hareketler) {
      final puan = (h['puan'] as num?)?.toDouble() ?? 0;
      if (puan > 0) {
        kazanilanToplam += puan;
      } else {
        harcananToplam += puan.abs();
      }
    }

    final now = DateTime.now().toIso8601String();
    if (kazanilanToplam > 0.005) {
      await txn.rawUpdate(
          'UPDATE musteri_puan SET toplam_puan = MAX(0, toplam_puan - ?), son_islem = ? WHERE cari_id = ?',
          [kazanilanToplam, now, cariId]);
      await txn.insert('puan_hareket', {
        'global_id': const Uuid().v4(), 'cari_id': cariId, 'islem_tipi': 'İptal',
        'puan': -kazanilanToplam, 'referans_id': satisId,
        'aciklama': 'Satış iptali/silindi — kazanılan puan geri alındı',
      });
    }
    if (harcananToplam > 0.005) {
      await txn.rawUpdate(
          'UPDATE musteri_puan SET kullanilan = MAX(0, kullanilan - ?), son_islem = ? WHERE cari_id = ?',
          [harcananToplam, now, cariId]);
      await txn.insert('puan_hareket', {
        'global_id': const Uuid().v4(), 'cari_id': cariId, 'islem_tipi': 'İptal',
        'puan': harcananToplam, 'referans_id': satisId,
        'aciklama': 'Satış iptali/silindi — kullanılan puan iade edildi',
      });
    }
  });
}

void main() {
  late Database db;
  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  group('PuanServisi.puanIptalEt() — satış silinince/iptal edilince', () {
    test('kazanılan puan tam olarak geri alınır', () async {
      final cariId = await TestVeritabani.ornekCariEkle(db);

      await _puanEkle(db, cariId: cariId, tutar: 500.0, satisId: 1);
      expect(await _puanBakiyesi(db, cariId), equals(500.0));

      await _puanIptalEt(db, cariId: cariId, satisId: 1);

      expect(await _puanBakiyesi(db, cariId), equals(0.0),
          reason: 'Satış silinince kazanılan puan geri alınmalı');
    });

    test('müşterinin BAŞKA satıştan kazandığı puan etkilenmez', () async {
      final cariId = await TestVeritabani.ornekCariEkle(db);
      await _puanEkle(db, cariId: cariId, tutar: 500.0, satisId: 1);
      await _puanEkle(db, cariId: cariId, tutar: 200.0, satisId: 2);
      expect(await _puanBakiyesi(db, cariId), equals(700.0));

      await _puanIptalEt(db, cariId: cariId, satisId: 1);

      expect(await _puanBakiyesi(db, cariId), equals(200.0),
          reason: 'Diğer satıştan kazanılan puan dokunulmamalı');
    });

    test('aynı satış için İKİNCİ KEZ çağrılırsa mükerrer geri alma OLMAZ (idempotent)', () async {
      final cariId = await TestVeritabani.ornekCariEkle(db);
      await _puanEkle(db, cariId: cariId, tutar: 300.0, satisId: 1);

      await _puanIptalEt(db, cariId: cariId, satisId: 1);
      await _puanIptalEt(db, cariId: cariId, satisId: 1); // tekrar

      expect(await _puanBakiyesi(db, cariId), equals(0.0),
          reason: 'İkinci çağrı puanı negatife düşürmemeli (idempotent guard)');
    });

    test('hiç puan kazanılmamış bir satış için çağrılırsa hiçbir şey yapmaz', () async {
      final cariId = await TestVeritabani.ornekCariEkle(db);
      await _puanIptalEt(db, cariId: cariId, satisId: 999);
      expect(await _puanBakiyesi(db, cariId), equals(0.0));
    });

    test('bu satışta HEM kazanılan HEM kullanılan puan varsa ikisi de doğru tersine çevrilir',
        () async {
      final cariId = await TestVeritabani.ornekCariEkle(db);
      await _puanEkle(db, cariId: cariId, tutar: 1000.0, satisId: 1);
      expect(await _puanBakiyesi(db, cariId), equals(1000.0));

      await _puanEkle(db, cariId: cariId, tutar: 100.0, satisId: 2);
      await _puanKullan(db, cariId: cariId, istenenPuan: 300.0, satisId: 2);
      expect(await _puanBakiyesi(db, cariId), equals(800.0));

      await _puanIptalEt(db, cariId: cariId, satisId: 2);

      expect(await _puanBakiyesi(db, cariId), equals(1000.0),
          reason: 'Sadece satış 1\'in orijinal 1000 puanı kalmalı');
    });
  });
}
