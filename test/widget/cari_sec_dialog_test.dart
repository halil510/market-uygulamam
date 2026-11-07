// test/widget/cari_sec_dialog_test.dart
//
// Ortak cari seçim diyaloğu (CLAUDE.md §4.7) — İade ve Alım aynı widget'ı,
// Hızlı Satış/Masa alt paneli aynı süzgeci (cariFiltrele) kullanır.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/modeller/cari_model.dart';
import 'package:market_plus/widgetlar/ortak/cari_sec_dialog.dart';

const _cariler = [
  CariModel(id: 1, unvan: 'İSMAİL GIDA', bakiye: 0, cariTipi: 'Tedarikçi', telefon: '05321112233'),
  CariModel(id: 2, unvan: 'Şükrü Çiçekçi', bakiye: 0, cariTipi: 'Müşteri'),
  CariModel(id: 3, unvan: 'Ahmet Usta', bakiye: 0, cariTipi: 'Müşteri', telefon: '05449998877'),
];

Future<CariModel?> _ac(WidgetTester tester, Widget dialog) async {
  CariModel? sonuc;
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (ctx) => ElevatedButton(
        onPressed: () async =>
            sonuc = await showDialog<CariModel>(context: ctx, builder: (_) => dialog),
        child: const Text('aç'),
      ),
    ),
  ));
  await tester.tap(find.text('aç'));
  await tester.pumpAndSettle();
  return sonuc;
}

void main() {
  group('cariFiltrele', () {
    test('boş / yalnız boşluk sorgu tüm listeyi döner', () {
      expect(cariFiltrele(_cariler, ''), hasLength(3));
      expect(cariFiltrele(_cariler, '   '), hasLength(3));
    });

    test('ünvanda Türkçe karakter ve büyük/küçük harf duyarsız', () {
      expect(cariFiltrele(_cariler, 'ismail').map((c) => c.id), [1]);
      expect(cariFiltrele(_cariler, 'SUKRU CICEK').map((c) => c.id), [2]);
    });

    test('telefonda içerme ile bulur, baştaki/sondaki boşluk yok sayılır', () {
      expect(cariFiltrele(_cariler, ' 9998 ').map((c) => c.id), [3]);
    });

    test('eşleşme yoksa boş liste', () {
      expect(cariFiltrele(_cariler, 'zzz'), isEmpty);
    });
  });

  group('CariSecDialog', () {
    testWidgets('varsayılan (İade): Kayıtsız seçeneği id=null işaretçi döner',
        (tester) async {
      CariModel? sonuc;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () async => sonuc = await showDialog<CariModel>(
                context: ctx, builder: (_) => const CariSecDialog(cariler: _cariler)),
            child: const Text('aç'),
          ),
        ),
      ));
      await tester.tap(find.text('aç'));
      await tester.pumpAndSettle();
      expect(find.text('Müşteri Seç'), findsOneWidget);
      await tester.tap(find.text('Kayıtsız / Perakende Müşteri'));
      await tester.pumpAndSettle();
      expect(sonuc, isNotNull);
      expect(sonuc!.id, isNull);
    });

    testWidgets('arama listeyi süzer ve seçilen cari döner', (tester) async {
      CariModel? sonuc;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () async => sonuc = await showDialog<CariModel>(
                context: ctx, builder: (_) => const CariSecDialog(cariler: _cariler)),
            child: const Text('aç'),
          ),
        ),
      ));
      await tester.tap(find.text('aç'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'ahmet');
      await tester.pumpAndSettle();
      expect(find.text('İSMAİL GIDA'), findsNothing);
      await tester.tap(find.text('Ahmet Usta'));
      await tester.pumpAndSettle();
      expect(sonuc?.id, 3);
    });

    testWidgets('Alım modu: kayıtsız seçeneği yok, boş listede mesaj gösterir',
        (tester) async {
      await _ac(
          tester,
          const CariSecDialog(
            cariler: [],
            baslik: 'Tedarikçi Seç',
            baslikIkonu: null,
            kayitsizSecenegi: false,
            bosListeMesaji: 'Tedarikçi bulunamadı',
          ));
      expect(find.text('Tedarikçi Seç'), findsOneWidget);
      expect(find.text('Kayıtsız / Perakende Müşteri'), findsNothing);
      expect(find.text('Tedarikçi bulunamadı'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('eşleşme yoksa özel mesaj gösterilir', (tester) async {
      await _ac(
          tester,
          const CariSecDialog(
            cariler: _cariler,
            kayitsizSecenegi: false,
            eslesmeYokMesaji: 'Eşleşen tedarikçi yok',
          ));
      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('Eşleşen tedarikçi yok'), findsOneWidget);
    });
  });
}
