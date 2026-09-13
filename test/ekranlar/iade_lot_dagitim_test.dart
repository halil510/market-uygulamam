// test/ekranlar/iade_lot_dagitim_test.dart
//
// "İade → Lot geri ekleme" (FAZ 5'in devamı): fişten iade akışında
// (lib/ekranlar/satis/iade_ekrani_fis.dart, _fisKalemIade) artık
// lot_takibi=1 ürünlerde iade edilen miktar, orijinal satışın (FAZ 5
// FEFO tüketiminin bıraktığı stok_hareket.lot_id'li satırlardan) hangi
// lot(lar)dan geldiği bulunup AYNI lotlara geri ekleniyor. Bu ekran
// widget içindeki private bir extension metodu olduğu için (part of
// desenli, doğrudan import edilemiyor) bu test, o metottaki BİREBİR aynı
// dağıtım algoritmasını (_fisKalemIade içindeki 'dagilim' hesaplama
// bloğu) gerçek şema üzerinde ayrı bir yardımcı fonksiyonla doğruluyor.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import '../helper/test_initializer.dart';

/// _fisKalemIade'deki dağıtım algoritmasının BİREBİR kopyası: verilen
/// (satisId, urunId) için orijinal tüketim ledger'ını okuyup, `atla`
/// kadarını (önceki kısmi iadeler) atlayıp `kalanMiktar`ı sırayla lotlara
/// dağıtır. Ledger yetersizse kalan lot_id=null ile döner.
Future<List<(int?, double)>> _iadeDagilimiHesapla(
  Database txn, {
  required int satisId,
  required int urunId,
  required double oncekiIadeMiktar,
  required double kalanMiktar,
}) async {
  final tuketimSatirlari = await txn.query('stok_hareket',
      where: 'referans_id = ? AND referans_turu = ? AND urun_id = ?',
      whereArgs: [satisId, 'satis', urunId],
      orderBy: 'id ASC');
  final dagilim = <(int?, double)>[];
  var atla = oncekiIadeMiktar;
  var kalanDagitilacak = kalanMiktar;
  for (final satir in tuketimSatirlari) {
    if (kalanDagitilacak <= 0.005) break;
    var tSatirMiktar = (satir['miktar'] as num?)?.toDouble() ?? 0;
    if (atla > 0.005) {
      final atlanan = atla < tSatirMiktar ? atla : tSatirMiktar;
      tSatirMiktar -= atlanan;
      atla -= atlanan;
      if (tSatirMiktar <= 0.005) continue;
    }
    final buSatirdanIadeEdilecek =
        kalanDagitilacak < tSatirMiktar ? kalanDagitilacak : tSatirMiktar;
    if (buSatirdanIadeEdilecek <= 0.005) continue;
    dagilim.add((satir['lot_id'] as int?, buSatirdanIadeEdilecek));
    kalanDagitilacak -= buSatirdanIadeEdilecek;
  }
  if (kalanDagitilacak > 0.005) {
    dagilim.add((null, kalanDagitilacak));
  }
  return dagilim;
}

void main() {
  late Database db;

  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  group('İade → Lot dağıtımı (fişten iade)', () {
    test('Tek lottan tüketilmiş satışın tamamı o lota geri döner', () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db, stok: 0);
      final lotId = await db.insert('lot_seri', {'urun_id': urunId, 'miktar': 0});
      final satisId = await db.insert('satislar', {'fis_no': 'F1', 'genel_toplam': 100, 'odenen_tutar': 100});
      await db.insert('stok_hareket', {
        'urun_id': urunId, 'hareket_turu': 'Çıkış', 'miktar': 10,
        'referans_id': satisId, 'referans_turu': 'satis', 'lot_id': lotId,
      });

      final dagilim = await _iadeDagilimiHesapla(db,
          satisId: satisId, urunId: urunId, oncekiIadeMiktar: 0, kalanMiktar: 10);

      expect(dagilim, [(lotId, 10.0)]);
    });

    test('İki lottan (FEFO) tüketilmiş satışın kısmi iadesi ilk (SKT\'si yakın) lottan düşer', () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db, stok: 0);
      final lotA = await db.insert('lot_seri', {'urun_id': urunId, 'miktar': 0, 'lot_no': 'A'});
      final lotB = await db.insert('lot_seri', {'urun_id': urunId, 'miktar': 5, 'lot_no': 'B'});
      final satisId = await db.insert('satislar', {'fis_no': 'F2', 'genel_toplam': 150, 'odenen_tutar': 150});
      // FEFO tüketimi: 15 adet satış → Lot A'dan 10, Lot B'den 5 (stokDusFefoTxn'in ürettiği sıra).
      await db.insert('stok_hareket', {
        'urun_id': urunId, 'hareket_turu': 'Çıkış', 'miktar': 10,
        'referans_id': satisId, 'referans_turu': 'satis', 'lot_id': lotA,
      });
      await db.insert('stok_hareket', {
        'urun_id': urunId, 'hareket_turu': 'Çıkış', 'miktar': 5,
        'referans_id': satisId, 'referans_turu': 'satis', 'lot_id': lotB,
      });

      // 1. kısmi iade: 8 adet → tamamı Lot A'dan (A'nın 10 kapasitesi içinde).
      final ilkIade = await _iadeDagilimiHesapla(db,
          satisId: satisId, urunId: urunId, oncekiIadeMiktar: 0, kalanMiktar: 8);
      expect(ilkIade, [(lotA, 8.0)]);

      // 2. kısmi iade: kalan 7 adet → önceki 8 atlanır (Lot A'nın kalan 2'si + Lot B'nin 5'i).
      final ikinciIade = await _iadeDagilimiHesapla(db,
          satisId: satisId, urunId: urunId, oncekiIadeMiktar: 8, kalanMiktar: 7);
      expect(ikinciIade, [(lotA, 2.0), (lotB, 5.0)]);
    });

    test('Ledger yetersizse (ör. lot özelliğinden önceki eski satış) kalan lot_id=null ile döner', () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db, stok: 0);
      final satisId = await db.insert('satislar', {'fis_no': 'F3', 'genel_toplam': 50, 'odenen_tutar': 50});
      // Bu satış için hiç stok_hareket kaydı yok (eski/lot-öncesi satış).

      final dagilim = await _iadeDagilimiHesapla(db,
          satisId: satisId, urunId: urunId, oncekiIadeMiktar: 0, kalanMiktar: 5);

      expect(dagilim, [(null, 5.0)]);
    });
  });
}
