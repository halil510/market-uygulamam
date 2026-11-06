// test/depolar/masa_toplu_ekle_numara_test.dart
//
// Regresyon (2026-11-06): MasaDeposu.sonrakiNo() içindeki desen
// `'^${onek}s+(d+)$'` olarak yazılmıştı — normal (raw olmayan) Dart
// metninde `\s`/`\d` kaçışları kaybolduğu için "Salon 7" hiç eşleşmiyor,
// fonksiyon HER ZAMAN 1 dönüyordu. Sonuç: "Salon 1..10" varken Toplu
// Masa Ekle yeniden "Salon 1..10" adlı mükerrer masalar üretiyordu.
//
// GERÇEK MasaDeposu metotları çağrılır.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/depolar/masa_deposu.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late MasaDeposu depo;

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (_) async => null);
    SharedPreferences.setMockInitialValues({});
    db = await TestVeritabani.olustur();
    Veritabani.testVeritabani = db;
    depo = MasaDeposu();
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    Veritabani.testVeritabani = null;
    await db.close();
  });

  Future<List<String>> adlar() async => (await db.query('masalar',
          columns: ['ad'], where: 'is_deleted = 0', orderBy: 'id'))
      .map((r) => r['ad'] as String)
      .toList();

  test('sonrakiNo: hiç masa yoksa 1', () async {
    expect(await depo.sonrakiNo('Salon'), 1);
  });

  test('sonrakiNo: "Salon 1..10" varken 11 döner (önek büyük/küçük harf ve boşluk duyarsız)',
      () async {
    await depo.topluMasaEkle(onek: 'Salon', adet: 10, kategori: 'Salon');
    expect(await depo.sonrakiNo('Salon'), 11);
    expect(await depo.sonrakiNo(' salon '), 11);
    // Başka önek etkilenmez
    expect(await depo.sonrakiNo('Bahçe'), 1);
  });

  test('topluMasaEkle ikinci kez çağrılınca mükerrer ad üretmez', () async {
    await depo.topluMasaEkle(onek: 'Salon', adet: 3, kategori: 'Salon');
    await depo.topluMasaEkle(onek: 'Salon', adet: 2, kategori: 'Salon');
    final liste = await adlar();
    expect(liste, ['Salon 1', 'Salon 2', 'Salon 3', 'Salon 4', 'Salon 5']);
    expect(liste.toSet().length, liste.length);
  });

  test('"Salon" öneki "Salon VIP 3" gibi farklı adları saymaz', () async {
    await db.insert('masalar', {
      'global_id': 'm-vip',
      'ad': 'Salon VIP 30',
      'kategori': 'Salon',
      'durum': 'bos',
      'is_deleted': 0,
    });
    expect(await depo.sonrakiNo('Salon'), 1);
  });
}
