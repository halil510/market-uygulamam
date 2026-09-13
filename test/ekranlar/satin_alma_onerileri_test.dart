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
}
