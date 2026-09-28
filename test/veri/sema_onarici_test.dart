// test/veri/sema_onarici_test.dart
//
// Eski sürümden migrasyonla yükseltilmiş veritabanı, yeni kurulum şemasıyla
// birebir aynı olmalı (kullanıcı bulgusu 2026-09-28: tablette buluttan Tam
// Al → "cari_hareket: 119/119 kayıt yazılamadı"; yükseltilmiş DB'de bazı
// sütunlar eksikti). Depodaki Ağustos tarihli gerçek market.db (DB sürüm 4)
// kopyası kullanılır.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:market_plus/cekirdek/sabitler/uygulama_sabitleri.dart';
import 'package:market_plus/veri/database/migrasyon_yonetici.dart';
import 'package:market_plus/veri/database/sema_onarici.dart';
import '../helper/test_initializer.dart';

Future<Map<String, Set<String>>> _sema(Database db) async {
  final tablolar = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'");
  final m = <String, Set<String>>{};
  for (final t in tablolar) {
    final ad = t['name'] as String;
    m[ad] = (await db.rawQuery('PRAGMA table_info("$ad")'))
        .map((r) => r['name'] as String)
        .toSet();
  }
  return m;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database eski;
  late String yol;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dizin = Directory.systemTemp.createTempSync('sema_onarim_');
    yol = '${dizin.path}/market_eski.db';
    File('market.db').copySync(yol);
    eski = await openDatabase(yol,
        version: UygSabitler.dbVersiyon,
        onUpgrade: (d, e, y) => MigrasyonYonetici.guncelle(d, e, y));
  });

  tearDown(() async {
    await eski.close();
    try { File(yol).parent.deleteSync(recursive: true); } catch (_) {}
  });

  test('Migrasyon tek başına eksik bırakıyor (onarımın gerekçesi)', () async {
    final yeni = await _sema(await TestVeritabani.olustur());
    final yukseltilmis = await _sema(eski);
    final eksik = <String>[
      for (final t in yeni.keys)
        for (final k in yeni[t]!)
          if (!(yukseltilmis[t]?.contains(k) ?? false)) '$t.$k'
    ];
    // ignore: avoid_print
    print('Onarımsız eksik: ${eksik.length} → ${eksik.take(15).join(', ')}…');
    expect(eksik, isNotEmpty);
  });

  test('Onarım sonrası yapı yeni kurulumla birebir; veri korunur; ikinci çalıştırma boş', () async {
    final onceSayilar = {
      for (final t in ['urunler', 'cari', 'satislar'])
        t: (await eski.rawQuery('SELECT COUNT(*) n FROM $t')).first['n']
    };

    final yapilan = await SemaOnarici.onar(eski);
    expect(yapilan, isNotEmpty);

    final yeni = await _sema(await TestVeritabani.olustur());
    final onarilmis = await _sema(eski);
    final hala = <String>[
      for (final t in yeni.keys)
        for (final k in yeni[t]!)
          if (!(onarilmis[t]?.contains(k) ?? false)) '$t.$k'
    ];
    expect(hala, isEmpty, reason: 'onarımdan sonra eksik sütun/tablo kalmamalı');

    for (final e in onceSayilar.entries) {
      expect((await eski.rawQuery('SELECT COUNT(*) n FROM ${e.key}')).first['n'], e.value,
          reason: '${e.key} verisi korunmalı');
    }

    expect(await SemaOnarici.onar(eski), isEmpty, reason: 'ikinci çalıştırma değişiklik yapmamalı');
  });

  test('Onarımdan sonra AYNI bağlantıyla yazılan kayıt dosyada kalıcıdır', () async {
    await SemaOnarici.onar(eski);
    await eski.insert('cari', {'unvan': 'Onarım Sonrası', 'cari_tipi': 'Müşteri', 'global_id': 'onarim-test-1'});
    final ayni = await eski.query('cari', where: 'global_id = ?', whereArgs: ['onarim-test-1']);
    expect(ayni, hasLength(1), reason: 'aynı bağlantı yazdığını görmeli');
    await eski.close();
    eski = await openDatabase(yol);
    final yeniden = await eski.query('cari', where: 'global_id = ?', whereArgs: ['onarim-test-1']);
    expect(yeniden, hasLength(1), reason: 'dosya kapanıp açılınca kayıt durmalı');
  });

  group('Sütun tanımı', () {
    test('NOT NULL + sabit varsayılan korunur', () {
      expect(SemaOnarici.sutunTanimi({'name': 'borc', 'type': 'REAL', 'notnull': 1, 'dflt_value': '0'}),
          '"borc" REAL NOT NULL DEFAULT 0');
    });
    test('Varsayılansız NOT NULL eklenebilir hale getirilir (NOT NULL düşer)', () {
      expect(SemaOnarici.sutunTanimi({'name': 'x', 'type': 'TEXT', 'notnull': 1, 'dflt_value': null}),
          '"x" TEXT');
    });
    test('CURRENT_TIMESTAMP varsayılanı ALTER ile eklenemez — atlanır', () {
      expect(SemaOnarici.sutunTanimi(
              {'name': 't', 'type': 'DATETIME', 'notnull': 1, 'dflt_value': 'CURRENT_TIMESTAMP'}),
          '"t" DATETIME');
    });
  });
}
