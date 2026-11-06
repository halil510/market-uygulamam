// test/depolar/kredi_karti_mutabakat_test.dart
//
// KrediKartiDeposu.limitMutabakatYap / uyumsuzlukSayisi (Veri Sağlığı).
// Regresyon (2026-11-06, CLAUDE.md §3.4): düzeltme kartın last_updated'ını
// yazmıyordu — bulutun "eski kayıt yeniyi ezmesin" koruması (LWW) düzeltmeyi
// eski sayıp reddedebiliyor, diğer cihazlar hiç görmüyordu.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/depolar/kredi_karti_deposu.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (_) async => null);
    SharedPreferences.setMockInitialValues({});
    db = await TestVeritabani.olustur();
    Veritabani.testVeritabani = db;
  });
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    Veritabani.testVeritabani = null;
    await db.close();
  });

  Future<int> bozukKart() async {
    final bankaId = await db.insert('bankalar', {'ad': 'Test Bankası'});
    final kartId = await db.insert('kredi_kartlari', {
      'banka_id': bankaId, 'kart_adi': 'Kart', 'kart_no_maskeli': '**** 1',
      'kartlimit': 1000, 'kullanilan_limit': 999, 'kalan_limit': 1,
      'aktif': 1, 'last_updated': '2020-01-01T00:00:00',
    });
    await db.insert('kredi_karti_hareket', {
      'kredi_karti_id': kartId, 'tutar': 300, 'yon': 'harcama', 'is_deleted': 0,
      'tarih': DateTime.now().toIso8601String(),
    });
    await db.insert('kredi_karti_hareket', {
      'kredi_karti_id': kartId, 'tutar': 100, 'yon': 'odeme', 'is_deleted': 0,
      'tarih': DateTime.now().toIso8601String(),
    });
    return kartId;
  }

  test('sapma tespit edilir ve hareketlerin net toplamına düzeltilir', () async {
    final id = await bozukKart();
    expect(await KrediKartiDeposu().uyumsuzlukSayisi(), 1);

    expect(await KrediKartiDeposu().limitMutabakatYap(), 1);

    final k = (await db.query('kredi_kartlari', where: 'id = ?', whereArgs: [id])).first;
    expect((k['kullanilan_limit'] as num).toDouble(), 200);
    expect((k['kalan_limit'] as num).toDouble(), 800);
    expect(await KrediKartiDeposu().uyumsuzlukSayisi(), 0);
  });

  test('düzeltme last_updated alanını ilerletir (senkron görsün)', () async {
    final id = await bozukKart();
    await KrediKartiDeposu().limitMutabakatYap();
    final k = (await db.query('kredi_kartlari', where: 'id = ?', whereArgs: [id])).first;
    expect(k['last_updated'], isNot('2020-01-01T00:00:00'));
  });
}
