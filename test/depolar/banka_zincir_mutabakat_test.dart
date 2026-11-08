// test/depolar/banka_zincir_mutabakat_test.dart
//
// Çoklu cihaz analizi (2026-11-08): banka bakiyesi "son hareketin
// sonraki_bakiye'si" zinciriyle tutuluyor. İki cihaz internetsizken aynı
// hesaba hareket yazınca (1000 → A: +100, B: −50) birleşmeden sonra bakiye
// 1050 yerine 950 görünüyordu; senkron sonrası hiçbir adım düzeltmiyordu.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/depolar/banka_hareket_deposu.dart';
import 'package:market_plus/modeller/banka_hareket_model.dart';
import 'package:market_plus/servisler/senkron_sonrasi_mutabakat.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

Future<int> _hesap(Database db, {double bakiye = 1000}) async {
  final bankaId = await db.insert('bankalar', {'global_id': 'banka-1', 'ad': 'Test Bank', 'aktif': 1});
  return db.insert('banka_hesaplar', {
    'global_id': 'hesap-1', 'banka_id': bankaId, 'hesap_adi': 'Vadesiz',
    'hesap_no': '1', 'bakiye': bakiye, 'kullanilabilir_bakiye': bakiye, 'aktif': 1,
  });
}

/// Başka cihazdan senkronla inen hareket (o cihazın zinciriyle).
Future<void> _gelenHareket(Database db, int hesapId,
    {required String gid, required String tip, required double tutar,
     required double onceki, required DateTime tarih}) =>
    db.insert('banka_hareketler', {
      'global_id': gid, 'banka_hesap_id': hesapId, 'islem_tipi': tip, 'tutar': tutar,
      'onceki_bakiye': onceki,
      'sonraki_bakiye': onceki + BankaHareketDeposu.isaretliTutar(tip, tutar),
      'tarih': tarih.toIso8601String(), 'is_deleted': 0,
    });

Future<double> _bakiye(Database db, int hesapId) async =>
    ((await db.query('banka_hesaplar', where: 'id = ?', whereArgs: [hesapId])).first['bakiye']
            as num)
        .toDouble();

void main() {
  late Database db;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await TestVeritabani.olustur();
    Veritabani.testVeritabani = db;
  });
  tearDown(() async {
    Veritabani.testVeritabani = null;
    await db.close();
  });

  test('iki cihazın internetsiz hareketleri birleşince bakiye açılış + toplam olur (950 değil 1050)', () async {
    final hesapId = await _hesap(db);
    final t0 = DateTime(2026, 11, 8, 10);
    // Bu cihaz: +100 (kendi zinciri 1000 → 1100).
    await BankaHareketDeposu().ekle(BankaHareketModel(
        bankaHesapId: hesapId, islemTipi: 'Gelen', tutar: 100, tarih: t0));
    // Diğer cihaz internetsizken: −50 (onun zinciri 1000 → 950), daha geç saat.
    await _gelenHareket(db, hesapId,
        gid: 'b-1', tip: 'Giden', tutar: 50, onceki: 1000, tarih: t0.add(const Duration(hours: 1)));
    // Senkronla gelen hesap satırı diğer cihazın bakiyesini (950) taşır.
    await db.update('banka_hesaplar', {'bakiye': 950}, where: 'id = ?', whereArgs: [hesapId]);

    await SenkronSonrasiMutabakat.calistir(degisenTablolar: {'banka_hareketler'});

    expect(await _bakiye(db, hesapId), 1050);
    final son = (await db.query('banka_hareketler', where: "global_id = 'b-1'")).first;
    expect((son['onceki_bakiye'] as num).toDouble(), 1100);
    expect((son['sonraki_bakiye'] as num).toDouble(), 1050);
  });

  test('tek cihazdaki tutarlı zincire dokunulmaz (idempotent)', () async {
    final hesapId = await _hesap(db);
    final t0 = DateTime(2026, 11, 8, 10);
    await BankaHareketDeposu().ekle(BankaHareketModel(
        bankaHesapId: hesapId, islemTipi: 'Gelen', tutar: 250.5, tarih: t0));
    await BankaHareketDeposu().ekle(BankaHareketModel(
        bankaHesapId: hesapId, islemTipi: 'Giden', tutar: 100.25,
        tarih: t0.add(const Duration(minutes: 5))));
    expect(await BankaHareketDeposu().zincirMutabakatYap(), 0);
    expect(await _bakiye(db, hesapId), closeTo(1150.25, 0.001));
  });

  test('buluttan gelen hesap satırı yerel (türetilmiş) bakiyeyi ezmez', () async {
    final hesapId = await _hesap(db);
    await BankaHareketDeposu().ekle(BankaHareketModel(
        bankaHesapId: hesapId, islemTipi: 'Gelen', tutar: 100, tarih: DateTime(2026, 11, 8)));
    await Veritabani().supaKayitlariGuncelle('banka_hesaplar', [
      {'global_id': 'hesap-1', 'hesap_adi': 'Yeni Ad', 'bakiye': 5.0, 'kullanilabilir_bakiye': 5.0,
       'last_updated': DateTime.now().add(const Duration(minutes: 1)).toIso8601String()},
    ]);
    final h = (await db.query('banka_hesaplar', where: 'id = ?', whereArgs: [hesapId])).first;
    expect(h['hesap_adi'], 'Yeni Ad');
    expect((h['bakiye'] as num).toDouble(), 1100);
  });
}
