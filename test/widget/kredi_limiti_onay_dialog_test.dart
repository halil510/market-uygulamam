// test/widget/kredi_limiti_onay_dialog_test.dart
//
// Ortak kredi limiti onayı (2026-11-06): Masa / Toptan / Hızlı Satış aynı
// diyaloğu kullanır. Hızlı Satış'ta veresiye satışta limit HİÇ kontrol
// edilmiyordu — artık bu tek kaynaktan sorulur.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/widgetlar/ortak/kredi_limiti_onay_dialog.dart';

void main() {
  const asilmadi = (asildi: false, mevcutBakiye: 100.0, limit: 1000.0, asimTutari: 0.0);
  const asildi = (asildi: true, mevcutBakiye: 900.0, limit: 1000.0, asimTutari: 150.0);

  Future<bool?> calistir(WidgetTester tester, Future<bool> Function(BuildContext) f) async {
    bool? sonuc;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => sonuc = await f(context),
            child: const Text('başlat'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('başlat'));
    await tester.pumpAndSettle();
    return sonuc;
  }

  testWidgets('limit aşılmıyorsa diyalog açılmaz, true döner', (tester) async {
    final sonuc = await calistir(tester,
        (c) => krediLimitiOnayla(c, sonuc: asilmadi, eklenecekTutar: 50));
    expect(find.text('Kredi Limiti Aşılıyor'), findsNothing);
    expect(sonuc, isTrue);
  });

  testWidgets('limit aşılıyorsa diyalog açılır; Vazgeç → false', (tester) async {
    bool? sonuc;
    await calistir(tester, (c) async {
      sonuc = await krediLimitiOnayla(c,
          sonuc: asildi, eklenecekTutar: 250, unvan: 'Ali Veli');
      return sonuc!;
    });
    expect(find.text('Kredi Limiti Aşılıyor'), findsOneWidget);
    expect(find.textContaining('Ali Veli için tanımlı kredi limiti'), findsOneWidget);
    expect(find.textContaining('Bu satışla birlikte'), findsOneWidget);
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(sonuc, isFalse);
  });

  testWidgets('limit aşılıyorsa "Yine de Devam Et" → true', (tester) async {
    bool? sonuc;
    await calistir(tester, (c) async {
      sonuc = await krediLimitiOnayla(c,
          sonuc: asildi, eklenecekTutar: 250, birlikteEtiketi: 'Bu ödemeyle');
      return sonuc!;
    });
    expect(find.textContaining('Tanımlı kredi limiti'), findsOneWidget);
    expect(find.textContaining('Bu ödemeyle birlikte'), findsOneWidget);
    await tester.tap(find.text('Yine de Devam Et'));
    await tester.pumpAndSettle();
    expect(sonuc, isTrue);
  });

  testWidgets('cariLimitiKontrolVeOnay: cari yoksa veya tutar 0 ise sorgu yapılmaz', (tester) async {
    expect(
        await calistir(tester,
            (c) => cariLimitiKontrolVeOnay(c, cariId: null, eklenecekTutar: 500)),
        isTrue);
    expect(
        await calistir(tester,
            (c) => cariLimitiKontrolVeOnay(c, cariId: 5, eklenecekTutar: 0)),
        isTrue);
  });
}
