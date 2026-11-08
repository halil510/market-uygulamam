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
  // 2026-11-08: açılış eylemi olan listeler (Fiyat Grupları, İrsaliye…).
  Future<(List<String>, List<String>)> kurAc(WidgetTester t, {required bool acVar}) async {
    final acilan = <String>[], duzenlenen = <String>[];
    t.view.physicalSize = const Size(1400, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BasitListeMasaustu<String>(
          satirlar: const ['Altın', 'Gümüş'],
          kolonlar: [TabloKolon(baslik: 'Grup', deger: (b) => b, esnek: true)],
          aramaMetniAl: (b) => b,
          onDuzenle: duzenlenen.add,
          onAc: acVar ? acilan.add : null,
        ),
      ),
    ));
    return (acilan, duzenlenen);
  }

  Future<void> ciftTikla(WidgetTester t, String ad) async {
    await t.tap(find.text(ad), kind: PointerDeviceKind.mouse);
    await t.pump(const Duration(milliseconds: 50));
    await t.tap(find.text(ad), kind: PointerDeviceKind.mouse);
    await t.pump(const Duration(milliseconds: 400));
  }

  testWidgets('onAc verilince çift tık ve Enter açar, F2 yine düzenler', (t) async {
    final (acilan, duzenlenen) = await kurAc(t, acVar: true);
    await ciftTikla(t, 'Altın');
    expect(acilan, ['Altın']);
    await t.tap(find.text('Altın'), kind: PointerDeviceKind.mouse); // seç
    await t.pump(const Duration(milliseconds: 400));
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(acilan, ['Altın', 'Altın']);
    await t.sendKeyEvent(LogicalKeyboardKey.f2);
    expect(duzenlenen, ['Altın']);
    expect(find.text('Enter : Aç'), findsOneWidget); // alt şerit tuşu
  });

  testWidgets('onAc yoksa çift tık eskisi gibi düzenler, Enter bir şey yapmaz', (t) async {
    final (acilan, duzenlenen) = await kurAc(t, acVar: false);
    await ciftTikla(t, 'Gümüş');
    expect(duzenlenen, ['Gümüş']);
    await t.tap(find.text('Altın'), kind: PointerDeviceKind.mouse); // seç
    await t.pump(const Duration(milliseconds: 400));
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(duzenlenen, ['Gümüş']);
    expect(acilan, isEmpty);
  });
}
