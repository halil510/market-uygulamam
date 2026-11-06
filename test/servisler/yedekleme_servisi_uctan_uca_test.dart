// test/servisler/yedekleme_servisi_uctan_uca_test.dart
//
// Kademe 2 (2026-11-06): YedeklemeServisi uçtan uca — önceden yalnız
// yedekGunuGeldiMi / butunlukKontrolEt test ediliyordu; asıl kurtarma yolu
// (yedek al → veri değişsin → geri yükle) hiç denenmemişti.
//
// GERÇEK YedeklemeServisi().yedekAl() / yedekiGeriYukle() çağrılır:
//  - veritabanı geçici dizinde GERÇEK bir market.db dosyasıdır (gerçek şema),
//    Veritabani.testVeritabani seam'i ile singleton'a bağlanır;
//  - getDatabasesPath() → databaseFactory.setDatabasesPath(geçici dizin);
//  - yedek klasörü (getApplicationDocumentsDirectory) path_provider kanalı
//    mock'lanarak geçici dizine yönlendirilir (robot_ortam.dart deseni).
// Geri yükleme bağlantıyı kapattığı için (Veritabani().kapat) her geri
// yüklemeden sonra test dosyayı kendisi yeniden açıp seam'e bağlar.
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:market_plus/servisler/yedekleme_servisi.dart';
import 'package:market_plus/veri/database/tablolar/tablo_olusturucu.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late String dbYolu;
  late Database db;
  final servis = YedeklemeServisi();

  Future<Database> dbAc() async {
    final d = await openDatabase(dbYolu);
    Veritabani.testVeritabani = d;
    return d;
  }

  Future<List<String>> urunAdlari() async {
    final d = await openDatabase(dbYolu, readOnly: true, singleInstance: false);
    try {
      return (await d.query('urunler', columns: ['urun_adi'], orderBy: 'id'))
          .map((r) => r['urun_adi'] as String)
          .toList();
    } finally {
      await d.close();
    }
  }

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('yedek_uctan_uca_');
    final dbDizini = p.join(tmp.path, 'db');
    await Directory(dbDizini).create();
    await databaseFactory.setDatabasesPath(dbDizini);
    dbYolu = p.join(dbDizini, 'market.db');

    final kanal = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    kanal.setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (_) async => null);
    kanal.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => p.join(tmp.path, 'belgeler'));
    SharedPreferences.setMockInitialValues({});

    // Gerçek şemayla dosya tabanlı veritabanı + 3 ürün.
    final ilk = await openDatabase(dbYolu,
        version: 1, onCreate: (d, v) => TabloOlusturucu.olustur(d));
    await ilk.close();
    db = await dbAc();
    for (final ad in ['Elma', 'Armut', 'Kiraz']) {
      await TestVeritabani.ornekUrunEkle(db, urunAdi: ad);
    }
  });

  tearDown(() async {
    await Veritabani().kapat();
    Veritabani.testVeritabani = null;
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('yedekAl: zip dosyası oluşur ve boş değildir', () async {
    final zip = await servis.yedekAl();
    final dosya = File(zip);
    expect(await dosya.exists(), isTrue);
    expect(await dosya.length(), greaterThan(0));
    expect(p.basename(zip), startsWith('barkopro_manuel_'));
  });

  test('yedek al → 4. ürün ekle → geri yükle: 4. ürün yok, ilk 3 ürün var', () async {
    final zip = await servis.yedekAl();
    await TestVeritabani.ornekUrunEkle(db, urunAdi: 'Muz');
    expect(await urunAdlari(), ['Elma', 'Armut', 'Kiraz', 'Muz']);

    await servis.yedekiGeriYukle(zip);
    db = await dbAc();

    expect(await urunAdlari(), ['Elma', 'Armut', 'Kiraz']);
  });

  test('içinde .db olmayan zip reddedilir, mevcut veriye dokunulmaz', () async {
    await TestVeritabani.ornekUrunEkle(db, urunAdi: 'Muz');
    final bozuk = p.join(tmp.path, 'bozuk.zip');
    final arsiv = Archive()..addFile(ArchiveFile('notlar.txt', 5, 'merhaba'.codeUnits));
    await File(bozuk).writeAsBytes(ZipEncoder().encode(arsiv)!);

    await expectLater(servis.yedekiGeriYukle(bozuk), throwsException);
    expect(await urunAdlari(), ['Elma', 'Armut', 'Kiraz', 'Muz']);
  });

  test('SQLite olmayan .db içeren zip reddedilir, mevcut veriye dokunulmaz', () async {
    await TestVeritabani.ornekUrunEkle(db, urunAdi: 'Muz');
    final bozuk = p.join(tmp.path, 'sahte.zip');
    final cop = List<int>.generate(4096, (i) => i % 251);
    final arsiv = Archive()..addFile(ArchiveFile('market.db', cop.length, cop));
    await File(bozuk).writeAsBytes(ZipEncoder().encode(arsiv)!);

    await expectLater(servis.yedekiGeriYukle(bozuk), throwsException);
    expect(await urunAdlari(), ['Elma', 'Armut', 'Kiraz', 'Muz']);
  });

  test('aynı yedek iki kez geri yüklenince sonuç aynı kalır (idempotent)', () async {
    final zip = await servis.yedekAl();
    await TestVeritabani.ornekUrunEkle(db, urunAdi: 'Muz');

    await servis.yedekiGeriYukle(zip);
    db = await dbAc();
    await servis.yedekiGeriYukle(zip);
    db = await dbAc();

    expect(await urunAdlari(), ['Elma', 'Armut', 'Kiraz']);
  });

  test('geri yükleme buluttan çekme filigranlarını sıfırlar, diğer ayarlara dokunmaz', () async {
    final zip = await servis.yedekAl();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mp_sync_al_urunler', '2026-11-06T17:00:00');
    await prefs.setString('mp_sync_al_sz_satislar', '2026-11-06T17:00:00');
    await prefs.setString('tema', 'koyu');

    await servis.yedekiGeriYukle(zip);
    db = await dbAc();

    expect(prefs.getKeys().where((k) => k.startsWith('mp_sync_al_')), isEmpty);
    expect(prefs.getString('tema'), 'koyu');
  });
}
