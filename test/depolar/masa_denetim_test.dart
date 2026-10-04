// test/depolar/masa_denetim_test.dart
//
// Masa modülü derin denetimi (2026-10): gerçek depo/servis fonksiyonları,
// gerçek şemalı bellek içi veritabanı.
//  • Masa adı benzersizliği, düzenlemede durum ezilmemesi
//  • Eşzamanlı "sipariş aç" tek açık sipariş üretir
//  • Masa/mutfak sorguları toplu (N+1 değil) ve doğru toplam/özet verir
//  • Ödeme sırasında sipariş değişirse ödeme reddedilir, hiçbir şey yazılmaz
//  • Rezervasyon çakışması (2 saatlik pencere) doğru tespit edilir
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/depolar/masa_deposu.dart';
import 'package:market_plus/modeller/masa_model.dart';
import 'package:market_plus/modeller/rezervasyon_model.dart';
import 'package:market_plus/servisler/masa/rezervasyon_servisi.dart';
import 'package:market_plus/servisler/masa_odeme_servisi.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late MasaDeposu depo;

  Future<int> kalem(int siparisId, String ad, double miktar, double fiyat) =>
      db.insert('masa_siparis_kalem', {
        'siparis_id': siparisId, 'urun_id': 1, 'urun_adi': ad, 'miktar': miktar,
        'birim_fiyat': fiyat, 'kdv_oran': 10,
      });
  Future<String> masaDurum(int id) async =>
      (await db.query('masalar', where: 'id = ?', whereArgs: [id])).first['durum'] as String;

  setUp(() async {
    // AuthServisi.mevcutKullanici() güvenli depolamayı okur; testte oturum yok.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (_) async => null);
    SharedPreferences.setMockInitialValues({});
    db = await TestVeritabani.olustur();
    Veritabani.testVeritabani = db;
    depo = MasaDeposu();
    await TestVeritabani.ornekUrunEkle(db);
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    Veritabani.testVeritabani = null;
    await db.close();
  });

  group('masa adı / düzenleme', () {
    test('aynı adlı masa (harf/boşluk duyarsız) eklenemez', () async {
      await depo.masaEkle(const MasaModel(ad: 'Masa 1'));
      expect(await depo.adKullanimda('  masa 1 '), isTrue);
      expect(() => depo.masaEkle(const MasaModel(ad: 'MASA 1')), throwsException);
      expect(() => depo.masaEkle(const MasaModel(ad: '   ')), throwsException);
      await depo.masaEkle(const MasaModel(ad: 'Masa 2'));
    });

    test('düzenleme durumu EZMEZ (açık siparişli masa boşa dönmez) ve ad çakışmasını reddeder', () async {
      final m1 = await depo.masaEkle(const MasaModel(ad: 'Masa 1'));
      await depo.masaEkle(const MasaModel(ad: 'Masa 2'));
      await depo.siparisAcVeyaGetir(m1); // başka bir cihaz masayı açtı → dolu
      expect(await masaDurum(m1), 'dolu');

      // Eski ekran kopyasıyla (durum: 'bos') düzenleme kaydedilir:
      await depo.masaBilgiGuncelle(m1, ad: 'Bahçe 1', kategori: 'Bahçe', kapasite: 6);
      final satir = (await db.query('masalar', where: 'id = ?', whereArgs: [m1])).first;
      expect(satir['ad'], 'Bahçe 1');
      expect(satir['kategori'], 'Bahçe');
      expect(satir['kapasite'], 6);
      expect(satir['durum'], 'dolu', reason: 'durum bayat kopyadan ezilmemeli');

      expect(() => depo.masaBilgiGuncelle(m1, ad: 'masa 2', kategori: 'Salon', kapasite: 4),
          throwsException);
      // Kendi adıyla kaydetmek serbest
      await depo.masaBilgiGuncelle(m1, ad: 'Bahçe 1', kategori: 'Bahçe', kapasite: 4);
    });
  });

  group('sipariş açma / toplu sorgular', () {
    test('eşzamanlı siparisAcVeyaGetir TEK açık sipariş üretir', () async {
      final m = await depo.masaEkle(const MasaModel(ad: 'Masa 1'));
      final sonuc = await Future.wait([
        depo.siparisAcVeyaGetir(m),
        depo.siparisAcVeyaGetir(m),
        depo.siparisAcVeyaGetir(m),
      ]);
      final acik = await db.query('masa_siparisleri',
          where: "masa_id = ? AND durum = 'acik' AND is_deleted = 0", whereArgs: [m]);
      expect(acik.length, 1);
      expect(sonuc.map((s) => s.id).toSet().length, 1);
      expect(await masaDurum(m), 'dolu');
    });

    test('masalariGetir / tumAcikSiparisler: toplam, özet ve silinmiş kalem doğru', () async {
      final m1 = await depo.masaEkle(const MasaModel(ad: 'Masa 1'));
      final m2 = await depo.masaEkle(const MasaModel(ad: 'Masa 2'));
      await depo.masaEkle(const MasaModel(ad: 'Masa 3')); // boş
      final s1 = await depo.siparisAcVeyaGetir(m1);
      final s2 = await depo.siparisAcVeyaGetir(m2);
      await kalem(s1.id!, 'Çay', 2, 10);
      await kalem(s1.id!, 'Tost', 1, 50);
      await kalem(s1.id!, 'Kek', 1, 30);
      final silinecek = await kalem(s1.id!, 'Silinen', 5, 100);
      await db.update('masa_siparis_kalem', {'is_deleted': 1}, where: 'id = ?', whereArgs: [silinecek]);
      await kalem(s2.id!, 'Su', 3, 5);

      final masalar = await depo.masalariGetir();
      expect(masalar.length, 3);
      final a = masalar.firstWhere((m) => m.id == m1);
      expect(a.aktifToplam, 100); // 2*10 + 50 + 30
      expect(a.aktifOzet, 'Çay, Tost +1');
      expect(masalar.firstWhere((m) => m.id == m2).aktifToplam, 15);
      expect(masalar.firstWhere((m) => m.ad == 'Masa 3').aktifSiparisId, isNull);

      final acik = await depo.tumAcikSiparisler();
      expect(acik.length, 2);
      expect(acik.firstWhere((s) => s.id == s1.id).kalemler.length, 3);
      expect(acik.firstWhere((s) => s.id == s2.id).kalemler.single.urunAdi, 'Su');
    });
  });

  group('son kalem silinip yeniden ürün eklenince', () {
    test('masa tekrar DOLU olur (sipariş açık kaldığı için önceden boş görünüyordu)', () async {
      final m = await depo.masaEkle(const MasaModel(ad: 'Masa 1'));
      final s = await depo.siparisAcVeyaGetir(m);
      final k = await kalem(s.id!, 'Çay', 1, 10);
      await depo.kalemSil(k); // son kalem silindi → masa boş
      expect(await masaDurum(m), 'bos');

      final yine = await depo.siparisAcVeyaGetir(m); // aynı açık sipariş
      expect(yine.id, s.id);
      expect(await masaDurum(m), 'dolu', reason: 'ürün eklenecek masa dolu olmalı');
    });

    test('masa satırı yine de boş kalmışsa (senkron vb.) listede kalemi olan masa DOLU görünür', () async {
      final m = await depo.masaEkle(const MasaModel(ad: 'Masa 1'));
      final s = await depo.siparisAcVeyaGetir(m);
      await kalem(s.id!, 'Çay', 2, 10);
      await db.update('masalar', {'durum': 'bos'}, where: 'id = ?', whereArgs: [m]);
      final masa = (await depo.masalariGetir()).single;
      expect(masa.durum, 'dolu');
      expect(masa.aktifToplam, 20);
    });
  });

  group('ödeme — bayat sipariş koruması', () {
    test('ödeme ekranı açıkken başka cihaz ürün eklerse ödeme REDDEDİLİR, hiçbir şey yazılmaz', () async {
      final m = await depo.masaEkle(const MasaModel(ad: 'Masa 1'));
      final s = await depo.siparisAcVeyaGetir(m);
      await kalem(s.id!, 'Çay', 2, 10);
      final ekrandakiKopya = (await depo.acikSiparisGetir(m))!; // ödeme penceresi bunu tutar

      // Pencere açıkken başka bir terminal/QR sipariş ekledi:
      await kalem(s.id!, 'Baklava', 1, 80);

      await expectLater(
        MasaOdemeServisi().odemeYap(
          siparis: ekrandakiKopya,
          masaAdi: 'Masa 1',
          odemeKalemleri: [
            {'yontem': 'Nakit', 'tutar': 20.0}
          ],
          paraUstu: 0,
        ),
        throwsA(isA<MasaSiparisDegistiHatasi>()),
      );

      expect((await db.query('satislar')).length, 0, reason: 'satış yazılmamalı');
      expect((await db.query('kasa_hareketleri')).length, 0);
      final sip = (await db.query('masa_siparisleri', where: 'id = ?', whereArgs: [s.id])).first;
      expect(sip['durum'], 'acik', reason: 'sipariş kapanmamalı');
      expect(await masaDurum(m), 'dolu');
    });

    test('sipariş değişmediyse ödeme normal tamamlanır', () async {
      final m = await depo.masaEkle(const MasaModel(ad: 'Masa 1'));
      final s = await depo.siparisAcVeyaGetir(m);
      await kalem(s.id!, 'Çay', 2, 10);
      final kopya = (await depo.acikSiparisGetir(m))!;

      final sonuc = await MasaOdemeServisi().odemeYap(
        siparis: kopya,
        masaAdi: 'Masa 1',
        odemeKalemleri: [
          {'yontem': 'Nakit', 'tutar': 20.0}
        ],
        paraUstu: 0,
      );
      expect(sonuc.genelToplam, 20);
      expect((await db.query('satislar')).length, 1);
      expect(await masaDurum(m), 'bos');
    });
  });

  group('rezervasyon çakışması', () {
    late int masa;
    final servis = RezervasyonServisi();
    final gun = DateTime(2030, 6, 15);
    RezervasyonModel rez(int saat, [int dakika = 0, int? masaId]) => RezervasyonModel(
          masaId: masaId ?? masa,
          musteriAdi: 'Müşteri',
          telefon: '5550000000',
          tarih: gun,
          saat: DateTime(2030, 6, 15, saat, dakika),
        );

    setUp(() async {
      masa = await db.insert('masalar', {'ad': 'Masa 1', 'durum': 'bos'});
    });

    test('2 saat içindeki yeni rezervasyon reddedilir (öncesi ve sonrası), dışındaki kabul edilir', () async {
      await servis.ekle(rez(19));
      await expectLater(servis.ekle(rez(20)), throwsException, reason: '19:00 varken 20:00');
      await expectLater(servis.ekle(rez(18, 30)), throwsException, reason: '19:00 varken 18:30');
      await expectLater(servis.ekle(rez(19)), throwsException, reason: 'aynı saat');
      await servis.ekle(rez(21)); // tam 2 saat sonra → çakışmaz
      await servis.ekle(rez(17)); // 2 saat önce → çakışmaz
      final baskaMasa = await db.insert('masalar', {'ad': 'Masa 2', 'durum': 'bos'});
      await servis.ekle(rez(19, 0, baskaMasa)); // başka masa serbest
    });

    test('iptal edilmiş rezervasyon çakışma sayılmaz; masaMusaitMi tutarlı', () async {
      final id = await servis.ekle(rez(19));
      expect(await servis.masaMusaitMi(masa, gun, DateTime(2030, 6, 15, 20)), isFalse);
      await servis.durumGuncelle(id, RezervasyonDurum.iptal);
      expect(await servis.masaMusaitMi(masa, gun, DateTime(2030, 6, 15, 20)), isTrue);
    });

    test('güncellemede çakışma reddedilir, kendi saatiyle kaydetmek serbest', () async {
      final a = await servis.ekle(rez(19));
      final b = await servis.ekle(rez(22));
      final kendisi = (await servis.idileGetir(a))!;
      await servis.guncelle(kendisi); // kendi kendine çakışmamalı

      final tasinan = (await servis.idileGetir(b))!;
      final cakisan = RezervasyonModel(
        id: tasinan.id, globalId: tasinan.globalId, masaId: tasinan.masaId,
        musteriAdi: tasinan.musteriAdi, telefon: tasinan.telefon,
        tarih: tasinan.tarih, saat: DateTime(2030, 6, 15, 20),
      );
      await expectLater(servis.guncelle(cakisan), throwsException);
    });
  });
}
