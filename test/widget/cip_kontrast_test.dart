// test/widget/cip_kontrast_test.dart
//
// Kullanıcı bulgusu (2026-09-28): Masa detayındaki "Müşteri Ekle" çipi ve
// Lot/Seri ekranındaki filtre çipleri beyaz görünüyor (okunmuyor).
// Uygulamanın GERÇEK temaları altında çip yazısının arka planla yeterli
// kontrastta olduğunu doğrular.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/uygulama/tema/uygulama_temasi.dart';

double _parlaklik(Color c) {
  double k(double v) => v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) * ((v + 0.055) / 1.055);
  return 0.2126 * k(c.r) + 0.7152 * k(c.g) + 0.0722 * k(c.b);
}

double kontrast(Color a, Color b) {
  final x = _parlaklik(a), y = _parlaklik(b);
  return (x > y ? x + 0.05 : y + 0.05) / (x > y ? y + 0.05 : x + 0.05);
}

void main() {
  for (final tema in ['light', 'dark', 'mavi', 'yesil', 'okyanus']) {
    testWidgets('$tema teması: ActionChip / FilterChip yazısı okunur', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: UygulamaTemasi.getTema(tema),
        home: Scaffold(
          body: Column(children: [
            ActionChip(
                avatar: const Icon(Icons.person_add_alt_1_outlined, size: 16),
                label: const Text('Müşteri Ekle'),
                onPressed: () {}),
            FilterChip(label: const Text('Tümü'), selected: true, onSelected: (_) {}),
            FilterChip(label: const Text('Aktif'), selected: false, onSelected: (_) {}),
          ]),
        ),
      ));
      for (final metin in ['Müşteri Ekle', 'Tümü', 'Aktif']) {
        final p = tester.renderObject<RenderParagraph>(
            find.descendant(of: find.text(metin), matching: find.byType(RichText)).first);
        // Rengi tanımsız yazıyı çizim motoru BEYAZ çizer — hatanın kaynağı buydu.
        final yazi = p.text.style?.color ?? Colors.white;
        // Çipin kendi zemini (chip Material'ı) — saydamsa sayfa zemini.
        final chip = find.ancestor(of: find.text(metin), matching: find.byWidgetPredicate(
            (w) => w is RawChip)).first;
        final mat = tester.widgetList<Material>(
            find.descendant(of: chip, matching: find.byType(Material))).first;
        var zemin = mat.color ?? Colors.transparent;
        if (zemin.a < 0.5) zemin = Theme.of(tester.element(chip)).scaffoldBackgroundColor;
        final k = kontrast(yazi, zemin);
        // ignore: avoid_print
        print('$tema / $metin: yazı $yazi zemin $zemin kontrast ${k.toStringAsFixed(2)}');
        expect(k, greaterThan(3.0), reason: '$tema temasında "$metin" okunmuyor');
      }
    });
  }
}
