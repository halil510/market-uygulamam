// test/servisler/iade_sil_test.dart
//
// Kullanıcı bulgusu (2026-09-22): "iade silme işlemini de kontrol et
// aynı hatalar olmasın" — Satış (SatisDeposu.sil()) ve Tedarikçi Alımı
// (AlimIslemServisi.sil()) silmede bulunan AYNI hata sınıfı İade'nin
// gerçek fiş-silme yolunda (IadeIslemServisi.gecmisFisIadeSil(), İade
// Geçmişi sekmesinden "Fişi Sil") da vardı: kasa reversal'ı orijinal
// iadenin GERÇEKTEN nakit olarak verilip verilmediğine bakmadan HER
// ZAMAN bir "Iade Iptali" (nakit GİRİŞ) kaydı ekliyordu — Kart/Banka
// veya Cari'ye işlenmiş bir iade silinince hiç var olmamış bir nakit
// girişi oluşturuluyordu.
//
// 2026-11-06 (test güvenilirliği, Kademe 1): bu test ÖNCEDEN
// gecmisFisIadeSil()'in kopyası olan bir simülasyon çağırıyordu — üretim
// kodu bozulsa bile yeşil kalırdı. Artık GERÇEK
// IadeIslemServisi().gecmisFisIadeSil() çağrılıyor; parametreler, İade
// Geçmişi ekranının (iade_ekrani_gecmis.dart) yaptığı gibi DB'deki iade ve
// iade_kalem satırlarından hazırlanıyor.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:market_plus/servisler/iade_islem_servisi.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

/// İade Geçmişi ekranındaki "Fişi Sil" çağrısıyla aynı parametrelerle
/// GERÇEK gecmisFisIadeSil()'i çağırır.
Future<void> _gecmisFisIadeSil(Database db, {required int iadeId}) async {
  final iade = (await db.query('iade', where: 'id = ?', whereArgs: [iadeId])).first;
  final kalemler = await db.query('iade_kalem', where: 'iade_id = ?', whereArgs: [iadeId]);
  await IadeIslemServisi().gecmisFisIadeSil(
    iadeId: iadeId,
    kalemler: kalemler.map((k) => Map<String, dynamic>.from(k)).toList(),
    toplamTutar: (iade['toplam_tutar'] as num?)?.toDouble() ?? 0,
    cariId: iade['cari_id'] as int?,
    fisNo: iade['fis_no']?.toString(),
  );
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

  group('gecmisFisIadeSil() — kasa reversal artık tahmine göre değil, GERÇEK satıra göre', () {
    test('Nakit iade silinince kasaya GERÇEK tutarla "Iade Iptali" eklenir', () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db, stok: 10);
      final iadeId = await db.insert('iade', {
        'cari_id': null, 'fis_no': 'IAD1', 'tarih': DateTime.now().toIso8601String(),
        'toplam_tutar': 60.0, 'durum': 'tamamlandi',
      });
      await db.insert('iade_kalem', {
        'iade_id': iadeId, 'urun_id': urunId, 'urun_adi': 'Test',
        'miktar': 2, 'birim_fiyat': 30.0, 'toplam': 60.0,
      });
      await db.update('urunler', {'stok': 12}, where: 'id = ?', whereArgs: [urunId]); // 10 + 2 iade
      await db.insert('kasa_hareketleri', {
        'global_id': const Uuid().v4(), 'hareket_tipi': 'İade', 'tutar': 60.0,
        'referans_id': iadeId, 'referans_turu': 'iade', 'tarih': DateTime.now().toIso8601String(),
      });

      await _gecmisFisIadeSil(db, iadeId: iadeId);

      final kasaTers = await db.query('kasa_hareketleri',
          where: 'referans_id = ? AND referans_turu = ?', whereArgs: [iadeId, 'iade_iptal']);
      expect(kasaTers, hasLength(1));
      expect((kasaTers.first['tutar'] as num).toDouble(), equals(60.0));

      final urun = (await db.query('urunler', where: 'id = ?', whereArgs: [urunId])).first;
      expect((urun['stok'] as num).toDouble(), equals(10.0));
    });

    test('Kart/Banka (kasa satırı OLMAYAN) iade silinince HAYALET nakit-giriş kaydı OLUŞMAZ', () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db, stok: 5);
      final iadeId = await db.insert('iade', {
        'cari_id': null, 'fis_no': 'IAD2', 'tarih': DateTime.now().toIso8601String(),
        'toplam_tutar': 40.0, 'durum': 'tamamlandi',
      });
      await db.insert('iade_kalem', {
        'iade_id': iadeId, 'urun_id': urunId, 'urun_adi': 'Test',
        'miktar': 1, 'birim_fiyat': 40.0, 'toplam': 40.0,
      });
      await db.update('urunler', {'stok': 6}, where: 'id = ?', whereArgs: [urunId]);
      // BİLİNÇLİ OLARAK kasa_hareketleri satırı EKLENMEDİ (Kart/Banka/Cari iade).

      await _gecmisFisIadeSil(db, iadeId: iadeId);

      final kasaTers = await db.query('kasa_hareketleri',
          where: 'referans_id = ? AND referans_turu = ?', whereArgs: [iadeId, 'iade_iptal']);
      expect(kasaTers, isEmpty,
          reason: 'Gerçekte nakit girmemiş bir iadenin silinmesi hayalet bir kasa kaydı OLUŞTURMAMALI');

      final urun = (await db.query('urunler', where: 'id = ?', whereArgs: [urunId])).first;
      expect((urun['stok'] as num).toDouble(), equals(5.0), reason: 'stok yine de geri düşmeli');
    });

    test('Cari (veresiye) iade silinince bakiye tam sıfırlanır', () async {
      final cariId = await TestVeritabani.ornekCariEkle(db);
      final urunId = await TestVeritabani.ornekUrunEkle(db, stok: 0);
      final iadeId = await db.insert('iade', {
        'cari_id': cariId, 'fis_no': 'IAD3', 'tarih': DateTime.now().toIso8601String(),
        'toplam_tutar': 90.0, 'durum': 'tamamlandi',
      });
      await db.insert('iade_kalem', {
        'iade_id': iadeId, 'urun_id': urunId, 'urun_adi': 'Test',
        'miktar': 3, 'birim_fiyat': 30.0, 'toplam': 90.0,
      });
      await db.update('urunler', {'stok': 3}, where: 'id = ?', whereArgs: [urunId]);
      await db.insert('cari_hareket', {
        'global_id': const Uuid().v4(), 'cari_id': cariId, 'tarih': DateTime.now().toIso8601String(),
        'fis_tipi': 'İade', 'fis_id': iadeId, 'fis_no': 'IAD3',
        'borc': 0, 'alacak': 90.0, 'odeme_turu': 'Nakit', 'is_deleted': 0,
      });
      await db.update('cari', {'bakiye': -90.0}, where: 'id = ?', whereArgs: [cariId]);

      await _gecmisFisIadeSil(db, iadeId: iadeId);

      final cari = (await db.query('cari', where: 'id = ?', whereArgs: [cariId])).first;
      expect((cari['bakiye'] as num).toDouble(), equals(0.0));
    });

    test('zaten "iptal" durumundaki bir iade TEKRAR silinemez (çift-iptal koruması)', () async {
      final iadeId = await db.insert('iade', {
        'cari_id': null, 'fis_no': 'IAD4', 'tarih': DateTime.now().toIso8601String(),
        'toplam_tutar': 20.0, 'durum': 'iptal',
      });

      await expectLater(
          _gecmisFisIadeSil(db, iadeId: iadeId), throwsException);
    });

    // CLAUDE.md §3.3 / §5.1: ikinci silme hiçbir ters kayıt üretmez.
    test('Nakit iade silindikten sonra ikinci silme reddedilir; kasa/stok bir kez ters çevrilir', () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db, stok: 12);
      final iadeId = await db.insert('iade', {
        'cari_id': null, 'fis_no': 'IAD5', 'tarih': DateTime.now().toIso8601String(),
        'toplam_tutar': 60.0, 'durum': 'tamamlandi',
      });
      await db.insert('iade_kalem', {
        'iade_id': iadeId, 'urun_id': urunId, 'urun_adi': 'Test',
        'miktar': 2, 'birim_fiyat': 30.0, 'toplam': 60.0,
      });
      await db.insert('kasa_hareketleri', {
        'global_id': const Uuid().v4(), 'hareket_tipi': 'İade', 'tutar': 60.0,
        'referans_id': iadeId, 'referans_turu': 'iade', 'tarih': DateTime.now().toIso8601String(),
      });

      await _gecmisFisIadeSil(db, iadeId: iadeId);
      await expectLater(_gecmisFisIadeSil(db, iadeId: iadeId), throwsException);

      final kasaTers = await db.query('kasa_hareketleri',
          where: 'referans_id = ? AND referans_turu = ?', whereArgs: [iadeId, 'iade_iptal']);
      expect(kasaTers, hasLength(1));
      final urun = (await db.query('urunler', where: 'id = ?', whereArgs: [urunId])).first;
      expect((urun['stok'] as num).toDouble(), equals(10.0));
    });
  });
}
