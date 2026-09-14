// test/depolar/urun_istatistikler_test.dart
//
// KOMPLE UYGULAMA DERİN ANALİZİNDE bulunan hata: UrunDeposu.istatistikler()
// içindeki 'kritik' ve 'stoksuz' sayaçları (a) 'aktif = 1' filtresi
// İÇERMİYORDU (sadece 'aktif' sayacı içeriyordu) VE (b) iki küme
// ÖRTÜŞÜYORDU — stok<=0 VE minimum_stok>0 olan bir ürün hem 'kritik' hem
// 'stoksuz' sayılıyordu. stok_rapor_ekrani.dart'ın 'saglikli = aktif -
// kritik - stoksuz' formülü bu yüzden YANLIŞ (olması gerekenden düşük)
// bir "Sağlıklı" sayısı üretiyordu.
//
// Bu test, UrunDeposu.istatistikler() ile BİREBİR aynı (düzeltilmiş) SQL'i
// TestVeritabani'nin gerçek şemasına karşı çalıştırıp üç kümenin (aktif,
// kritik, stoksuz) ARTIK ayrık olduğunu ve pasif ürünleri saymadığını
// doğrular.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import '../helper/test_initializer.dart';

// UrunDeposu.istatistikler() ile BİREBİR aynı (düzeltilmiş) SQL.
Future<Map<String, int>> _istatistikler(Database db) async {
  final res = await db.rawQuery('''
    SELECT
      COUNT(*)                                                           AS toplam,
      COUNT(CASE WHEN aktif = 1 AND is_deleted = 0 THEN 1 END)          AS aktif,
      COUNT(CASE WHEN aktif = 1 AND is_deleted = 0
                      AND stok > 0 AND stok <= minimum_stok
                      AND minimum_stok > 0 THEN 1 END)                  AS kritik,
      COUNT(CASE WHEN aktif = 1 AND is_deleted = 0
                      AND stok <= 0 THEN 1 END)                         AS stoksuz
    FROM urunler
    WHERE is_deleted = 0
  ''');
  final r = res.first;
  return {
    'toplam':  (r['toplam']  as int?) ?? 0,
    'aktif':   (r['aktif']   as int?) ?? 0,
    'kritik':  (r['kritik']  as int?) ?? 0,
    'stoksuz': (r['stoksuz'] as int?) ?? 0,
  };
}

int _barkodSayaci = 0;

Future<int> _urunEkle(Database db,
    {required double stok, required double minimumStok, int aktif = 1, int isDeleted = 0}) {
  return db.insert('urunler', {
    'urun_adi': 'Ürün',
    'barkod': '869${(_barkodSayaci++).toString().padLeft(10, '0')}',
    'satis_fiyati': 10,
    'alis_fiyat': 5,
    'stok': stok,
    'minimum_stok': minimumStok,
    'birim_adi': 'Adet',
    'kdv_oran': '20',
    'aktif': aktif,
    'is_deleted': isDeleted,
  });
}

void main() {
  late Database db;

  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  group('UrunDeposu.istatistikler — ayrık kümeler', () {
    test('stok=0 VE minimum_stok>0 olan ürün SADECE stoksuz sayılır, '
        'kritik\'e de dahil edilmez (eskiden ikisine de sayılıyordu)', () async {
      await _urunEkle(db, stok: 0, minimumStok: 5); // hem eski kritik hem stoksuz
      await _urunEkle(db, stok: 3, minimumStok: 5); // sadece kritik (0'dan büyük)
      await _urunEkle(db, stok: 20, minimumStok: 5); // sağlıklı

      final ist = await _istatistikler(db);
      expect(ist['aktif'], equals(3));
      expect(ist['kritik'], equals(1), reason: 'sadece stok=3 olan ürün kritik');
      expect(ist['stoksuz'], equals(1), reason: 'sadece stok=0 olan ürün stoksuz');
      final saglikli = ist['aktif']! - ist['kritik']! - ist['stoksuz']!;
      expect(saglikli, equals(1), reason: 'stok=20 olan ürün sağlıklı');
    });

    test('pasif (aktif=0) ürünler kritik/stoksuz sayaçlarına DAHİL EDİLMEZ '
        '(eskiden aktif filtresi hiç yoktu)', () async {
      await _urunEkle(db, stok: 0, minimumStok: 5, aktif: 0);
      await _urunEkle(db, stok: 1, minimumStok: 5, aktif: 0);

      final ist = await _istatistikler(db);
      expect(ist['aktif'], equals(0));
      expect(ist['kritik'], equals(0));
      expect(ist['stoksuz'], equals(0));
    });
  });
}
