// test/widget/donanim_barkod_dinleyici_test.dart
//
// El terminali / USB okuyucu (klavye gibi davranan) girişinin insan
// yazmasından ayırt edilmesi.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/widgetlar/ortak/donanim_barkod_dinleyici.dart';

void main() {
  group('BarkodTusTamponu', () {
    final t0 = DateTime(2026, 1, 1, 12);
    DateTime ms(int n) => t0.add(Duration(milliseconds: n));

    test('hızlı akış + Enter → barkod', () {
      final t = BarkodTusTamponu();
      var z = 0;
      for (final c in '8690504000011'.split('')) {
        t.karakter(c, ms(z));
        z += 10;
      }
      expect(t.enter(ms(z)), '8690504000011');
    });

    test('yavaş (insan) yazma → barkod sayılmaz', () {
      final t = BarkodTusTamponu();
      var z = 0;
      for (final c in '12345'.split('')) {
        t.karakter(c, ms(z));
        z += 250;
      }
      expect(t.enter(ms(z)), isNull);
    });

    test('Enter geç gelirse (bekleme sonrası) barkod sayılmaz', () {
      final t = BarkodTusTamponu();
      for (var i = 0; i < 8; i++) {
        t.karakter('1', ms(i * 10));
      }
      expect(t.enter(ms(2000)), isNull);
    });

    test('çok kısa akış yok sayılır; tampon Enter sonrası temizlenir', () {
      final t = BarkodTusTamponu();
      t.karakter('1', ms(0));
      t.karakter('2', ms(5));
      expect(t.enter(ms(10)), isNull);
      t.karakter('9', ms(20));
      t.karakter('9', ms(25));
      t.karakter('9', ms(30));
      expect(t.enter(ms(35)), '999');
    });

    test('önceki yavaş tuşlar hızlı akışı kirletmez', () {
      final t = BarkodTusTamponu();
      t.karakter('x', ms(0));
      for (var i = 0; i < 6; i++) {
        t.karakter('5', ms(1000 + i * 10));
      }
      expect(t.enter(ms(1070)), '555555');
    });
  });

  test('barkodaBenziyor', () {
    expect(barkodaBenziyor('8690504000011'), isTrue);
    expect(barkodaBenziyor('  1234 '), isTrue);
    expect(barkodaBenziyor('123'), isFalse);
    expect(barkodaBenziyor('süt'), isFalse);
    expect(barkodaBenziyor('ABC123'), isFalse);
  });

  testWidgets('metin kutusu odakta değilken okuyucu girişi yakalanır', (tester) async {
    final okunan = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: DonanimBarkodDinleyici(
        onBarkod: okunan.add,
        child: const Scaffold(body: Text('ekran')),
      ),
    ));
    for (final c in '4006381333931'.split('')) {
      await tester.sendKeyEvent(LogicalKeyboardKey(c.codeUnitAt(0)), character: c);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(okunan, ['4006381333931']);
  });

  testWidgets('metin kutusu odaktayken dinleyici karışmaz', (tester) async {
    final okunan = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: DonanimBarkodDinleyici(
        onBarkod: okunan.add,
        child: const Scaffold(body: TextField(autofocus: true)),
      ),
    ));
    await tester.pump();
    for (final c in '4006381333931'.split('')) {
      await tester.sendKeyEvent(LogicalKeyboardKey(c.codeUnitAt(0)), character: c);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(okunan, isEmpty);
  });
}
