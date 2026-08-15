import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/cekirdek/utils/para_utils.dart';

void main() {
  group('Ürün Kartı', () {
    testWidgets('Ürün adı görünür', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: ListTile(
          title: Text('Test Ürünü'),
          subtitle: Text('Alış: 25,00 ₺')))));
      expect(find.text('Test Ürünü'), findsOneWidget);
      expect(find.text('Alış: 25,00 ₺'), findsOneWidget);
    });

    testWidgets('Para formatı doğru', (tester) async {
      final sonuc = ParaUtils.formatla(1234.56);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Text(sonuc))));
      expect(find.text(sonuc), findsOneWidget);
    });
  });
}
