// test/servisler/bulut_satis_kimlik_test.dart
//
// "Sync çakışması" kök neden regresyonları (2026-09-27):
//  - Satış buluta İKİ farklı global_id ile gidiyordu (bellekteki model
//    global_id=null ile bildirilince BulutManager yeni kimlik üretiyordu)
//    → diğer cihazda / geri çekimde "-SYNC" hayalet satış.
//  - Kalemler k.toMap() ile satis_id=0 ve kimliksiz gidiyordu.
//  - Fiş güncellemede silinen kalemler bulutta kalıyordu.
//  - fisNoUret başka cihazın kullandığı numarayı yeniden verebiliyordu.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/depolar/satis_deposu.dart';
import 'package:market_plus/modeller/satis_kalem_model.dart';
import 'package:market_plus/modeller/satis_model.dart';
import 'package:market_plus/servisler/bulut/bulut_manager.dart';
import 'package:market_plus/servisler/bulut/bulut_saglayici.dart';
import 'package:market_plus/servisler/kolon_haritalama.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

class _SahteSaglayici implements IBulutSaglayici {
  final upsertler = <String, List<Map<String, dynamic>>>{};
  final kaliciSilinenler = <String, List<String>>{};

  @override String get ad => 'Sahte';
  @override String get ikon => '🧪';
  @override Future<BaglantiSonuc> baglantiTest() async =>
      const BaglantiSonuc(basarili: true, mesaj: 'ok');
  @override
  Future<void> upsert({required String tablo, required Map<String, dynamic> veri,
      required String uniqueAlan}) async =>
      upsertler.putIfAbsent(tablo, () => []).add(veri);
  @override
  Future<BulutSonuc> topluUpsert({required String tablo,
      required List<Map<String, dynamic>> veriler, required String uniqueAlan}) async {
    upsertler.putIfAbsent(tablo, () => []).addAll(veriler);
    return BulutSonuc(basarili: veriler.length);
  }
  @override
  Future<List<Map<String, dynamic>>> cek({required String tablo,
      DateTime? sonGuncelleme, int limit = 1000}) async => [];
  @override
  Future<void> sil({required String tablo, required String uniqueAlan,
      required String deger}) async {}
  @override
  Future<void> kaliciSil({required String tablo, required String uniqueAlan,
      required String deger}) async =>
      kaliciSilinenler.putIfAbsent(tablo, () => []).add(deger);
  @override Future<void> ayarlariKaydet(Map<String, String> ayarlar) async {}
  @override Future<Map<String, String>> ayarlariYukle() async => {};
}

/// Kuyruk boşalana kadar gönderim turlarını çalıştırır.
Future<void> _kuyruguBosalt(Database db) async {
  for (var i = 0; i < 60; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await BulutManager().zorlaGonder();
    final r = await db.rawQuery(
        "SELECT COUNT(*) AS c FROM sync_queue WHERE durum = 'beklemede'");
    if ((r.first['c'] as int) == 0) return;
  }
  fail('sync_queue boşalmadı');
}

SatisKalemModel _kalem(int urunId, {double miktar = 1}) => SatisKalemModel(
    satisId: 0, urunId: urunId, urunAdi: 'Test Ürün',
    miktar: miktar, birimFiyat: 10, toplamTutar: 10 * miktar);

void main() {
  late Database db;
  late _SahteSaglayici sahte;
  late int urunId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await TestVeritabani.olustur();
    Veritabani.testVeritabani = db;
    urunId = await TestVeritabani.ornekUrunEkle(db);
    sahte = _SahteSaglayici();
    await BulutManager().saglayiciAyarla(sahte);
    await _kuyruguBosalt(db);
    sahte.upsertler.clear();
  });

  tearDown(() async {
    BulutManager().testIcinSifirla();
    Veritabani.testVeritabani = null;
    await db.close();
  });

  Future<int> satisYap(Database db) async {
    late int satisId;
    await db.transaction((txn) async {
      satisId = await SatisDeposu().satisEkleTxn(
          txn,
          SatisModel(fisNo: 'T-1', tarih: DateTime.now(), toplamTutar: 20,
              genelToplam: 20, odenenTutar: 20, odemeYontemi: 'Nakit', fisTipi: 'Satış'),
          [_kalem(urunId), _kalem(urunId)]);
    });
    return satisId;
  }

  test('satış buluta TEK global_id ile gider, yerel kimlik değişmez', () async {
    final satisId = await satisYap(db);
    final yerelGid = (await db.query('satislar', where: 'id = ?', whereArgs: [satisId]))
        .first['global_id'] as String;

    await SatisDeposu().bulutaBildir(satisId);
    await _kuyruguBosalt(db);

    final gidenGidler = sahte.upsertler['satislar']!.map((r) => r['global_id']).toSet();
    expect(gidenGidler, {yerelGid});
    final sonGid = (await db.query('satislar', where: 'id = ?', whereArgs: [satisId]))
        .first['global_id'];
    expect(sonGid, yerelGid);

    final kalemler = sahte.upsertler['satis_kalem']!;
    expect(kalemler.map((k) => k['global_id']).toSet().length, 2);
    expect(kalemler.every((k) => k['global_id'] != null), isTrue);
    expect(kalemler.every((k) => k['satis_id'] == satisId), isTrue);
  });

  test('eski çağrı biçimi (global_id=null model) yeni kimlik ÜRETMEZ; kimliksiz kalem reddedilir', () async {
    final satisId = await satisYap(db);
    final yerelGid = (await db.query('satislar', where: 'id = ?', whereArgs: [satisId]))
        .first['global_id'] as String;
    await _kuyruguBosalt(db);
    sahte.upsertler.clear();

    final model = SatisModel(fisNo: 'T-1', tarih: DateTime.now(), toplamTutar: 20,
        genelToplam: 20, odenenTutar: 20, odemeYontemi: 'Nakit', fisTipi: 'Satış');
    BulutManager().upsert('satislar', {...model.toMap(), 'id': satisId, 'global_id': null});
    BulutManager().upsert('satis_kalem', _kalem(urunId).toMap());
    await _kuyruguBosalt(db);

    expect(sahte.upsertler['satislar']!.map((r) => r['global_id']).toSet(), {yerelGid});
    expect(sahte.upsertler['satis_kalem'], isNull);
    final sonGid = (await db.query('satislar', where: 'id = ?', whereArgs: [satisId]))
        .first['global_id'];
    expect(sonGid, yerelGid);
  });

  test('fiş güncellemede eski kalemler bulutta kalıcı silinir', () async {
    final satisId = await satisYap(db);
    await _kuyruguBosalt(db);
    final eskiGidler = (await db.query('satis_kalem', where: 'satis_id = ?', whereArgs: [satisId]))
        .map((r) => r['global_id'] as String)
        .toSet();

    await db.transaction((txn) => SatisDeposu().fisiGuncelleTxn(txn,
        satisId: satisId, yeniKalemler: [_kalem(urunId, miktar: 3)],
        yeniGenelToplam: 30, yeniOdenenTutar: 30));
    await _kuyruguBosalt(db);

    expect(sahte.kaliciSilinenler['satis_kalem']!.toSet(), eskiGidler);
  });

  test('fisNoUret yerelde kullanılmış satış numarasını atlar', () async {
    final yil = DateTime.now().year;
    await db.insert('satislar', {
      'global_id': 'baska-cihaz', 'fis_no': 'MKP$yil${1.toString().padLeft(9, '0')}',
      'tarih': DateTime.now().toIso8601String(),
    });
    final no = await Veritabani().fisNoUret('satis');
    expect(no, 'MKP$yil${2.toString().padLeft(9, '0')}');
  });

  test('kasa bazlı fiş no: her kasa kendi serisi, eski seriyle çakışmaz', () async {
    final yil = DateTime.now().year;
    final eski = await Veritabani().fisNoUret('satis'); // terminal kaydı yok
    expect(eski, 'MKP$yil${1.toString().padLeft(9, '0')}');

    await db.insert('yerel_terminal', {'id': 1, 'terminal_id': 3, 'terminal_kodu': 'T3'});
    final k1 = await Veritabani().fisNoUret('satis');
    final k2 = await Veritabani().fisNoUret('satis');
    expect(k1, 'MKP${yil}03${1.toString().padLeft(7, '0')}');
    expect(k2, 'MKP${yil}03${2.toString().padLeft(7, '0')}');
    final seri = await db.query('fis_seri', where: 'fis_tipi = ?', whereArgs: ['satis#T03']);
    expect(seri.single['son_fis_no'], 2);
  });

  test('last_updated buluta açık UTC gider', () {
    final yerel = DateTime(2026, 9, 27, 20, 15).toIso8601String(); // dilimsiz
    final cevrilmis = KolonHaritalama.cevir('satislar', {'last_updated': yerel});
    expect(cevrilmis['last_updated'], endsWith('Z'));
    expect(DateTime.parse(cevrilmis['last_updated'] as String)
        .isAtSameMomentAs(DateTime.parse(yerel)), isTrue); // aynı an
  });

  test('ebeveyn tablo çocuklarından önce gönderilir', () {
    expect(KolonHaritalama.derinlik('satislar'), lessThan(KolonHaritalama.derinlik('satis_kalem')));
    expect(KolonHaritalama.derinlik('cari'), lessThan(KolonHaritalama.derinlik('cari_hareket')));
    expect(KolonHaritalama.derinlik('kategoriler'), 0); // kendine referans döngü değil
  });
}
