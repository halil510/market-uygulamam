// test/depolar/cari_coklu_terminal_test.dart
//
// Cari modülü — çoklu terminal ve ekstre regresyonları (2026-09-27):
//  - Buluttan gelen cari satırındaki 'bakiye' yerel bakiyeyi ezmez.
//  - Başka kasada iptal edilen hareket (is_deleted güncellemesi — INSERT
//    tetikleyicisi çalışmaz) sonrası mutabakat bakiyeyi düzeltir.
//  - Mükerrer cari kodu düzeltmesi her kasada AYNI cariyi korur (global_id).
//  - Vadesi geçmiş listesi ödenmiş eski borcu saymaz (FIFO).
//  - Devreden bakiye (ekstre).
//  - Polimorfik referans haritası (referans_id / fis_id).
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/depolar/cari_deposu.dart';
import 'package:market_plus/servisler/kolon_haritalama.dart';
import 'package:market_plus/servisler/senkron_sonrasi_mutabakat.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

Future<void> _hareket(Database db, int cariId,
    {double borc = 0, double alacak = 0, required DateTime tarih, String gid = '', String fisTipi = 'Satış'}) async {
  await db.insert('cari_hareket', {
    'global_id': gid.isEmpty ? 'h-${DateTime.now().microsecondsSinceEpoch}-$borc-$alacak' : gid,
    'cari_id': cariId,
    'tarih': tarih.toIso8601String(),
    'fis_tipi': fisTipi,
    'aciklama': 'test',
    'borc': borc,
    'alacak': alacak,
    'is_deleted': 0,
  });
}

Future<double> _bakiye(Database db, int cariId) async =>
    ((await db.query('cari', columns: ['bakiye'], where: 'id = ?', whereArgs: [cariId]))
            .first['bakiye'] as num)
        .toDouble();

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

  test('buluttan gelen cari güncellemesi yerel bakiyeyi ezmez', () async {
    final cariId = await TestVeritabani.ornekCariEkle(db);
    await db.update('cari', {'global_id': 'cari-1'}, where: 'id = ?', whereArgs: [cariId]);
    await _hareket(db, cariId, borc: 100, tarih: DateTime.now());
    expect(await _bakiye(db, cariId), 100);

    await Veritabani().supaKayitlariGuncelle('cari', [
      {'global_id': 'cari-1', 'unvan': 'Yeni Ad', 'bakiye': 999.0,
       'last_updated': DateTime.now().add(const Duration(minutes: 1)).toIso8601String()},
    ]);
    final satir = (await db.query('cari', where: 'id = ?', whereArgs: [cariId])).first;
    expect(satir['unvan'], 'Yeni Ad');
    expect((satir['bakiye'] as num).toDouble(), 100);
  });

  test('başka kasada iptal edilen hareket sonrası mutabakat bakiyeyi düzeltir', () async {
    final cariId = await TestVeritabani.ornekCariEkle(db);
    await _hareket(db, cariId, borc: 100, tarih: DateTime.now(), gid: 'satis-h');
    await _hareket(db, cariId, alacak: 40, tarih: DateTime.now(), gid: 'tahsilat-h', fisTipi: 'Tahsilat');
    expect(await _bakiye(db, cariId), 60);

    // Buluttan soft-delete (UPDATE) — INSERT tetikleyicisi çalışmaz.
    await db.update('cari_hareket', {'is_deleted': 1}, where: 'global_id = ?', whereArgs: ['tahsilat-h']);
    expect(await _bakiye(db, cariId), 60); // bayat

    await SenkronSonrasiMutabakat.calistir();
    expect(await _bakiye(db, cariId), 100);
  });

  test('aynı cari kodu buluttan inerse: her kasada aynı cari kodu korur', () async {
    final ayniTarih = DateTime(2026, 9, 1).toIso8601String();
    // Senaryo 1: yerel cari global_id 'zzz', gelen 'aaa' → gelen korur,
    // YEREL yeniden adlandırılır.
    final yerel = await db.insert('cari', {'unvan': 'Yerel', 'cari_tipi': 'Müşteri',
        'cari_kodu': 'CARIO-5', 'global_id': 'zzz', 'olusturma_tarihi': ayniTarih,
        'bakiye': 0, 'aktif': 1, 'is_deleted': 0});
    await Veritabani().supaKayitlariEkle('cari', [
      {'unvan': 'Gelen', 'cari_tipi': 'Müşteri', 'cari_kodu': 'CARIO-5',
       'global_id': 'aaa', 'olusturma_tarihi': ayniTarih, 'bakiye': 0, 'aktif': 1, 'is_deleted': 0},
    ]);
    final gelenKod = (await db.query('cari', where: 'global_id = ?', whereArgs: ['aaa'])).first['cari_kodu'];
    final yerelKod = (await db.query('cari', where: 'id = ?', whereArgs: [yerel])).first['cari_kodu'];
    expect(gelenKod, 'CARIO-5');
    expect(yerelKod, isNot('CARIO-5'));

    // Senaryo 2: gelen daha sonra oluşturulmuş → gelen yeni kod alır.
    await Veritabani().supaKayitlariEkle('cari', [
      {'unvan': 'Geç', 'cari_tipi': 'Müşteri', 'cari_kodu': 'CARIO-5',
       'global_id': 'bbb', 'olusturma_tarihi': DateTime(2026, 9, 2).toIso8601String(),
       'bakiye': 0, 'aktif': 1, 'is_deleted': 0},
    ]);
    final gecKod = (await db.query('cari', where: 'global_id = ?', whereArgs: ['bbb'])).first['cari_kodu'];
    expect(gecKod, isNot('CARIO-5'));
    expect((await db.query('cari', where: 'global_id = ?', whereArgs: ['aaa'])).first['cari_kodu'], 'CARIO-5');
  });

  test('vadesi geçmiş: ödenmiş eski borç sayılmaz, ödenmemiş sayılır', () async {
    final eski = DateTime.now().subtract(const Duration(days: 60));
    final bugun = DateTime.now();

    final odemis = await TestVeritabani.ornekCariEkle(db, unvan: 'Ödemiş');
    await db.update('cari', {'vade_gun': 30}, where: 'id = ?', whereArgs: [odemis]);
    await _hareket(db, odemis, borc: 100, tarih: eski);
    await _hareket(db, odemis, alacak: 100, tarih: eski.add(const Duration(days: 5)), fisTipi: 'Tahsilat');
    await _hareket(db, odemis, borc: 50, tarih: bugun);

    final odememis = await TestVeritabani.ornekCariEkle(db, unvan: 'Ödememiş');
    await db.update('cari', {'vade_gun': 30}, where: 'id = ?', whereArgs: [odememis]);
    await _hareket(db, odememis, borc: 100, tarih: eski);
    await _hareket(db, odememis, borc: 50, tarih: bugun);

    final liste = await CariDeposu().vadesiGecmisler();
    final idler = liste.map((c) => c.id).toSet();
    expect(idler.contains(odemis), isFalse);
    expect(idler.contains(odememis), isTrue);
  });

  test('devreden bakiye: tarihten önceki hareketlerin neti', () async {
    final cariId = await TestVeritabani.ornekCariEkle(db);
    await _hareket(db, cariId, borc: 100, tarih: DateTime(2026, 8, 10));
    await _hareket(db, cariId, alacak: 30, tarih: DateTime(2026, 8, 20), fisTipi: 'Tahsilat');
    await _hareket(db, cariId, borc: 500, tarih: DateTime(2026, 9, 5));
    expect(await CariDeposu().devredenBakiye(cariId, DateTime(2026, 9, 1)), 70);
  });

  test('polimorfik referans: tür değerine göre doğru tabloya eşlenir', () {
    expect(KolonHaritalama.satirFkHaritasi('kasa_hareketleri',
        {'referans_turu': 'satis'})!['referans_id'], 'satislar');
    expect(KolonHaritalama.satirFkHaritasi('kasa_hareketleri',
        {'referans_turu': 'cari_hareket'})!['referans_id'], 'cari_hareket');
    expect(KolonHaritalama.satirFkHaritasi('kasa_hareketleri',
        {'referans_turu': 'toplu_islem'})!.containsKey('referans_id'), isFalse);
    expect(KolonHaritalama.satirFkHaritasi('cari_hareket',
        {'fis_tipi': 'İade'})!['fis_id'], 'iade');
    expect(KolonHaritalama.satirFkHaritasi('cari_hareket',
        {'fis_tipi': 'Tahsilat'})!.containsKey('fis_id'), isFalse);
    // Ebeveynler çocuklardan önce gönderilir.
    expect(KolonHaritalama.derinlik('cari_hareket'),
        greaterThan(KolonHaritalama.derinlik('satislar')));
    expect(KolonHaritalama.derinlik('kasa_hareketleri'),
        greaterThan(KolonHaritalama.derinlik('cari_hareket')));
  });
}
