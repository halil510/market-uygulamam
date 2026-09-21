// test/widget/ts_bottom_sheet_chart_test.dart
//
// TsBottomSheet/TsChart — yeni tasarım sistemi bileşenleri (bkz.
// DEEP_AUDIT_REPORT madde 25). Salt görsel bileşenler oldukları için
// (TsDialog gibi) kapsamlı davranış testi yok — burada sadece hatasız
// render olduklarını ve `goster()` kısayolunun gerçekten açılıp
// kapandığını doğrulayan bir duman (smoke) testi var.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/tasarim_sistemi/tasarim_sistemi.dart';

void main() {
  testWidgets('TsBottomSheet.goster() açılır, içeriği gösterir ve sonuç döner',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () async {
            final sonuc = await TsBottomSheet.goster<String>(
              context,
              child: const Text('Sheet İçeriği'),
            );
            expect(sonuc, 'tamam');
          },
          child: const Text('Aç'),
        );
      }),
    ));

    await tester.tap(find.text('Aç'));
    await tester.pumpAndSettle();

    expect(find.text('Sheet İçeriği'), findsOneWidget);

    Navigator.of(tester.element(find.text('Sheet İçeriği'))).pop('tamam');
    await tester.pumpAndSettle();
  });

  testWidgets('TsChart veri varken child\'ı, boşken bosMesaj\'ı gösterir',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: TsChart(
          baslik: 'Test Grafiği',
          yukseklik: 100,
          child: Text('Grafik Widget'),
        ),
      ),
    ));

    expect(find.text('Test Grafiği'), findsOneWidget);
    expect(find.text('Grafik Widget'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: TsChart(
          baslik: 'Test Grafiği',
          bosMu: true,
          bosMesaj: 'Henüz veri yok',
          child: Text('Grafik Widget'),
        ),
      ),
    ));

    expect(find.text('Henüz veri yok'), findsOneWidget);
    expect(find.text('Grafik Widget'), findsNothing);
  });
}
