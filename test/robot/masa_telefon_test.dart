// test/robot/masa_telefon_test.dart
//
// Dar (telefon) pencerede Masa listesi eski davranışını korur: masaya tıklayınca
// TAM SAYFA detay açılır (masaüstü ana-detay paneli yalnızca >1100 px).
// Ayrı dosya: robot ortamı süreç içi global durum bıraktığı için testler
// birbirinden bağımsız çalıştırılır.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:market_plus/servisler/auth_servisi.dart';
import 'package:market_plus/servisler/masa/qr_siparis_cekici_servisi.dart';
import 'package:market_plus/uygulama/uygulama.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import 'robot_ortam.dart';

void main() {
  Future<void> bekle(WidgetTester t, [int adim = 12]) async {
    for (var i = 0; i < adim; i++) {
      await t.pump(const Duration(milliseconds: 60));
    }
  }

  Future<void> temizle(WidgetTester t, dynamic db) async {
    QrSiparisCekiciServisi().durdur();
    await t.pumpWidget(const SizedBox());
    for (var i = 0; i < 30; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
    await t.pump(const Duration(minutes: 2));
    Veritabani.testVeritabani = null;
    await db.close();
  }

  testWidgets('telefon genişliğinde eski davranış: tıklayınca tam sayfa masa detayı',
      (tester) async {
    tester.view.physicalSize = const Size(411, 914);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await RobotOrtam.hazirla();
    final db = await RobotOrtam.veritabaniAc();
    await RobotOrtam.tohumla(db);
    expect(await AuthServisi().girisYap('admin', '1234'), isTrue);

    await tester.pumpWidget(const ProviderScope(
        child: BarkoProApp(baslangicTema: robotTema)));
    await bekle(tester, 30);
    final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
    router.go('/');
    await bekle(tester, 6);
    unawaited(router.push('/masa'));
    await bekle(tester, 20);

    expect(find.text('Sipariş için soldan bir masa seçin'), findsNothing);
    await tester.tap(find.text('Masa 1').first);
    await bekle(tester, 25);
    expect(find.text('Masa 1 - Masa Detayı'), findsOneWidget);

    await temizle(tester, db);
  });
}
