// lib/veri/database/sema_onarici.dart
//
// ŞEMA ONARICI (kullanıcı bulgusu 2026-09-28 — tablette "Buluttan Tam Al"
// → "cari_hareket: 119/119 kayıt yazılamadı").
//
// KÖK NEDEN: yeni kurulum şeması (TabloOlusturucu) ile eski sürümlerden
// MİGRASYONLA yükseltilmiş veritabanları birebir aynı değil — bazı sütunlar
// migrasyon adımlarında hiç eklenmemiş (ör. v4'ten yükseltilen bir DB'de
// urunler.kdv_dahil, cari_adres.global_id yok). Buluttan gelen satır bu
// sütunları taşıyınca yerel yazım her satırda hata verir. Hangi tablonun
// etkilendiği, cihazın hangi sürümden geldiğine göre değişir.
//
// ÇÖZÜM: her DB sürümünde BİR KEZ, cihazın tabloları bellek içinde kurulan
// GÜNCEL şemayla karşılaştırılır; eksik tablo/sütun/indeks VERİYE
// DOKUNMADAN eklenir. Sütun eklemede SQLite kısıtları: NOT NULL yalnız
// varsayılan değer varsa korunur, UNIQUE/PRIMARY KEY ALTER ile eklenemez
// (UNIQUE için güncel şemadaki indeks ayrıca oluşturulur).
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../../servisler/log_servisi.dart';
import 'tablolar/tablo_olusturucu.dart';

class SemaOnarici {
  /// [hedef] veritabanını güncel şemaya tamamlar. Döner: yapılan
  /// değişikliklerin okunabilir listesi (boşsa şema zaten eksiksiz).
  static Future<List<String>> onar(Database hedef) async {
    final yapilan = <String>[];
    // singleInstance:false — başka bir bellek içi DB'yi paylaşıp kapatmasın.
    final referans = await openDatabase(inMemoryDatabasePath,
        version: 1, singleInstance: false,
        onCreate: (db, _) => TabloOlusturucu.olustur(db));
    try {
      final refTablolar = await referans.rawQuery(
          "SELECT name, sql FROM sqlite_master WHERE type='table' "
          "AND name NOT LIKE 'sqlite_%' AND sql IS NOT NULL");
      final hedefTablolar = (await hedef.rawQuery(
              "SELECT name FROM sqlite_master WHERE type='table'"))
          .map((r) => r['name'] as String)
          .toSet();

      for (final t in refTablolar) {
        final ad = t['name'] as String;
        if (!hedefTablolar.contains(ad)) {
          try {
            await hedef.execute(t['sql'] as String);
            yapilan.add('tablo eklendi: $ad');
          } catch (e) {
            LogServisi().uyari('SemaOnarici: tablo eklenemedi ($ad)', hata: e);
          }
          continue;
        }
        final refKolon = await referans.rawQuery('PRAGMA table_info("$ad")');
        final hedefKolon = (await hedef.rawQuery('PRAGMA table_info("$ad")'))
            .map((r) => r['name'] as String)
            .toSet();
        for (final k in refKolon) {
          final kolon = k['name'] as String;
          if (hedefKolon.contains(kolon)) continue;
          final tanim = sutunTanimi(k);
          try {
            await hedef.execute('ALTER TABLE "$ad" ADD COLUMN $tanim');
            yapilan.add('sütun eklendi: $ad.$kolon');
          } catch (e) {
            LogServisi().uyari('SemaOnarici: sütun eklenemedi ($ad.$kolon)', hata: e);
          }
        }
      }

      // Eksik indeksler (UNIQUE dahil — mevcut veride çakışma varsa atlanır).
      final refIndeksler = await referans.rawQuery(
          "SELECT name, sql FROM sqlite_master WHERE type='index' AND sql IS NOT NULL");
      final hedefIndeksler = (await hedef.rawQuery(
              "SELECT name FROM sqlite_master WHERE type='index'"))
          .map((r) => r['name'] as String)
          .toSet();
      for (final i in refIndeksler) {
        final ad = i['name'] as String;
        if (hedefIndeksler.contains(ad)) continue;
        try {
          await hedef.execute(
              (i['sql'] as String).replaceFirst(RegExp(r'INDEX\s+(?!IF NOT EXISTS)', caseSensitive: false), 'INDEX IF NOT EXISTS '));
          yapilan.add('indeks eklendi: $ad');
        } catch (e) {
          if (kDebugMode) debugPrint('SemaOnarici indeks atlandı ($ad): $e');
        }
      }
    } finally {
      await referans.close();
    }
    if (yapilan.isNotEmpty) {
      LogServisi().bilgi('Şema onarıldı: ${yapilan.length} değişiklik',
          ek: yapilan.join(', '));
    }
    return yapilan;
  }

  /// PRAGMA table_info satırından ALTER TABLE ADD COLUMN tanımı üretir.
  @visibleForTesting
  static String sutunTanimi(Map<String, Object?> k) {
    final ad = k['name'] as String;
    final tip = (k['type'] as String?) ?? '';
    final varsayilan = k['dflt_value'];
    final notNull = (k['notnull'] as int? ?? 0) == 1;
    final b = StringBuffer('"$ad"');
    if (tip.isNotEmpty) b.write(' $tip');
    // ALTER ADD COLUMN: NOT NULL yalnız sabit varsayılan değerle mümkün;
    // CURRENT_TIMESTAMP gibi sabit olmayan varsayılan kabul edilmez.
    final sabitVarsayilan = varsayilan != null &&
        !RegExp(r'CURRENT_|\(', caseSensitive: false).hasMatch(varsayilan.toString());
    if (sabitVarsayilan) {
      if (notNull) b.write(' NOT NULL');
      b.write(' DEFAULT $varsayilan');
    }
    return b.toString();
  }
}
