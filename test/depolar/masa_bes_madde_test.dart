// test/depolar/masa_bes_madde_test.dart
//
// Masa modülü 5 açık maddesi (2026-10-05):
//  1. Masa kalemlerinde promosyon / indirimli fiyat (Hızlı Satış kuralı)
//  2. Boş masa yaklaşan rezervasyonla "rezerve" GÖRÜNÜR (DB'ye yazılmaz)
//  3. Masa raporu iptal edilen / iade edilen satışı düşer
//  4. Masa yazımları sync_queue ile aynı transaction'da atomik
//  5. Ürün seçim ekranı büyük katalogla (limitsiz) çalışır
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/depolar/masa_deposu.dart';
import 'package:market_plus/depolar/urun_deposu.dart';
import 'package:market_plus/modeller/masa_model.dart';
import 'package:market_plus/servisler/masa/masa_rapor_servisi.dart';
import 'package:market_plus/servisler/masa/rezervasyon_servisi.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late MasaDeposu depo;
  late int urunId;

  Future<List<Map<String, Object?>>> kuyruk(String tablo) => db.query('sync_queue',
      where: 'tablo_adi = ? AND durum = ?', whereArgs: [tablo, 'beklemede']);

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (_) async => null);
    SharedPreferences.setMockInitialValues({});
    db = await TestVeritabani.olustur();
    Veritabani.testVeritabani = db;
    depo = MasaDeposu();
    urunId = await TestVeritabani.ornekUrunEkle(db, satisFiyati: 100);
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    Veritabani.testVeritabani = null;
    await db.close();
  });

  group('1. promosyon / indirimli fiyat', () {
    Future<void> promosyon(double oran, double minMiktar) => db.insert('promosyonlar', {
          'global_id': 'p-$oran-$minMiktar',
          'urun_id': urunId,
          'promosyon_adi': 'Test',
          'iskonto_oran': oran,
          'min_miktar': minMiktar,
          'aktif': 1,
        });

    Future<double> fiyat(int siparisId) async =>
        ((await db.query('masa_siparis_kalem', where: 'siparis_id = ?', whereArgs: [siparisId]))
                .first['birim_fiyat'] as num)
            .toDouble();

    test('liste fiyatıyla eklenen ürüne geçerli promosyon uygulanır', () async {
      await promosyon(10, 1);
      final m = await depo.masaEkle(const MasaModel(ad: 'M1'));
      final s = await depo.siparisAcVeyaGetir(m);
      await depo.kalemEkle(s.id!, urunId: urunId, urunAdi: 'Ürün', birimFiyat: 100, kdvOran: 20);
      expect(await fiyat(s.id!), 90.0);
      expect(((await db.query('masa_siparisleri')).first['toplam_tutar'] as num).toDouble(), 90.0);
    });

    test('miktar eşikli promosyon: eşik aşılınca fiyat düşer, geri inince yükselir', () async {
      await promosyon(20, 3);
      final m = await depo.masaEkle(const MasaModel(ad: 'M1'));
      final s = await depo.siparisAcVeyaGetir(m);
      await depo.kalemEkle(s.id!, urunId: urunId, urunAdi: 'Ürün', birimFiyat: 100, kdvOran: 20, miktar: 2);
      expect(await fiyat(s.id!), 100.0);
      await depo.kalemEkle(s.id!, urunId: urunId, urunAdi: 'Ürün', birimFiyat: 100, kdvOran: 20); // 3 adet
      expect(await fiyat(s.id!), 80.0);
      final kalemId = (await db.query('masa_siparis_kalem')).first['id'] as int;
      await depo.kalemMiktarGuncelle(kalemId, 1);
      expect(await fiyat(s.id!), 100.0);
    });

    test('elle verilen (liste dışı) fiyat korunur', () async {
      await promosyon(10, 1);
      final m = await depo.masaEkle(const MasaModel(ad: 'M1'));
      final s = await depo.siparisAcVeyaGetir(m);
      await depo.kalemEkle(s.id!, urunId: urunId, urunAdi: 'Ürün', birimFiyat: 55, kdvOran: 20);
      expect(await fiyat(s.id!), 55.0);
    });

    test('promosyonsuz ürün liste fiyatında kalır', () async {
      final m = await depo.masaEkle(const MasaModel(ad: 'M1'));
      final s = await depo.siparisAcVeyaGetir(m);
      await depo.kalemEkle(s.id!, urunId: urunId, urunAdi: 'Ürün', birimFiyat: 100, kdvOran: 20);
      expect(await fiyat(s.id!), 100.0);
    });
  });

  group('2. rezerve görünümü', () {
    Future<void> rez(int masaId, DateTime saat, {String durum = 'beklemede'}) =>
        db.insert('masa_rezervasyon', {
          'global_id': 'r-${saat.microsecondsSinceEpoch}',
          'masa_id': masaId,
          'musteri_adi': 'Ayşe',
          'telefon': '5',
          'kisi_sayisi': 2,
          'tarih': saat.toIso8601String(),
          'saat': saat.toIso8601String(),
          'durum': durum,
        });

    Future<String> gorunum(int masaId) async =>
        (await depo.masalariGetir()).firstWhere((x) => x.id == masaId).durum;

    test('yaklaşan rezervasyon → rezerve görünür, DB durumu bos kalır', () async {
      final m = await depo.masaEkle(const MasaModel(ad: 'M1'));
      await rez(m, DateTime.now().add(const Duration(minutes: 30)));
      expect(await gorunum(m), 'rezerve');
      expect((await db.query('masalar', where: 'id = ?', whereArgs: [m])).first['durum'], 'bos');
    });

    test('uzak / iptal / geç kalınmış rezervasyon masayı rezerve göstermez', () async {
      final m = await depo.masaEkle(const MasaModel(ad: 'M1'));
      await rez(m, DateTime.now().add(const Duration(hours: 5)));
      await rez(m, DateTime.now().add(const Duration(minutes: 10)), durum: 'iptal');
      await rez(m, DateTime.now().subtract(const Duration(hours: 2)));
      expect(await gorunum(m), 'bos');
    });

    test('masa açılınca (dolu) rezerve görünümü kalkar; rezervasyon iptali masayı serbest bırakır', () async {
      final m = await depo.masaEkle(const MasaModel(ad: 'M1'));
      await rez(m, DateTime.now().add(const Duration(minutes: 20)));
      expect(await gorunum(m), 'rezerve');
      expect(await RezervasyonServisi().masaYaklasanRezervasyonlariIptalEt(m), 1);
      expect(await gorunum(m), 'bos');

      await rez(m, DateTime.now().add(const Duration(minutes: 20)));
      await depo.siparisAcVeyaGetir(m);
      expect(await gorunum(m), 'dolu');
    });
  });

  group('3. masa raporu iptal / iade', () {
    var sayac = 0;
    Future<int> odenmisSiparis(int masaId, double tutar,
        {int iptal = 0, bool satisYok = false}) async {
      final n = ++sayac;
      int? satisId;
      if (!satisYok) {
        satisId = await db.insert('satislar', {
          'global_id': 'sat-$n',
          'fis_no': 'F$n',
          'toplam_tutar': tutar,
          'genel_toplam': tutar,
          'iptal': iptal,
        });
      }
      return db.insert('masa_siparisleri', {
        'global_id': 's-$n',
        'masa_id': masaId,
        'durum': 'odendi',
        'acilis_zamani': DateTime.now().toIso8601String(),
        'kapanis_zamani': DateTime.now().toIso8601String(),
        'toplam_tutar': tutar,
        'satis_id': satisId,
      });
    }

    test('iptal edilen satışın siparişi ciroya ve sayıya girmez', () async {
      final m = await depo.masaEkle(const MasaModel(ad: 'M1'));
      await odenmisSiparis(m, 100);
      await odenmisSiparis(m, 50, iptal: 1);
      final rapor = MasaRaporServisi();
      expect(await rapor.toplamMasaCiro(DateTime.now()), 100.0);
      final gunluk = await rapor.gunlukMasaCiro(DateTime.now());
      expect((gunluk.first['ciro'] as num).toDouble(), 100.0);
      expect(gunluk.first['siparis_sayisi'], 1);
      final perf = (await rapor.masaPerformansAnalizi()).first;
      expect((perf['ciro'] as num).toDouble(), 100.0);
      expect(perf['siparis_sayisi'], 1);
    });

    test('tamamlanmış iade ciro toplamından düşülür; satışsız eski sipariş aynen sayılır', () async {
      final m = await depo.masaEkle(const MasaModel(ad: 'M1'));
      final sip = await odenmisSiparis(m, 100);
      final satisId = (await db.query('masa_siparisleri', where: 'id = ?', whereArgs: [sip]))
          .first['satis_id'] as int;
      await db.insert('iade', {
        'global_id': 'i1', 'satis_id': satisId, 'toplam_tutar': 30, 'durum': 'tamamlandi',
      });
      await odenmisSiparis(m, 40, satisYok: true);
      expect(await MasaRaporServisi().toplamMasaCiro(DateTime.now()), 110.0); // 70 + 40
    });
  });

  group('4. atomik sync kuyruğu', () {
    test('masa/sipariş/kalem yazımları AYNI transaction\'da kuyruğa düşer', () async {
      final m = await depo.masaEkle(const MasaModel(ad: 'M1'));
      expect((await kuyruk('masalar')).length, 1);
      final s = await depo.siparisAcVeyaGetir(m);
      await depo.kalemEkle(s.id!, urunId: urunId, urunAdi: 'Ürün', birimFiyat: 100, kdvOran: 20);
      expect((await kuyruk('masa_siparisleri')).length, 1);
      expect((await kuyruk('masa_siparis_kalem')).length, 1);
      // Kuyruktaki sipariş kaydı EN GÜNCEL toplamı taşır.
      final q = (await kuyruk('masa_siparisleri')).first['veri_json'] as String;
      expect(q.contains('"toplam_tutar":100'), isTrue);
    });

    test('işlem hata verirse kuyruğa da HİÇBİR şey yazılmaz', () async {
      final m = await depo.masaEkle(const MasaModel(ad: 'M1'));
      final s = await depo.siparisAcVeyaGetir(m);
      await depo.kalemEkle(s.id!, urunId: urunId, urunAdi: 'Ürün', birimFiyat: 100, kdvOran: 20);
      await db.delete('sync_queue');
      await db.execute('''
        CREATE TRIGGER test_hata BEFORE UPDATE OF durum ON masalar
        WHEN NEW.durum = 'bos'
        BEGIN SELECT RAISE(ABORT, 'yapay hata'); END''');
      await expectLater(depo.siparisIptal(s.id!, m), throwsA(anything));
      expect((await db.query('masa_siparisleri')).first['durum'], 'acik');
      expect((await db.query('sync_queue')).length, 0);
    });

    test('masaTasi kuyruğa kaynak+hedef sipariş, kalem ve iki masayı yazar', () async {
      final m1 = await depo.masaEkle(const MasaModel(ad: 'M1'));
      final m2 = await depo.masaEkle(const MasaModel(ad: 'M2'));
      final s = await depo.siparisAcVeyaGetir(m1);
      await depo.kalemEkle(s.id!, urunId: urunId, urunAdi: 'Ürün', birimFiyat: 100, kdvOran: 20);
      await db.delete('sync_queue');
      await depo.masaTasi(s.id!, m2);
      expect((await kuyruk('masa_siparisleri')).length, 2);
      expect((await kuyruk('masalar')).length, 2);
      expect((await kuyruk('masa_siparis_kalem')).length, 1);
    });
  });

  test('5. ürün seçim ekranı için katalog limitsiz yüklenir (2000+ ürün)', () async {
    final batch = db.batch();
    for (var i = 0; i < 2100; i++) {
      batch.insert('urunler', {
        'urun_adi': 'Ürün $i', 'barkod': 'b$i', 'satis_fiyati': 1, 'alis_fiyat': 1,
        'stok': 1, 'birim_adi': 'Adet', 'kdv_oran': '20', 'aktif': 1, 'is_deleted': 0,
      });
    }
    await batch.commit(noResult: true);
    final tum = await UrunDeposu().tumunuGetir(sadecaAktif: true);
    expect(tum.length, greaterThan(2000));
  });
}
