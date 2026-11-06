// test/veri/cari_bakiye_trigger_yuvarlama_test.dart
//
// Regresyon (2026-11-06, CLAUDE.md bulgu #2 / §3.1): trg_cari_hareket_bakiye
// tetikleyicisi cari bakiyesini YUVARLAMADAN yazıyordu; uygulamanın kendi
// yolları ise ROUND(..., 2) kullanıyor. Tetikleyici yalnız buluttan gelen
// (supaKayitlariEkle) hareketlerde son sözü söylediği için senkron sonrası
// bakiye 0.30000000000000004 gibi kuruş-altı kalıntılar taşıyabiliyordu
// (para_utils.dart notu: "0,00 görünüp borçlu sayılan hayalet borç").
// Artık tetikleyici de kuruşa yuvarlar — sıfırdan kurulumda ve v82
// migrasyonuyla yükseltilen cihazlarda.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/veri/database/migrasyon_yonetici.dart';
import '../helper/test_initializer.dart';

Future<double> _bakiyeSonrasi(Database db, List<double> borclar) async {
  final cariId = await TestVeritabani.ornekCariEkle(db);
  for (final b in borclar) {
    await db.insert('cari_hareket', {
      'cari_id': cariId, 'borc': b, 'alacak': 0, 'is_deleted': 0,
      'fis_tipi': 'Satış', 'tarih': DateTime.now().toIso8601String(),
    });
  }
  return ((await db.query('cari', columns: ['bakiye'], where: 'id = ?', whereArgs: [cariId]))
          .first['bakiye'] as num)
      .toDouble();
}

void main() {
  late Database db;
  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  test('sıfırdan kurulum: 0,10 + 0,20 borç → bakiye tam 0,30 (kuruş-altı kalıntı yok)', () async {
    expect(0.1 + 0.2 == 0.3, isFalse, reason: 'ön koşul: ham toplam 0.30000000000000004');
    expect(await _bakiyeSonrasi(db, [0.1, 0.2]), 0.3);
  });

  test('v81 → v82 migrasyonu eski (yuvarlamasız) tetikleyiciyi yuvarlayan sürümle değiştirir', () async {
    // v81 cihazındaki eski tetikleyici.
    await db.execute('DROP TRIGGER IF EXISTS trg_cari_hareket_bakiye');
    await db.execute('''
      CREATE TRIGGER trg_cari_hareket_bakiye
      AFTER INSERT ON cari_hareket BEGIN
      UPDATE cari SET bakiye = (
        SELECT COALESCE(SUM(borc - alacak), 0) FROM cari_hareket
        WHERE cari_id = NEW.cari_id AND is_deleted = 0
      ) WHERE id = NEW.cari_id; END''');
    expect(await _bakiyeSonrasi(db, [0.1, 0.2]), isNot(0.3),
        reason: 'ön koşul: eski tetikleyici yuvarlamıyor');

    await MigrasyonYonetici.guncelle(db, 81, 82);

    expect(await _bakiyeSonrasi(db, [0.1, 0.2]), 0.3);
  });
}
