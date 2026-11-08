// test/depolar/urun_birlestirme_test.dart
//
// Aynı ürün iki cihazda internetsizken ayrı açıldı (çoklu cihaz analizi,
// 2026-11-08). ÖNCEDEN senkronda gelenin barkodu silinip iki ayrı ürün
// kalıyor, stok ikiye bölünüyordu; yeni cihazın ilk tam çekiminde ise
// REPLACE aynı barkodlu ilk ürünü sessizce siliyordu.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:market_plus/veri/database/tablolar/tablo_olusturucu.dart';
import 'package:market_plus/depolar/stok_deposu.dart';
import 'package:market_plus/veri/database/urun_birlestirme.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

const _ean = '8690000000011';
final _zaman = DateTime(2026, 11, 8, 12).toIso8601String();

Future<int> _urun(Database db, String gid, {String barkod = _ean, String ad = 'Cola 1L'}) =>
    db.insert('urunler', {
      'global_id': gid, 'urun_adi': ad, 'barkod': barkod, 'kod': barkod,
      'is_deleted': 0, 'aktif': 1, 'last_updated': _zaman,
    });

Map<String, dynamic> _gelen(String gid, {String barkod = _ean, String ad = 'Coca Cola 1 L'}) => {
      'global_id': gid, 'urun_adi': ad, 'barkod': barkod, 'kod': barkod,
      'is_deleted': 0, 'aktif': 1, 'last_updated': _zaman,
    };

Future<Map<String, Object?>> _gid(Database db, String gid) async =>
    (await db.query('urunler', where: 'global_id = ?', whereArgs: [gid])).first;

void main() {
  late Database db;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await TestVeritabani.olustur();
    Veritabani.testVeritabani = db;
  });
  tearDown(() async {
    Veritabani.testVeritabani = null;
    await db.close();
  });

  test('kural: gerçek barkod ya da aynı ad birleşir; kısa barkod + farklı ad birleşmez', () {
    expect(UrunBirlestirme.birlestirilebilir(_gelen('a'), _gelen('b', ad: 'Bambaşka')), isTrue);
    expect(UrunBirlestirme.birlestirilebilir(
        _gelen('a', barkod: '12', ad: 'Elma'), _gelen('b', barkod: '12', ad: 'elma ')), isTrue);
    expect(UrunBirlestirme.birlestirilebilir(
        _gelen('a', barkod: '12', ad: 'Elma'), _gelen('b', barkod: '12', ad: 'Armut')), isFalse);
    expect(UrunBirlestirme.birlestirilebilir(_gelen('a'), {..._gelen('b'), 'is_deleted': 1}), isFalse);
    // Her cihaz aynı hedefi seçer (sıradan/saatten bağımsız).
    expect(UrunBirlestirme.hedefMi('aaa', 'zzz'), isTrue);
    expect(UrunBirlestirme.hedefMi('zzz', 'aaa'), isFalse);
  });

  test('yereldeki kopya: satış kalemi ve stok hareketleri kalan ürüne taşınır, stok tek üründe toplanır', () async {
    final yerelId = await _urun(db, 'zzz-yerel');
    final satisId = await db.insert('satislar',
        {'global_id': 's1', 'fis_no': 'F1', 'tarih': _zaman, 'is_deleted': 0});
    await db.insert('satis_kalem', {
      'global_id': 'k1', 'satis_id': satisId, 'urun_id': yerelId,
      'urun_adi': 'Cola 1L', 'miktar': 2, 'birim_fiyat': 30, 'last_updated': _zaman,
    });
    await db.insert('stok_hareket', {
      'global_id': 'sh1', 'urun_id': yerelId, 'hareket_turu': 'Giriş', 'miktar': 10,
      'onceki_stok': 0, 'sonraki_stok': 10, 'tarih': _zaman, 'last_updated': _zaman,
    });

    await Veritabani().supaKayitlariEkle('urunler', [_gelen('aaa-gelen')]);
    // Gelen ürünün (diğer kasa) kendi hareketi de sonra iner.
    final hedefId = (await _gid(db, 'aaa-gelen'))['id'] as int;
    await db.insert('stok_hareket', {
      'global_id': 'sh2', 'urun_id': hedefId, 'hareket_turu': 'Giriş', 'miktar': 5,
      'onceki_stok': 0, 'sonraki_stok': 5, 'tarih': _zaman, 'last_updated': _zaman,
    });

    final hedef = await _gid(db, 'aaa-gelen');
    expect(hedef['barkod'], _ean);
    expect(hedef['is_deleted'], 0);
    final kopya = await _gid(db, 'zzz-yerel');
    expect(kopya['is_deleted'], 1);
    expect(kopya['barkod'], isNull);

    final kalem = (await db.query('satis_kalem', where: "global_id = 'k1'")).first;
    expect(kalem['urun_id'], hedefId);
    final sh1 = (await db.query('stok_hareket', where: "global_id = 'sh1'")).first;
    expect(sh1['urun_id'], hedefId);

    await StokDeposu().stokMutabakatYap();
    expect(((await _gid(db, 'aaa-gelen'))['stok'] as num).toDouble(), 15);

    // Taşınan satırlar buluta gitsin diye kuyrukta.
    final kuyruk = await db.query('sync_queue', columns: ['tablo_adi', 'kayit_global_id']);
    final gidler = kuyruk.map((r) => r['kayit_global_id']).toSet();
    expect(gidler, containsAll(['k1', 'sh1', 'zzz-yerel']));
  });

  test('gelen kopya: yerel ürün aynen kalır, gelen silinmiş ve barkodsuz yazılır', () async {
    await _urun(db, 'aaa-yerel');
    await Veritabani().supaKayitlariEkle('urunler', [_gelen('zzz-gelen')]);
    final yerel = await _gid(db, 'aaa-yerel');
    expect(yerel['is_deleted'], 0);
    expect(yerel['barkod'], _ean);
    final gelen = await _gid(db, 'zzz-gelen');
    expect(gelen['is_deleted'], 1);
    expect(gelen['barkod'], isNull);
  });

  test('birleşmeyen çakışma eski davranışı korur (gelenin barkodu boşalır, iki ürün aktif)', () async {
    await _urun(db, 'aaa-yerel', barkod: '12', ad: 'Elma');
    await Veritabani().supaKayitlariEkle('urunler', [_gelen('zzz-gelen', barkod: '12', ad: 'Armut')]);
    expect((await _gid(db, 'aaa-yerel'))['is_deleted'], 0);
    final gelen = await _gid(db, 'zzz-gelen');
    expect(gelen['is_deleted'], 0);
    expect(gelen['barkod'], isNull);
  });

  test('aynı çekimde gelen iki aynı ürün: ikisi de yazılır, biri kopya olur (REPLACE silmez)', () async {
    await Veritabani().supaKayitlariEkle('urunler', [_gelen('zzz-2'), _gelen('aaa-1')]);
    final hepsi = await db.query('urunler', where: "global_id IN ('aaa-1','zzz-2')");
    expect(hepsi, hasLength(2));
    expect((await _gid(db, 'aaa-1'))['is_deleted'], 0);
    expect((await _gid(db, 'aaa-1'))['barkod'], _ean);
    expect((await _gid(db, 'zzz-2'))['is_deleted'], 1);
  });

  test('iki cihaz aynı kuralla aynı ürünü seçer (yakınsama)', () async {
    // Cihaz X: yerelde aaa, buluttan zzz gelir. Cihaz Y: yerelde zzz, buluttan aaa.
    await _urun(db, 'aaa');
    await Veritabani().supaKayitlariEkle('urunler', [_gelen('zzz')]);
    final xKalan = (await db.query('urunler', where: 'is_deleted = 0 AND barkod = ?', whereArgs: [_ean]))
        .single['global_id'];

    final y = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(
            version: 1, singleInstance: false,
            onCreate: (d, _) => TabloOlusturucu.olustur(d)));
    Veritabani.testVeritabani = y;
    await _urun(y, 'zzz');
    await Veritabani().supaKayitlariEkle('urunler', [_gelen('aaa')]);
    final yKalan = (await y.query('urunler', where: 'is_deleted = 0 AND barkod = ?', whereArgs: [_ean]))
        .single['global_id'];
    await y.close();
    Veritabani.testVeritabani = db;

    expect(xKalan, 'aaa');
    expect(yKalan, xKalan);
  });
}
