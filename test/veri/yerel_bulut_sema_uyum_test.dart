// test/veri/yerel_bulut_sema_uyum_test.dart
//
// SENKRON ŞEMA UYUM TESTİ — "iade'de indirim bulutta olmadığı için diğer
// masaüstüne gelmedi" hata sınıfının kalıcı önlemi.
//
// Yerelde bir sütun eklenip supabase_tam_sema.sql'e (bulut şeması) eklenmezse
// ya veri diğer cihaza HİÇ gitmez ya da PostgREST tablonun TÜM gönderimini
// reddeder (PGRST204). Bu test, taze kurulum şemasındaki HER sütunun bulut SQL
// dosyasında tanımlı olduğunu doğrular. Bilinçli yerel-only sütun/tablolar
// aşağıda AÇIKÇA listelenir — yenisi eklenirken burada da gerekçeyle belirtilmeli.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/servisler/kolon_haritalama.dart';
import '../helper/test_initializer.dart';

/// Cihaza özgü/yerel bakım tabloları — bilinçli olarak bulutta YOK
/// (bkz. protokol: yalnız senkron edilen her şey bulut dosyasında olmalı).
const _yerelOnlyTablolar = {
  'favori_urunler', 'gecici_sayim', 'sube_fiyat_gecmis', 'vardiya_detay',
  'yerel_terminal', 'yerel_fatura_blok', 'gunluk_rapor_ozet', 'bildirimler',
  'yazicilar', 'efatura_log', 'app_log', 'bildirim_tercihleri', 'sync_queue',
  'sync_meta', 'sync_cakismalar', 'doviz_kurlari', 'bildirim_okundu',
  'biyometrik_kayitlar',
};

Map<String, Set<String>> _bulutSemasiniOku(String sql) {
  final tablolar = <String, Set<String>>{};
  // CREATE TABLE [IF NOT EXISTS] ad ( ... );
  final createRe = RegExp(
      r'CREATE TABLE IF NOT EXISTS\s+([a-z_0-9]+)\s*\((.*?)\n\);',
      dotAll: true);
  for (final m in createRe.allMatches(sql)) {
    final ad = m.group(1)!;
    final kolonlar = <String>{};
    for (final satir in m.group(2)!.split('\n')) {
      final s = satir.trim();
      if (s.isEmpty || s.startsWith('--')) continue;
      final k = RegExp(r'^([a-z_0-9]+)\s').firstMatch(s)?.group(1);
      if (k != null && !const {'primary', 'foreign', 'unique', 'constraint', 'check'}.contains(k)) {
        kolonlar.add(k);
      }
    }
    tablolar.putIfAbsent(ad, () => {}).addAll(kolonlar);
  }
  // ALTER TABLE ad ADD COLUMN IF NOT EXISTS kolon
  final alterRe = RegExp(
      r'ALTER TABLE\s+([a-z_0-9]+)\s+ADD COLUMN IF NOT EXISTS\s+([a-z_0-9]+)');
  for (final m in alterRe.allMatches(sql)) {
    tablolar.putIfAbsent(m.group(1)!, () => {}).add(m.group(2)!);
  }
  return tablolar;
}

void main() {
  test('yerel şemadaki her sütun bulut SQL şemasında tanımlı (bilinçli yerel-only hariç)', () async {
    final sql = File('supabase_tam_sema.sql').readAsStringSync();
    final bulut = _bulutSemasiniOku(sql);
    expect(bulut.length, greaterThan(50), reason: 'SQL ayrıştırılamadı');

    final db = await TestVeritabani.olustur();
    final tablolar = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'");

    final eksikTablolar = <String>[];
    final eksikSutunlar = <String>[];
    for (final t in tablolar) {
      final ad = t['name'] as String;
      if (_yerelOnlyTablolar.contains(ad)) continue;
      final bulutKolonlar = bulut[ad];
      if (bulutKolonlar == null) {
        eksikTablolar.add(ad);
        continue;
      }
      final yerelOzgu = KolonHaritalama.yereleOzguSutunlar[ad] ?? const <String>{};
      final cols = await db.rawQuery('PRAGMA table_info("$ad")');
      for (final c in cols) {
        final k = c['name'] as String;
        if (!bulutKolonlar.contains(k) && !yerelOzgu.contains(k)) {
          eksikSutunlar.add('$ad.$k');
        }
      }
    }

    expect(eksikTablolar, isEmpty,
        reason: 'Bulut SQL dosyasında OLMAYAN tablolar (senkron edilecekse eklenmeli, '
            'cihaza özelse _yerelOnlyTablolar listesine gerekçeyle eklenmeli)');
    expect(eksikSutunlar, isEmpty,
        reason: 'Yerelde olup bulut SQL dosyasında OLMAYAN sütunlar — supabase_tam_sema.sql '
            'BÖLÜM 1 (CREATE) ve BÖLÜM 2 (ALTER ADD COLUMN) güncellenmeli; '
            'bilinçli yerel-only ise KolonHaritalama.yereleOzguSutunlar\'a eklenmeli.');
  });

  test('iade_kalem indirim sütunları yerelde ve bulut şemasında var', () async {
    final db = await TestVeritabani.olustur();
    final cols = (await db.rawQuery('PRAGMA table_info(iade_kalem)')).map((c) => c['name']).toSet();
    expect(cols, containsAll(['iskonto_oran', 'iskonto_tutar']));
    final bulut = _bulutSemasiniOku(File('supabase_tam_sema.sql').readAsStringSync());
    expect(bulut['iade_kalem'], containsAll(['iskonto_oran', 'iskonto_tutar']));
  });
}
