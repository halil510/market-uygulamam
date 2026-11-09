// test/depolar/satis_sil_lot_sube_test.dart
//
// Derin denetim (2026-11-09), orta:
//  #25 Satış silmede şube stok payı (sube_urun) geri yüklenmiyordu.
//  #26 Lot takipli üründe satış silinince lot_seri miktarı geri gelmiyordu.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/depolar/satis_deposu.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

void main() {
  late Database db;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await TestVeritabani.olustur();
    Veritabani.testVeritabani = db;
    if ((await db.query('subeler', where: 'id = 1')).isEmpty) {
      await db.insert('subeler', {'id': 1, 'sube_kodu': 'MRK', 'sube_adi': 'Merkez'});
    }
  });
  tearDown(() async {
    Veritabani.testVeritabani = null;
    await db.close();
  });

  test('lotlu ürünün satışı silinince lot miktarı ve şube payı geri gelir', () async {
    final urun = await TestVeritabani.ornekUrunEkle(db, stok: 6);
    await db.update('urunler', {'lot_takibi': 1}, where: 'id = ?', whereArgs: [urun]);
    final lot = await db.insert('lot_seri', {
      'urun_id': urun, 'lot_no': 'L1', 'miktar': 6, 'aktif': 1,
    });
    await db.insert('sube_urun', {'urun_id': urun, 'sube_id': 1, 'stok': 6});
    final t = DateTime(2026, 11, 9).toIso8601String();
    final satis = await db.insert('satislar', {
      'global_id': 's1', 'fis_no': 'F1', 'tarih': t, 'sube_id': 1,
      'genel_toplam': 400, 'odeme_yontemi': 'Kredi Kartı', 'is_deleted': 0, 'iptal': 0,
    });
    await db.insert('satis_kalem', {
      'satis_id': satis, 'urun_id': urun, 'urun_adi': 'X', 'miktar': 4, 'birim_fiyat': 100,
    });
    // FEFO düşümü: lot 10 → 6.
    await db.insert('stok_hareket', {
      'urun_id': urun, 'hareket_turu': 'Çıkış', 'miktar': 4, 'onceki_stok': 10,
      'sonraki_stok': 6, 'referans_id': satis, 'referans_turu': 'satis', 'lot_id': lot,
      'tarih': t, 'sube_id': 1,
    });

    await SatisDeposu().sil(satis);

    final l = (await db.query('lot_seri', where: 'id = ?', whereArgs: [lot])).single;
    expect((l['miktar'] as num).toDouble(), 10, reason: '#26 önceden 6 kalıyordu');
    final su = (await db.query('sube_urun', where: 'urun_id = ? AND sube_id = 1', whereArgs: [urun])).single;
    expect((su['stok'] as num).toDouble(), 10, reason: '#25 önceden 6 kalıyordu');
  });
}
