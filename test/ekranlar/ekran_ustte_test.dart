// test/ekranlar/ekran_ustte_test.dart
//
// ekranUstte: opak bir sayfanın altında kalan (TickerMode kapalı) ekran
// klavye kısayollarına cevap vermemeli; üstteki / tek ekran vermeli.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/widgetlar/masaustu/ekran_ustte.dart';

void main() {
  Widget olcer(void Function(bool) sonuc) => Builder(builder: (c) {
        sonuc(ekranUstte(c));
        return const SizedBox();
      });

  testWidgets('normal ekran → üstte', (t) async {
    bool? s;
    await t.pumpWidget(MaterialApp(home: olcer((v) => s = v)));
    expect(s, isTrue);
  });

  testWidgets('TickerMode kapalı (opak sayfanın altında) → üstte değil', (t) async {
    bool? s;
    await t.pumpWidget(MaterialApp(
        home: TickerMode(enabled: false, child: olcer((v) => s = v))));
    expect(s, isFalse);
  });
}
