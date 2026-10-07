// test/servisler/senkron_mutabakat_kismi_test.dart
//
// Bulut Veri Güvenliği Raporu (2026-10-07), Bulgu 11 — kısmi/anlık çekimde
// yalnız değişen tablolardan beslenen mutabakat adımları çalışır. Her adımın
// kaynak tablo listesi olmalı; yoksa kısmi çekimde filtresiz çalışır.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/servisler/senkron_sonrasi_mutabakat.dart';

void main() {
  test('her mutabakat adımının kaynak tabloları tanımlı', () {
    final kaynak = File('lib/servisler/senkron_sonrasi_mutabakat.dart').readAsStringSync();
    final etiketler = RegExp(r"await adim\('([^']+)'")
        .allMatches(kaynak)
        .map((m) => m.group(1)!)
        .toSet();
    expect(etiketler, isNotEmpty);
    expect(etiketler.difference(SenkronSonrasiMutabakat.adimTablolari.keys.toSet()), isEmpty);
  });

  test('anlık çekimin tetiklediği hareket tabloları bir adıma bağlı', () {
    final hepsi = SenkronSonrasiMutabakat.adimTablolari.values.expand((s) => s).toSet();
    for (final t in ['cari_hareket', 'stok_hareket', 'kredi_karti_hareket', 'borc_odemeler',
        'puan_hareket', 'masa_siparis_kalem']) {
      expect(hepsi, contains(t));
    }
  });
}
