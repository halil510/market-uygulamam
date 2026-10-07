// test/servisler/bulut_null_yayilim_test.dart
//
// Bulut Veri Güvenliği Raporu (2026-10-07), Bulgu 4 — TEMİZLENEN alan
// (null) buluta ve diğer kasalara yayılmalı; ama ilişki/türetilmiş
// alanlar ve kısmi kayıtların gönderilmeyen alanları ezilmemeli.
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/servisler/bulut/supabase_saglayici.dart';
import 'package:market_plus/servisler/kolon_haritalama.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import 'package:sqflite/sqflite.dart';
import '../helper/test_initializer.dart';

void main() {
  group('gönderim (cevir)', () {
    test('null alan korunur — bulutta da temizlensin', () {
      final m = KolonHaritalama.cevir('urunler',
          {'global_id': 'g', 'lot_aciklama': null, 'urun_adi': 'A'});
      expect(m.containsKey('lot_aciklama'), isTrue);
      expect(m['lot_aciklama'], isNull);
    });

    test('deleted_at null gitmez (silinmiş bulut kaydı geri açılmasın)', () {
      final m = KolonHaritalama.cevir('faturalar', {'global_id': 'g', 'deleted_at': null});
      expect(m.containsKey('deleted_at'), isFalse);
    });
  });

  test('toplu gönderim: farklı sütunlu kayıtlar ayrı istekte (null doldurulmaz)', () {
    final veriler = [
      {'global_id': 'a', 'stok': 1},
      {'global_id': 'b', 'urun_adi': 'X', 'stok': 2},
      {'stok': 3, 'global_id': 'c'},
    ];
    expect(SupabaseSaglayici.sutunKumesineGoreGrupla(veriler), [
      [0, 2],
      [1],
    ]);
    expect(veriler[0].containsKey('urun_adi'), isFalse);
  });

  test('nullKorunurMu: kimlik, türetilmiş ve ilişki sütunları korunur', () {
    expect(KolonHaritalama.nullKorunurMu('urunler', 'stok'), isTrue);
    expect(KolonHaritalama.nullKorunurMu('cari', 'bakiye'), isTrue);
    expect(KolonHaritalama.nullKorunurMu('urunler', 'kategori_id'), isTrue);
    expect(KolonHaritalama.nullKorunurMu('cari_hareket', 'fis_id'), isTrue);
    expect(KolonHaritalama.nullKorunurMu('urunler', 'global_id'), isTrue);
    expect(KolonHaritalama.nullKorunurMu('urunler', 'lot_aciklama'), isFalse);
  });

  group('çekim (supaKayitlariGuncelle)', () {
    late Database db;
    late int urunId;
    const gid = 'URUN-NULL-1';

    setUp(() async {
      db = await TestVeritabani.olustur();
      Veritabani.testVeritabani = db;
      urunId = await TestVeritabani.ornekUrunEkle(db, barkod: 'N1', stok: 10);
      await db.update('urunler', {
        'global_id': gid,
        'last_updated': '2026-10-01T09:00:00.000Z',
        'lot_aciklama': 'eski not',
        'kategori_id': 1,
      }, where: 'id = ?', whereArgs: [urunId]);
    });
    tearDown(() async {
      Veritabani.testVeritabani = null;
      await db.close();
    });

    test('bulutta temizlenen alan yerelde de temizlenir; ilişki/stok korunur', () async {
      await Veritabani().supaKayitlariGuncelle('urunler', [
        {'global_id': gid, 'lot_aciklama': null, 'kategori_id': null, 'stok': null,
          'last_updated': '2026-10-07T10:00:00Z'},
      ]);
      final r = (await db.query('urunler', where: 'id = ?', whereArgs: [urunId])).first;
      expect(r['lot_aciklama'], isNull);
      expect(r['kategori_id'], 1, reason: 'ilişki null\'u uygulanmaz');
      expect(r['stok'], 10, reason: 'türetilmiş alan uygulanmaz');
      expect(r['urun_adi'], isNotNull, reason: 'gelmeyen alan dokunulmaz');
    });
  });
}
