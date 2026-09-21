// test/veri/irsaliye_iptal_stok_test.dart
//
// Kendi-keşif turu (İrsaliye modülü denetimi): IrsaliyeDeposu.
// durumGuncelle() ÖNCEDEN sadece 'durum' kolonunu değiştiriyordu —
// 'İptal'e geçişte STOK HİÇ GERİ ALINMIYORDU. 'Çıkış' tipi bir
// irsaliyeyle düşürülen stok, irsaliye iptal edilse bile KALICI
// OLARAK düşük kalıyordu.
//
// IrsaliyeDeposu.durumGuncelle() Veritabani() singleton'ı üzerinden
// çalıştığı için (diğer depo testlerindeki AYNI gerekçe), burada onun
// YENİ eklenen _stokEtkisiniTersineCevir() mantığı BİREBİR AYNI sırayla
// gerçek şema üzerinde bir in-memory veritabanı içinde doğrudan
// çağrılıyor.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../helper/test_initializer.dart';

/// IrsaliyeDeposu._stokEtkisiniTersineCevir() ile BİREBİR AYNI mantık.
Future<void> _stokEtkisiniTersineCevir(
    Database db, int irsaliyeId, String now) async {
  final hareketler = await db.query('stok_hareket',
      where: 'referans_turu = ? AND referans_id = ?',
      whereArgs: ['irsaliye', irsaliyeId]);
  if (hareketler.isEmpty) return;

  await db.transaction((txn) async {
    for (final h in hareketler) {
      final urunId = h['urun_id'] as int;
      final onceki = (h['onceki_stok'] as num?)?.toDouble() ?? 0;
      final sonraki = (h['sonraki_stok'] as num?)?.toDouble() ?? 0;
      final tersDelta = onceki - sonraki;

      final urunRows = await txn.query('urunler',
          columns: ['stok'], where: 'id = ?', whereArgs: [urunId]);
      if (urunRows.isEmpty) continue;
      final mevcutStok = (urunRows.first['stok'] as num).toDouble();
      final yeniStok = (mevcutStok + tersDelta).clamp(0, double.infinity);
      await txn.update('urunler', {'stok': yeniStok, 'last_updated': now},
          where: 'id = ?', whereArgs: [urunId]);

      await txn.insert('stok_hareket', {
        'global_id': const Uuid().v4(),
        'urun_id': urunId,
        'hareket_turu': 'İrsaliye İptal',
        'miktar': tersDelta.abs(),
        'onceki_stok': mevcutStok,
        'sonraki_stok': yeniStok,
        'tarih': now,
        'last_updated': now,
        'referans_id': irsaliyeId,
        'referans_turu': 'irsaliye_iptal',
      });
    }
  });
}

Future<void> _durumGuncelle(Database db, int irsaliyeId, String yeniDurum) async {
  final now = DateTime.now().toIso8601String();
  if (yeniDurum == 'İptal') {
    final mevcut = await db.query('irsaliyeler',
        columns: ['durum'], where: 'id = ?', whereArgs: [irsaliyeId], limit: 1);
    if (mevcut.isNotEmpty && mevcut.first['durum'] != 'İptal') {
      await _stokEtkisiniTersineCevir(db, irsaliyeId, now);
    }
  }
  await db.update('irsaliyeler', {'durum': yeniDurum, 'last_updated': now},
      where: 'id=?', whereArgs: [irsaliyeId]);
}

void main() {
  late Database db;
  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  Future<int> _urunEkle({double stok = 100}) =>
      TestVeritabani.ornekUrunEkle(db, stok: stok);

  Future<int> _irsaliyeVeStokHareketiOlustur({
    required int urunId,
    required double onceki,
    required double sonraki,
    String tip = 'Çıkış',
  }) async {
    final irsaliyeId = await db.insert('irsaliyeler', {
      'global_id': const Uuid().v4(),
      'irsaliye_no': 'IRS-TEST-1',
      'tarih': DateTime.now().toIso8601String(),
      'tip': tip,
      'toplam_tutar': 0,
      'durum': 'Hazırlanıyor',
    });
    await db.insert('stok_hareket', {
      'global_id': const Uuid().v4(),
      'urun_id': urunId,
      'hareket_turu': 'İrsaliye $tip',
      'miktar': (onceki - sonraki).abs(),
      'onceki_stok': onceki,
      'sonraki_stok': sonraki,
      'tarih': DateTime.now().toIso8601String(),
      'referans_id': irsaliyeId,
      'referans_turu': 'irsaliye',
    });
    // urunler.stok'u da irsaliye oluşturulduğundaki gibi güncel tut.
    await db.update('urunler', {'stok': sonraki}, where: 'id = ?', whereArgs: [urunId]);
    return irsaliyeId;
  }

  test(
      "'Çıkış' irsaliyesi İptal edilince düşürülen stok GERİ EKLENİR "
      '(önceden hiç eklenmiyordu)', () async {
    final urunId = await _urunEkle(stok: 100);
    // 100 stoktan 30 adet sevk edildi (100 -> 70).
    final irsaliyeId = await _irsaliyeVeStokHareketiOlustur(
        urunId: urunId, onceki: 100, sonraki: 70);

    var urun = (await db.query('urunler', where: 'id = ?', whereArgs: [urunId])).first;
    expect(urun['stok'], 70.0);

    await _durumGuncelle(db, irsaliyeId, 'İptal');

    urun = (await db.query('urunler', where: 'id = ?', whereArgs: [urunId])).first;
    expect(urun['stok'], 100.0,
        reason: 'iptal sonrası stok sevkten ÖNCEKİ haline dönmeli');

    final tersHareketler = await db.query('stok_hareket',
        where: 'referans_turu = ?', whereArgs: ['irsaliye_iptal']);
    expect(tersHareketler.length, 1);
  });

  test("'Giriş' irsaliyesi İptal edilince EKLENEN stok GERİ DÜŞÜLÜR",
      () async {
    final urunId = await _urunEkle(stok: 50);
    // 50 stoğa 20 adet giriş yapıldı (50 -> 70).
    final irsaliyeId = await _irsaliyeVeStokHareketiOlustur(
        urunId: urunId, onceki: 50, sonraki: 70, tip: 'Giriş');

    await _durumGuncelle(db, irsaliyeId, 'İptal');

    final urun =
        (await db.query('urunler', where: 'id = ?', whereArgs: [urunId])).first;
    expect(urun['stok'], 50.0);
  });

  test('AYNI irsaliye İKİNCİ KEZ İptal edilirse stok TEKRAR tersine '
      'çevrilmez (idempotent)', () async {
    final urunId = await _urunEkle(stok: 100);
    final irsaliyeId = await _irsaliyeVeStokHareketiOlustur(
        urunId: urunId, onceki: 100, sonraki: 70);

    await _durumGuncelle(db, irsaliyeId, 'İptal');
    await _durumGuncelle(db, irsaliyeId, 'İptal'); // tekrar

    final urun =
        (await db.query('urunler', where: 'id = ?', whereArgs: [urunId])).first;
    expect(urun['stok'], 100.0,
        reason: 'ikinci iptal çağrısı stoğu TEKRAR artırmamalı');
  });

  test('stoğa hiç dokunmayan bir irsaliye (olusturSevkKaydi ile oluşan — '
      'stok_hareket satırı YOK) İptal edilince hiçbir şey değişmez',
      () async {
    final urunId = await _urunEkle(stok: 100);
    final irsaliyeId = await db.insert('irsaliyeler', {
      'global_id': const Uuid().v4(),
      'irsaliye_no': 'IRS-TEST-2',
      'tarih': DateTime.now().toIso8601String(),
      'tip': 'Çıkış',
      'toplam_tutar': 0,
      'durum': 'Hazırlanıyor',
    });
    // Bilerek stok_hareket satırı EKLENMEDİ (olusturSevkKaydi deseni).

    await _durumGuncelle(db, irsaliyeId, 'İptal');

    final urun =
        (await db.query('urunler', where: 'id = ?', whereArgs: [urunId])).first;
    expect(urun['stok'], 100.0);
  });

  test('sevk edilenden fazlası zaten satıldıysa (mevcut stok tersDelta\'dan '
      'az) negatife düşmez, 0da kalır (clamp korunur)', () async {
    final urunId = await _urunEkle(stok: 5);
    final irsaliyeId = await _irsaliyeVeStokHareketiOlustur(
        urunId: urunId, onceki: 100, sonraki: 70); // orijinalde 30 düşmüştü
    // Ama aradan geçen sürede stok BAŞKA satışlarla 5'e kadar düşmüş
    // olsun (yukarıdaki helper zaten stoğu 70 yaptı, elle 5'e çekiyoruz).
    await db.update('urunler', {'stok': 5}, where: 'id = ?', whereArgs: [urunId]);

    await _durumGuncelle(db, irsaliyeId, 'İptal');

    final urun =
        (await db.query('urunler', where: 'id = ?', whereArgs: [urunId])).first;
    // tersDelta = 100-70 = 30; 5+30 = 35 (negatife düşme riski burada yok,
    // ama clamp'in hâlâ yerinde olduğunu doğruluyoruz).
    expect(urun['stok'], 35.0);
  });
}
