// test/servisler/bulut/sync_kuyruk_yazici_test.dart
//
// MASTER ERP DEEP AUDIT — Madde 5 sertleştirmesi: SyncKuyrukYazici.ekleTxn
// — business data ile AYNI transaction içinde kalıcı senkron kuyruğu
// satırı yazan, atomikliğin temel taşı. Gerçek üretim şemasıyla
// bellek-içi bir SQLite kullanılarak test edilir (TestVeritabani).
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/servisler/bulut/sync_kuyruk_yazici.dart';

import '../../helper/test_initializer.dart';

Future<List<Map<String, dynamic>>> _kuyrukSatirlari(Database db) =>
    db.query('sync_queue');

void main() {
  late Database db;
  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  test('bir satır ekler — tablo/global_id/islem_tipi/durum doğru yazılır',
      () async {
    await db.transaction((txn) async {
      await SyncKuyrukYazici.ekleTxn(txn,
          tablo: 'urunler', veri: {'id': 1, 'global_id': 'g-1', 'ad': 'Ekmek'});
    });

    final satirlar = await _kuyrukSatirlari(db);
    expect(satirlar, hasLength(1));
    expect(satirlar.first['tablo_adi'], 'urunler');
    expect(satirlar.first['kayit_global_id'], 'g-1');
    expect(satirlar.first['islem_tipi'], 'UPSERT');
    expect(satirlar.first['durum'], 'beklemede');
    expect(satirlar.first['deneme_sayisi'], 0);
    expect(satirlar.first['veri_json'], contains('Ekmek'));
  });

  test('aynı tablo+global_id ile ikinci çağrı — ESKİYİ SİLİP YENİYİ '
      'yazar (dedup, RAM kuyruğun "replace" davranışıyla aynı)', () async {
    await db.transaction((txn) async {
      await SyncKuyrukYazici.ekleTxn(txn,
          tablo: 'urunler', veri: {'id': 1, 'global_id': 'g-1', 'ad': 'Eski Ad'});
    });
    await db.transaction((txn) async {
      await SyncKuyrukYazici.ekleTxn(txn,
          tablo: 'urunler', veri: {'id': 1, 'global_id': 'g-1', 'ad': 'Yeni Ad'});
    });

    final satirlar = await _kuyrukSatirlari(db);
    // Aynı kayıt için kuyrukta TEK satır olmalı — birikip çoğalmamalı.
    expect(satirlar, hasLength(1));
    expect(satirlar.first['veri_json'], contains('Yeni Ad'));
    expect(satirlar.first['veri_json'], isNot(contains('Eski Ad')));
  });

  test('farklı global_id\'ler ayrı satır olarak birikir', () async {
    await db.transaction((txn) async {
      await SyncKuyrukYazici.ekleTxn(txn,
          tablo: 'urunler', veri: {'id': 1, 'global_id': 'g-1'});
      await SyncKuyrukYazici.ekleTxn(txn,
          tablo: 'urunler', veri: {'id': 2, 'global_id': 'g-2'});
    });

    final satirlar = await _kuyrukSatirlari(db);
    expect(satirlar, hasLength(2));
  });

  test('DELETE islemTipi ile eklenen satır önceki bekleyen UPSERT\'in '
      'yerini alır (aynı kayıt için artık sadece silme kuyrukta olmalı)',
      () async {
    await db.transaction((txn) async {
      await SyncKuyrukYazici.ekleTxn(txn,
          tablo: 'iade', veri: {'global_id': 'g-9'}, islemTipi: 'UPSERT');
    });
    await db.transaction((txn) async {
      await SyncKuyrukYazici.ekleTxn(txn,
          tablo: 'iade', veri: {'global_id': 'g-9'}, islemTipi: 'DELETE');
    });

    final satirlar = await _kuyrukSatirlari(db);
    expect(satirlar, hasLength(1));
    expect(satirlar.first['islem_tipi'], 'DELETE');
  });

  test('bekleyen olmayan (zaten işlenmiş/silinmiş) eski bir satır '
      'dedup tarafından etkilenmez — sadece durum=beklemede olanlar '
      'silinir', () async {
    await db.transaction((txn) async {
      await SyncKuyrukYazici.ekleTxn(txn,
          tablo: 'urunler', veri: {'id': 1, 'global_id': 'g-1'});
    });
    // İlk satırı elle "işlenmiş" (beklemede DIŞI) yap.
    await db.update('sync_queue', {'durum': 'kalici_hata'});

    await db.transaction((txn) async {
      await SyncKuyrukYazici.ekleTxn(txn,
          tablo: 'urunler', veri: {'id': 1, 'global_id': 'g-1'});
    });

    final satirlar = await _kuyrukSatirlari(db);
    // Eski (kalici_hata) satır silinmedi, yeni (beklemede) satır eklendi.
    expect(satirlar, hasLength(2));
    expect(satirlar.where((s) => s['durum'] == 'kalici_hata'), hasLength(1));
    expect(satirlar.where((s) => s['durum'] == 'beklemede'), hasLength(1));
  });

  test('rollback olan transaction — kuyruk satırı da geri alınır '
      '(business data ile atomiklik)', () async {
    try {
      await db.transaction((txn) async {
        await SyncKuyrukYazici.ekleTxn(txn,
            tablo: 'urunler', veri: {'id': 1, 'global_id': 'g-rollback'});
        throw Exception('kasıtlı hata — transaction rollback olmalı');
      });
    } catch (_) {
      // beklenen
    }

    final satirlar = await _kuyrukSatirlari(db);
    expect(satirlar, isEmpty);
  });
}
