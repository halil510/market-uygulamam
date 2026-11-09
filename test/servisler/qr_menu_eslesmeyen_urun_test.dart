// test/servisler/qr_menu_eslesmeyen_urun_test.dart
//
// DERİN DENETİM (2026-11-09, #74): QrMenuServisi.musteriSiparisKaydet
// eşleşmeyen ürünü urun_id=0 ile eklemeye çalışıyordu; FK açık olduğu için
// kalem düşüyor, hata yutuluyor ve sipariş "alındı" dönüyordu.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/depolar/masa_deposu.dart';
import 'package:market_plus/modeller/masa_model.dart';
import 'package:market_plus/servisler/masa/qr_menu_servisi.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late int urunId;
  late int masaId;

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (_) async => null);
    SharedPreferences.setMockInitialValues({});
    db = await TestVeritabani.olustur();
    Veritabani.testVeritabani = db;
    urunId = await TestVeritabani.ornekUrunEkle(db, satisFiyati: 100);
    masaId = await MasaDeposu().masaEkle(const MasaModel(ad: 'QR1'));
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    Veritabani.testVeritabani = null;
    await db.close();
  });

  Future<List<String>> kaydet(List<Map<String, dynamic>> kalemler) =>
      QrMenuServisi().musteriSiparisKaydet(
          masaId: masaId, kalemler: kalemler, musteriAdi: '', musteriTel: '');

  test('hiçbir ürün eşleşmezse hata fırlatır, sipariş açılmaz (masa boş kalır)', () async {
    await expectLater(
        kaydet([
          {'urun_id': 987654, 'urun_adi': 'Olmayan Ürün', 'miktar': 1},
        ]),
        throwsException);
    expect(await db.query('masa_siparisleri'), isEmpty);
    expect(await db.query('masa_siparis_kalem'), isEmpty);
  });

  test('kısmi eşleşmede eşleşen eklenir, atlanan ürün adı döner', () async {
    final atlanan = await kaydet([
      {'urun_id': urunId, 'urun_adi': 'x', 'miktar': 2},
      {'urun_id': 987654, 'urun_adi': 'Olmayan Ürün', 'miktar': 1},
    ]);
    expect(atlanan, ['Olmayan Ürün']);
    final kalemler = await db.query('masa_siparis_kalem');
    expect(kalemler, hasLength(1));
    expect(kalemler.first['urun_id'], urunId);
  });

  test('hepsi eşleşirse atlanan listesi boş döner', () async {
    expect(
        await kaydet([
          {'urun_id': urunId, 'urun_adi': 'x', 'miktar': 1},
        ]),
        isEmpty);
  });

  test('#90: ödenmiş siparişe kalem eklenemez, toplam değişmez', () async {
    final depo = MasaDeposu();
    final s = await depo.siparisAcVeyaGetir(masaId);
    await depo.kalemEkle(s.id!, urunId: urunId, urunAdi: 'x', birimFiyat: 100, kdvOran: 20);
    await db.update('masa_siparisleri', {'durum': 'odendi'}, where: 'id = ?', whereArgs: [s.id]);
    final onceki = (await db.query('masa_siparisleri', where: 'id = ?', whereArgs: [s.id]))
        .first['toplam_tutar'];
    await expectLater(
        depo.kalemEkle(s.id!, urunId: urunId, urunAdi: 'x', birimFiyat: 100, kdvOran: 20),
        throwsException);
    final kalemId = (await db.query('masa_siparis_kalem')).first['id'] as int;
    await expectLater(depo.kalemSil(kalemId), throwsException);
    expect((await db.query('masa_siparisleri', where: 'id = ?', whereArgs: [s.id]))
        .first['toplam_tutar'], onceki);
  });
}
