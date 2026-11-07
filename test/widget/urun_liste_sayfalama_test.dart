// test/widget/urun_liste_sayfalama_test.dart
//
// Regresyon (2026-11-07, kullanıcı: "masaüstü ürün listesi tam gelmiyor"):
// liste 50'şer yüklenir, sonraki sayfa yalnızca kaydırınca istenirdi. Bir
// sayfa pencereyi DOLDURMAZSA (büyük ekran, "sadece kritik stok" filtresi
// 50'den 3 ürün bırakınca) kaydırma olmuyor, kalan ürünler hiç gelmiyordu.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/ekranlar/urun/urun_liste_ekrani.dart';
import 'package:market_plus/saglayicilar/riverpod/urun_provider.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

void main() {
  late Database db;

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (_) async => null);
    // Ekran barkod bip sesi için audioplayers kurar — testte platform yok.
    for (final kanal in const [
      'xyz.luan/audioplayers',
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers.global/events',
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(kanal), (_) async => null);
    }
    SharedPreferences.setMockInitialValues({});
    db = await TestVeritabani.olustur();
    Veritabani.testVeritabani = db;
    await db.transaction((txn) async {
      for (var i = 0; i < 120; i++) {
        await txn.insert('urunler', {
          'urun_adi': 'Ürün ${i.toString().padLeft(3, '0')}',
          'barkod': 'B$i',
          'satis_fiyati': 10,
          'alis_fiyat': 5,
          'stok': 10,
          'kdv_oran': '18',
          'aktif': 1,
          'is_deleted': 0,
          'global_id': 'gid-$i',
          'last_updated': DateTime.now().toIso8601String(),
        });
      }
    });
  });

  tearDown(() async {
    Veritabani.testVeritabani = null;
    await db.close();
  });

  testWidgets('ilk sayfa pencereyi doldurmuyorsa kaydırmadan kalan sayfalar da yüklenir',
      (t) async {
    // 50 satır × 34 px ≈ 1700 px; pencere 4000 px — kaydırma imkânı yok.
    t.view.physicalSize = const Size(1600, 4000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);

    // Barkod bip sesi oynatıcıları rastgele adlı olay kanalları açar; test
    // ortamında platform yok — yalnızca bu eklenti hatası yok sayılır.
    final eskiHata = FlutterError.onError;
    FlutterError.onError = (d) {
      if (d.exception is MissingPluginException &&
          d.exception.toString().contains('audioplayers')) {
        return;
      }
      eskiHata?.call(d);
    };

    late ProviderContainer kap;
    await t.runAsync(() async {
      await t.pumpWidget(ProviderScope(
        child: Consumer(builder: (context, ref, _) {
          kap = ProviderScope.containerOf(context);
          return const MaterialApp(home: UrunListeEkrani());
        }),
      ));
      // DB sorguları gerçek isolate'te — sayfalar gelene kadar bekle.
      for (var i = 0; i < 60; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await t.pump();
        final d = kap.read(urunlerProvider);
        if (!d.yukleniyor && !d.dahaSonraVar) break;
      }
    });
    final durum = kap.read(urunlerProvider);

    await t.pumpWidget(const SizedBox());
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    FlutterError.onError = eskiHata;

    expect(durum.urunler.length, 120,
        reason: 'kaydırma olmadan da 3 sayfanın (50+50+20) tamamı yüklenmeli');
    expect(durum.dahaSonraVar, isFalse);
  });
}
