// test/veri/migrasyon_tam_yukseltme_test.dart
//
// Yükseltme yolunun TAMAMI (MigrasyonYonetici + SemaOnarici — uygulamanın
// açılışta yaptığı) yeni kurulumla aynı yapıyı üretmeli: tablo/sütun
// (sema_onarici_test zaten bakıyor) + İNDEKS + TRIGGER. Trigger eksikliği
// sessizdir: ör. cari_hareket bakiye trigger'ı yoksa cari bakiyeleri
// kaymaya başlar, hiçbir hata görünmez.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:market_plus/cekirdek/sabitler/uygulama_sabitleri.dart';
import 'package:market_plus/veri/database/migrasyon_yonetici.dart';
import 'package:market_plus/veri/database/sema_onarici.dart';
import '../helper/test_initializer.dart';

Future<Set<String>> _nesneler(Database db, String tip) async => (await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = ? AND name NOT LIKE 'sqlite_%'",
        [tip]))
    .map((r) => r['name'] as String)
    .toSet();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database eski;
  late Database yeni;
  late String yol;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dizin = Directory.systemTemp.createTempSync('tam_yukseltme_');
    yol = '${dizin.path}/market_eski.db';
    File('market.db').copySync(yol); // depodaki gerçek eski DB (sürüm 4)
    eski = await openDatabase(yol,
        version: UygSabitler.dbVersiyon,
        onUpgrade: (d, e, y) => MigrasyonYonetici.guncelle(d, e, y));
    await SemaOnarici.onar(eski);
    yeni = await TestVeritabani.olustur();
  });

  tearDown(() async {
    await eski.close();
    await yeni.close();
    try { File(yol).parent.deleteSync(recursive: true); } catch (_) {}
  });

  test('yükseltilmiş DB yeni kurulumdaki tüm trigger\'lara sahip', () async {
    final eksik = (await _nesneler(yeni, 'trigger'))
        .difference(await _nesneler(eski, 'trigger'));
    expect(eksik, isEmpty, reason: 'eksik trigger: $eksik');
  });

  test('trigger GÖVDELERİ de yeni kurulumla aynı (eski/hatalı sürüm kalmamış)', () async {
    Future<Map<String, String>> govdeler(Database db) async => {
          for (final r in await db.rawQuery(
              "SELECT name, sql FROM sqlite_master WHERE type='trigger'"))
            r['name'] as String: (r['sql'] as String)
                .replaceAll(RegExp(r'IF NOT EXISTS\s+', caseSensitive: false), '')
                .replaceAll(RegExp(r'\s+'), ' ')
                .trim()
        };
    final y = await govdeler(yeni);
    final e = await govdeler(eski);
    expect(y, isNotEmpty);
    final farkli = [for (final ad in y.keys) if (e[ad] != y[ad]) ad];
    expect(farkli, isEmpty,
        reason: 'gövdesi farklı trigger: $farkli\n'
            '${[for (final ad in farkli) '--- $ad\nYENİ: ${y[ad]}\nESKİ: ${e[ad]}'].join('\n')}');
  });

  test('yükseltilmiş DB\'de yeni kurulumda OLMAYAN (eski) trigger kalmamış', () async {
    // Eski migrasyonların bıraktığı, artık tanımlanmayan trigger'lar
    // sessizce çalışmaya devam eder (ör. aynı işi yapan ikinci trigger →
    // çift kayıt).
    final fazla = (await _nesneler(eski, 'trigger'))
        .difference(await _nesneler(yeni, 'trigger'));
    expect(fazla, isEmpty, reason: 'fazla trigger: $fazla');
  });

  test('fiyat değişikliği her iki kurulumda TEK satır + değiştiren yazar', () async {
    for (final db in [eski, yeni]) {
      final id = await db.insert('urunler', {
        'urun_adi': 'Fiyat Test', 'satis_fiyati': 10.0, 'alis_fiyat': 5.0,
        'stok': 1.0, 'global_id': 'fiyat-test-${db.hashCode}',
      });
      await db.update('urunler',
          {'satis_fiyati': 12.0, 'fiyat_guncelleyen_kullanici': 'mudur'},
          where: 'id = ?', whereArgs: [id]);
      final gecmis = await db.query('fiyat_gecmis', where: 'urun_id = ?', whereArgs: [id]);
      expect(gecmis, hasLength(1), reason: 'fiyat geçmişi çift yazılmamalı');
      expect(gecmis.single['degistiren'], 'mudur');
    }
  });

  test('yükseltilmiş DB yeni kurulumdaki tüm indekslere sahip', () async {
    final eksik = (await _nesneler(yeni, 'index'))
        .difference(await _nesneler(eski, 'index'));
    expect(eksik, isEmpty, reason: 'eksik indeks: $eksik');
  });

  test('yükseltilmiş DB yeni kurulumdaki tüm view\'lara sahip', () async {
    final eksik = (await _nesneler(yeni, 'view'))
        .difference(await _nesneler(eski, 'view'));
    expect(eksik, isEmpty, reason: 'eksik view: $eksik');
  });

  test('yükseltilmiş DB\'de foreign key ve bütünlük kontrolü temiz', () async {
    expect((await eski.rawQuery('PRAGMA integrity_check')).first.values.first, 'ok');
    final fk = await eski.rawQuery('PRAGMA foreign_key_check');
    expect(fk, isEmpty, reason: 'FK ihlali: ${fk.take(5).toList()}');
  });
}
