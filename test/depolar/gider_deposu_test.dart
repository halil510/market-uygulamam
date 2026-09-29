// test/depolar/gider_deposu_test.dart
//
// Gider modülü taraması (2026-09-29): liste kategori adını hiç getirmiyordu
// (her gider "Genel"), banka ile ödenen giderin ekle → düzenle → sil
// zinciri banka bakiyesini doğru tutmalı.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/depolar/gider_deposu.dart';
import 'package:market_plus/modeller/gider_model.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

void main() {
  late Database db;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await TestVeritabani.olustur();
    Veritabani.testVeritabani = db;
  });
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    Veritabani.testVeritabani = null;
    await db.close();
  });

  Future<int> kategori(String ad) =>
      db.insert('gider_kategoriler', {'ad': ad});

  Future<double> bakiye(int hesapId) async =>
      ((await db.query('banka_hesaplar', where: 'id = ?', whereArgs: [hesapId]))
              .first['bakiye'] as num)
          .toDouble();

  test('liste kategori adını getirir', () async {
    final kid = await kategori('Kira');
    await GiderDeposu().ekle(GiderModel(
        kategoriId: kid, tutar: 100, tarih: DateTime.now(), odemeYontemi: 'Çek'));

    final liste = await GiderDeposu().tumunuGetir();
    expect(liste.single.kategoriAdi, 'Kira');
  });

  test('banka gideri: ekle → tutarı düzelt → sil zinciri bakiyeyi doğru tutar',
      () async {
    final kid = await kategori('Elektrik');
    final bankaId = await db.insert('bankalar', {'ad': 'Test Bankası'});
    final hesapId = await db.insert('banka_hesaplar', {
      'banka_id': bankaId, 'hesap_adi': 'Vadesiz', 'hesap_no': '1',
      'bakiye': 1000.0, 'kullanilabilir_bakiye': 1000.0,
    });

    final gid = await GiderDeposu().ekle(GiderModel(
        kategoriId: kid, tutar: 200, tarih: DateTime.now(),
        odemeYontemi: 'Banka', bankaHesapId: hesapId));
    expect(await bakiye(hesapId), 800);

    final kayit = (await GiderDeposu().tumunuGetir()).single;
    await GiderDeposu().guncelle(GiderModel(
        id: gid, globalId: kayit.globalId, kategoriId: kid, tutar: 350,
        tarih: kayit.tarih, odemeYontemi: 'Banka', bankaHesapId: hesapId));
    expect(await bakiye(hesapId), 650);

    // Nakit'e çevrilince banka tarafı tamamen geri alınır.
    await GiderDeposu().guncelle(GiderModel(
        id: gid, globalId: kayit.globalId, kategoriId: kid, tutar: 350,
        tarih: kayit.tarih, odemeYontemi: 'Nakit'));
    expect(await bakiye(hesapId), 1000);
    final satir = (await db.query('giderler', where: 'id = ?', whereArgs: [gid])).first;
    expect(satir['banka_hesap_id'], isNull);

    await GiderDeposu().sil(gid);
    expect(await bakiye(hesapId), 1000);
    expect(await GiderDeposu().tumunuGetir(), isEmpty);
  });
}
