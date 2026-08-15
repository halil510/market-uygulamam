// test/helper/test_initializer.dart
//
// TEK MERKEZİ TEST VERİTABANI YARDIMCISI
// ------------------------------------------------------------------
// Önceden her test dosyası kendi CREATE TABLE SQL'ini elle yazıyordu
// (bkz. satis_servisi_test.dart) — bu hem tekrar hem de gerçek şemadan
// sapma riski taşıyordu. Bu yardımcı, projenin GERÇEK üretim şemasını
// (TabloOlusturucu — lib/veri/database/tablolar/tablo_olusturucu.dart)
// kullanarak bellek-içi (in-memory) bir SQLite veritabanı kurar. Böylece
// testler her zaman gerçek tablo yapısıyla çalışır, şema değişince
// testler otomatik güncel kalır.
//
// Kullanım:
//   late Database db;
//   setUp(() async => db = await TestVeritabani.olustur());
//   tearDown(() => db.close());
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:market_plus/veri/database/tablolar/tablo_olusturucu.dart';

class TestVeritabani {
  static bool _ffiHazir = false;

  /// Gerçek üretim şemasıyla bellek-içi (geçici) bir test veritabanı
  /// oluşturur. Her çağrıda tamamen yeni/temiz bir veritabanı döner.
  static Future<Database> olustur() async {
    if (!_ffiHazir) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      _ffiHazir = true;
    }
    final db = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onCreate: (db, version) => TabloOlusturucu.olustur(db),
    );
    return db;
  }

  /// Hızlı testler için örnek bir ürün ekler ve id'sini döner.
  static Future<int> ornekUrunEkle(
    Database db, {
    String urunAdi = 'Test Ürün',
    String? barkod,
    double satisFiyati = 100,
    double alisFiyat = 80,
    double stok = 50,
  }) {
    return db.insert('urunler', {
      'urun_adi': urunAdi,
      'barkod': barkod ?? '869${DateTime.now().microsecondsSinceEpoch % 1000000000}',
      'satis_fiyati': satisFiyati,
      'alis_fiyat': alisFiyat,
      'stok': stok,
      'birim_adi': 'Adet',
      'kdv_oran': '20',
      'aktif': 1,
      'is_deleted': 0,
    });
  }

  /// Hızlı testler için örnek bir cari (müşteri/tedarikçi) ekler.
  static Future<int> ornekCariEkle(
    Database db, {
    String unvan = 'Test Cari',
    String cariTipi = 'Müşteri',
  }) {
    return db.insert('cari', {
      'unvan': unvan,
      'cari_tipi': cariTipi,
      'bakiye': 0,
      'aktif': 1,
      'is_deleted': 0,
    });
  }
}
