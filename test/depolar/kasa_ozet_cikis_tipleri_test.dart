// test/depolar/kasa_ozet_cikis_tipleri_test.dart
//
// Regresyon (2026-11-06): KasaDeposu.gunlukOzet()/aralikOzet() "çıkış"
// toplamını elle yazılmış ('Gider','Ödeme','KapanışKasa') listesiyle
// hesaplıyordu — Alım, İade, Borç Ödemesi, Virman Çıkış ve Satış İptali
// çıkış sayılmıyordu. Kasa bakiyesi ise girisTipleri DIŞINDAKİ her tipi
// çıkış sayar. Kural: giriş − çıkış == bakiye değişimi.
//
// GERÇEK KasaDeposu metotları çağrılır (kopya SQL yok).
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/depolar/kasa_deposu.dart';
import 'package:market_plus/modeller/kasa_hareket_model.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

void main() {
  late Database db;
  final depo = KasaDeposu();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await TestVeritabani.olustur();
    Veritabani.testVeritabani = db;
  });
  tearDown(() async {
    Veritabani.testVeritabani = null;
    await db.close();
  });

  Future<void> hareket(String tip, double tutar) async {
    await db.transaction((txn) => depo.hareketEkleTxn(
        txn,
        KasaHareketModel(
          hareketTipi: tip,
          tutar: tutar,
          tarih: DateTime.now(),
          aciklama: 'test $tip',
        )));
  }

  Future<void> senaryo() async {
    await hareket('AçılışKasa', 1000);
    await hareket('Satış', 500);
    await hareket('Gider', 50);
    await hareket('Alım', 200);
    await hareket('İade', 30);
    await hareket('Iade', 10);
    await hareket('Borç Ödemesi', 70);
    await hareket('Virman Çıkış', 100);
    await hareket('Satış İptali', 40);
  }

  // Çıkışlar: 50 + 200 + 30 + 10 + 70 + 100 + 40 = 500
  const beklenenCikis = 500.0;
  const beklenenGiris = 1500.0;

  test('gunlukOzet: Alım/İade/Borç Ödemesi/Virman Çıkış/Satış İptali çıkış sayılır',
      () async {
    await senaryo();
    final ozet = await depo.gunlukOzet();
    expect(ozet['giris'], closeTo(beklenenGiris, 0.001));
    expect(ozet['cikis'], closeTo(beklenenCikis, 0.001));
  });

  test('aralikOzet: aynı çıkış tipleri sayılır', () async {
    await senaryo();
    final simdi = DateTime.now();
    final ozet = await depo.aralikOzet(
        simdi.subtract(const Duration(hours: 1)),
        simdi.add(const Duration(hours: 1)));
    expect(ozet['giris'], closeTo(beklenenGiris, 0.001));
    expect(ozet['cikis'], closeTo(beklenenCikis, 0.001));
  });

  test('giriş − çıkış == güncel kasa bakiyesi', () async {
    await senaryo();
    final ozet = await depo.gunlukOzet();
    final bakiye = await depo.guncelBakiye();
    expect(ozet['giris']! - ozet['cikis']!, closeTo(bakiye, 0.001));
  });
}
