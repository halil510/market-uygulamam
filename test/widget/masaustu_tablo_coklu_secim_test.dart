// test/widget/masaustu_tablo_coklu_secim_test.dart
//
// Masaüstü tablosunda çoklu seçim (kullanıcı isteği 2026-10-07): Ctrl+tık
// ekle/çıkar, Shift+tık aralık, fareyle sürükleyerek aralık seçimi.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/widgetlar/masaustu/masaustu_tablo.dart';

void main() {
  late Set<Object> secim;

  Future<void> kur(WidgetTester t) async {
    secim = {};
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, ss) => MasaustuTablo<int>(
            satirlar: List.generate(10, (i) => i),
            kolonlar: [TabloKolon(baslik: 'No', deger: (i) => 'satır $i', esnek: true)],
            onSec: (_) {},
            anahtar: (i) => i,
            seciliAnahtarlar: secim,
            onCokluSecim: (s) => ss(() => secim = s),
          ),
        ),
      ),
    ));
  }

  Future<void> tikla(WidgetTester t, int i) async {
    await t.tap(find.text('satır $i'), kind: PointerDeviceKind.mouse);
    await t.pump(const Duration(milliseconds: 400)); // çift tık penceresi
  }

  testWidgets('düz tık tek seçer, Ctrl+tık ekler/çıkarır', (t) async {
    await kur(t);
    await tikla(t, 1);
    expect(secim, {1});
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tikla(t, 3);
    await tikla(t, 5);
    expect(secim, {1, 3, 5});
    await tikla(t, 3);
    expect(secim, {1, 5}, reason: 'Ctrl+tık seçili satırı çıkarır');
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tikla(t, 7);
    expect(secim, {7}, reason: 'düz tık seçimi sıfırlar');
  });

  testWidgets('Shift+tık son tıklanandan aralık seçer', (t) async {
    await kur(t);
    await tikla(t, 2);
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tikla(t, 6);
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(secim, {2, 3, 4, 5, 6});
  });

  testWidgets('tuş, gecikmeli tık işlenmeden bırakılsa da Ctrl/Shift sayılır', (t) async {
    await kur(t);
    await tikla(t, 2);
    // Gerçek kullanıcı: Shift basılı tık, tuşu hemen bırakır — onTap
    // çift-tık penceresi yüzünden ~300 ms SONRA gelir.
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.tap(find.text('satır 5'), kind: PointerDeviceKind.mouse);
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await t.pump(const Duration(milliseconds: 400));
    expect(secim, {2, 3, 4, 5});

    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.tap(find.text('satır 8'), kind: PointerDeviceKind.mouse);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await t.pump(const Duration(milliseconds: 400));
    expect(secim, {2, 3, 4, 5, 8});
  });

  testWidgets('fareyle sürükleyerek aralık seçer', (t) async {
    await kur(t);
    final bas = t.getCenter(find.text('satır 1'));
    final son = t.getCenter(find.text('satır 4'));
    final g = await t.startGesture(bas, kind: PointerDeviceKind.mouse, buttons: kPrimaryMouseButton);
    await t.pump();
    await g.moveTo(Offset(bas.dx, (bas.dy + son.dy) / 2));
    await g.moveTo(son);
    await g.up();
    await t.pump(const Duration(milliseconds: 400));
    expect(secim, {1, 2, 3, 4});
  });
}
