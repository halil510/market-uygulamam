// test/servisler/fis_guncelleme_kredi_limiti_test.dart
//
// Regresyon (2026-11-07): Hızlı Satış'ın "Fiş Güncelle" akışında kredi
// limiti HİÇ kontrol edilmiyordu — veresiye fişe ürün eklenerek ya da peşin
// fiş Cari'ye çevrilerek limit sessizce aşılabiliyordu. Ekran artık kayıttan
// önce SatisTamamlamaServisi.fisGuncellemeCariArtisi kadar onay istiyor; bu
// test o tutarın (yalnızca EK borç) doğru hesaplandığını doğrular.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/depolar/cari_deposu.dart';
import 'package:market_plus/depolar/urun_deposu.dart';
import 'package:market_plus/modeller/sepet_model.dart';
import 'package:market_plus/servisler/satis_tamamlama_servisi.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

void main() {
  group('SatisTamamlamaServisi.cariPayi (saf)', () {
    test('Cari → genel toplamın tamamı', () {
      expect(SatisTamamlamaServisi.cariPayi(odemeYontemi: 'Cari', genelToplam: 150), 150);
    });
    test('Nakit / Kart → 0', () {
      expect(SatisTamamlamaServisi.cariPayi(odemeYontemi: 'Nakit', genelToplam: 150), 0);
      expect(SatisTamamlamaServisi.cariPayi(odemeYontemi: 'Kredi Kartı', genelToplam: 150), 0);
    });
    test('Karma → yalnız Cari kalemlerinin toplamı (kuruşa yuvarlı)', () {
      expect(
          SatisTamamlamaServisi.cariPayi(
            odemeYontemi: 'Karma',
            genelToplam: 100,
            karmaKalemler: [
              {'yontem': 'Nakit', 'tutar': 40},
              {'yontem': 'Cari', 'tutar': 30.1},
              {'yontem': 'Cari', 'tutar': 0.2},
            ],
          ),
          30.3);
    });
  });

  group('fisGuncellemeCariArtisi (gerçek DB)', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    late Database db;
    late int urunId;
    late int cariId;

    setUp(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
              (_) async => null);
      SharedPreferences.setMockInitialValues({});
      db = await TestVeritabani.olustur();
      Veritabani.testVeritabani = db;
      urunId = await TestVeritabani.ornekUrunEkle(db, stok: 50, satisFiyati: 20);
      cariId = await TestVeritabani.ornekCariEkle(db);
    });
    tearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      Veritabani.testVeritabani = null;
      await db.close();
    });

    Future<int> satis(String odemeYontemi, {required double miktar}) async {
      final urun = (await UrunDeposu().idileGetir(urunId))!;
      final musteri = await CariDeposu().idileGetir(cariId);
      final s = await SatisTamamlamaServisi().tamamla(
        kalemler: [SepetKalem(urun: urun, miktar: miktar, birimFiyat: 20)],
        musteri: musteri,
        genelToplam: miktar * 20,
        odemeYontemi: odemeYontemi,
        odenenTutar: odemeYontemi == 'Cari' ? 0 : miktar * 20,
      );
      return s.satisId;
    }

    test('veresiye fişe ürün eklenince yalnızca FARK kadar ek borç sayılır', () async {
      final id = await satis('Cari', miktar: 5); // 100 TL borç
      expect(await CariDeposu().fisNetBorcu(id, cariId), 100);
      final artis = await SatisTamamlamaServisi().fisGuncellemeCariArtisi(
          satisId: id, yeniCariId: cariId, yeniCariPayi: 160);
      expect(artis, 60, reason: '160 - 100 (zaten bakiyede olan) = 60');
    });

    test('peşin fiş Cari\'ye çevrilirse toplamın tamamı ek borçtur', () async {
      final id = await satis('Nakit', miktar: 5);
      final artis = await SatisTamamlamaServisi().fisGuncellemeCariArtisi(
          satisId: id, yeniCariId: cariId, yeniCariPayi: 100);
      expect(artis, 100);
    });

    test('tutar düşerse artış negatif — limit sorulmaz', () async {
      final id = await satis('Cari', miktar: 5);
      final artis = await SatisTamamlamaServisi().fisGuncellemeCariArtisi(
          satisId: id, yeniCariId: cariId, yeniCariPayi: 40);
      expect(artis, lessThanOrEqualTo(0));
    });

    test('cari kaldırılırsa (müşterisiz) artış 0', () async {
      final id = await satis('Cari', miktar: 5);
      expect(
          await SatisTamamlamaServisi().fisGuncellemeCariArtisi(
              satisId: id, yeniCariId: null, yeniCariPayi: 0),
          0);
    });

    test('limit kontrolü ek borçla yapılır: limit 150, bakiye 100, +60 → aşılır', () async {
      await db.update('cari', {'limit_tutari': 150}, where: 'id = ?', whereArgs: [cariId]);
      final id = await satis('Cari', miktar: 5);
      final artis = await SatisTamamlamaServisi().fisGuncellemeCariArtisi(
          satisId: id, yeniCariId: cariId, yeniCariPayi: 160);
      final sonuc = await CariDeposu().limitKontrolEt(cariId, artis);
      expect(sonuc.asildi, isTrue);
      expect(sonuc.asimTutari, closeTo(10, 0.001));

      // Toplamın tamamıyla (160) sorulsaydı aşım 110 görünürdü — yanlış.
      final kucukArtis = await SatisTamamlamaServisi().fisGuncellemeCariArtisi(
          satisId: id, yeniCariId: cariId, yeniCariPayi: 140);
      expect((await CariDeposu().limitKontrolEt(cariId, kucukArtis)).asildi, isFalse);
    });
  });
}
