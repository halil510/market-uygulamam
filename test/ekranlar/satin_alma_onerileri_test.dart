// test/ekranlar/satin_alma_onerileri_test.dart
//
// FAZ 6 (Satın Alma): "Satın Alma Önerileri" ekranı
// (lib/ekranlar/tedarik/satin_alma_onerileri_ekrani.dart) kritik stoktaki
// ürünleri UrunDeposu.kritikStoklar()'ın kullandığı SORGU ile bulur ve her
// biri için "önerilen miktar" hesaplar. Bu test o sorguyu ve formülü
// (ekrandaki private _onerilenMiktar ile BİREBİR aynı: eksik = minimum_stok
// - stok; eksik > 0 ise eksik, değilse 1) gerçek şema üzerinde doğrular.
// Not: UrunDeposu() singleton Veritabani() üzerinden gerçek db'ye bağlandığı
// için (diğer depo testlerinde de olduğu gibi) burada repo sınıfı değil,
// aynı SQL doğrudan test db'sine karşı çalıştırılıyor.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/ekranlar/tedarik/satin_alma_onerileri_ekrani.dart'
    show satinAlmaGerekceOlustur;
import '../helper/test_initializer.dart';

Future<List<Map<String, Object?>>> _kritikStoklar(Database db) {
  return db.rawQuery(
    'SELECT * FROM urunler'
    ' WHERE is_deleted = 0 AND aktif = 1'
    '   AND minimum_stok > 0 AND stok <= minimum_stok'
    ' ORDER BY stok ASC',
  );
}

double _onerilenMiktar({required double stok, required double minimumStok}) {
  final eksik = minimumStok - stok;
  return eksik > 0 ? eksik : 1;
}

void main() {
  late Database db;

  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  group('Satın Alma Önerileri (FAZ 6)', () {
    test('kritik stoktaki ürünleri bulur, eşik dışındakileri hariç tutar', () async {
      final kritikId = await TestVeritabani.ornekUrunEkle(db, urunAdi: 'Kritik', barkod: 'B1', stok: 2);
      await db.update('urunler', {'minimum_stok': 10}, where: 'id = ?', whereArgs: [kritikId]);

      final tamKritikId = await TestVeritabani.ornekUrunEkle(db, urunAdi: 'Tam Eşikte', barkod: 'B2', stok: 5);
      await db.update('urunler', {'minimum_stok': 5}, where: 'id = ?', whereArgs: [tamKritikId]);

      final yeterliId = await TestVeritabani.ornekUrunEkle(db, urunAdi: 'Yeterli', barkod: 'B3', stok: 20);
      await db.update('urunler', {'minimum_stok': 5}, where: 'id = ?', whereArgs: [yeterliId]);

      // minimum_stok = 0 (varsayılan) → eşik tanımsız, stok 0 olsa bile kritik SAYILMAZ.
      final esiksizId = await TestVeritabani.ornekUrunEkle(db, urunAdi: 'Eşiksiz', barkod: 'B4', stok: 0);

      final pasifId = await TestVeritabani.ornekUrunEkle(db, urunAdi: 'Pasif', barkod: 'B5', stok: 1);
      await db.update('urunler', {'minimum_stok': 10, 'aktif': 0}, where: 'id = ?', whereArgs: [pasifId]);

      final silinmisId = await TestVeritabani.ornekUrunEkle(db, urunAdi: 'Silinmiş', barkod: 'B6', stok: 1);
      await db.update('urunler', {'minimum_stok': 10, 'is_deleted': 1}, where: 'id = ?', whereArgs: [silinmisId]);

      final sonuc = await _kritikStoklar(db);
      final idler = sonuc.map((r) => r['id'] as int).toSet();

      expect(idler, {kritikId, tamKritikId}, reason: 'Sadece minimum_stok>0 VE stok<=minimum_stok olan aktif/silinmemiş ürünler dönmeli');
      expect(idler.contains(yeterliId), isFalse);
      expect(idler.contains(esiksizId), isFalse);
      expect(idler.contains(pasifId), isFalse);
      expect(idler.contains(silinmisId), isFalse);
    });

    test('önerilen miktar eksik kadar, eksik yoksa/negatifse en az 1', () {
      expect(_onerilenMiktar(stok: 2, minimumStok: 10), equals(8.0));
      expect(_onerilenMiktar(stok: 5, minimumStok: 5), equals(1.0), reason: 'eksik=0 → en az 1 önerilmeli');
      expect(_onerilenMiktar(stok: 7, minimumStok: 5), equals(1.0), reason: 'zaten fazlaysa da en az 1 önerilmeli (satır zaten kritik değilse ekrana hiç gelmez)');
    });
  });

  // FAZ 8 — "Akıllı Satın Alma" gerekçesi (erp_roadmap madde 17).
  group('satinAlmaGerekceOlustur (FAZ 8)', () {
    test('son 30 günde satış yoksa sadece minimum stok eşiğine dayandığını belirtir', () {
      final metin = satinAlmaGerekceOlustur(
          stok: 5, minimumStok: 10, satilan30: 0, birim: 'Adet');
      expect(metin, contains('satış yok'));
    });

    test('satış varsa günlük ortalama ve tükenme gününü hesaplar', () {
      // 30 günde 60 adet → günde 2 adet. Stok 10 → 10/2 = 5 günde tükenir.
      final metin = satinAlmaGerekceOlustur(
          stok: 10, minimumStok: 20, satilan30: 60, birim: 'Adet');
      expect(metin, contains('60 Adet satıldı'));
      expect(metin, contains('günde ~2.0'));
      expect(metin, contains('~5 günde tükenir'));
    });

    test('stok zaten tükenmişse (0) ayrı bir mesaj verir', () {
      final metin = satinAlmaGerekceOlustur(
          stok: 0, minimumStok: 20, satilan30: 30, birim: 'Kg');
      expect(metin, contains('Stok tükendi'));
    });
  });

  // UrunDeposu.satisHiziGetir Veritabani() singleton'ı üzerinden çalıştığı
  // için burada AYNI SQL gerçek şema üzerinde doğrulanıyor.
  group('satisHiziGetir SQL (şema doğrulaması)', () {
    late Database db2;
    setUp(() async => db2 = await TestVeritabani.olustur());
    tearDown(() => db2.close());

    test('iptal hariç, seçilen ürün id\'leri için toplam satılan miktarı döner', () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db2, urunAdi: 'Süt', barkod: 'SHG-1');
      final digerUrunId =
          await TestVeritabani.ornekUrunEkle(db2, urunAdi: 'Diğer', barkod: 'SHG-2');
      final satisId = await db2.insert('satislar', {
        'fis_no': 'F1', 'genel_toplam': 20, 'tarih': '2026-09-01 10:00:00',
        'iptal': 0, 'is_deleted': 0,
      });
      await db2.insert('satis_kalem', {
        'satis_id': satisId, 'urun_id': urunId, 'urun_adi': 'Süt',
        'miktar': 4, 'birim_fiyat': 5, 'toplam_tutar': 20,
      });

      final yerTutucular = [urunId, digerUrunId].map((_) => '?').join(',');
      final rows = await db2.rawQuery('''
        SELECT sk.urun_id AS urun_id, SUM(sk.miktar) AS miktar
        FROM satis_kalem sk
        JOIN satislar s ON s.id = sk.satis_id
        WHERE s.iptal = 0 AND s.is_deleted = 0
          AND DATE(s.tarih) >= DATE('now', 'localtime', ?)
          AND sk.urun_id IN ($yerTutucular)
        GROUP BY sk.urun_id
      ''', ['-30 days', urunId, digerUrunId]);

      expect(rows.length, 1);
      expect(rows.first['urun_id'], urunId);
      expect(rows.first['miktar'], 4);
    });
  });
}
