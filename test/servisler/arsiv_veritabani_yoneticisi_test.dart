// test/servisler/arsiv_veritabani_yoneticisi_test.dart
//
// Yıl Sonu Devir / Dönem Kapatma / Arşivleme sistemi — arşiv okuma
// altyapısı testleri (2026-09-16). ArsivVeritabaniYoneticisi.test()
// (path_provider platform kanalını atlayan özel kurucu) ile gerçek bir
// geçici dizine karşı çalışır — salt-okunuzluk, FIFO tahliye ve
// "dosya yoksa null" davranışlarını doğrular.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:market_plus/servisler/arsiv_veritabani_yoneticisi.dart';

void main() {
  late Directory geciciDizin;
  late ArsivVeritabaniYoneticisi yonetici;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    geciciDizin = Directory.systemTemp.createTempSync('arsiv_test_');
    yonetici = ArsivVeritabaniYoneticisi.test(dizinSaglayici: () => geciciDizin);
  });

  tearDown(() async {
    await yonetici.hepsiniKapat();
    if (geciciDizin.existsSync()) geciciDizin.deleteSync(recursive: true);
  });

  /// Belirli bir yıl için (yönetici ile AYNI yol kuralını kullanarak)
  /// gerçek, geçerli bir SQLite dosyası oluşturur — örnek bir tablo ve
  /// satırla.
  Future<void> ornekArsivDosyasiOlustur(int yil) async {
    final yol = await yonetici.arsivDosyaYolu(yil);
    await Directory(yol).parent.create(recursive: true);
    final db = await openDatabase(yol, version: 1, onCreate: (db, v) async {
      await db.execute('CREATE TABLE ornek (id INTEGER PRIMARY KEY, ad TEXT)');
      await db.insert('ornek', {'ad': 'test-$yil'});
    });
    await db.close();
  }

  group('Dosya yoksa (henüz arşivlenmemiş dönem)', () {
    test('arsivVarMi false döner', () async {
      expect(await yonetici.arsivVarMi(2020), isFalse);
    });

    test('arsivAc null döner (hata FIRLATMAZ)', () async {
      expect(await yonetici.arsivAc(2020), isNull);
    });
  });

  group('Dosya varsa', () {
    test('arsivVarMi true döner', () async {
      await ornekArsivDosyasiOlustur(2025);
      expect(await yonetici.arsivVarMi(2025), isTrue);
    });

    test('arsivAc SALT OKUNUR açar — SELECT çalışır', () async {
      await ornekArsivDosyasiOlustur(2025);
      final db = await yonetici.arsivAc(2025);
      expect(db, isNotNull);
      final rows = await db!.query('ornek');
      expect(rows, hasLength(1));
      expect(rows.first['ad'], 'test-2025');
    });

    test('arsivAc ile açılan bağlantıya YAZMA denemesi başarısız olur', () async {
      await ornekArsivDosyasiOlustur(2025);
      final db = await yonetici.arsivAc(2025);
      expect(
        () => db!.insert('ornek', {'ad': 'yeni'}),
        throwsA(anything),
      );
    });

    test('aynı yıl ikinci kez açılınca AYNI (önbellekteki) bağlantı döner', () async {
      await ornekArsivDosyasiOlustur(2025);
      final db1 = await yonetici.arsivAc(2025);
      final db2 = await yonetici.arsivAc(2025);
      expect(identical(db1, db2), isTrue);
    });
  });

  group('FIFO tahliye (maksimum 2 açık bağlantı)', () {
    test('3. yıl açılınca en eski (1.) bağlantı kapatılıp yeniden açılabilir hale gelir', () async {
      await ornekArsivDosyasiOlustur(2023);
      await ornekArsivDosyasiOlustur(2024);
      await ornekArsivDosyasiOlustur(2025);

      final db2023Once = await yonetici.arsivAc(2023);
      await yonetici.arsivAc(2024);
      // 3. bağlantı (2025) açılınca en eski (2023) tahliye edilmeli.
      await yonetici.arsivAc(2025);

      // 2023 tekrar açılınca ÖNBELLEKTE olmadığından YENİDEN açılır —
      // yani artık İLK açılan nesneyle AYNI olmayan bir Database döner
      // (eski bağlantı kapatılıp tahliye edildiğinin dolaylı kanıtı).
      final db2023Sonra = await yonetici.arsivAc(2023);
      expect(identical(db2023Once, db2023Sonra), isFalse);
      // Yeniden açılan bağlantı hâlâ çalışır durumda olmalı.
      final rows = await db2023Sonra!.query('ornek');
      expect(rows, hasLength(1));
    });
  });

  group('kapat / hepsiniKapat', () {
    test('kapat(yil) sonrası tekrar arsivAc çağrısı yeni bir bağlantı açar', () async {
      await ornekArsivDosyasiOlustur(2025);
      final db1 = await yonetici.arsivAc(2025);
      await yonetici.kapat(2025);
      final db2 = await yonetici.arsivAc(2025);
      expect(identical(db1, db2), isFalse);
    });

    test('hepsiniKapat tüm önbelleği temizler', () async {
      await ornekArsivDosyasiOlustur(2024);
      await ornekArsivDosyasiOlustur(2025);
      final dbA = await yonetici.arsivAc(2024);
      await yonetici.arsivAc(2025);
      await yonetici.hepsiniKapat();

      final dbAYeniden = await yonetici.arsivAc(2024);
      expect(identical(dbA, dbAYeniden), isFalse);
    });
  });
}
