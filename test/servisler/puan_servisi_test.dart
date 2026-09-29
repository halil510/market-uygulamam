// test/servisler/puan_servisi_test.dart
//
// Puan modülü taraması (2026-09-29): mutabakat 'İptal' hareketlerini
// puanIptalEt'ten farklı sınıflandırıyordu (her senkronda sayaçlar değişip
// buluta yeniden gidiyordu); puanKullan bakiye kontrolünü transaction
// dışında yapıyordu; tarih UTC yazılıyordu.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/servisler/puan_servisi.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

void main() {
  late Database db;
  late int cariId;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await TestVeritabani.olustur();
    Veritabani.testVeritabani = db;
    cariId = await TestVeritabani.ornekCariEkle(db);
  });
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    Veritabani.testVeritabani = null;
    await db.close();
  });

  Future<Map<String, Object?>> sayac() async =>
      (await db.query('musteri_puan', where: 'cari_id = ?', whereArgs: [cariId])).first;

  test('satış iptalinden sonra mutabakat hiçbir şeyi değiştirmez', () async {
    final puan = PuanServisi();
    await puan.puanEkle(cariId: cariId, tutar: 100, satisId: 1);
    await puan.puanEkle(cariId: cariId, tutar: 50, satisId: 2);
    await puan.puanKullan(cariId: cariId, istenenPuan: 30, satisId: 2);
    await puan.puanIptalEt(cariId: cariId, satisId: 2);

    final once = await sayac();
    expect(once['toplam_puan'], 100);
    expect(once['kullanilan'], 0);
    expect(await puan.puanBakiyesi(cariId), 100);

    expect(await puan.puanMutabakatYap(), 0);
    final sonra = await sayac();
    expect(sonra['toplam_puan'], 100);
    expect(sonra['kullanilan'], 0);
  });

  test('bakiyeden fazla puan harcanamaz, eşzamanlı iki çağrıda da', () async {
    final puan = PuanServisi();
    await puan.puanEkle(cariId: cariId, tutar: 100, satisId: 1);

    final sonuclar = await Future.wait([
      puan.puanKullan(cariId: cariId, istenenPuan: 80, satisId: 0),
      puan.puanKullan(cariId: cariId, istenenPuan: 80, satisId: 0),
    ]);
    expect(sonuclar.fold<double>(0, (a, b) => a + b), 100);
    expect(await puan.puanBakiyesi(cariId), 0);
  });

  test('hareket tarihi yerel saatle yazılır', () async {
    await PuanServisi().puanEkle(cariId: cariId, tutar: 10, satisId: 1);
    final tarih = (await db.query('puan_hareket')).single['tarih'] as String;
    expect(tarih, contains('T'));
    expect(DateTime.parse(tarih).difference(DateTime.now()).inMinutes.abs(), lessThan(2));
  });

  test('sayaç kuralı: eksi İptal kazanılanı, artı İptal harcananı düşürür', () {
    final (k, h) = PuanServisi.sayaclariHesapla([
      {'islem_tipi': 'Kazanıldı', 'puan': 50.0},
      {'islem_tipi': 'Harcandı', 'puan': -30.0},
      {'islem_tipi': 'İptal', 'puan': -50.0},
      {'islem_tipi': 'İptal', 'puan': 30.0},
    ]);
    expect(k, 0);
    expect(h, 0);
  });
}
