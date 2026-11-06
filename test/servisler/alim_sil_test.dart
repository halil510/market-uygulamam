// test/servisler/alim_sil_test.dart
//
// Kullanıcı bulgusu (2026-09-22): "tedarikçi alım da aynı silme de
// listede gözüküyor sonra alacaklı konuma geçmiyor" — bir Alım
// silindiğinde (a) Alım Listesi'nin "Teslim Alınan" sekmesinde AYNEN
// görünmeye devam ediyordu, (b) stok hiç geri düşülmüyordu, (c) Nakit/
// Havale ile yapılmış bir alımda kasadan/bankadan çıkan para GERİ
// GELMİYORDU. Kök neden: AlimIslemServisi'nin hiç sil() metodu yoktu —
// silme, 'Alım' kavramından habersiz genel amaçlı CariDeposu.
// hareketIptalEt()'e düşüyordu (referans_turu='cari_hareket' arıyordu,
// ama alimKaydet() referans_turu='alim' yazıyordu — asla eşleşmiyordu).
//
//
// 2026-11-06 (test güvenilirliği, Kademe 1): bu test ÖNCEDEN sil()'in
// kopyası olan bir simülasyon fonksiyonunu çağırıyordu — üretim kodu
// bozulsa bile yeşil kalırdı. Artık GERÇEK AlimIslemServisi().sil()
// çağrılıyor (Veritabani.testVeritabani seam'i ile bellek-içi gerçek şema).
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:market_plus/servisler/alim_islem_servisi.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

Future<void> _alimSil(int alimId) => AlimIslemServisi().sil(alimId);

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

  group('AlimIslemServisi.sil() — Cari (veresiye) alım', () {
    test('bakiye TAM olarak eski haline döner (tedarikçiye olan borcumuz kalkar)', () async {
      final cariId = await TestVeritabani.ornekCariEkle(db, cariTipi: 'Tedarikçi');
      final urunId = await TestVeritabani.ornekUrunEkle(db, stok: 10);

      final alimId = await db.insert('tedarikci_siparisler', {
        'cari_id': cariId, 'siparis_no': 'AL2026000001', 'siparis_tarihi': DateTime.now().toIso8601String(),
        'toplam_tutar': 150.0, 'durum': 'teslim_alindi', 'is_deleted': 0,
      });
      await db.insert('tedarikci_siparis_kalem', {
        'siparis_id': alimId, 'urun_id': urunId, 'siparis_mik': 5, 'teslim_mik': 5,
        'birim_fiyat': 30.0, 'kdv_oran': 0, 'toplam_tutar': 150.0,
      });
      await db.update('urunler', {'stok': 15}, where: 'id = ?', whereArgs: [urunId]); // 10 + 5 alım
      await db.insert('cari_hareket', {
        'global_id': const Uuid().v4(), 'cari_id': cariId, 'tarih': DateTime.now().toIso8601String(),
        'fis_tipi': 'Alım', 'fis_id': alimId, 'fis_no': 'AL2026000001',
        'aciklama': 'Mal Alımı: AL2026000001', 'borc': 0, 'alacak': 150.0, 'odeme_turu': 'Cari', 'is_deleted': 0,
      });
      await db.update('cari', {'bakiye': -150.0}, where: 'id = ?', whereArgs: [cariId]);

      await _alimSil(alimId);

      final cari = (await db.query('cari', where: 'id = ?', whereArgs: [cariId])).first;
      expect((cari['bakiye'] as num).toDouble(), equals(0.0),
          reason: 'Alım silinince tedarikçiye olan borcumuz tam sıfırlanmalı ("alacaklı" konumuna dönmeli)');

      final urun = (await db.query('urunler', where: 'id = ?', whereArgs: [urunId])).first;
      expect((urun['stok'] as num).toDouble(), equals(10.0), reason: 'alınan mal stoktan geri düşmeli');

      final siparis = (await db.query('tedarikci_siparisler', where: 'id = ?', whereArgs: [alimId])).first;
      expect(siparis['durum'], 'iptal', reason: 'Alım Listesi "Teslim Alınan" sekmesinden düşmeli');
      expect(siparis['is_deleted'], 1);
    });

    test('zaten "iptal" durumundaki bir alım TEKRAR silinemez', () async {
      final cariId = await TestVeritabani.ornekCariEkle(db, cariTipi: 'Tedarikçi');
      final alimId = await db.insert('tedarikci_siparisler', {
        'cari_id': cariId, 'siparis_no': 'AL2', 'siparis_tarihi': DateTime.now().toIso8601String(),
        'toplam_tutar': 50.0, 'durum': 'iptal', 'is_deleted': 1,
      });

      await expectLater(_alimSil(alimId), throwsException);
    });

    // CLAUDE.md §3.3 / §5.1: ikinci silme hiçbir ters kayıt üretmez.
    test('silinen alım ikinci kez silinince reddedilir, ters kayıtlar tekrarlanmaz', () async {
      final cariId = await TestVeritabani.ornekCariEkle(db, cariTipi: 'Tedarikçi');
      final urunId = await TestVeritabani.ornekUrunEkle(db, stok: 5);
      final alimId = await db.insert('tedarikci_siparisler', {
        'cari_id': cariId, 'siparis_no': 'AL4', 'siparis_tarihi': DateTime.now().toIso8601String(),
        'toplam_tutar': 60.0, 'durum': 'teslim_alindi', 'is_deleted': 0,
      });
      await db.insert('tedarikci_siparis_kalem', {
        'siparis_id': alimId, 'urun_id': urunId, 'siparis_mik': 2, 'teslim_mik': 2,
        'birim_fiyat': 30.0, 'kdv_oran': 0, 'toplam_tutar': 60.0,
      });
      await db.insert('cari_hareket', {
        'global_id': const Uuid().v4(), 'cari_id': cariId, 'tarih': DateTime.now().toIso8601String(),
        'fis_tipi': 'Alım', 'fis_id': alimId, 'fis_no': 'AL4',
        'aciklama': 'Mal Alımı: AL4', 'borc': 0, 'alacak': 60.0, 'odeme_turu': 'Cari', 'is_deleted': 0,
      });

      await _alimSil(alimId);
      await expectLater(_alimSil(alimId), throwsException);

      final iptaller = await db.query('cari_hareket',
          where: 'fis_id = ? AND fis_tipi = ?', whereArgs: [alimId, 'Alım İptali']);
      expect(iptaller, hasLength(1));
      final urun = (await db.query('urunler', where: 'id = ?', whereArgs: [urunId])).first;
      expect((urun['stok'] as num).toDouble(), equals(3.0), reason: 'stok yalnız bir kez düşmeli');
    });
  });

  group('AlimIslemServisi.sil() — Nakit alım', () {
    test('kasadan çıkan para GERİ GELİR', () async {
      final cariId = await TestVeritabani.ornekCariEkle(db, cariTipi: 'Tedarikçi');
      final urunId = await TestVeritabani.ornekUrunEkle(db, stok: 0);
      final alimId = await db.insert('tedarikci_siparisler', {
        'cari_id': cariId, 'siparis_no': 'AL3', 'siparis_tarihi': DateTime.now().toIso8601String(),
        'toplam_tutar': 80.0, 'durum': 'teslim_alindi', 'is_deleted': 0,
      });
      await db.insert('tedarikci_siparis_kalem', {
        'siparis_id': alimId, 'urun_id': urunId, 'siparis_mik': 4, 'teslim_mik': 4,
        'birim_fiyat': 20.0, 'kdv_oran': 0, 'toplam_tutar': 80.0,
      });
      await db.update('urunler', {'stok': 4}, where: 'id = ?', whereArgs: [urunId]);
      await db.insert('kasa_hareketleri', {
        'global_id': const Uuid().v4(), 'hareket_tipi': 'Alım', 'tutar': 80.0,
        'referans_id': alimId, 'referans_turu': 'alim', 'tarih': DateTime.now().toIso8601String(),
        'bakiye_sonrasi': -80.0,
      });

      await _alimSil(alimId);

      final kasaTers = await db.query('kasa_hareketleri',
          where: 'referans_id = ? AND referans_turu = ?', whereArgs: [alimId, 'alim_iptal']);
      expect(kasaTers, hasLength(1));
      expect((kasaTers.first['tutar'] as num).toDouble(), equals(80.0));

      final urun = (await db.query('urunler', where: 'id = ?', whereArgs: [urunId])).first;
      expect((urun['stok'] as num).toDouble(), equals(0.0));
    });
  });
}
