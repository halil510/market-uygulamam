// test/servisler/alim_havale_sil_test.dart
//
// Derin denetim (2026-11-09) #6, yüksek: Havale ile yapılan alım silinince
// bankadan çıkan para hiç geri yazılmıyordu (banka satırına referans
// yazılmadığı için sil() onu bulamıyordu).
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/servisler/alim_islem_servisi.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

Future<double> _bankaBakiye(Database db, int hesapId) async =>
    ((await db.query('banka_hesaplar', where: 'id = ?', whereArgs: [hesapId])).first['bakiye']
            as num)
        .toDouble();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late int hesapId;
  late int urunId;
  late int tedarikciId;
  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (_) async => null);
    SharedPreferences.setMockInitialValues({});
    db = await TestVeritabani.olustur();
    Veritabani.testVeritabani = db;
    if ((await db.query('subeler', where: 'id = 1')).isEmpty) {
      await db.insert('subeler', {'id': 1, 'sube_kodu': 'MRK', 'sube_adi': 'Merkez'});
    }
    final bankaId = await db.insert('bankalar', {'ad': 'Test Bank', 'aktif': 1});
    hesapId = await db.insert('banka_hesaplar', {
      'global_id': 'h1', 'banka_id': bankaId, 'hesap_adi': 'Vadesiz', 'hesap_no': '1',
      'bakiye': 10000.0, 'kullanilabilir_bakiye': 10000.0, 'aktif': 1,
    });
    urunId = await TestVeritabani.ornekUrunEkle(db, stok: 0);
    tedarikciId = await TestVeritabani.ornekCariEkle(db, cariTipi: 'Tedarikçi');
  });
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    Veritabani.testVeritabani = null;
    await db.close();
  });

  test('havale alımı silinince banka bakiyesi eski hâline döner', () async {
    await AlimIslemServisi().alimKaydet(
      mevcutSiparisId: null,
      kalemler: [AlimKalemGirdi(urunId: urunId, miktar: 10, alisFiyat: 500)],
      tedarikciId: tedarikciId, tedarikciAdi: 'Tedarikçi', genelToplam: 5000,
      odemeYontemi: 'Havale', bankaHesapId: hesapId,
      kullaniciId: null, kullaniciAdi: null,
    );
    expect(await _bankaBakiye(db, hesapId), 5000);
    final alimId = (await db.query('tedarikci_siparisler')).single['id'] as int;

    await AlimIslemServisi().sil(alimId);

    expect(await _bankaBakiye(db, hesapId), 10000, reason: 'önceden 5000 eksik kalıyordu');
  });

  test('referanssız eski havale alımı da açıklamasından bulunup geri alınır', () async {
    await AlimIslemServisi().alimKaydet(
      mevcutSiparisId: null,
      kalemler: [AlimKalemGirdi(urunId: urunId, miktar: 10, alisFiyat: 500)],
      tedarikciId: tedarikciId, tedarikciAdi: 'Tedarikçi', genelToplam: 5000,
      odemeYontemi: 'Havale', bankaHesapId: hesapId,
      kullaniciId: null, kullaniciAdi: null,
    );
    // Düzeltmeden önceki kayıt biçimi: referans yok.
    await db.update('banka_hareketler', {'referans_id': null, 'referans_turu': null});
    final alimId = (await db.query('tedarikci_siparisler')).single['id'] as int;

    await AlimIslemServisi().sil(alimId);

    expect(await _bankaBakiye(db, hesapId), 10000);
  });
}
