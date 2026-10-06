// test/ekranlar/toptan_alt_masaustu_test.dart
//
// Toptan ürün listesi ve Bekleyen Siparişler masaüstü tablo görünümleri.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/ekranlar/toptan/masaustu/bekleyen_siparis_masaustu_gorunum.dart';
import 'package:market_plus/ekranlar/toptan/masaustu/toptan_urun_masaustu_gorunum.dart';
import 'package:market_plus/modeller/urun_model.dart';

void main() {
  Future<void> boyutla(WidgetTester t) async {
    t.view.physicalSize = const Size(1366, 768);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
  }

  testWidgets('Toptan ürün tablosu: satır, fiyatlar ve F4 kaldır', (t) async {
    await boyutla(t);
    final olaylar = <int?>[];
    final liste = [
      UrunModel.fromMap({
        'id': 1,
        'urun_adi': 'Deterjan 5kg',
        'barkod': '869000000001',
        'alis_fiyat': 100.0,
        'satis_fiyati': 150.0,
        'toptan_fiyat': 120.0,
        'koli_ici_miktar': 4.0,
        'koli_birim_adi': 'Koli',
        'stok': 12.0,
      }),
      UrunModel.fromMap({'id': 2, 'urun_adi': 'Şampuan', 'stok': 3.0}),
    ];
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ToptanUrunMasaustuGorunum(
            urunler: liste, onKaldir: (u) => olaylar.add(u.id)),
      ),
    ));
    await t.pump();
    expect(t.takeException(), isNull);
    expect(find.text('Deterjan 5kg'), findsOneWidget);
    expect(find.text('Koli (4)'), findsOneWidget);

    await t.tap(find.text('Deterjan 5kg'));
    await t.pump(const Duration(milliseconds: 400));
    await t.sendKeyEvent(LogicalKeyboardKey.f4);
    expect(olaylar, [1]);
  });

  testWidgets('Bekleyen siparişler: satır, toplam ve F2 detay', (t) async {
    await boyutla(t);
    final olaylar = <Object?>[];
    final liste = [
      {'id': 7, 'cari_unvan': 'Atlas Market', 'tarih': '2026-10-05T10:30:00', 'genel_toplam': 1500.0},
      {'id': 8, 'cari_unvan': 'Boran Bakkal', 'tarih': '2026-10-06T09:00:00', 'genel_toplam': 500},
    ];
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BekleyenSiparisMasaustuGorunum(
          siparisler: liste,
          onDetay: (s) => olaylar.add(s['id']),
          onYenile: () async => olaylar.add('yenile'),
        ),
      ),
    ));
    await t.pump();
    expect(t.takeException(), isNull);
    expect(find.text('Atlas Market'), findsOneWidget);
    expect(find.text('05.10.2026 10:30'), findsOneWidget);

    await t.tap(find.text('Boran Bakkal'));
    await t.pump(const Duration(milliseconds: 400));
    await t.sendKeyEvent(LogicalKeyboardKey.f2);
    await t.sendKeyEvent(LogicalKeyboardKey.f5);
    expect(olaylar, [8, 'yenile']);
  });
}
