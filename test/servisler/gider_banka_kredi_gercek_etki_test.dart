// test/servisler/gider_banka_kredi_gercek_etki_test.dart
//
// Paralel fork denetimi (2026-09-22, "tam ERP" turu) KRİTİK bir bulgu
// buldu: Banka/Kredi Kartı ödeme yöntemiyle girilen GİDERLER hiçbir
// gerçek banka_hareketler/kredi_karti_hareket satırı oluşturmuyordu —
// sadece 'giderler' tablosuna düşüyor, şirketin gerçek banka bakiyesi/
// kart limit kullanımı hiç etkilenmiyordu (Virman/İade'de daha önce
// bulunan AYNI hata sınıfı).
//
// GiderDeposu.ekle()/guncelle()/sil() artık CariTahsilatOdemeServisi'ndeki
// AYNI desenle gerçek hareket yazıyor/tersine çeviriyor — hesap/kart
// DEĞİŞTİRİLEBİLİR olduğundan (guncelle'de) uzlaştırma HESAP/KART
// BAZINDA yapılıyor.
//
// 2026-11-06 (test güvenilirliği, Kademe 1): bu test ÖNCEDEN guncelle()'nin
// banka/kart uzlaştırma bloklarını KOPYALAYAN yardımcılar çağırıyordu —
// üretim kodu bozulsa bile yeşil kalırdı. Artık GERÇEK GiderDeposu().ekle()
// / guncelle() / sil() çağrılıyor.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/depolar/gider_deposu.dart';
import 'package:market_plus/modeller/gider_model.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late int kategoriId;
  final depo = GiderDeposu();
  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (_) async => null);
    SharedPreferences.setMockInitialValues({});
    db = await TestVeritabani.olustur();
    Veritabani.testVeritabani = db;
    kategoriId = await db.insert('gider_kategoriler', {'ad': 'Test Gider'});
  });
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    Veritabani.testVeritabani = null;
    await db.close();
  });

  GiderModel gider({
    int? id,
    required double tutar,
    String odemeYontemi = 'Banka',
    int? bankaHesapId,
    int? krediKartiId,
  }) =>
      GiderModel(
        id: id,
        kategoriId: kategoriId,
        kategoriAdi: 'Test Gider',
        tutar: tutar,
        aciklama: 'test',
        tarih: DateTime.now(),
        odemeYontemi: odemeYontemi,
        bankaHesapId: bankaHesapId,
        krediKartiId: krediKartiId,
      );

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

  group('Gider — Banka ödeme yöntemi artık GERÇEK banka hareketi yaratıyor', () {
    test('500₺ Banka gideri girilince hesap bakiyesi GERÇEKTEN 500₺ düşer', () async {
      final hesapId = await bankaHesabiEkle(bakiye: 10000);

      await depo.ekle(gider(tutar: 500.0, bankaHesapId: hesapId));

      final hesap = (await db.query('banka_hesaplar', where: 'id = ?', whereArgs: [hesapId])).first;
      expect((hesap['bakiye'] as num).toDouble(), equals(9500.0));
    });

    test('gider silinince (net→0 uzlaştırma) banka bakiyesi GERİ GELİR', () async {
      final hesapId = await bankaHesabiEkle(bakiye: 10000);
      final giderId = await depo.ekle(gider(tutar: 300.0, bankaHesapId: hesapId));

      await depo.sil(giderId);

      final hesap = (await db.query('banka_hesaplar', where: 'id = ?', whereArgs: [hesapId])).first;
      expect((hesap['bakiye'] as num).toDouble(), equals(10000.0),
          reason: 'Silinen gider kadar tutar bankaya geri dönmeli');
    });

    test('gider Nakit\'ten Banka\'ya güncellenip SONRA tutar artırılırsa hesap doğru düşer', () async {
      final hesapId = await bankaHesabiEkle(bakiye: 5000);
      final giderId = await depo.ekle(gider(tutar: 200.0, odemeYontemi: 'Nakit'));
      // İlk düzenleme: Nakit → Banka, 200₺
      await depo.guncelle(gider(id: giderId, tutar: 200.0, bankaHesapId: hesapId));
      // İkinci düzenleme: 350₺'ye çıkarıldı (sadece FARK yazılmalı).
      await depo.guncelle(gider(id: giderId, tutar: 350.0, bankaHesapId: hesapId));

      final hesap = (await db.query('banka_hesaplar', where: 'id = ?', whereArgs: [hesapId])).first;
      expect((hesap['bakiye'] as num).toDouble(), equals(4650.0));

      final hareketler = await db.query('banka_hareketler', where: 'referans_id = ?', whereArgs: [giderId]);
      expect(hareketler, hasLength(2), reason: 'İlk yazım + fark düzeltmesi, orijinal satır DEĞİŞTİRİLMEMELİ');
    });

    test('gider Banka A\'dan Banka B\'ye taşınınca A geri gelir, B düşer', () async {
      final hesapA = await bankaHesabiEkle(bakiye: 5000);
      final hesapB = await bankaHesabiEkle(bakiye: 5000);
      final giderId = await depo.ekle(gider(tutar: 1000.0, bankaHesapId: hesapA));

      // Hesap değiştirildi: artık B hedef, A hiç hedef değil (→ 0'a uzlaşır).
      await depo.guncelle(gider(id: giderId, tutar: 1000.0, bankaHesapId: hesapB));

      final a = (await db.query('banka_hesaplar', where: 'id = ?', whereArgs: [hesapA])).first;
      final b = (await db.query('banka_hesaplar', where: 'id = ?', whereArgs: [hesapB])).first;
      expect((a['bakiye'] as num).toDouble(), equals(5000.0), reason: 'A hesabı tam geri gelmeli');
      expect((b['bakiye'] as num).toDouble(), equals(4000.0), reason: 'B hesabı 1000 düşmeli');
    });

    // CLAUDE.md §3.3 / §5.1: ikinci silme hiçbir ters kayıt üretmez.
    test('aynı gider iki kez silinirse banka ikinci kez geri ALINMAZ (idempotent)', () async {
      final hesapId = await bankaHesabiEkle(bakiye: 10000);
      final giderId = await depo.ekle(gider(tutar: 300.0, bankaHesapId: hesapId));

      await depo.sil(giderId);
      await depo.sil(giderId);

      final hesap = (await db.query('banka_hesaplar', where: 'id = ?', whereArgs: [hesapId])).first;
      expect((hesap['bakiye'] as num).toDouble(), equals(10000.0));
    });
  });

  group('Gider — Kredi Kartı ödeme yöntemi artık GERÇEK kart hareketi yaratıyor', () {
    test('400₺ Kredi Kartı gideri girilince kullanılan limit GERÇEKTEN artar', () async {
      final kartId = await krediKartiEkle(limit: 5000);

      await depo.ekle(gider(tutar: 400.0, odemeYontemi: 'Kredi Kartı', krediKartiId: kartId));

      final kart = (await db.query('kredi_kartlari', where: 'id = ?', whereArgs: [kartId])).first;
      expect((kart['kullanilan_limit'] as num).toDouble(), equals(400.0));
      expect((kart['kalan_limit'] as num).toDouble(), equals(4600.0));
    });

    test('gider silinince kullanılan limit GERİ AZALIR', () async {
      final kartId = await krediKartiEkle(limit: 5000);
      final giderId = await depo.ekle(
          gider(tutar: 250.0, odemeYontemi: 'Kredi Kartı', krediKartiId: kartId));

      await depo.sil(giderId);

      final kart = (await db.query('kredi_kartlari', where: 'id = ?', whereArgs: [kartId])).first;
      expect((kart['kullanilan_limit'] as num).toDouble(), equals(0.0));
    });
  });
}
