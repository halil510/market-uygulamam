// test/servisler/bulut_turetilmis_alan_test.dart
//
// Bulut Veri Güvenliği Raporu (2026-10-07):
//  Bulgu 2 — stok değişimi ürünün last_updated'ini İLERLETMEMELİ (aksi hâlde
//            tam ürün satırı LWW'de başka kasanın fiyat değişikliğini ezer);
//            çekimde türetilmiş stok mevcut kayda uygulanmamalı.
//  Bulgu 3 — kuyruğa kimliksiz (global_id'siz) kısmi ürün satırı girmemeli.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/depolar/stok_deposu.dart';
import 'package:market_plus/depolar/urun_deposu.dart';
import 'package:market_plus/servisler/bulut/sync_kuyruk_yazici.dart';
import 'package:market_plus/servisler/kolon_haritalama.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import 'package:sqflite/sqflite.dart';
import '../helper/test_initializer.dart';

void main() {
  late Database db;
  late int urunId;
  const gid = 'URUN-GID-1';
  const eskiDamga = '2026-10-01T09:00:00.000';

  setUp(() async {
    db = await TestVeritabani.olustur();
    Veritabani.testVeritabani = db;
    urunId = await TestVeritabani.ornekUrunEkle(db, barkod: 'T1', stok: 10);
    await db.update('urunler', {'global_id': gid, 'last_updated': eskiDamga},
        where: 'id = ?', whereArgs: [urunId]);
    await db.delete('sync_queue');
  });
  tearDown(() => db.close());

  Future<String?> damga() async =>
      (await db.query('urunler', where: 'id = ?', whereArgs: [urunId])).first['last_updated']
          ?.toString();

  Future<List<Map<String, dynamic>>> urunKuyrugu() async {
    final q = await db.query('sync_queue', where: "tablo_adi = 'urunler'");
    return [for (final r in q) jsonDecode(r['veri_json'] as String) as Map<String, dynamic>];
  }

  group('Bulgu 2: stok değişimi damgayı ilerletmez', () {
    test('satış (stokDus) last_updated değiştirmez, kuyruk tam ve kimlikli', () async {
      await StokDeposu().stokDus(urunId: urunId, miktar: 3);
      expect(await damga(), eskiDamga);
      final k = await urunKuyrugu();
      expect(k, isNotEmpty);
      expect(k.every((v) => v['global_id'] == gid), isTrue);
      expect(k.last['stok'], 7);
      expect(k.last['urun_adi'], isNotNull, reason: 'tam satır gitmeli');
    });

    test('stok girişi (stokGir) last_updated değiştirmez', () async {
      await StokDeposu().stokGir(urunId: urunId, miktar: 5);
      expect(await damga(), eskiDamga);
    });

    test('çekimde mevcut ürünün stoğu buluttan ezilmez, diğer alanlar uygulanır', () async {
      await Veritabani().supaKayitlariGuncelle('urunler', [
        {'global_id': gid, 'urun_adi': 'Buluttaki Ad', 'stok': 999.0,
          'last_updated': '2026-10-07T10:00:00+00:00'},
      ]);
      final r = (await db.query('urunler', where: 'id = ?', whereArgs: [urunId])).first;
      expect(r['urun_adi'], 'Buluttaki Ad');
      expect(r['stok'], 10, reason: 'stok yerelde stok_hareket mutabakatından gelir');
    });
  });

  group('Bulgu 3: kuyruğa kimliksiz satır girmez', () {
    test('stok sayımı (stokDuzelt) tam ve kimlikli satır yazar', () async {
      await StokDeposu().stokDuzelt(urunId, 4, 1, aciklama: 'sayım');
      final k = await urunKuyrugu();
      expect(k, isNotEmpty);
      expect(k.every((v) => v['global_id'] == gid), isTrue);
      expect(k.last['stok'], 4);
      expect(await damga(), eskiDamga);
      // Buluta gidecek hâl de kimlikli olmalı (id atılır, global_id kalır).
      expect(KolonHaritalama.cevir('urunler', k.last)['global_id'], gid);
    });

    test('toplu/döviz alış fiyatı (alisFiyatiGuncelle) kimlikli satır yazar', () async {
      await UrunDeposu().alisFiyatiGuncelle(urunId, 12);
      final k = await urunKuyrugu();
      expect(k, isNotEmpty);
      expect(k.every((v) => v['global_id'] == gid), isTrue);
      expect(k.last['alis_fiyat'], 12);
    });

    test('ekleTxn: kısmi haritanın kimliği aynı işlemden tamamlanır', () async {
      await db.transaction((txn) => SyncKuyrukYazici.ekleTxn(txn,
          tablo: 'urunler', veri: {'id': urunId, 'stok': 1}));
      final q = await db.query('sync_queue');
      expect(q.single['kayit_global_id'], gid);
      expect((jsonDecode(q.single['veri_json'] as String) as Map)['global_id'], gid);
    });

    test('ekleTxn: kimliği hiç olmayan satıra kalıcı kimlik üretilir', () async {
      await db.update('urunler', {'global_id': null}, where: 'id = ?', whereArgs: [urunId]);
      await db.transaction((txn) => SyncKuyrukYazici.ekleTxn(txn,
          tablo: 'urunler', veri: {'id': urunId, 'stok': 1}));
      final yeni = (await db.query('urunler', where: 'id = ?', whereArgs: [urunId]))
          .first['global_id']?.toString();
      expect(yeni, isNotNull);
      expect((await db.query('sync_queue')).single['kayit_global_id'], yeni);
    });
  });
}
