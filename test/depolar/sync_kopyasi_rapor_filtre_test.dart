// test/depolar/sync_kopyasi_rapor_filtre_test.dart
//
// 2026-09-29 taraması: sync_cakisma_kopyasi=1 satışlar yalnız Satış Listesi
// ve Gün Sonu'ndan dışlanıyordu; Dashboard günlük ciro, Kâr-Zarar, Vardiya,
// Raporlar, Müşteri 360, AI raporları ve 5 depo sorgusu kopyayı da sayıp
// ciroyu şişiriyordu.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/depolar/rapor_deposu.dart';
import 'package:market_plus/depolar/satis_deposu.dart';
import 'package:market_plus/modeller/satis_kalem_model.dart';
import 'package:market_plus/modeller/satis_model.dart';
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

  Future<int> satis(String fisNo, double tutar, int urunId) =>
      SatisDeposu().satisEkle(
          SatisModel(fisNo: fisNo, tarih: DateTime.now(), toplamTutar: tutar,
              genelToplam: tutar, odenenTutar: tutar, odemeYontemi: 'Nakit',
              fisTipi: 'Satış'),
          [SatisKalemModel(satisId: 0, urunId: urunId, urunAdi: 'Test',
              miktar: 1, birimFiyat: tutar, toplamTutar: tutar)]);

  test('sync kopyası günlük ciroya ve aylık rapora girmez', () async {
    final urunId = await TestVeritabani.ornekUrunEkle(db, stok: 10, barkod: 'B-SK');
    await satis('T-ASIL', 100, urunId);
    final kopyaId = await satis('T-ASIL-SYNC', 100, urunId);
    await db.update('satislar', {'sync_cakisma_kopyasi': 1},
        where: 'id = ?', whereArgs: [kopyaId]);

    final gunluk = await SatisDeposu().gunlukIstatistik();
    expect(gunluk['ciro'], 100);
    expect(gunluk['satis_sayisi'], 1);

    final simdi = DateTime.now();
    final aylik = await RaporDeposu().aylikOzet(simdi.year, simdi.month);
    expect(aylik['ciro'], 100);
  });
}
