// test/uygulama/menu_rotalari_test.dart
//
// Masaüstü yan menüsündeki ve Dashboard'daki her öğenin adresi router'da
// TANIMLI olmalı. 2026-10-07 canlı testinde "Cari Hareket" ve
// "Tahsilat/Ödeme" menü öğeleri yalnız `/cari/.../:id` rotası olduğu için
// "Bu sayfa bulunamadı" gösteriyordu.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('menü öğelerinin tüm adresleri router\'da tanımlı', () {
    final rotalar = <String>{};
    for (final f in Directory('lib/uygulama/router').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final metin = f.readAsStringSync();
      rotalar.addAll(RegExp(r"path: *'(/[^']*)'").allMatches(metin).map((m) => m.group(1)!));
      // Yardımcıyla tanımlanan cari seçim rotaları: _cariSecRotasi(key, '/yol', ...)
      rotalar.addAll(RegExp(r"_cariSecRotasi\(\s*\w+,\s*'(/[^']*)'")
          .allMatches(metin)
          .map((m) => m.group(1)!));
    }
    expect(rotalar, isNotEmpty);

    final kirik = <String>[];
    for (final (dosya, desen) in [
      ('lib/uygulama/masaustu/masaustu_yan_menu.dart', r"_Oge\([^;]*?'(/[^']*)'\)"),
      ('lib/ekranlar/dashboard/dashboard_menu_verileri.dart', r"_UygulamaItem\([^;]*?'(/[^']*)'\)"),
    ]) {
      final metin = File(dosya).readAsStringSync();
      final adresler = RegExp(desen, dotAll: true).allMatches(metin).map((m) => m.group(1)!).toList();
      expect(adresler, isNotEmpty, reason: '$dosya içinde menü öğesi bulunamadı (desen eskidi mi?)');
      for (final a in adresler) {
        if (!rotalar.contains(a)) kirik.add('$dosya → $a');
      }
    }
    expect(kirik, isEmpty, reason: 'router\'da karşılığı olmayan menü adresleri');
  });
}
