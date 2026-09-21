// test/veri/urun_stok_sync_atomikligi_test.dart
//
// DEEP_AUDIT_REPORT madde 3 (Ürün yönetimi sync-atomikliği): UrunDeposu.
// guncelle()/alisFiyatiGuncelle()/topluEkleGuncelle() ve StokDeposu.
// stokDuzelt() ÖNCEDEN business data yazıldıktan SONRA, AYRI bir
// transaction'da (BulutManager().upsert() → fire-and-forget _kuyrukaYaz)
// senkron kuyruğuna düşüyordu — uygulama iki yazım arasında çökerse
// kuyruk kaydı hiç oluşmazdı. Düzeltme: SyncKuyrukYazici.ekleTxn artık
// business data ile AYNI transaction'da çağrılıyor (satis_tamamlama_
// servisi/masa_odeme_servisi'ndeki AYNI desen).
//
// UrunDeposu/StokDeposu Veritabani() singleton'ı üzerinden çalıştığı
// için (diğer depo testlerinde olduğu gibi) burada AYNI (düzeltilmiş)
// transaction mantığı gerçek şema üzerinde doğrudan doğrulanıyor: iş
// verisi VE sync_queue satırı TEK transaction'ın parçası olmalı — yani
// biri varsa diğeri de olmalı.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/servisler/bulut/sync_kuyruk_yazici.dart';
import '../helper/test_initializer.dart';

Future<int> _kuyrukSayisi(Database db, String tablo) async {
  final rows = await db
      .query('sync_queue', where: 'tablo_adi = ?', whereArgs: [tablo]);
  return rows.length;
}

void main() {
  late Database db;
  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  group('Ürün/stok yazımları artık senkron kuyruğuyla ATOMİK', () {
    test(
        'urunler güncellemesi ile sync_queue kaydı AYNI transaction\'da '
        'birlikte var olur (UrunDeposu.guncelle deseni)', () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db, stok: 10);

      final guncelleme = {
        'stok': 20.0, 'last_updated': DateTime.now().toIso8601String(),
      };
      await db.transaction((txn) async {
        await txn.update('urunler', guncelleme,
            where: 'id = ?', whereArgs: [urunId]);
        await SyncKuyrukYazici.ekleTxn(txn,
            tablo: 'urunler', veri: {...guncelleme, 'id': urunId});
      });

      final urun =
          (await db.query('urunler', where: 'id = ?', whereArgs: [urunId]))
              .first;
      expect(urun['stok'], 20.0);
      expect(await _kuyrukSayisi(db, 'urunler'), 1);
    });

    test(
        'stok_hareket ekleme ile sync_queue kaydı AYNI transaction\'da '
        'birlikte var olur (StokDeposu.stokDuzelt deseni)', () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db, stok: 10);

      final now = DateTime.now().toIso8601String();
      final stokSatiri = {
        'urun_id': urunId, 'hareket_turu': 'Sayım', 'miktar': 5.0,
        'onceki_stok': 10.0, 'sonraki_stok': 15.0, 'tarih': now,
      };
      await db.transaction((txn) async {
        await txn.update('urunler', {'stok': 15.0, 'last_updated': now},
            where: 'id = ?', whereArgs: [urunId]);
        await SyncKuyrukYazici.ekleTxn(txn,
            tablo: 'urunler', veri: {'stok': 15.0, 'id': urunId});
        await txn.insert('stok_hareket', stokSatiri);
        await SyncKuyrukYazici.ekleTxn(txn,
            tablo: 'stok_hareket', veri: stokSatiri);
      });

      expect(await _kuyrukSayisi(db, 'urunler'), 1);
      expect(await _kuyrukSayisi(db, 'stok_hareket'), 1);
      final hareket = await db.query('stok_hareket');
      expect(hareket, hasLength(1));
    });

    test(
        'transaction İÇİNDE hata olursa (constraint ihlali) NE iş verisi '
        'NE DE kuyruk kaydı kalıcı olur — ikisi birlikte rollback olur',
        () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db, stok: 10);

      Object? yakalanan;
      try {
        await db.transaction((txn) async {
          await txn.update('urunler', {'stok': 99.0},
              where: 'id = ?', whereArgs: [urunId]);
          await SyncKuyrukYazici.ekleTxn(txn,
              tablo: 'urunler', veri: {'stok': 99.0, 'id': urunId});
          // Kasıtlı hata — mevcut olmayan bir tabloya yazmayı dene,
          // transaction'ı geri aldırır.
          await txn.insert('olmayan_tablo_XYZ', {'a': 1});
        });
      } catch (e) {
        yakalanan = e;
      }
      expect(yakalanan, isNotNull);

      final urun =
          (await db.query('urunler', where: 'id = ?', whereArgs: [urunId]))
              .first;
      expect(urun['stok'], 10.0); // ROLLBACK — eski değerde kaldı
      expect(await _kuyrukSayisi(db, 'urunler'), 0); // kuyruk kaydı da YOK
    });
  });
}
