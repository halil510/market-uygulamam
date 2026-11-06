// test/ekranlar/alim_para_hareketi_test.dart
//
// Derin analizde bulundu (P0): alim_ekrani.dart'ta Nakit/Havale ile
// yapılan alışlarda gerçek bir kasa/banka hareketi HİÇ oluşturulmuyordu
// — stok artıyor ama kasadan/bankadan hiç para çıkmamış gibi görünüyordu
// (protokol §10 ihlali). Bu test, _alimKaydet()'in düzeltilen mantığını
// (kalemler+stok+kasa/banka hareketi TEK transaction'da) gerçek depo Txn
// metotlarıyla, gerçek şema üzerinde doğruluyor.
//
// 2026-11-06 (test güvenilirliği, Kademe 1): bu test ÖNCEDEN _alimKaydet()
// mantığını KOPYALAYAN basitleştirilmiş bir yardımcı çağırıyordu — üretim
// kodu bozulsa bile yeşil kalırdı. Artık ekranın kullandığı GERÇEK
// AlimIslemServisi().alimKaydet() çağrılıyor.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/servisler/alim_islem_servisi.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

/// GERÇEK AlimIslemServisi().alimKaydet(); oluşan alım fişinin id'sini döner.
Future<int> _alimKaydet(
  Database db, {
  required int urunId,
  required int cariId,
  required double miktar,
  required double alisFiyat,
  required String odemeYontemi,
  int? bankaHesapId,
}) async {
  await AlimIslemServisi().alimKaydet(
    mevcutSiparisId: null,
    kalemler: [AlimKalemGirdi(urunId: urunId, miktar: miktar, alisFiyat: alisFiyat)],
    tedarikciId: cariId,
    tedarikciAdi: 'Test Tedarikçi',
    genelToplam: miktar * alisFiyat,
    odemeYontemi: odemeYontemi,
    bankaHesapId: bankaHesapId,
    kullaniciId: null,
    kullaniciAdi: null,
  );
  final son = await db.query('tedarikci_siparisler', orderBy: 'id DESC', limit: 1);
  return son.first['id'] as int;
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

  group('Alım — gerçek para hareketi (P0 regresyonu)', () {
    test('Nakit alışta kasadan gerçek çıkış hareketi oluşur', () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db, stok: 10);
      final cariId = await TestVeritabani.ornekCariEkle(db, cariTipi: 'Tedarikçi');
      final alimId = await _alimKaydet(db,
          urunId: urunId, cariId: cariId, miktar: 20, alisFiyat: 5, odemeYontemi: 'Nakit');

      final kasa = await db.query('kasa_hareketleri',
          where: 'referans_id = ? AND referans_turu = ?', whereArgs: [alimId, 'alim']);
      expect(kasa, hasLength(1), reason: 'Nakit alışta kasa çıkışı OLUŞMALI');
      expect((kasa.first['tutar'] as num).toDouble(), equals(100.0));

      final urun = (await db.query('urunler', where: 'id = ?', whereArgs: [urunId])).first;
      expect((urun['stok'] as num).toDouble(), equals(30.0));
    });

    test('Havale alışta banka hesabından gerçek çıkış hareketi oluşur', () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db, stok: 0);
      final cariId = await TestVeritabani.ornekCariEkle(db, cariTipi: 'Tedarikçi');
      final hesapId = await db.insert('banka_hesaplar', {
        'banka_id': 1, 'hesap_adi': 'Test Hesap', 'hesap_no': '123', 'bakiye': 1000,
      });

      await _alimKaydet(db,
          urunId: urunId, cariId: cariId, miktar: 10, alisFiyat: 8,
          odemeYontemi: 'Havale', bankaHesapId: hesapId);

      final banka = await db.query('banka_hareketler', where: 'banka_hesap_id = ?', whereArgs: [hesapId]);
      expect(banka, hasLength(1), reason: 'Havale alışta banka çıkışı OLUŞMALI');
      expect(banka.first['islem_tipi'], equals('Giden'));
      expect((banka.first['tutar'] as num).toDouble(), equals(80.0));

      final hesap = (await db.query('banka_hesaplar', where: 'id = ?', whereArgs: [hesapId])).first;
      expect((hesap['bakiye'] as num).toDouble(), equals(920.0), reason: '1000 - 80 = 920');
    });

    test('Cari alışta kasa/banka hareketi OLUŞMAZ (borç olarak kalır)', () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db, stok: 0);
      final cariId = await TestVeritabani.ornekCariEkle(db, cariTipi: 'Tedarikçi');
      final alimId = await _alimKaydet(db,
          urunId: urunId, cariId: cariId, miktar: 5, alisFiyat: 10, odemeYontemi: 'Cari');

      final kasa = await db.query('kasa_hareketleri', where: 'referans_id = ?', whereArgs: [alimId]);
      final banka = await db.query('banka_hareketler');
      expect(kasa, isEmpty);
      expect(banka, isEmpty);
    });
  });
}
