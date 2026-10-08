// test/widget/basit_liste_masaustu_test.dart
//
// Kategori/Marka/Birim masaüstü tablosu (2026-10-08): arama süzer, F4 seçili
// satırı siler, silinemez (varsayılan) satırda F4 çalışmaz, F1 ekler.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/widgetlar/masaustu/basit_liste_masaustu.dart';
import 'package:market_plus/widgetlar/masaustu/masaustu_tablo.dart';

void main() {
  late List<String> silinen;
  late int eklenen;

  Future<void> kur(WidgetTester t) async {
    silinen = [];
    eklenen = 0;
    t.view.physicalSize = const Size(1400, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BasitListeMasaustu<String>(
          satirlar: const ['Adet', 'Koli', 'Paket'],
          kolonlar: [TabloKolon(baslik: 'Birim', deger: (b) => b, esnek: true)],
          aramaMetniAl: (b) => b,
          onEkle: () => eklenen++,
          onSil: silinen.add,
          silinebilir: (b) => b != 'Adet',
        ),
      ),
    ));
  }

  Future<void> sec(WidgetTester t, String ad) async {
    await t.tap(find.text(ad), kind: PointerDeviceKind.mouse);
    await t.pump(const Duration(milliseconds: 400));
  }

  testWidgets('F4 seçili satırı siler, varsayılan satırda çalışmaz', (t) async {
    await kur(t);
    await sec(t, 'Adet');
    await t.sendKeyEvent(LogicalKeyboardKey.f4);
    expect(silinen, isEmpty);
    await sec(t, 'Koli');
    await t.sendKeyEvent(LogicalKeyboardKey.f4);
    expect(silinen, ['Koli']);
    await t.sendKeyEvent(LogicalKeyboardKey.f1);
    expect(eklenen, 1);
  });

  testWidgets('arama listeyi süzer, toplam sayı değişmez', (t) async {
    await kur(t);
    await t.enterText(find.byType(TextField), 'pak');
    await t.pump();
    expect(find.text('Paket'), findsOneWidget);
    expect(find.text('Koli'), findsNothing);
    expect(find.text('3'), findsOneWidget); // alt şeritteki kayıt sayısı
  });
}
