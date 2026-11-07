// test/widget/masaustu_tablo_kaydirma_test.dart
//
// Regresyon (2026-11-07, kullanıcı: "masaüstü ürün listesinde yandan
// kaydırma görünmüyor"): dikey liste yatay kayan GENİŞ gövdenin içinde
// olduğundan otomatik dikey kaydırma çubuğu tablonun en sağ kenarına —
// sütunlar pencereden genişse ekran dışına — çiziliyordu. Çubuk artık
// pencerenin sağ kenarında: oradan fareyle sürüklemek listeyi kaydırır.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/widgetlar/masaustu/masaustu_tablo.dart';

void main() {
  Future<ScrollController> kur(WidgetTester t, {required double kolonGenisligi}) async {
    t.view.physicalSize = const Size(800, 600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final dikey = ScrollController();
    addTearDown(dikey.dispose);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MasaustuTablo<int>(
          satirlar: List.generate(200, (i) => i),
          kolonlar: [
            TabloKolon(baslik: 'No', deger: (i) => 'satır $i', genislik: kolonGenisligi),
            TabloKolon(baslik: 'Ad', deger: (i) => 'ürün $i', genislik: kolonGenisligi),
          ],
          onSec: (_) {},
          scrollController: dikey,
        ),
      ),
    ));
    await t.pumpAndSettle();
    return dikey;
  }

  Future<void> sagKenardanSurukle(WidgetTester t) async {
    final g = await t.startGesture(const Offset(797, 60), kind: PointerDeviceKind.mouse);
    for (var i = 0; i < 10; i++) {
      await g.moveBy(const Offset(0, 30));
      await t.pump();
    }
    await g.up();
    await t.pumpAndSettle();
  }

  testWidgets('sütunlar pencereden GENİŞKEN dikey çubuk pencerenin sağ kenarında, '
      'sürüklenince liste kayar', (t) async {
    final dikey = await kur(t, kolonGenisligi: 1500); // toplam 3000 px > 800 px
    expect(dikey.offset, 0);
    await sagKenardanSurukle(t);
    expect(dikey.offset, greaterThan(0));
  });

  testWidgets('sütunlar pencereye sığarken de dikey çubuk çalışır', (t) async {
    final dikey = await kur(t, kolonGenisligi: 200);
    await sagKenardanSurukle(t);
    expect(dikey.offset, greaterThan(0));
  });

  testWidgets('yatay kaydırma bozulmadı: geniş tabloda sağdaki sütun kaydırılarak görünür',
      (t) async {
    await kur(t, kolonGenisligi: 1500);
    expect(find.text('ürün 0').hitTestable(), findsNothing);
    await t.drag(find.byType(SingleChildScrollView), const Offset(-1500, 0));
    await t.pumpAndSettle();
    expect(find.text('ürün 0').hitTestable(), findsOneWidget);
  });
}
