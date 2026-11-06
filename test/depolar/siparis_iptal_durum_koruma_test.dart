// test/depolar/siparis_iptal_durum_koruma_test.dart
//
// Regresyon (2026-11-06, CLAUDE.md §3.3 / §5.1 — Faz A-3):
//  - MasaDeposu.siparisIptal() durum kontrolü yapmıyordu: ÖDENMİŞ bir
//    masa siparişi (bayat ekran / başka terminal) "iptal"e çekilip masa
//    boşaltılabiliyordu — satış kayıtlıyken sipariş iptal görünüyordu.
//  - BekleyenSiparisDeposu.iptalEt() de durum bakmıyordu: SATIŞA ÇEVRİLMİŞ
//    (onaylandi) bir bayi siparişi "iptal" olarak işaretlenebiliyordu.
// Artık ikisi de yalnız açık/bekleyen kayıtta çalışır, aksi halde hata.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/depolar/bekleyen_siparis_deposu.dart';
import 'package:market_plus/depolar/masa_deposu.dart';
import 'package:market_plus/modeller/masa_model.dart';
import 'package:market_plus/servisler/masa_odeme_servisi.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

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

  group('MasaDeposu.siparisIptal', () {
    Future<(int, int)> acikSiparis() async {
      final urunId = await TestVeritabani.ornekUrunEkle(db, satisFiyati: 40);
      final masaId = await MasaDeposu().masaEkle(const MasaModel(ad: 'Masa 9'));
      final s = await MasaDeposu().siparisAcVeyaGetir(masaId);
      await MasaDeposu().kalemEkle(s.id!,
          urunId: urunId, urunAdi: 'Çay', birimFiyat: 40, kdvOran: 10);
      return (masaId, s.id!);
    }

    test('açık sipariş iptal edilir, masa boşalır', () async {
      final (masaId, siparisId) = await acikSiparis();
      await MasaDeposu().siparisIptal(siparisId, masaId);
      final s = (await db.query('masa_siparisleri', where: 'id = ?', whereArgs: [siparisId])).first;
      expect(s['durum'], 'iptal');
    });

    test('ÖDENMİŞ sipariş iptal edilemez, durumu "odendi" kalır', () async {
      final (masaId, siparisId) = await acikSiparis();
      final siparis = (await MasaDeposu().acikSiparisGetir(masaId))!;
      await MasaOdemeServisi().odemeYap(
          siparis: siparis, masaAdi: 'Masa 9', paraUstu: 0,
          odemeKalemleri: [{'yontem': 'Nakit', 'tutar': 40.0}]);

      await expectLater(MasaDeposu().siparisIptal(siparisId, masaId), throwsException);
      final s = (await db.query('masa_siparisleri', where: 'id = ?', whereArgs: [siparisId])).first;
      expect(s['durum'], 'odendi');
    });

    test('iki kez iptal: ikincisi hata verir', () async {
      final (masaId, siparisId) = await acikSiparis();
      await MasaDeposu().siparisIptal(siparisId, masaId);
      await expectLater(MasaDeposu().siparisIptal(siparisId, masaId), throwsException);
    });
  });

  group('BekleyenSiparisDeposu.iptalEt', () {
    Future<int> siparis(String durum) async {
      final cariId = await TestVeritabani.ornekCariEkle(db);
      return db.insert('bekleyen_siparisler', {
        'global_id': 'bs-$durum-$cariId', 'cari_id': cariId, 'durum': durum,
        'genel_toplam': 100,
      });
    }

    test('bekleyen sipariş iptal edilir', () async {
      final id = await siparis('bekliyor');
      await BekleyenSiparisDeposu().iptalEt(id);
      final s = (await db.query('bekleyen_siparisler', where: 'id = ?', whereArgs: [id])).first;
      expect(s['durum'], 'iptal');
    });

    test('satışa çevrilmiş (onaylandi) sipariş iptal edilemez', () async {
      final id = await siparis('onaylandi');
      await expectLater(BekleyenSiparisDeposu().iptalEt(id), throwsException);
      final s = (await db.query('bekleyen_siparisler', where: 'id = ?', whereArgs: [id])).first;
      expect(s['durum'], 'onaylandi');
    });
  });
}
