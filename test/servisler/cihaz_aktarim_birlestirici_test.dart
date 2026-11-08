// test/servisler/cihaz_aktarim_birlestirici_test.dart
//
// Cihazdan cihaza WiFi aktarımı regresyonları (çoklu cihaz analizi,
// 2026-11-08). Eski içe aktarım ilişki sütunlarını GÖNDERENİN yerel id'siyle
// yazıyordu: yerel id'ler iki cihazda farklı olunca satış kalemi başka
// fişe, cari hareketi başka müşteriye bağlanıyordu. Testler iki ayrı
// veritabanında id'leri bilerek kaydırır.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:market_plus/servisler/cihaz_aktarim_birlestirici.dart';
import 'package:market_plus/veri/database/tablolar/tablo_olusturucu.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

Future<Database> _ayriDb() async {
  await TestVeritabani.olustur(); // ffi kurulumu
  return databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        singleInstance: false,
        onCreate: (db, _) => TabloOlusturucu.olustur(db),
      ));
}

final _simdi = DateTime(2026, 11, 8, 12).toIso8601String();

/// Gönderen cihaz: ürün + cari + satış + kalem + cari hareket + stok hareketi.
Future<void> _gonderenVerisi(Database a) async {
  // id'leri kaydırmak için önce ilgisiz kayıtlar.
  for (var i = 0; i < 5; i++) {
    await a.insert('urunler', {'urun_adi': 'A-dolgu-$i', 'global_id': 'a-dolgu-u$i', 'is_deleted': 0});
    await a.insert('cari', {'unvan': 'A-dolgu-$i', 'cari_tipi': 'Müşteri', 'global_id': 'a-dolgu-c$i', 'is_deleted': 0});
  }
  final u = await a.insert('urunler', {
    'urun_adi': 'Cola', 'barkod': '111', 'global_id': 'u1', 'stok': 10,
    'satis_fiyati': 30, 'is_deleted': 0, 'last_updated': _simdi,
  });
  final c = await a.insert('cari', {
    'unvan': 'Ahmet', 'cari_tipi': 'Müşteri', 'cari_kodu': 'CARIO-1',
    'global_id': 'c1', 'is_deleted': 0, 'last_updated': _simdi,
  });
  final s = await a.insert('satislar', {
    'global_id': 's1', 'fis_no': 'MKP2026010000001', 'cari_id': c,
    'genel_toplam': 60, 'tarih': _simdi, 'is_deleted': 0, 'last_updated': _simdi,
  });
  await a.insert('satis_kalem', {
    'global_id': 'k1', 'satis_id': s, 'urun_id': u, 'urun_adi': 'Cola',
    'miktar': 2, 'birim_fiyat': 30, 'last_updated': _simdi,
  });
  await a.insert('cari_hareket', {
    'global_id': 'h1', 'cari_id': c, 'fis_tipi': 'Satış', 'borc': 60, 'alacak': 0,
    'tarih': _simdi, 'is_deleted': 0, 'last_updated': _simdi,
  });
  await a.insert('stok_hareket', {
    'global_id': 'sh1', 'urun_id': u, 'hareket_turu': 'Giriş', 'miktar': 12,
    'onceki_stok': 0, 'sonraki_stok': 12, 'tarih': _simdi, 'last_updated': _simdi,
  });
  await a.insert('stok_hareket', {
    'global_id': 'sh2', 'urun_id': u, 'hareket_turu': 'Çıkış', 'miktar': 2,
    'onceki_stok': 12, 'sonraki_stok': 10, 'tarih': _simdi, 'last_updated': _simdi,
  });
}

Future<int> _idGid(Database db, String tablo, String gid) async =>
    (await db.query(tablo, columns: ['id'], where: 'global_id = ?', whereArgs: [gid]))
        .first['id'] as int;

void main() {
  late Database a;
  late Database b;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    a = await _ayriDb();
    b = await _ayriDb();
    // Alan cihazın kendi verisi — id'ler gönderenden farklı başlasın.
    await b.insert('urunler', {'urun_adi': 'B-kendi', 'global_id': 'b-u', 'is_deleted': 0});
    await b.insert('cari', {'unvan': 'B-kendi', 'cari_tipi': 'Müşteri', 'global_id': 'b-c', 'is_deleted': 0});
    await b.insert('satislar', {'global_id': 'b-s', 'fis_no': 'MKP2026020000001', 'tarih': _simdi, 'is_deleted': 0});
  });

  tearDown(() async {
    Veritabani.testVeritabani = null;
    await a.close();
    await b.close();
  });

  Future<Map<String, dynamic>> aktar() async {
    Veritabani.testVeritabani = a;
    final data = await CihazAktarimBirlestirici.tumunuDisaAktar();
    Veritabani.testVeritabani = b;
    return CihazAktarimBirlestirici.iceAktar(data);
  }

  test('ilişkiler yerel id değil global_id üzerinden kurulur (satış kalemi doğru fişe, hareket doğru cariye)', () async {
    await _gonderenVerisi(a);
    final sonuc = await aktar();
    expect(sonuc['hata_sayisi'], 0, reason: '${sonuc['hatalar']}');

    final satisB = await _idGid(b, 'satislar', 's1');
    final urunB = await _idGid(b, 'urunler', 'u1');
    final cariB = await _idGid(b, 'cari', 'c1');
    // Kendi id'leri gönderenden farklı olmalı ki test anlamlı olsun.
    expect(urunB, isNot(await _idGid(a, 'urunler', 'u1')));
    expect(cariB, isNot(await _idGid(a, 'cari', 'c1')));

    final kalem = (await b.query('satis_kalem', where: "global_id = 'k1'")).first;
    expect(kalem['satis_id'], satisB);
    expect(kalem['urun_id'], urunB);
    final satis = (await b.query('satislar', where: "global_id = 's1'")).first;
    expect(satis['cari_id'], cariB);
    final hareket = (await b.query('cari_hareket', where: "global_id = 'h1'")).first;
    expect(hareket['cari_id'], cariB);
    final stokH = await b.query('stok_hareket', where: "global_id IN ('sh1','sh2')");
    expect(stokH.every((r) => r['urun_id'] == urunB), isTrue);

    // Alan cihazın kendi kayıtlarına bağlanan hiçbir şey yok.
    final yanlis = await b.rawQuery(
        "SELECT COUNT(*) n FROM satis_kalem WHERE satis_id = (SELECT id FROM satislar WHERE global_id='b-s')");
    expect(yanlis.first['n'], 0);
  });

  test('aktarım sonrası türetilmiş alanlar hareketlerden hesaplanır (stok, cari bakiye)', () async {
    await _gonderenVerisi(a);
    final sonuc = await aktar();
    expect(sonuc['hata_sayisi'], 0, reason: '${sonuc['hatalar']}');
    final urun = (await b.query('urunler', where: "global_id = 'u1'")).first;
    expect((urun['stok'] as num).toDouble(), 10);
    final cari = (await b.query('cari', where: "global_id = 'c1'")).first;
    expect((cari['bakiye'] as num).toDouble(), 60);
  });

  test('aynı barkodlu farklı ürün eşleşip alan cihazın global_id\'sini ezmez', () async {
    await b.insert('urunler', {
      'urun_adi': 'Cola (B)', 'barkod': '111', 'global_id': 'b-cola', 'is_deleted': 0,
    });
    await _gonderenVerisi(a);
    await aktar();
    final bCola = await b.query('urunler', where: "global_id = 'b-cola'");
    expect(bCola, hasLength(1), reason: 'alan cihazın ürün kimliği korunmalı');
    expect(bCola.first['barkod'], '111');
    expect(await b.query('urunler', where: "global_id = 'u1'"), hasLength(1));
  });

  test('karşı cihazda silinen kayıt bu cihazda da silinir (ikinci aktarımda)', () async {
    await _gonderenVerisi(a);
    await aktar();
    await a.update('cari_hareket', {'is_deleted': 1, 'last_updated': _simdi},
        where: "global_id = 'h1'");
    final sonuc = await aktar();
    expect(sonuc['silinen'], greaterThanOrEqualTo(1));
    final h = (await b.query('cari_hareket', where: "global_id = 'h1'")).first;
    expect(h['is_deleted'], 1);
    final cari = (await b.query('cari', where: "global_id = 'c1'")).first;
    expect((cari['bakiye'] as num).toDouble(), 0);
  });

  test('aynı veri iki kez aktarılınca kopya oluşmaz (idempotent)', () async {
    await _gonderenVerisi(a);
    await aktar();
    await aktar();
    expect(await b.query('satis_kalem', where: "global_id = 'k1'"), hasLength(1));
    expect(await b.query('cari_hareket', where: "global_id = 'h1'"), hasLength(1));
    final urun = (await b.query('urunler', where: "global_id = 'u1'")).first;
    expect((urun['stok'] as num).toDouble(), 10);
  });

  test('ebeveyni aktarılmayan zorunlu ilişkili satır yetim yazılmaz, atlanır', () async {
    await _gonderenVerisi(a);
    Veritabani.testVeritabani = a;
    final data = await CihazAktarimBirlestirici.tumunuDisaAktar();
    data['satislar'] = <Map<String, dynamic>>[]; // ebeveyn yok
    Veritabani.testVeritabani = b;
    final sonuc = await CihazAktarimBirlestirici.iceAktar(data);
    expect(sonuc['atlanan'], greaterThanOrEqualTo(1));
    expect(await b.query('satis_kalem', where: "global_id = 'k1'"), isEmpty);
  });

  test('ilişki bilgisi taşımayan eski sürüm verisi reddedilir, hiçbir şey yazılmaz', () async {
    Veritabani.testVeritabani = b;
    final eski = {
      'satis_kalem': [
        {'id': 1, 'global_id': 'k-eski', 'satis_id': 1, 'urun_id': 1,
         'urun_adi': 'X', 'miktar': 1, 'birim_fiyat': 1},
      ],
    };
    await expectLater(CihazAktarimBirlestirici.iceAktar(eski), throwsException);
    expect(await b.query('satis_kalem', where: "global_id = 'k-eski'"), isEmpty);
  });
}
