// test/servisler/veritabani_dosya_servisi_test.dart
//
// VeritabaniDosyaServisi.dosyayiDegistir(): Yedekten Geri Yükle ve
// Veritabanını İçe Al'ın ortak, güvenli dosya değiştirme yolu.
// Önceden İçe Al'da bütünlük kontrolü, Geri Yükle'de -wal/-shm temizliği
// yoktu; ikisi artık aynı koddan geçiyor.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:market_plus/servisler/veritabani_dosya_servisi.dart';

Future<List<int>> _dbOlustur(String yol, String deger) async {
  final db = await openDatabase(yol, version: 1,
      onCreate: (db, v) => db.execute('CREATE TABLE t (deger TEXT)'));
  await db.insert('t', {'deger': deger});
  await db.close();
  return File(yol).readAsBytes();
}

Future<String?> _degerOku(String yol) async {
  final db = await openDatabase(yol, readOnly: true);
  try {
    final rows = await db.rawQuery('SELECT deger FROM t');
    return rows.isEmpty ? null : rows.first['deger'] as String?;
  } finally {
    await db.close();
  }
}

void main() {
  late Directory tmp;
  late String hedef;
  late int kapatSayisi;
  final servis = VeritabaniDosyaServisi();

  Future<void> kapat() async => kapatSayisi++;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('vt_dosya_test');
    hedef = '${tmp.path}/market.db';
    kapatSayisi = 0;
    await _dbOlustur(hedef, 'eski');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  List<File> bakDosyalari(String onek) => tmp
      .listSync()
      .whereType<File>()
      .where((f) => f.path.contains('market.db.${onek}_') && f.path.endsWith('.bak'))
      .toList();

  test('sağlam dosya yazılır, eski -wal/-shm silinir, güvenlik kopyası alınır',
      () async {
    final yeni = await _dbOlustur('${tmp.path}/kaynak.db', 'yeni');
    await File('$hedef-wal').writeAsString('eski wal');
    await File('$hedef-shm').writeAsString('eski shm');

    await servis.dosyayiDegistir(
        hedef: hedef, yeniIcerik: yeni, yedekOneki: 'import_oncesi', kapat: kapat);

    expect(await _degerOku(hedef), 'yeni');
    expect(kapatSayisi, 1);
    expect(File('$hedef-wal').existsSync(), isFalse);
    expect(File('$hedef-shm').existsSync(), isFalse);
    final bak = bakDosyalari('import_oncesi');
    expect(bak, hasLength(1));
    expect(await _degerOku(bak.single.path), 'eski');
  });

  test('SQLite olmayan dosya reddedilir, mevcut veriye ve bağlantıya dokunulmaz',
      () async {
    await expectLater(
      servis.dosyayiDegistir(
          hedef: hedef,
          yeniIcerik: 'bu bir veritabanı değil, düz metin'.codeUnits,
          yedekOneki: 'import_oncesi',
          kapat: kapat),
      throwsException,
    );
    expect(kapatSayisi, 0);
    expect(await _degerOku(hedef), 'eski');
    expect(bakDosyalari('import_oncesi'), isEmpty);
  });

  test('imzası doğru ama içi bozuk dosya: işlem iptal, önceki veri geri konur',
      () async {
    // Büyük bir veritabanının ilk yarısı — imza doğru, sayfalar eksik.
    final kaynak = '${tmp.path}/buyuk.db';
    final db = await openDatabase(kaynak, version: 1,
        onCreate: (db, v) => db.execute('CREATE TABLE t (deger TEXT)'));
    final batch = db.batch();
    for (var i = 0; i < 2000; i++) {
      batch.insert('t', {'deger': 'satir $i ${'x' * 50}'});
    }
    await batch.commit(noResult: true);
    await db.close();
    final tum = await File(kaynak).readAsBytes();
    final kesik = tum.sublist(0, tum.length ~/ 2);

    await expectLater(
      servis.dosyayiDegistir(
          hedef: hedef, yeniIcerik: kesik, yedekOneki: 'import_oncesi', kapat: kapat),
      throwsException,
    );
    expect(await _degerOku(hedef), 'eski');
  });

  test('aynı önekli güvenlik kopyalarının yalnızca son 3 tanesi tutulur',
      () async {
    for (var i = 1; i <= 5; i++) {
      await File('$hedef.import_oncesi_100000000000$i.bak').writeAsString('x');
    }
    // Başka önekli kopyalara dokunulmaz.
    await File('$hedef.geri_yukleme_oncesi_1000000000001.bak').writeAsString('x');

    final yeni = await _dbOlustur('${tmp.path}/kaynak.db', 'yeni');
    await servis.dosyayiDegistir(
        hedef: hedef, yeniIcerik: yeni, yedekOneki: 'import_oncesi', kapat: kapat);

    expect(bakDosyalari('import_oncesi'), hasLength(3));
    expect(bakDosyalari('geri_yukleme_oncesi'), hasLength(1));
  });
}
