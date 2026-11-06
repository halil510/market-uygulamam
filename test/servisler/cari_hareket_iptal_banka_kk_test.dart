// test/servisler/cari_hareket_iptal_banka_kk_test.dart
//
// DEEP_AUDIT (kendi-keşif turu, 2026-09-21): CariDeposu.hareketIptalEt()
// ÖNCEDEN sadece kasa (nakit) tarafını bulup tersine çevirebiliyordu —
// Banka/Kredi Kartı ile yapılan bir tahsilat/ödeme iptal edildiğinde o
// taraf hiç dokunulmadan kalıyordu (banka_hareketler/kredi_karti_hareket
// tablolarında referans_id/referans_turu kolonu hiç yoktu). Migrasyon
// v72 bu kolonları ekledi, CariTahsilatOdemeServisi.kaydet() artık
// dolduruyor, hareketIptalEt() artık kasa ile AYNI desende bulup
// tersine çeviriyor.
//
// 2026-11-06 (test güvenilirliği, Kademe 1): bu test ÖNCEDEN
// hareketIptalEt()'in banka/kart bloklarını KOPYALAYAN bir yardımcı
// çağırıyordu — üretim kodu bozulsa bile yeşil kalırdı. Artık GERÇEK
// CariDeposu().hareketIptalEt() çağrılıyor; bunun için kurulum gerçek bir
// cari + cari_hareket (Tahsilat/Ödeme) satırı yazar (önceden sabit id).
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:market_plus/depolar/banka_hareket_deposu.dart';
import 'package:market_plus/depolar/cari_deposu.dart';
import 'package:market_plus/depolar/kredi_karti_deposu.dart';
import 'package:market_plus/modeller/banka_hareket_model.dart';
import 'package:market_plus/modeller/cari_hareket_model.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

/// GERÇEK CariDeposu().hareketIptalEt() — hareket DB'den okunur.
Future<void> _hareketIptalEt(Database db, {required int cariHareketId}) async {
  final satir = (await db.query('cari_hareket',
          where: 'id = ?', whereArgs: [cariHareketId]))
      .first;
  await CariDeposu().hareketIptalEt(CariHareketModel.fromMap(satir));
}

/// İptal edilecek gerçek cari hareketi (Tahsilat: alacak, Ödeme: borç).
Future<int> _cariHareketEkle(Database db,
    {required String fisTipi, required double tutar, required String odemeTuru}) async {
  final cariId = await TestVeritabani.ornekCariEkle(db);
  final tahsilat = fisTipi == 'Tahsilat';
  return db.insert('cari_hareket', {
    'global_id': const Uuid().v4(),
    'cari_id': cariId,
    'tarih': DateTime.now().toIso8601String(),
    'fis_tipi': fisTipi,
    'aciklama': '$fisTipi (test)',
    'borc': tahsilat ? 0.0 : tutar,
    'alacak': tahsilat ? tutar : 0.0,
    'odeme_turu': odemeTuru,
    'is_deleted': 0,
  });
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

  Future<int> bankaIdAl() async => db.insert('bankalar', {'ad': 'Test Bankası'});

  Future<int> bankaHesabiEkle({double bakiye = 0}) async {
    final bankaId = await bankaIdAl();
    return db.insert('banka_hesaplar', {
      'banka_id': bankaId, 'hesap_adi': 'Test Hesap', 'hesap_no': '123',
      'bakiye': bakiye, 'kullanilabilir_bakiye': bakiye,
    });
  }

  Future<int> krediKartiEkle({double limit = 10000}) async {
    final bankaId = await bankaIdAl();
    return db.insert('kredi_kartlari', {
      'banka_id': bankaId, 'kart_adi': 'Test Kart', 'kart_no_maskeli': '**** 1234',
      'kartlimit': limit, 'kullanilan_limit': 0, 'kalan_limit': limit,
    });
  }

  group('Banka tarafı — cari hareket iptali artık tersine çeviriyor', () {
    test(
        'müşteriden Banka ile 5.000₺ tahsilat iptal edilince banka '
        'bakiyesi de GERİ DÜŞER (önceden hiç düşmüyordu)', () async {
      final hesapId = await bankaHesabiEkle(bakiye: 0);
      // 1. Orijinal tahsilat: müşteriden banka'ya 5000 giriyor (Gelen).
      final cariHareketId = await _cariHareketEkle(db, fisTipi: 'Tahsilat', tutar: 5000, odemeTuru: 'Banka');
      await db.transaction((txn) => BankaHareketDeposu().ekleTxn(
          txn,
          BankaHareketModel(
            bankaHesapId: hesapId, islemTipi: 'Gelen', tutar: 5000,
            tarih: DateTime.now(), referansId: cariHareketId,
            referansTuru: 'cari_hareket',
          )));

      var hesap = (await db.query('banka_hesaplar', where: 'id = ?', whereArgs: [hesapId])).first;
      expect(hesap['bakiye'], 5000.0);

      // 2. İptal: hareketIptalEt() mantığıyla bul + tersine çevir.
      await _hareketIptalEt(db, cariHareketId: cariHareketId);

      hesap = (await db.query('banka_hesaplar', where: 'id = ?', whereArgs: [hesapId])).first;
      expect(hesap['bakiye'], 0.0,
          reason: 'iptal sonrası banka bakiyesi orijinal tahsilattan ÖNCEKİ '
              'haline dönmeli — önceden bu asla olmuyordu');
    });

    test('tedarikçiye Banka ile yapılan 3.000₺ ödeme iptal edilince para GERİ GELİR',
        () async {
      final hesapId = await bankaHesabiEkle(bakiye: 10000);
      final cariHareketId = await _cariHareketEkle(db, fisTipi: 'Ödeme', tutar: 3000, odemeTuru: 'Banka');
      await db.transaction((txn) => BankaHareketDeposu().ekleTxn(
          txn,
          BankaHareketModel(
            bankaHesapId: hesapId, islemTipi: 'Giden', tutar: 3000,
            tarih: DateTime.now(), referansId: cariHareketId,
            referansTuru: 'cari_hareket',
          )));

      var hesap = (await db.query('banka_hesaplar', where: 'id = ?', whereArgs: [hesapId])).first;
      expect(hesap['bakiye'], 7000.0);

      await _hareketIptalEt(db, cariHareketId: cariHareketId);

      hesap = (await db.query('banka_hesaplar', where: 'id = ?', whereArgs: [hesapId])).first;
      expect(hesap['bakiye'], 10000.0);
    });

    // CLAUDE.md §3.3 / §5.1: ikinci iptal hiçbir ters kayıt üretmez.
    test('aynı hareket ikinci kez iptal edilmek istenirse reddedilir, banka iki kez ters çevrilmez',
        () async {
      final hesapId = await bankaHesabiEkle(bakiye: 0);
      final cariHareketId =
          await _cariHareketEkle(db, fisTipi: 'Tahsilat', tutar: 800, odemeTuru: 'Banka');
      await db.transaction((txn) => BankaHareketDeposu().ekleTxn(
          txn,
          BankaHareketModel(
            bankaHesapId: hesapId, islemTipi: 'Gelen', tutar: 800,
            tarih: DateTime.now(), referansId: cariHareketId,
            referansTuru: 'cari_hareket',
          )));

      await _hareketIptalEt(db, cariHareketId: cariHareketId);
      await expectLater(
          _hareketIptalEt(db, cariHareketId: cariHareketId), throwsException);

      final hesap = (await db.query('banka_hesaplar', where: 'id = ?', whereArgs: [hesapId])).first;
      expect(hesap['bakiye'], 0.0);
    });
  });

  group('Kredi kartı tarafı — cari hareket iptali artık tersine çeviriyor', () {
    test(
        "müşteriden Kredi Kartı ile tahsilat (limit azaltan 'odeme' yönü) "
        'iptal edilince kullanılan limit GERİ ARTAR', () async {
      final kartId = await krediKartiEkle(limit: 10000);
      final cariHareketId = await _cariHareketEkle(db, fisTipi: 'Tahsilat', tutar: 1500, odemeTuru: 'Kredi Kartı');
      // Müşteriden tahsilat = kart kullanımını AZALTIR (negatif delta, 'odeme').
      await db.transaction((txn) => KrediKartiDeposu().limitDegistirTxn(
          txn, kartId, -1500,
          referansId: cariHareketId, referansTuru: 'cari_hareket'));

      var kart = (await db.query('kredi_kartlari', where: 'id = ?', whereArgs: [kartId])).first;
      expect(kart['kullanilan_limit'], -1500.0);

      await _hareketIptalEt(db, cariHareketId: cariHareketId);

      kart = (await db.query('kredi_kartlari', where: 'id = ?', whereArgs: [kartId])).first;
      expect(kart['kullanilan_limit'], 0.0,
          reason: 'iptal sonrası kullanılan limit orijinal işlemden ÖNCEKİ '
              'haline dönmeli');
    });
  });
}
