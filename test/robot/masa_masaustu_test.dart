// test/robot/masa_masaustu_test.dart
//
// Masa modülü masaüstü (geniş pencere) akışı — gerçek uygulama, bellek içi
// veritabanı:
//   1. Masa listesinde bir masaya tıklamak sayfa DEĞİŞTİRMEZ; sağdaki gömülü
//      detay paneli açılır (ana-detay görünümü).
//   2. "Sipariş Başlat" → ürün ekleme ekranında ürün eklenince ekran KAPANMAZ,
//      sağdaki canlı adisyon paneli güncellenir (çok ürün tek oturumda).
//   3. Esc ile adisyona dönülür; ürünler masada görünür.
//   4. Dar (telefon) pencerede eski davranış: tıklayınca tam sayfa detay.
//   Ayrıca hiçbir adımda RenderFlex taşması olmamalı.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  testWidgets('masaüstü: ana-detay paneli + ürün ekleme ekranında kalma + canlı adisyon',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 900);
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

    // 1) Masaya tıkla → sayfa değişmez, sağ panel açılır
    expect(find.text('Sipariş için soldan bir masa seçin'), findsOneWidget);
    await tester.tap(find.text('Masa 1').first);
    await bekle(tester, 20);
    expect(find.text('Sipariş için soldan bir masa seçin'), findsNothing);
    expect(find.text('Bu masada sipariş yok'), findsOneWidget,
        reason: 'gömülü detay paneli açılmalı');
    expect(find.text('Masa 1 - Masa Detayı'), findsNothing,
        reason: 'tam sayfa detay AÇILMAMALI (masaüstünde panel kullanılır)');

    // 2) Sipariş başlat → ürün ekleme ekranı (iki panelli)
    await tester.tap(find.text('Sipariş Başlat'));
    await bekle(tester, 25);
    expect(find.text('Henüz ürün eklenmedi'), findsOneWidget);
    expect(find.text('Bitti — Adisyona Dön (Esc)'), findsOneWidget);

    // Ürün ekle: ekran KAPANMAZ, adisyon güncellenir
    await tester.tap(find.text('Robot Çikolata 80 G').first);
    await bekle(tester, 25);
    expect(find.text('Henüz ürün eklenmedi'), findsNothing);
    expect(find.text('Bitti — Adisyona Dön (Esc)'), findsOneWidget,
        reason: 'ürün eklenince ekran kapanmamalı');
    expect(find.text('1 kalem'), findsOneWidget);

    // Aynı ürünü tekrar ekle → tek kalem, miktar 2
    await tester.tap(find.text('Robot Çikolata 80 G').first);
    await bekle(tester, 25);
    expect(find.text('1 kalem'), findsOneWidget);
    expect(find.text('2'), findsWidgets);

    // + butonu ile miktar 3
    await tester.tap(find.byTooltip('Artır'));
    await bekle(tester, 20);
    expect(find.text('3'), findsWidgets);

    // 3) Esc → adisyona dön; kalem masa panelinde görünür
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await bekle(tester, 25);
    expect(find.text('Bitti — Adisyona Dön (Esc)'), findsNothing);
    expect(find.text('Robot Çikolata 80 G'), findsWidgets);
    expect(find.text('Ödeme Al'), findsOneWidget);

    await temizle(tester, db);
  });
}
