// test/veri/gecici_sayim_onay_test.dart
//
// Sayım Onay Sistemi (Madde 13 denetimi, 2026-09-16) — StokDeposu
// Veritabani() singleton'ına bağımlı olduğundan (projenin yerleşik test
// deseni, bkz. donem_devir_snapshot_test.dart), gecici_sayim ile ilgili
// SQL mantığı StokDeposu'ndakiyle BİREBİR aynı şekilde, gerçek şema
// üzerinde (TestVeritabani) doğrulanıyor.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import '../helper/test_initializer.dart';

Future<void> _geciciSayimEkleGuncelle(
    Database db, int urunId, double mevcutStok, double yeniStok, {int? kullaniciId}) {
  return db.insert(
      'gecici_sayim',
      {
        'urun_id': urunId,
        'mevcut_stok': mevcutStok,
        'yeni_stok': yeniStok,
        'kullanici_id': kullaniciId,
      },
      conflictAlgorithm: ConflictAlgorithm.replace);
}

Future<List<Map<String, Object?>>> _geciciSayimListesi(Database db) {
  return db.rawQuery(
    'SELECT g.*, u.urun_adi, u.barkod, u.birim_adi, k.ad_soyad AS sayan_adi '
    'FROM gecici_sayim g '
    'JOIN urunler u ON g.urun_id = u.id '
    'LEFT JOIN kullanicilar k ON g.kullanici_id = k.id',
  );
}

/// StokDeposu.geciciSayimUygula() içindeki aciklama üretim mantığıyla
/// BİREBİR aynı — saf, DB'den bağımsız.
String? _aciklamaUret(String? sayanAdi) =>
    (sayanAdi != null && sayanAdi.trim().isNotEmpty)
        ? 'Stok sayım düzeltme (Sayan: $sayanAdi)'
        : null;

void main() {
  late Database db;
  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  Future<int> kullaniciEkle(String adSoyad, {String rol = 'kasiyer'}) {
    return db.insert('kullanicilar', {
      'kullanici_adi': adSoyad.toLowerCase().replaceAll(' ', '_'),
      'sifre_hash': 'x', 'ad_soyad': adSoyad, 'rol': rol, 'aktif': 1,
    });
  }

  group('gecici_sayim — ekle/güncelle', () {
    test('kullanici_id doğru kaydedilir (önceden hiç doldurulmuyordu)', () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db, stok: 10);
      final kasiyerId = await kullaniciEkle('Ayşe Kasiyer');

      await _geciciSayimEkleGuncelle(db, urunId, 10, 12, kullaniciId: kasiyerId);

      final liste = await _geciciSayimListesi(db);
      expect(liste, hasLength(1));
      expect(liste.first['kullanici_id'], kasiyerId);
      expect(liste.first['sayan_adi'], 'Ayşe Kasiyer');
    });

    test('aynı ürün için ikinci sayım İLKİNİN ÜZERİNE yazar (UNIQUE urun_id)', () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db, stok: 10);
      final k1 = await kullaniciEkle('İlk Sayan');
      final k2 = await kullaniciEkle('Son Sayan');

      await _geciciSayimEkleGuncelle(db, urunId, 10, 12, kullaniciId: k1);
      await _geciciSayimEkleGuncelle(db, urunId, 10, 15, kullaniciId: k2);

      final liste = await _geciciSayimListesi(db);
      expect(liste, hasLength(1));
      expect(liste.first['yeni_stok'], 15);
      expect(liste.first['sayan_adi'], 'Son Sayan');
    });

    test('kullanici_id verilmezse null kalır (yine de listelenir)', () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db, stok: 10);
      await _geciciSayimEkleGuncelle(db, urunId, 10, 12);

      final liste = await _geciciSayimListesi(db);
      expect(liste, hasLength(1));
      expect(liste.first['sayan_adi'], isNull);
    });
  });

  group('aciklama enrichment (StokDeposu.geciciSayimUygula ile aynı mantık)', () {
    test('sayan biliniyorsa aciklamaya eklenir', () {
      expect(_aciklamaUret('Ayşe Kasiyer'), 'Stok sayım düzeltme (Sayan: Ayşe Kasiyer)');
    });

    test('sayan bilinmiyorsa (null) varsayılan aciklamaya düşülür (null döner)', () {
      expect(_aciklamaUret(null), isNull);
    });

    test('sayan boş string ise varsayılana düşülür', () {
      expect(_aciklamaUret('   '), isNull);
    });
  });

  group('gecici_sayim listesi birden çok bekleyen ürünü doğru döner', () {
    test('farklı ürünler için farklı satırlar korunur', () async {
      final u1 = await TestVeritabani.ornekUrunEkle(db, urunAdi: 'Kola', barkod: '1111111111', stok: 10);
      final u2 = await TestVeritabani.ornekUrunEkle(db, urunAdi: 'Su', barkod: '2222222222', stok: 20);
      final kasiyerId = await kullaniciEkle('Sayan Kişi');

      await _geciciSayimEkleGuncelle(db, u1, 10, 8, kullaniciId: kasiyerId);
      await _geciciSayimEkleGuncelle(db, u2, 20, 25, kullaniciId: kasiyerId);

      final liste = await _geciciSayimListesi(db);
      expect(liste, hasLength(2));
      expect(liste.map((r) => r['urun_adi']), containsAll(['Kola', 'Su']));
    });
  });
}
