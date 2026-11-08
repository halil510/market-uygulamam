// test/widget/ts_responsive_test.dart
//
// Tablet / PC / el terminali düzeni: kök genişlik sınırı ve form
// sarmalayıcı telefonda hiçbir şeyi değiştirmemeli.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/tasarim_sistemi/ts_responsive.dart';

Future<Size> _olc(WidgetTester tester, Size ekran, Widget Function(BuildContext) govde) async {
  tester.view.physicalSize = ekran;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    builder: TsResponsive.uygulamaSarmalayici,
    home: Scaffold(body: Builder(builder: govde)),
  ));
  return tester.getSize(find.byKey(const ValueKey('icerik')));
}

void main() {
  testWidgets('PC (1920px): uygulama 1440px ile sınırlanır', (tester) async {
    final s = await _olc(tester, const Size(1920, 1080),
        (_) => const SizedBox.expand(key: ValueKey('icerik')));
    expect(s.width, TsResponsive.masaustuMaxGenislik);
  });

  testWidgets('el terminali / telefon (400px): hiçbir sınırlama yok', (tester) async {
    final s = await _olc(tester, const Size(400, 800),
        (_) => const SizedBox.expand(key: ValueKey('icerik')));
    expect(s.width, 400);
  });

  testWidgets('form tablette sınırlanır, telefonda tam genişlik', (tester) async {
    Widget form(BuildContext c) => TsResponsive.formSarmalayici(
        context: c, maxGenislik: 720,
        child: const SizedBox(key: ValueKey('icerik'), width: double.infinity, height: 50));
    expect((await _olc(tester, const Size(1200, 900), form)).width, 720);
    expect((await _olc(tester, const Size(400, 800), form)).width, 400);
  });
  // Faz D sonrası masaüstü taraması (2026-11-08): tek sütunlu formlar
  // (Tahsilat/Ödeme, GİB, Para Üstü…) 1366 px pencerede tüm genişliğe
  // yayılıyordu. masaustuForm yalnız Windows'ta sınırlar; Android/iOS
  // düzeni (tablet dahil) değişmez.
  group('masaustuForm', () {
    Widget form(BuildContext _) => TsResponsive.masaustuForm(
        maxGenislik: 720,
        child: const SizedBox(key: ValueKey('icerik'), width: double.infinity, height: 50));

    testWidgets('Windows: 720 ile sınırlanır ve ortalanır', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        expect((await _olc(tester, const Size(1366, 768), form)).width, 720);
        expect(tester.getTopLeft(find.byKey(const ValueKey('icerik'))).dx, (1366 - 720) / 2);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('Android tablet: hiçbir sınırlama yok', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        expect((await _olc(tester, const Size(1200, 900), form)).width, 1200);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
