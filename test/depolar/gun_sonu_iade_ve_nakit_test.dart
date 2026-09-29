// Gün Sonu: iade düşülür, nakit kırılımı para üstünü içermez.
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
  });
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    Veritabani.testVeritabani = null;
    await db.close();
  });

  test('iadeTutarVeMaliyet: iptal edilmeyen iadeleri toplar, iptali saymaz', () async {
    final urunId = await TestVeritabani.ornekUrunEkle(db, stok: 10, satisFiyati: 200);
    await db.update('urunler', {'alis_fiyat_kdv_dahil': 118.0},
        where: 'id = ?', whereArgs: [urunId]);
    final simdi = DateTime.now().toIso8601String();
    Future<void> iade(double tutar, double miktar, String durum) async {
      final id = await db.insert('iade', {
        'tarih': simdi, 'toplam_tutar': tutar, 'durum': durum,
      });
      await db.insert('iade_kalem', {
        'iade_id': id, 'urun_id': urunId, 'urun_adi': 'Test',
        'miktar': miktar, 'birim_fiyat': 200.0, 'toplam': tutar,
      });
    }
    await iade(600, 3, 'tamamlandi');
    await iade(200, 1, 'iptal');

    final bas = DateTime.now().subtract(const Duration(hours: 1));
    final bit = DateTime.now().add(const Duration(hours: 1));
    final r = await SatisDeposu().iadeTutarVeMaliyet(bas, bit);
    expect(r.tutar, 600);
    expect(r.maliyet, closeTo(3 * 118, 1e-9));
  });

  test('gunlukIstatistik: nakit, para üstünü (alınan − satış) içermez', () async {
    await db.insert('satislar', {
      'fis_no': 'T1', 'tarih': DateTime.now().toIso8601String(),
      'toplam_tutar': 600, 'genel_toplam': 600, 'odenen_tutar': 1000,
      'odeme_yontemi': 'Nakit', 'fis_tipi': 'Satış',
    });
    final i = await SatisDeposu().gunlukIstatistik();
    expect(i['nakit'], 600);
    expect(i['ciro'], 600);
  });
}
