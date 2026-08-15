// test/veri/tablo_semasi_test.dart
//
// Bu test dosyası, modülerleştirilmiş şema dosyalarının (lib/veri/database/
// semalar/) gerçekten çalışan, tutarlı bir veritabanı ürettiğini doğrular.
// Router/ekran testlerinden farklı olarak burada gerçek SQL çalıştırılır —
// bu da 15 modüle bölünen tablo_olusturucu.dart'ın (bkz. YOL_HARITASI.md)
// hiçbir tabloyu kaybetmediğini, FOREIGN KEY sırasının doğru olduğunu ve
// temel CRUD işlemlerinin çalıştığını kanıtlar.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import '../helper/test_initializer.dart';

void main() {
  late Database db;

  setUp(() async {
    db = await TestVeritabani.olustur();
  });

  tearDown(() async {
    await db.close();
  });

  group('Şema Bütünlüğü', () {
    test('temel tablolar oluşuyor', () async {
      final tablolar = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table'");
      final isimler = tablolar.map((t) => t['name'] as String).toSet();

      // 15 modülün her birinden en az bir tablo bekleniyor
      const beklenenler = [
        'urunler', 'cari', 'satislar', 'satis_kalem', 'stok_hareket',
        'iade', 'promosyonlar', 'bankalar', 'banka_hesaplar',
        'kredi_kartlari', 'borclar', 'masalar', 'personel', 'kullanicilar',
      ];
      for (final t in beklenenler) {
        expect(isimler, contains(t), reason: '"$t" tablosu oluşmadı');
      }
    });

    test('kredi_kartlari tablosunda "cvc" veya düz "kart_no" kolonu YOK',
        () async {
      // Güvenlik regresyon testi — bkz. DERIN_YOL_HARITASI.md A1
      final kolonlar = await db.rawQuery("PRAGMA table_info(kredi_kartlari)");
      final kolonAdlari = kolonlar.map((k) => k['name'] as String).toSet();
      expect(kolonAdlari.contains('cvc'), isFalse);
      expect(kolonAdlari.contains('kart_no'), isFalse);
      expect(kolonAdlari.contains('kart_no_maskeli'), isTrue);
    });

    test('banka_hesaplar tablosu banka_id ile FOREIGN KEY kurabiliyor',
        () async {
      final bankaId = await db.insert('bankalar', {'ad': 'Test Bankası'});
      final hesapId = await db.insert('banka_hesaplar', {
        'banka_id': bankaId,
        'hesap_adi': 'Ana Hesap',
        'hesap_no': '123456',
        'para_birimi': 'TRY',
      });
      expect(hesapId, greaterThan(0));

      final hesaplar = await db.query('banka_hesaplar',
          where: 'banka_id = ?', whereArgs: [bankaId]);
      expect(hesaplar.length, equals(1));
    });
  });

  group('Temel CRUD İşlemleri (gerçek şema ile)', () {
    test('ürün eklenip okunabiliyor', () async {
      final id = await TestVeritabani.ornekUrunEkle(db,
          urunAdi: 'Süt 1L', satisFiyati: 45.50);
      final urun = await db.query('urunler', where: 'id = ?', whereArgs: [id]);
      expect(urun.single['urun_adi'], equals('Süt 1L'));
      expect(urun.single['satis_fiyati'], equals(45.50));
    });

    test('cari eklenip okunabiliyor', () async {
      final id = await TestVeritabani.ornekCariEkle(db, unvan: 'ABC Market');
      final cari = await db.query('cari', where: 'id = ?', whereArgs: [id]);
      expect(cari.single['unvan'], equals('ABC Market'));
      expect(cari.single['cari_tipi'], equals('Müşteri'));
    });

    test('is_deleted=0 filtresi yumuşak silinmiş kayıtları gizler', () async {
      final id = await TestVeritabani.ornekUrunEkle(db, urunAdi: 'Silinecek');
      await db.update('urunler', {'is_deleted': 1},
          where: 'id = ?', whereArgs: [id]);

      final aktifler = await db.query('urunler', where: 'is_deleted = 0');
      expect(aktifler.any((u) => u['id'] == id), isFalse);

      final tumu = await db.query('urunler');
      expect(tumu.any((u) => u['id'] == id), isTrue);
    });

    test('borç kaydı ekleyip kalan tutarı SQL ile hesaplayabiliyoruz',
        () async {
      await db.insert('borclar', {
        'baslik': 'Elektrik',
        'tur': 'fatura',
        'tutar': 1000.0,
        'odenen_tutar': 300.0,
        'kesim_tarihi': DateTime(2026, 1, 1).toIso8601String(),
        'son_odeme_tarihi': DateTime(2026, 1, 15).toIso8601String(),
      });
      final sonuc = await db
          .rawQuery('SELECT tutar - odenen_tutar as kalan FROM borclar');
      expect(sonuc.single['kalan'], equals(700.0));
    });
  });
}
