// test/widget/tekrar_gorununce_yenile_test.dart
//
// Liste ekranının üstüne sayfa açılıp kapatılınca (Windows'ta menüden Hızlı
// Satış'a gidip satış yapıp Geri) liste yenilenmeli; ilk açılışta ve ekran
// öndeyken gereksiz yenileme olmamalı.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/widgetlar/masaustu/tekrar_gorununce_yenile.dart';

class _Liste extends StatefulWidget {
  final VoidCallback onYenile;
  const _Liste({required this.onYenile});
  @override
  State<_Liste> createState() => _ListeState();
}

class _ListeState extends State<_Liste> with TekrarGorununceYenile {
  @override
  void tekrarGorununce() => widget.onYenile();
  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('liste'));
}

void main() {
  testWidgets('üstü örtülüp geri dönülünce bir kez yenilenir', (t) async {
    var yenileme = 0;
    final nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(MaterialApp(
        navigatorKey: nav, home: _Liste(onYenile: () => yenileme++)));
    await t.pumpAndSettle();
    expect(yenileme, 0, reason: 'ilk açılışta yenileme yok');

    nav.currentState!.push(MaterialPageRoute(
        builder: (_) => const Scaffold(body: Text('hızlı satış'))));
    await t.pumpAndSettle();
    expect(yenileme, 0, reason: 'örtülürken yenileme yok');

    nav.currentState!.pop();
    await t.pumpAndSettle();
    expect(yenileme, 1, reason: 'öne gelince yenilenmeli');

    // Saydam diyalog ekranı örtmez → yenileme gerekmez.
    showDialog<void>(
        context: nav.currentContext!, builder: (_) => const AlertDialog(title: Text('x')));
    await t.pumpAndSettle();
    nav.currentState!.pop();
    await t.pumpAndSettle();
    expect(yenileme, 1, reason: 'diyalog açılıp kapanınca yenileme yok');
  });
}
