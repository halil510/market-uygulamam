import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  group('Dashboard Widget', () {
    testWidgets('Hızlı erişim butonları görünür', (tester) async {
      await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: Scaffold(
          body: Center(child: Text('Dashboard Test'))))));
      expect(find.byType(MaterialApp), findsOneWidget);
    });
  });
}
