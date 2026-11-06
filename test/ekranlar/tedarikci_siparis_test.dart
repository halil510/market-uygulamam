// test/ekranlar/tedarikci_siparis_test.dart
//
// FAZ 6 (Satın Alma): "Tedarikçi Siparişleri" ekranındaki 'Bekleyen' sipariş
// akışı önceden hiç implement edilmemişti — 'Sipariş Ver' doğrudan Alım
// (mal kabul) ekranına atlıyor, hiçbir zaman 'beklemede' kayıt açmıyordu.
// Bu test, düzeltilen iki adımı (SiparisOlusturEkrani ve
// AlimEkrani(mevcutSiparisId:)) gerçek şema üzerinde, o ekranlardaki
// mantıkla BİREBİR aynı sırada doğrular:
//   1) Sipariş oluşturma: SADECE 'beklemede' kayıt açar, stok/kasa/cari
//      hiçbir şekilde etkilenmez.
//   2) Teslim alma: var olan siparişi GÜNCELLER (mükerrer kayıt açmaz),
//      kalemin teslim_mik'ini işler, stok artar, gerçek kasa hareketi oluşur.
//
// 2026-11-06 (test güvenilirliği, Kademe 1): bu test ÖNCEDEN iki adımı
// KOPYALAYAN yardımcılar çağırıyordu — üretim kodu bozulsa bile yeşil
// kalırdı. Artık ekranların kullandığı GERÇEK metotlar çağrılıyor:
// sipariş → TedarikciSiparisDeposu().olustur() (no: BelgeNoServisi),
// teslim alma → AlimIslemServisi().alimKaydet(mevcutSiparisId: ...).
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/depolar/tedarikci_siparis_deposu.dart';
import 'package:market_plus/servisler/alim_islem_servisi.dart';
import 'package:market_plus/servisler/belge_no_servisi.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

/// SiparisOlusturEkrani ile aynı çağrı: GERÇEK TedarikciSiparisDeposu().olustur().
Future<int> _siparisOlustur(
  Database db, {
  required int cariId,
  required int urunId,
  required double miktar,
  required double birimFiyat,
}) async {
  return TedarikciSiparisDeposu().olustur(
    tedarikciId: cariId,
    tedarikciUnvan: 'Test Tedarikçi',
    kalemler: [
      TedarikciSiparisKalemGirdi(urunId: urunId, miktar: miktar, birimFiyat: birimFiyat),
    ],
    genelToplam: miktar * birimFiyat,
    siparisNo: await BelgeNoServisi().uret('siparis'),
    olusturanId: null,
  );
}

/// AlimEkrani(mevcutSiparisId:) ile aynı çağrı: GERÇEK
/// AlimIslemServisi().alimKaydet() sipariş modunda, Nakit ödeme.
Future<void> _siparisiTeslimAl(
  Database db, {
  required int siparisId,
  required int cariId,
  required int urunId,
  required double teslimMiktar,
  required double birimFiyat,
}) async {
  await AlimIslemServisi().alimKaydet(
    mevcutSiparisId: siparisId,
    kalemler: [AlimKalemGirdi(urunId: urunId, miktar: teslimMiktar, alisFiyat: birimFiyat)],
    tedarikciId: cariId,
    tedarikciAdi: 'Test Tedarikçi',
    genelToplam: teslimMiktar * birimFiyat,
    odemeYontemi: 'Nakit',
    kullaniciId: null,
    kullaniciAdi: null,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;

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

  group('Tedarikçi Siparişi — bekleyen sipariş → teslim alma (FAZ 6)', () {
    test('Sipariş oluşturma stok/kasa/cariyi ETKİLEMEZ, sadece beklemede kayıt açar', () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db, stok: 5);
      final cariId = await TestVeritabani.ornekCariEkle(db, cariTipi: 'Tedarikçi');

      final siparisId = await _siparisOlustur(db, cariId: cariId, urunId: urunId, miktar: 20, birimFiyat: 5);

      final siparis = (await db.query('tedarikci_siparisler', where: 'id = ?', whereArgs: [siparisId])).first;
      expect(siparis['durum'], equals('beklemede'));

      final urun = (await db.query('urunler', where: 'id = ?', whereArgs: [urunId])).first;
      expect((urun['stok'] as num).toDouble(), equals(5.0), reason: 'Sipariş vermek stoğu artırmamalı');

      final kasa = await db.query('kasa_hareketleri', where: 'referans_id = ?', whereArgs: [siparisId]);
      expect(kasa, isEmpty, reason: 'Sipariş vermek kasa hareketi oluşturmamalı');
    });

    test('Teslim alma mevcut siparişi GÜNCELLER, mükerrer kayıt açmaz, stok/kasa etkilenir', () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db, stok: 5);
      final cariId = await TestVeritabani.ornekCariEkle(db, cariTipi: 'Tedarikçi');
      final siparisId = await _siparisOlustur(db, cariId: cariId, urunId: urunId, miktar: 20, birimFiyat: 5);

      await _siparisiTeslimAl(db, siparisId: siparisId, cariId: cariId, urunId: urunId, teslimMiktar: 20, birimFiyat: 5.5);

      final tumSiparisler = await db.query('tedarikci_siparisler', where: 'cari_id = ?', whereArgs: [cariId]);
      expect(tumSiparisler, hasLength(1), reason: 'Teslim alma mükerrer sipariş satırı AÇMAMALI');
      expect(tumSiparisler.first['durum'], equals('teslim_alindi'));

      final kalem = (await db.query('tedarikci_siparis_kalem', where: 'siparis_id = ?', whereArgs: [siparisId])).first;
      expect((kalem['teslim_mik'] as num).toDouble(), equals(20.0));

      final urun = (await db.query('urunler', where: 'id = ?', whereArgs: [urunId])).first;
      expect((urun['stok'] as num).toDouble(), equals(25.0), reason: '5 + 20 = 25');

      final kasa = await db.query('kasa_hareketleri', where: 'referans_id = ? AND referans_turu = ?', whereArgs: [siparisId, 'alim']);
      expect(kasa, hasLength(1));
      expect((kasa.first['tutar'] as num).toDouble(), equals(110.0), reason: '20 × 5.5 = 110');
    });

    // Çift dokunma / geri tuşu: aynı sipariş ikinci kez teslim alınamaz.
    test('aynı sipariş ikinci kez teslim alınmak istenirse reddedilir, stok/kasa bir kez işlenir', () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db, stok: 5);
      final cariId = await TestVeritabani.ornekCariEkle(db, cariTipi: 'Tedarikçi');
      final siparisId = await _siparisOlustur(db, cariId: cariId, urunId: urunId, miktar: 10, birimFiyat: 5);

      await _siparisiTeslimAl(db, siparisId: siparisId, cariId: cariId, urunId: urunId, teslimMiktar: 10, birimFiyat: 5);
      await expectLater(
          _siparisiTeslimAl(db, siparisId: siparisId, cariId: cariId, urunId: urunId, teslimMiktar: 10, birimFiyat: 5),
          throwsException);

      final urun = (await db.query('urunler', where: 'id = ?', whereArgs: [urunId])).first;
      expect((urun['stok'] as num).toDouble(), equals(15.0));
      final kasa = await db.query('kasa_hareketleri', where: 'referans_id = ? AND referans_turu = ?', whereArgs: [siparisId, 'alim']);
      expect(kasa, hasLength(1));
    });
  });
}
