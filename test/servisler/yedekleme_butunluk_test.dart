// test/servisler/yedekleme_butunluk_test.dart
//
// DEEP_AUDIT_REPORT madde 5 ("Restore sonrası bütünlük/veri sağlığı
// kontrolü yok"): YedeklemeServisi.yedekiGeriYukle() önceden dosyanın
// SADECE "SQLite format 3" imzasıyla BAŞLADIĞINI doğruluyordu — içeriğin
// (ör. yarıda kesilmiş bir kopyalama nedeniyle) sayfa düzeyinde bozuk
// OLMADIĞINI kanıtlamıyordu. Artık PRAGMA integrity_check ile tüm
// sayfalar taranıyor; bozuksa restore iptal edilip güvenlik yedeğinden
// geri dönülüyor.
//
// YedeklemeServisi._butunlukKontrolEt() private olduğu için burada
// BİREBİR AYNI mantık (readOnly bağlantı + PRAGMA integrity_check)
// gerçek, disk üzerindeki (geçici) SQLite dosyalarına karşı mirror
// edilip doğrulanıyor.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:market_plus/veri/database/tablolar/tablo_olusturucu.dart';

Future<bool> _butunlukKontrolEt(String dbYolu) async {
  Database? kontrolDb;
  try {
    kontrolDb = await openDatabase(dbYolu, readOnly: true);
    final rows = await kontrolDb.rawQuery('PRAGMA integrity_check');
    final sonuc = rows.isNotEmpty ? rows.first.values.first.toString() : 'unknown';
    return sonuc == 'ok';
  } catch (e) {
    return false;
  } finally {
    await kontrolDb?.close();
  }
}

void main() {
  late Directory tmpDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('yedek_butunluk_test');
  });

  tearDown(() async {
    if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
  });

  test('sağlam bir SQLite veritabanı bütünlük kontrolünden GEÇER', () async {
    final path = '${tmpDir.path}/saglam.db';
    final db = await openDatabase(path, version: 1,
        onCreate: (db, v) => TabloOlusturucu.olustur(db));
    await db.insert('urunler', {
      'urun_adi': 'Test', 'satis_fiyati': 10.0, 'stok': 5.0,
      'birim_adi': 'Adet', 'kdv_oran': '20', 'aktif': 1, 'is_deleted': 0,
    });
    await db.close();

    expect(await _butunlukKontrolEt(path), isTrue);
  });

  test('SQLite imzasıyla başlayıp İÇERİĞİ bozuk/kesik bir dosya '
      'bütünlük kontrolünden GEÇEMEZ (önceden bu hiç kontrol edilmiyordu)',
      () async {
    final saglamPath = '${tmpDir.path}/saglam2.db';
    final db = await openDatabase(saglamPath, version: 1,
        onCreate: (db, v) => TabloOlusturucu.olustur(db));
    await db.close();

    // Sağlam dosyanın SADECE İLK YARISINI kopyala — "SQLite format 3"
    // imzasıyla başlar (ilk bayt onda) ama sayfa düzeyinde eksik/bozuk.
    final tumBaytlar = await File(saglamPath).readAsBytes();
    final kesikBaytlar = tumBaytlar.sublist(0, tumBaytlar.length ~/ 2);
    final kesikPath = '${tmpDir.path}/kesik.db';
    await File(kesikPath).writeAsBytes(kesikBaytlar);

    expect(await _butunlukKontrolEt(kesikPath), isFalse);
  });

  test('var olmayan/erişilemeyen bir dosyada exception fırlatmadan '
      'güvenle false döner', () async {
    expect(await _butunlukKontrolEt('${tmpDir.path}/hic_olmayan.db'), isFalse);
  });
}
