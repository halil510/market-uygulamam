// test/ekranlar/borc_silme_test.dart
//
// "Borç Silme" özelliği (2026-09-13, kullanıcı isteği — hem cari
// müşteri borcu hem de Borç Takip modülü kapsandı). CariDeposu ve
// BorcDeposu Veritabani() singleton'ı üzerinden çalıştığı için (diğer
// depo testlerinde olduğu gibi) burada AYNI SQL/mantık gerçek şema
// üzerinde doğrulanıyor.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/veri/database/migrasyon_yonetici.dart';
import '../helper/test_initializer.dart';

void main() {
  late Database db;
  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  group('Cari borç silme (CariDeposu.hareketEkle ile aynı mantık)', () {
    test('tam tutar silinince bakiye sıfırlanır, geçmiş hareketler silinmez', () async {
      final cariId = await TestVeritabani.ornekCariEkle(db, unvan: 'Borçlu Müşteri');
      // 300 TL borç oluştur (satış gibi)
      await db.insert('cari_hareket', {
        'cari_id': cariId, 'fis_tipi': 'Satış', 'tarih': DateTime.now().toIso8601String(),
        'aciklama': 'Test satış', 'borc': 300, 'alacak': 0, 'is_deleted': 0,
      });
      await db.rawUpdate(
        'UPDATE cari SET bakiye = (SELECT COALESCE(SUM(borc),0)-COALESCE(SUM(alacak),0) FROM cari_hareket WHERE cari_id=? AND is_deleted=0) WHERE id=?',
        [cariId, cariId]);

      var cari = (await db.query('cari', where: 'id=?', whereArgs: [cariId])).first;
      expect((cari['bakiye'] as num).toDouble(), 300.0);

      // Borç Silme: tam tutar için alacak kaydı (fisTipi='Borç Silme')
      await db.insert('cari_hareket', {
        'cari_id': cariId, 'fis_tipi': 'Borç Silme', 'tarih': DateTime.now().toIso8601String(),
        'aciklama': 'Borç Silindi: test', 'borc': 0, 'alacak': 300, 'is_deleted': 0,
      });
      await db.rawUpdate(
        'UPDATE cari SET bakiye = (SELECT COALESCE(SUM(borc),0)-COALESCE(SUM(alacak),0) FROM cari_hareket WHERE cari_id=? AND is_deleted=0) WHERE id=?',
        [cariId, cariId]);

      cari = (await db.query('cari', where: 'id=?', whereArgs: [cariId])).first;
      expect((cari['bakiye'] as num).toDouble(), 0.0);

      // Orijinal satış kaydı hâlâ duruyor — hiçbir kayıt silinmedi.
      final hareketler = await db.query('cari_hareket', where: 'cari_id=?', whereArgs: [cariId]);
      expect(hareketler.length, 2);
      expect(hareketler.any((h) => h['fis_tipi'] == 'Satış'), isTrue);
      expect(hareketler.any((h) => h['fis_tipi'] == 'Borç Silme'), isTrue);
    });

    test('kısmi silme yalnızca girilen tutar kadar bakiyeyi azaltır', () async {
      final cariId = await TestVeritabani.ornekCariEkle(db, unvan: 'Kısmi Borçlu');
      await db.insert('cari_hareket', {
        'cari_id': cariId, 'fis_tipi': 'Satış', 'tarih': DateTime.now().toIso8601String(),
        'aciklama': 'Test', 'borc': 500, 'alacak': 0, 'is_deleted': 0,
      });
      await db.insert('cari_hareket', {
        'cari_id': cariId, 'fis_tipi': 'Borç Silme', 'tarih': DateTime.now().toIso8601String(),
        'aciklama': 'Borç Silindi: kısmi', 'borc': 0, 'alacak': 120, 'is_deleted': 0,
      });
      await db.rawUpdate(
        'UPDATE cari SET bakiye = (SELECT COALESCE(SUM(borc),0)-COALESCE(SUM(alacak),0) FROM cari_hareket WHERE cari_id=? AND is_deleted=0) WHERE id=?',
        [cariId, cariId]);

      final cari = (await db.query('cari', where: 'id=?', whereArgs: [cariId])).first;
      expect((cari['bakiye'] as num).toDouble(), 380.0);
    });
  });

  group('Borç Takip — borç kaydı silme (BorcDeposu.sil ile aynı mantık)', () {
    test('soft-delete sonrası aktif listede görünmez, ödeme geçmişi kalır', () async {
      final borcId = await db.insert('borclar', {
        'baslik': 'Kira', 'tur': 'kira', 'tutar': 1000, 'odenen_tutar': 300,
        'kesim_tarihi': DateTime.now().toIso8601String(),
        'son_odeme_tarihi': DateTime.now().toIso8601String(),
        'odendi': 0, 'is_deleted': 0,
      });
      await db.insert('borc_odemeler', {
        'borc_id': borcId, 'tutar': 300, 'tarih': DateTime.now().toIso8601String(),
        'odeme_yontemi': 'Nakit',
      });

      // BorcDeposu.sil() ile birebir aynı: gerçek DELETE değil, is_deleted=1
      await db.update('borclar', {'is_deleted': 1}, where: 'id=?', whereArgs: [borcId]);

      final aktifler = await db.query('borclar', where: 'is_deleted = 0');
      expect(aktifler, isEmpty);

      final tumKayit = await db.query('borclar', where: 'id=?', whereArgs: [borcId]);
      expect(tumKayit.first['is_deleted'], 1);
      expect((tumKayit.first['tutar'] as num).toDouble(), 1000.0);

      // Ödeme geçmişi (borc_odemeler) SİLİNMEDİ — tarihsel iz korunuyor.
      final odemeler = await db.query('borc_odemeler', where: 'borc_id=?', whereArgs: [borcId]);
      expect(odemeler.length, 1);
      expect((odemeler.first['tutar'] as num).toDouble(), 300.0);
    });
  });

  // 🔴🔴 KRİTİK DÜZELTME DOĞRULAMASI: 'borclar' tablosu migrasyon
  // zincirinde (fresh-install şemasının aksine) is_deleted sütunu hiç
  // içermiyordu — v58->v59 migrasyonu bunu ekliyor. Bu test, fresh-install
  // şemasını DEĞİL, gerçek migrasyon SQL'ini (eski cihazları taklit
  // ederek) çalıştırıp doğruluyor.
  group('borclar.is_deleted migrasyonu (v58 -> v59)', () {
    test('is_deleted sütunu olmayan eski bir borclar tablosuna sütun ekleniyor', () async {
      // singleInstance:false ZORUNLU — aksi halde sqflite, setUp()'ta
      // TestVeritabani.olustur() ile AÇILMIŞ OLAN (inMemoryDatabasePath
      // ile aynı) veritabanını path bazlı önbellekten geri döndürür ve
      // bu test kendi tablosunu değil, o veritabanını (is_deleted zaten
      // var) görür — yanlış pozitif.
      final eskiDb = await databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(version: 1, singleInstance: false, onCreate: (d, v) async {
          // Migrasyon zincirindeki (semalar/borc_semasi.dart'ın AKSİNE)
          // is_deleted İÇERMEYEN eski CREATE TABLE'ın birebir aynısı.
          await d.execute('''
            CREATE TABLE borclar (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              global_id TEXT UNIQUE,
              baslik TEXT NOT NULL,
              tur TEXT NOT NULL,
              tutar REAL NOT NULL,
              odenen_tutar REAL NOT NULL DEFAULT 0,
              son_odeme_tarihi TEXT NOT NULL,
              odendi INTEGER NOT NULL DEFAULT 0
            )
          ''');
        }),
      );

      // Migrasyondan önce: is_deleted yok, bir güncelleme hata verir.
      var kolonlar = await eskiDb.rawQuery('PRAGMA table_info(borclar)');
      expect(kolonlar.any((k) => k['name'] == 'is_deleted'), isFalse);

      await MigrasyonYonetici.guncelle(eskiDb, 58, 59);

      kolonlar = await eskiDb.rawQuery('PRAGMA table_info(borclar)');
      expect(kolonlar.any((k) => k['name'] == 'is_deleted'), isTrue);

      // Artık BorcDeposu.sil()'ün yaptığı güncelleme hatasız çalışır.
      final id = await eskiDb.insert('borclar', {
        'baslik': 'Test', 'tur': 'kira', 'tutar': 100, 'son_odeme_tarihi': DateTime.now().toIso8601String(),
      });
      await eskiDb.update('borclar', {'is_deleted': 1}, where: 'id=?', whereArgs: [id]);
      final row = (await eskiDb.query('borclar', where: 'id=?', whereArgs: [id])).first;
      expect(row['is_deleted'], 1);

      await eskiDb.close();
    });
  });
}
