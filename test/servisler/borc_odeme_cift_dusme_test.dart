// test/servisler/borc_odeme_cift_dusme_test.dart
//
// Derin denetim (2026-11-09), yüksek:
//  #9  Masaüstü Borç listesinde ESKİ seçili borçla ödenmiş borç ikinci kez
//      ödenebiliyordu (kasadan ikinci kez para çıkıyordu).
//  #10/#11 Borç ödemesinin açtığı gider Giderler'den (yalnız açıklama
//      değişse bile) kaydedilince kasa/banka/kart ikinci kez düşülüyordu.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/depolar/gider_deposu.dart';
import 'package:market_plus/modeller/borc_model.dart';
import 'package:market_plus/modeller/gider_model.dart';
import 'package:market_plus/modeller/kasa_hareket_model.dart';
import 'package:market_plus/servisler/borc_odeme_islem_servisi.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

Future<double> _kasaNet(Database db) async {
  var n = 0.0;
  for (final r in await db.query('kasa_hareketleri', where: 'deleted_at IS NULL')) {
    final t = (r['tutar'] as num).toDouble();
    n += KasaHareketModel.girisMi(r['hareket_tipi'] as String) ? t : -t;
  }
  return n;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (_) async => null);
    SharedPreferences.setMockInitialValues({});
    db = await TestVeritabani.olustur();
    Veritabani.testVeritabani = db;
    if ((await db.query('subeler', where: 'id = 1')).isEmpty) {
      await db.insert('subeler', {'id': 1, 'sube_kodu': 'MRK', 'sube_adi': 'Merkez'});
    }
  });
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    Veritabani.testVeritabani = null;
    await db.close();
  });

  Future<BorcModel> borc({double tutar = 1000}) async {
    final id = await db.insert('borclar', {
      'baslik': 'Test Borç', 'tur': 'tedarikci', 'tutar': tutar, 'odenen_tutar': 0,
      'odendi': 0, 'kesim_tarihi': DateTime.now().toIso8601String(),
      'son_odeme_tarihi': DateTime.now().toIso8601String(), 'is_deleted': 0,
    });
    return BorcModel.fromMap((await db.query('borclar', where: 'id = ?', whereArgs: [id])).first);
  }

  test('#9 eski (bayat) borç modeliyle ikinci ödeme reddedilir, kasadan ikinci kez para çıkmaz', () async {
    final eski = await borc();
    await BorcOdemeIslemServisi().odemeYap(borc: eski, tutar: 1000, odemeYontemi: 'Nakit');
    expect(await _kasaNet(db), -1000);

    await expectLater(
        BorcOdemeIslemServisi().odemeYap(borc: eski, tutar: 1000, odemeYontemi: 'Nakit'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'mesaj', contains('zaten ödenmiş'))));
    expect(await _kasaNet(db), -1000, reason: 'önceden −2000 oluyordu');
    expect(await db.query('borc_odemeler'), hasLength(1));
  });

  test('#9 kısmi ödemeden sonra bayat modelle kalandan fazlası ödenemez', () async {
    final eski = await borc();
    await BorcOdemeIslemServisi().odemeYap(borc: eski, tutar: 500, odemeYontemi: 'Nakit');
    await expectLater(
        BorcOdemeIslemServisi().odemeYap(borc: eski, tutar: 1000, odemeYontemi: 'Nakit'),
        throwsA(isA<Exception>()));
    expect(await _kasaNet(db), -500);
  });

  test('#10/#11 borç ödemesi gideri yalnız açıklaması değişince kasa ikinci kez düşmez', () async {
    await BorcOdemeIslemServisi().odemeYap(borc: await borc(tutar: 500), tutar: 500, odemeYontemi: 'Nakit');
    expect(await _kasaNet(db), -500);
    final gider = GiderModel.fromMap((await db.query('giderler')).single);

    await GiderDeposu().guncelle(gider.copyWith(aciklama: 'yeni açıklama'));

    expect(await _kasaNet(db), -500, reason: 'önceden −1000 oluyordu');
    expect((await db.query('giderler')).single['aciklama'], 'yeni açıklama');
  });

  test('#10/#11 borç ödemesi giderinin tutarı Giderler\'den değiştirilemez', () async {
    await BorcOdemeIslemServisi().odemeYap(borc: await borc(tutar: 500), tutar: 500, odemeYontemi: 'Nakit');
    final gider = GiderModel.fromMap((await db.query('giderler')).single);
    await expectLater(GiderDeposu().guncelle(gider.copyWith(tutar: 800)),
        throwsA(isA<Exception>().having((e) => e.toString(), 'mesaj', contains('Borç Merkezi'))));
    expect(await _kasaNet(db), -500);
  });
}
