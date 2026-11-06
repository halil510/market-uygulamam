// test/servisler/satis_tamamlama_servisi_test.dart
//
// SatisTamamlamaServisi, hizli_satis_ekrani.dart'tan (protokol §6/§35 —
// mimari borç) birebir taşınan satış tamamlama mantığını içerir: satış +
// kalemler + stok düşümü + kasa/cari hareketi TEK transaction'da.
//
// 2026-11-06 (test güvenilirliği, Kademe 1): bu test ÖNCEDEN tamamla()'nın
// adımlarını kopyalayan bir simülasyon (_satisiSimuleEt) ve fisiGuncelle
// adımlarının elle tekrarını çağırıyordu — üretim kodu bozulsa bile yeşil
// kalırdı. Artık GERÇEK SatisTamamlamaServisi().tamamla() / fisiGuncelle()
// çağrılıyor. Atomiklik testleri, stok adımının yazacağı tabloyu düşürerek
// gerçek transaction'ın gerçekten geri alındığını doğrular.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/depolar/cari_deposu.dart';
import 'package:market_plus/depolar/satis_deposu.dart';
import 'package:market_plus/depolar/urun_deposu.dart';
import 'package:market_plus/modeller/sepet_model.dart';
import 'package:market_plus/servisler/satis_tamamlama_servisi.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

/// GERÇEK SatisTamamlamaServisi().tamamla() — tek kalemli sepet.
/// [stokAdimindaPatlat]: stok hareketi tablosu düşürülür → transaction
/// satış yazıldıktan SONRA, stok adımında patlar.
Future<int> _satisTamamla(
  Database db, {
  required int urunId,
  required double miktar,
  required double birimFiyat,
  required String odemeYontemi,
  int? cariId,
  double odenenTutar = 0,
  bool stokAdimindaPatlat = false,
}) async {
  final urun = (await UrunDeposu().idileGetir(urunId))!;
  final musteri = cariId != null ? await CariDeposu().idileGetir(cariId) : null;
  if (stokAdimindaPatlat) await db.execute('DROP TABLE stok_hareket');
  final sonuc = await SatisTamamlamaServisi().tamamla(
    kalemler: [SepetKalem(urun: urun, miktar: miktar, birimFiyat: birimFiyat)],
    musteri: musteri,
    genelToplam: miktar * birimFiyat,
    odemeYontemi: odemeYontemi,
    odenenTutar: odenenTutar,
  );
  return sonuc.satisId;
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

  group('SatisTamamlamaServisi mantığı — nakit satış', () {
    test('satış, kalem, stok düşümü ve kasa hareketi tek işlemde oluşur', () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db, stok: 50, satisFiyati: 20);

      final satisId = await _satisTamamla(db,
          urunId: urunId, miktar: 3, birimFiyat: 20,
          odemeYontemi: 'Nakit', odenenTutar: 60);

      final satis = (await db.query('satislar', where: 'id = ?', whereArgs: [satisId])).first;
      expect((satis['genel_toplam'] as num).toDouble(), equals(60.0));

      final kalemler = await db.query('satis_kalem', where: 'satis_id = ?', whereArgs: [satisId]);
      expect(kalemler, hasLength(1));

      final urun = (await db.query('urunler', where: 'id = ?', whereArgs: [urunId])).first;
      expect((urun['stok'] as num).toDouble(), equals(47.0), reason: '50 - 3 = 47');

      final kasa = await db.query('kasa_hareketleri',
          where: 'referans_id = ? AND referans_turu = ?', whereArgs: [satisId, 'satis']);
      expect(kasa, hasLength(1));
      expect((kasa.first['tutar'] as num).toDouble(), equals(60.0));

      final cariHareket = await db.query('cari_hareket', where: 'fis_id = ?', whereArgs: [satisId]);
      expect(cariHareket, isEmpty, reason: 'nakit satışta cari hareketi oluşmamalı');
    });
  });

  group('SatisTamamlamaServisi mantığı — veresiye (Cari) satış', () {
    test('kasa hareketi OLUŞMAZ, cari hareketi borç olarak oluşur', () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db, stok: 20, satisFiyati: 100);
      final cariId = await TestVeritabani.ornekCariEkle(db);

      final satisId = await _satisTamamla(db,
          urunId: urunId, miktar: 2, birimFiyat: 100,
          odemeYontemi: 'Cari', cariId: cariId, odenenTutar: 0);

      final kasa = await db.query('kasa_hareketleri',
          where: 'referans_id = ? AND referans_turu = ?', whereArgs: [satisId, 'satis']);
      expect(kasa, isEmpty, reason: 'veresiye satışta kasa hareketi OLUŞMAMALI');

      final cariHareket = await db.query('cari_hareket', where: 'fis_id = ?', whereArgs: [satisId]);
      expect(cariHareket, hasLength(1));
      expect((cariHareket.first['borc'] as num).toDouble(), equals(200.0));
      expect((cariHareket.first['alacak'] as num).toDouble(), equals(0.0));

      final cari = (await db.query('cari', where: 'id = ?', whereArgs: [cariId])).first;
      expect((cari['bakiye'] as num).toDouble(), equals(200.0),
          reason: 'Cari bakiye borç hareketiyle artmalı (protokol §8)');
    });
  });

  group('SatisTamamlamaServisi mantığı — atomiklik', () {
    test('stok adımı başarısız olursa satış TAMAMEN geri alınır', () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db, stok: 10, satisFiyati: 50);

      await expectLater(
        _satisTamamla(db, urunId: urunId, miktar: 1, birimFiyat: 50,
            odemeYontemi: 'Nakit', odenenTutar: 50, stokAdimindaPatlat: true),
        throwsException,
      );

      expect(await db.query('satislar'), isEmpty,
          reason: 'Rollback sonrası satış kaydı KALMAMALI');
      final urun = (await db.query('urunler', where: 'id = ?', whereArgs: [urunId])).first;
      expect((urun['stok'] as num).toDouble(), equals(10.0),
          reason: 'Stok değişmemiş olmalı');
    });
  });

  group('SatisTamamlamaServisi.fisiGuncelle mantığı', () {
    Future<void> fisiGuncelle(int satisId, int urunId,
        {required double yeniMiktar, required double birimFiyat}) async {
      final satis = (await SatisDeposu().idileGetir(satisId))!;
      final urun = (await UrunDeposu().idileGetir(urunId))!;
      await SatisTamamlamaServisi().fisiGuncelle(
        satis: satis,
        yeniKalemler: [SepetKalem(urun: urun, miktar: yeniMiktar, birimFiyat: birimFiyat)],
        yeniGenelToplam: yeniMiktar * birimFiyat,
        odemeYontemi: 'Nakit',
        odenenTutar: yeniMiktar * birimFiyat,
      );
    }

    test('miktar artışı: stok ekstra düşer, kasaya ek tutar yazılır (nakit fiş)', () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db, stok: 100, satisFiyati: 10);
      // Önce 2 adetlik bir satış oluştur (stok 100 -> 98).
      final satisId = await _satisTamamla(db,
          urunId: urunId, miktar: 2, birimFiyat: 10, odemeYontemi: 'Nakit', odenenTutar: 20);

      // Fişi 5 adede çıkar (miktar farkı: +3) — GERÇEK fisiGuncelle.
      await fisiGuncelle(satisId, urunId, yeniMiktar: 5, birimFiyat: 10);

      final fark = await db.query('stok_hareket',
          where: 'referans_id = ? AND referans_turu = ? AND urun_id = ?',
          whereArgs: [satisId, 'fis_guncelleme', urunId]);
      expect(fark, hasLength(1));
      expect((fark.first['miktar'] as num).toDouble(), equals(3.0),
          reason: '5 - 2 = 3 adet fazladan düşülmeli');

      final urun = (await db.query('urunler', where: 'id = ?', whereArgs: [urunId])).first;
      expect((urun['stok'] as num).toDouble(), equals(95.0), reason: '100 - 2 - 3 = 95');

      final satis = (await db.query('satislar', where: 'id = ?', whereArgs: [satisId])).first;
      expect((satis['genel_toplam'] as num).toDouble(), equals(50.0));

      final kalemler = await db.query('satis_kalem', where: 'satis_id = ?', whereArgs: [satisId]);
      expect(kalemler, hasLength(1));
      expect((kalemler.first['miktar'] as num).toDouble(), equals(5.0));
    });

    test('adımlardan biri hata fırlatırsa fiş güncellemesi TAMAMEN geri alınır', () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db, stok: 100, satisFiyati: 10);
      final satisId = await _satisTamamla(db,
          urunId: urunId, miktar: 2, birimFiyat: 10, odemeYontemi: 'Nakit', odenenTutar: 20);

      // Kalemler güncellendikten SONRA stok adımı patlasın.
      await db.execute('DROP TABLE stok_hareket');
      await expectLater(
        fisiGuncelle(satisId, urunId, yeniMiktar: 9, birimFiyat: 10),
        throwsException,
      );

      // Rollback sonrası hem satış başlığı hem kalemler ESKİ haliyle kalmalı.
      final satis = (await db.query('satislar', where: 'id = ?', whereArgs: [satisId])).first;
      expect((satis['genel_toplam'] as num).toDouble(), equals(20.0),
          reason: 'Rollback sonrası eski toplam (20) korunmalı, 90 olmamalı');
      final kalemler = await db.query('satis_kalem', where: 'satis_id = ?', whereArgs: [satisId]);
      expect((kalemler.first['miktar'] as num).toDouble(), equals(2.0));
    });
  });
}
