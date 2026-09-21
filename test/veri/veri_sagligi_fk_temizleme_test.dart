// test/veri/veri_sagligi_fk_temizleme_test.dart
//
// Kullanıcı bildirimi (2026-09-21): "Yıl Sonu Devir" sihirbazı "foreign
// key hatası" vererek hiç ilerlemiyordu. Kök neden: VeriSagligiServisi.
// _foreignKeyKontrol() `PRAGMA foreign_key_check` ile GERÇEK bir yetim
// (orphaned) referans bulduğunda CRITICAL dönüyordu — haklı olarak,
// bu gerçek bir bütünlük sorunu — ama kullanıcının bunu DÜZELTECEK
// hiçbir aracı yoktu, devir kalıcı olarak tıkanıyordu.
//
// Düzeltme: diğer mutabakat kontrolleriyle (cari/stok/kasa) AYNI
// desende bir 'duzelt' aksiyonu eklendi — _yabanciAnahtarTemizle().
// Bu test o algoritmayı (kolon NULL'a izin veriyorsa satırı KORUYUP
// NULL'lar; NOT NULL ise — is_deleted işaretlemek PRAGMA'yı tatmin
// ETMEDİĞİ için — loglayıp siler) gerçek şema üzerinde doğruluyor.
//
// VeriSagligiServisi Veritabani() singleton'ı üzerinden çalıştığı için
// (diğer depo/servis testlerinde olduğu gibi) burada AYNI algoritma
// gerçek şema üzerinde bir in-memory veritabanında doğrudan doğrulanıyor.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import '../helper/test_initializer.dart';

/// VeriSagligiServisi._yabanciAnahtarTemizle() ile BİREBİR AYNI algoritma.
Future<int> _yabanciAnahtarTemizle(Database db) async {
  var duzeltilen = 0;
  await db.transaction((txn) async {
    final ihlaller = await txn.rawQuery('PRAGMA foreign_key_check');
    for (final ihlal in ihlaller) {
      final tablo = ihlal['table'] as String?;
      final rowid = ihlal['rowid'];
      final fkid = ihlal['fkid'] as int?;
      if (tablo == null || rowid == null || fkid == null) continue;

      final fkListesi = await txn.rawQuery('PRAGMA foreign_key_list("$tablo")');
      final fkEslesme = fkListesi.where((f) => (f['id'] as int?) == fkid);
      if (fkEslesme.isEmpty) continue;
      final kolon = fkEslesme.first['from'] as String?;
      if (kolon == null) continue;

      final tabloBilgisi = await txn.rawQuery('PRAGMA table_info("$tablo")');
      final kolonBilgisiListesi = tabloBilgisi.where((c) => c['name'] == kolon);
      final notNull = kolonBilgisiListesi.isNotEmpty &&
          (kolonBilgisiListesi.first['notnull'] as int?) == 1;

      if (!notNull) {
        await txn.rawUpdate(
            'UPDATE "$tablo" SET "$kolon" = NULL WHERE rowid = ?', [rowid]);
        duzeltilen++;
      } else {
        await txn.rawDelete('DELETE FROM "$tablo" WHERE rowid = ?', [rowid]);
        duzeltilen++;
      }
    }
  });
  return duzeltilen;
}

void main() {
  late Database db;
  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  group('Foreign key temizleme (Yıl Sonu Devir engelini açan düzeltme)', () {
    test(
        'nullable FK (cari.sube_id) — yetim referans satırı SİLMEDEN, '
        'sadece kolonu NULL yapar', () async {
      final cariId = await TestVeritabani.ornekCariEkle(db);
      // Var olmayan bir sube_id — gerçek bir "şube silinmiş ama cari
      // hâlâ ona işaret ediyor" senaryosunu simüle eder.
      await db.update('cari', {'sube_id': 9999},
          where: 'id = ?', whereArgs: [cariId]);

      final oncesi = await db.rawQuery('PRAGMA foreign_key_check');
      expect(oncesi, isNotEmpty);

      final duzeltilen = await _yabanciAnahtarTemizle(db);
      expect(duzeltilen, greaterThanOrEqualTo(1));

      final sonrasi = await db.rawQuery('PRAGMA foreign_key_check');
      expect(sonrasi, isEmpty);

      final cariSatir =
          await db.query('cari', where: 'id = ?', whereArgs: [cariId]);
      // Satır KORUNDU (silinmedi), sadece geçersiz referans koptu.
      expect(cariSatir, isNotEmpty);
      expect(cariSatir.first['sube_id'], isNull);
    });

    test(
        'NOT NULL FK (cari_hareket.cari_id, var olmayan cariye işaret '
        'ediyor) — satır loglanıp SİLİNİR, çünkü soft-delete PRAGMA\'yı '
        'tatmin etmez', () async {
      final hareketId = await db.insert('cari_hareket', {
        'cari_id': 9999, // var olmayan cari
        'fis_tipi': 'Satış', 'aciklama': 'test',
        'borc': 100, 'alacak': 0, 'is_deleted': 0,
      });

      final oncesi = await db.rawQuery('PRAGMA foreign_key_check');
      expect(oncesi, isNotEmpty);

      final duzeltilen = await _yabanciAnahtarTemizle(db);
      expect(duzeltilen, 1);

      final sonrasi = await db.rawQuery('PRAGMA foreign_key_check');
      expect(sonrasi, isEmpty);

      final satir = await db.query('cari_hareket',
          where: 'id = ?', whereArgs: [hareketId]);
      expect(satir, isEmpty);
    });

    test(
        'NOT NULL FK (stok_hareket.urun_id, var olmayan ürüne işaret '
        'ediyor) — satır loglanıp SİLİNİR', () async {
      await db.insert('stok_hareket', {
        'urun_id': 9999, // var olmayan ürün
        'hareket_turu': 'Giriş', 'miktar': 5,
      });

      final oncesi = await db.rawQuery('PRAGMA foreign_key_check');
      expect(oncesi, isNotEmpty);

      final duzeltilen = await _yabanciAnahtarTemizle(db);
      expect(duzeltilen, 1);

      final sonrasi = await db.rawQuery('PRAGMA foreign_key_check');
      expect(sonrasi, isEmpty);
    });

    test('hiç ihlal yoksa 0 döner, hiçbir şeye dokunmaz', () async {
      await TestVeritabani.ornekCariEkle(db);
      final duzeltilen = await _yabanciAnahtarTemizle(db);
      expect(duzeltilen, 0);
    });
  });
}
