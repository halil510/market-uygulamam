// test/veri/tedarikci_iade_migrasyon_test.dart
//
// v80 → v81: tedarikçiye iade tabloları yükseltilen cihazda oluşturulur
// (sıfırdan kurulumla aynı tanım — TedarikSemasi.iadeTablolariniOlustur).
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/veri/database/migrasyon_yonetici.dart';
import '../helper/test_initializer.dart';

void main() {
  test('v80 cihazında olmayan tedarikçi iade tabloları v81 yükseltmesiyle oluşur', () async {
    final db = await TestVeritabani.olustur();
    addTearDown(db.close);
    await db.execute('DROP TABLE tedarikci_iade_kalem');
    await db.execute('DROP TABLE tedarikci_iadeler');

    await MigrasyonYonetici.guncelle(db, 80, 81);

    Future<Set<String>> sutunlar(String t) async =>
        {for (final r in await db.rawQuery('PRAGMA table_info($t)')) r['name'] as String};
    expect(await sutunlar('tedarikci_iadeler'),
        containsAll(['global_id', 'cari_id', 'iade_no', 'toplam_tutar', 'last_updated', 'is_deleted']));
    expect(await sutunlar('tedarikci_iade_kalem'),
        containsAll(['global_id', 'iade_id', 'urun_id', 'miktar', 'birim_fiyat', 'kdv_oran', 'toplam_tutar']));

    // Tekrar çalıştırmak güvenli (IF NOT EXISTS).
    await MigrasyonYonetici.guncelle(db, 80, 81);
  });
}
