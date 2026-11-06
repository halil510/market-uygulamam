// test/servisler/iade_oturum_kalem_sil_test.dart
//
// Regresyon (2026-11-06): IadeIslemServisi.oturumIadeSil() — İade ekranı
// oturum listesinden BİR ürün satırını silme. Belge (iade) birden çok ürün
// taşıyabildiği halde fonksiyon:
//   - TÜM iade belgesini 'iptal'e çekiyordu (diğer ürünler raporlardan düşer),
//   - belgenin TÜM nakdini kasaya geri yazıyordu (yalnız silinen ürünü değil),
//   - silinen ürünün iade_kalem satırına hiç dokunmuyordu (cari "kalan" yanlış),
//   - ikinci çağrıda kasayı TEKRAR ters çeviriyordu (idempotent değildi).
// GERÇEK manuelKalemEkle / oturumIadeSil çağrılır.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/servisler/iade_islem_servisi.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  final servis = IadeIslemServisi();

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (_) async => null);
    SharedPreferences.setMockInitialValues({});
    db = await TestVeritabani.olustur();
    Veritabani.testVeritabani = db;
  });
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    Veritabani.testVeritabani = null;
    await db.close();
  });

  /// Aynı iade belgesine A (2×30=60) ve B (1×40=40) ürünlerini ekler.
  Future<({int iadeId, int a, int b, int? cariId})> ikiKalemliIade(
      {String odeme = 'Nakit', bool cariIle = false}) async {
    final a = await TestVeritabani.ornekUrunEkle(db, urunAdi: 'A', barkod: '8690000000011', stok: 10);
    final b = await TestVeritabani.ornekUrunEkle(db, urunAdi: 'B', barkod: '8690000000028', stok: 10);
    final cariId = cariIle ? await TestVeritabani.ornekCariEkle(db) : null;
    final iadeId = await servis.manuelKalemEkle(
        oturumIadeId: null, cariId: cariId, cariTipi: cariIle ? 'Müşteri' : null,
        fisNo: 'IAD-T1', urunId: a, urunAdi: 'A', miktar: 2, fiyat: 30, toplam: 60,
        neden: 'test', odemeYontemi: odeme, kullaniciId: null, kullaniciAdi: 'T');
    await servis.manuelKalemEkle(
        oturumIadeId: iadeId, cariId: cariId, cariTipi: cariIle ? 'Müşteri' : null,
        fisNo: 'IAD-T1', urunId: b, urunAdi: 'B', miktar: 1, fiyat: 40, toplam: 40,
        neden: 'test', odemeYontemi: odeme, kullaniciId: null, kullaniciAdi: 'T');
    return (iadeId: iadeId, a: a, b: b, cariId: cariId);
  }

  Future<void> sil(int iadeId, int urunId, double miktar, double toplam, int? cariId) =>
      servis.oturumIadeSil(iadeId: iadeId, urunId: urunId, miktar: miktar,
          toplam: toplam, cariId: cariId, fisNo: 'IAD-T1');

  Future<double> stok(int urunId) async =>
      ((await db.query('urunler', columns: ['stok'], where: 'id = ?', whereArgs: [urunId]))
              .first['stok'] as num)
          .toDouble();

  Future<double> kasaIptalToplami(int iadeId) async => ((await db.rawQuery(
              "SELECT COALESCE(SUM(tutar),0) AS t FROM kasa_hareketleri "
              "WHERE referans_id = ? AND referans_turu = 'iade_iptal'", [iadeId]))
          .first['t'] as num)
      .toDouble();

  Future<Map<String, Object?>> iade(int id) async =>
      (await db.query('iade', where: 'id = ?', whereArgs: [id])).first;

  test('iki ürünlü belgeden A silinince yalnız A çıkar: belge açık kalır, toplam 40, kasa 60 geri', () async {
    final h = await ikiKalemliIade();
    expect(await stok(h.a), 12);
    expect(await stok(h.b), 11);

    await sil(h.iadeId, h.a, 2, 60, null);

    final i = await iade(h.iadeId);
    expect(i['durum'], isNot('iptal'), reason: 'B hâlâ iade edilmiş durumda');
    expect((i['toplam_tutar'] as num).toDouble(), 40.0);
    expect(await kasaIptalToplami(h.iadeId), 60.0, reason: 'yalnız A nakdi geri alınır');
    expect(await stok(h.a), 10, reason: 'A stoğu iade öncesine döner');
    expect(await stok(h.b), 11, reason: 'B etkilenmez');
    final kalemA = (await db.query('iade_kalem',
            where: 'iade_id = ? AND urun_id = ?', whereArgs: [h.iadeId, h.a]))
        .first;
    expect((kalemA['miktar'] as num).toDouble(), 0.0);
    expect((kalemA['toplam'] as num).toDouble(), 0.0);
  });

  test('aynı satır iki kez silinmek istenirse ikinci çağrı reddedilir; kasa/stok bir kez ters çevrilir', () async {
    final h = await ikiKalemliIade();
    await sil(h.iadeId, h.a, 2, 60, null);
    await expectLater(sil(h.iadeId, h.a, 2, 60, null), throwsException);

    expect(await kasaIptalToplami(h.iadeId), 60.0);
    expect(await stok(h.a), 10);
  });

  test('A sonra B silinince belge iptal olur ve kasa net etkisi sıfırlanır', () async {
    final h = await ikiKalemliIade();
    await sil(h.iadeId, h.a, 2, 60, null);
    await sil(h.iadeId, h.b, 1, 40, null);

    expect((await iade(h.iadeId))['durum'], 'iptal');
    expect(await kasaIptalToplami(h.iadeId), 100.0);
    final net = ((await db.rawQuery(
            "SELECT COALESCE(SUM(CASE WHEN referans_turu='iade' THEN -tutar ELSE tutar END),0) AS n "
            "FROM kasa_hareketleri WHERE referans_id = ? AND referans_turu IN ('iade','iade_iptal')",
            [h.iadeId]))
        .first['n'] as num)
        .toDouble();
    expect(net, 0.0);
    expect(await stok(h.a), 10);
    expect(await stok(h.b), 10);
  });

  test('Cari iadede A silinince müşterinin alacağı yalnız B kadar kalır', () async {
    final h = await ikiKalemliIade(odeme: 'Cari', cariIle: true);
    var cari = (await db.query('cari', where: 'id = ?', whereArgs: [h.cariId])).first;
    expect((cari['bakiye'] as num).toDouble(), -100.0);

    await sil(h.iadeId, h.a, 2, 60, h.cariId);

    cari = (await db.query('cari', where: 'id = ?', whereArgs: [h.cariId])).first;
    expect((cari['bakiye'] as num).toDouble(), -40.0);
    expect(await kasaIptalToplami(h.iadeId), 0.0, reason: 'Cari iadede kasa hiç etkilenmemişti');
  });

  test('tek ürünlü belgede satır silinince belge iptal olur (eski davranış korunur)', () async {
    final a = await TestVeritabani.ornekUrunEkle(db, urunAdi: 'A', stok: 5);
    final iadeId = await servis.manuelKalemEkle(
        oturumIadeId: null, cariId: null, cariTipi: null, fisNo: 'IAD-T2',
        urunId: a, urunAdi: 'A', miktar: 1, fiyat: 25, toplam: 25, neden: 'test',
        odemeYontemi: 'Nakit', kullaniciId: null, kullaniciAdi: 'T');

    await servis.oturumIadeSil(iadeId: iadeId, urunId: a, miktar: 1, toplam: 25,
        cariId: null, fisNo: 'IAD-T2');

    expect((await iade(iadeId))['durum'], 'iptal');
    expect(await kasaIptalToplami(iadeId), 25.0);
    expect(await stok(a), 5);
  });
}
