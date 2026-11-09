// test/servisler/donem_devir_coklu_cihaz_test.dart
//
// Derin denetim (2026-11-09) — iki KRİTİK yıl sonu devri bulgusu:
//  1) Devir dönem bitişinden SONRA (ör. 5 Ocak) yapılınca cari/kasa açılışı
//     devir anındaki GÜNCEL bakiyeden yazılıyor, silinmeyen Ocak hareketleri
//     bakiyeye İKİ KEZ giriyordu.
//  2) Devir silmesi yalnız yerelde ama açılış satırları buluta gidiyordu —
//     eski hareketleri taşıyan diğer kasalar / buluttan kurulan cihaz /
//     "Tam Al" dönemi İKİ KEZ sayıyordu.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/depolar/kasa_deposu.dart';
import 'package:market_plus/servisler/bulut/bulut_manager.dart';
import 'package:market_plus/servisler/cihaz_aktarim_birlestirici.dart';
import 'package:market_plus/servisler/donem_arsiv_servisi.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import 'package:market_plus/veri/database/yerel_arsiv_araliklari.dart';
import '../helper/test_initializer.dart';

final _bas = DateTime(2026, 1, 1);
final _bit = DateTime(2026, 12, 31, 23, 59, 59);
const _sube = 1;

Future<double> _cariBakiye(Database db, int cariId) async => ((await db.rawQuery(
            'SELECT COALESCE(SUM(borc),0) - COALESCE(SUM(alacak),0) b FROM cari_hareket '
            'WHERE cari_id = ? AND is_deleted = 0',
            [cariId]))
        .first['b'] as num)
    .toDouble();

Future<void> _devir(Database db) => DonemArsivServisi().aktifTablolardanSilVeAcilisYaz(
      donemId: 1, donemYili: 2026, subeId: _sube,
      baslangic: _bas, bitis: _bit, aktifDbTest: db,
    );

void main() {
  late Database db;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await TestVeritabani.olustur();
    Veritabani.testVeritabani = db;
    if ((await db.query('subeler', where: 'id = 1')).isEmpty) {
      await db.insert('subeler', {'id': 1, 'sube_kodu': 'MRK', 'sube_adi': 'Merkez'});
    }
  });
  tearDown(() async {
    Veritabani.testVeritabani = null;
    await db.close();
  });

  test('devir Ocak\'ta yapılınca cari bakiyesi Ocak hareketlerini iki kez saymaz', () async {
    final cariId = await TestVeritabani.ornekCariEkle(db);
    for (final h in [
      {'fis_tipi': 'Satış', 'borc': 500.0, 'alacak': 0.0, 'tarih': DateTime(2026, 3, 1)},
      {'fis_tipi': 'Tahsilat', 'borc': 0.0, 'alacak': 200.0, 'tarih': DateTime(2026, 6, 1)},
      {'fis_tipi': 'Satış', 'borc': 200.0, 'alacak': 0.0, 'tarih': DateTime(2027, 1, 3)},
    ]) {
      await db.insert('cari_hareket', {
        ...h, 'tarih': (h['tarih'] as DateTime).toIso8601String(),
        'cari_id': cariId, 'is_deleted': 0,
      });
    }
    // FAZ 5 snapshot'ı devir anındaki GÜNCEL bakiyeyi (Ocak dahil) yazmış olsa da…
    await db.insert('cari_kapanis_snapshot',
        {'devir_id': 'd', 'donem_id': 1, 'cari_id': cariId, 'bakiye': 500.0});
    expect(await _cariBakiye(db, cariId), 500);

    await _devir(db);

    expect(await _cariBakiye(db, cariId), 500, reason: 'önceden 700 çıkıyordu');
    final devir = await db.query('cari_hareket',
        where: "cari_id = ? AND fis_tipi = 'Devir'", whereArgs: [cariId]);
    expect(devir.single['borc'], 300.0);
  });

  test('devir Ocak\'ta yapılınca kasa zinciri Ocak hareketlerini iki kez saymaz', () async {
    Future<void> kasa(String tip, double tutar, double sonra, DateTime t) =>
        db.insert('kasa_hareketleri', {
          'hareket_tipi': tip, 'tutar': tutar, 'bakiye_sonrasi': sonra,
          'sube_id': _sube, 'tarih': t.toIso8601String(),
        });
    await kasa('Satış', 400, 400, DateTime(2026, 3, 1));
    await kasa('Gider', 50, 350, DateTime(2026, 7, 1));
    await kasa('Satış', 100, 450, DateTime(2027, 1, 3));
    await db.insert('kasa_kapanis_snapshot',
        {'devir_id': 'd', 'donem_id': 1, 'sube_id': _sube, 'bakiye': 450.0});

    await _devir(db);
    await KasaDeposu().zincirMutabakatYap();

    final acilis = (await db.query('kasa_hareketleri', where: "hareket_tipi = 'AçılışKasa'")).single;
    expect((acilis['tutar'] as num).toDouble(), 350);
    final son = await db.rawQuery(
        'SELECT bakiye_sonrasi FROM kasa_hareketleri ORDER BY tarih DESC, id DESC LIMIT 1');
    expect((son.first['bakiye_sonrasi'] as num).toDouble(), 450, reason: 'önceden 550 çıkıyordu');
  });

  test('açılış satırları yalnız yerelde kalır: kuyruğa, elle gönderime ve WiFi aktarımına girmez', () async {
    final cariId = await TestVeritabani.ornekCariEkle(db);
    final urunId = await TestVeritabani.ornekUrunEkle(db);
    await db.insert('cari_hareket', {
      'cari_id': cariId, 'fis_tipi': 'Satış', 'borc': 100.0, 'alacak': 0.0,
      'tarih': DateTime(2026, 3, 1).toIso8601String(), 'is_deleted': 0,
    });
    await db.insert('stok_hareket', {
      'urun_id': urunId, 'hareket_turu': 'Giriş', 'miktar': 10, 'onceki_stok': 0,
      'sonraki_stok': 10, 'sube_id': _sube, 'tarih': DateTime(2026, 3, 1).toIso8601String(),
    });
    await db.insert('kasa_hareketleri', {
      'hareket_tipi': 'Satış', 'tutar': 100, 'bakiye_sonrasi': 100, 'sube_id': _sube,
      'tarih': DateTime(2026, 3, 1).toIso8601String(),
    });

    await _devir(db);

    for (final t in ['cari_hareket', 'stok_hareket', 'kasa_hareketleri']) {
      final acilis = t == 'cari_hareket' ? "fis_tipi = 'Devir'" : "referans_turu = 'devir_acilis'";
      expect(await db.query(t, where: acilis), hasLength(1), reason: t);
      expect(await db.query('sync_queue', where: 'tablo_adi = ?', whereArgs: [t]), isEmpty,
          reason: '$t açılışı kuyruğa girmemeli');
      expect(await Veritabani().supaTumKayitlariGetir(t, false), isEmpty,
          reason: '$t açılışı elle gönderime girmemeli');
      expect(await CihazAktarimBirlestirici.tabloDisaAktar(t), isEmpty,
          reason: '$t açılışı WiFi aktarımına girmemeli');
    }
    // Anlık bildirim yolu da (ör. Devir satırı sonradan düzenlenirse) kuyruğa yazmaz.
    final devir = (await db.query('cari_hareket', where: "fis_tipi = 'Devir'")).first;
    BulutManager().upsert('cari_hareket', Map<String, dynamic>.from(devir));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(await db.query('sync_queue', where: "tablo_adi = 'cari_hareket'"), isEmpty);
  });

  test('devri yapan cihaz Tam Al\'da arşivlenen dönemin eski hareketlerini geri yazmaz', () async {
    final cariId = await TestVeritabani.ornekCariEkle(db);
    await YerelArsivAraliklari.ekle(subeId: _sube, baslangic: _bas, bitis: _bit);

    await Veritabani().supaKayitlariEkle('cari_hareket', [
      {'global_id': 'eski', 'cari_id': cariId, 'fis_tipi': 'Satış', 'borc': 500.0,
       'alacak': 0.0, 'tarih': '2026-03-01T10:00:00+00:00', 'is_deleted': 0},
      {'global_id': 'yeni', 'cari_id': cariId, 'fis_tipi': 'Satış', 'borc': 200.0,
       'alacak': 0.0, 'tarih': '2027-01-03T10:00:00', 'is_deleted': 0},
    ]);
    expect(await db.query('cari_hareket', where: "global_id = 'eski'"), isEmpty);
    expect(await db.query('cari_hareket', where: "global_id = 'yeni'"), hasLength(1));

    // Başka şubenin kasa hareketi aynı tarihte olsa da yazılır (şube bazlı aralık).
    await Veritabani().supaKayitlariEkle('kasa_hareketleri', [
      {'global_id': 'k-diger', 'hareket_tipi': 'Satış', 'tutar': 10.0, 'sube_id': 2,
       'tarih': '2026-03-01T10:00:00'},
      {'global_id': 'k-bu', 'hareket_tipi': 'Satış', 'tutar': 10.0, 'sube_id': _sube,
       'tarih': '2026-03-01T10:00:00'},
    ]);
    expect(await db.query('kasa_hareketleri', where: "global_id = 'k-diger'"), hasLength(1));
    expect(await db.query('kasa_hareketleri', where: "global_id = 'k-bu'"), isEmpty);
  });
}
