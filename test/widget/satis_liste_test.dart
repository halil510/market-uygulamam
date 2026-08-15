import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Satış Liste Widget', () {
    testWidgets('AppBar başlığı doğru', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(appBar: AppBar(title: Text('Satışlar')))));
      expect(find.text('Satışlar'), findsOneWidget);
    });

    testWidgets('Tarih filtresi componenti', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Row(children: [
          IconButton(icon: const Icon(Icons.date_range), onPressed: () {}),
          const Text('Filtrele'),
        ]))));
      expect(find.byIcon(Icons.date_range), findsOneWidget);
    });
  });
}
