// test/widget/iade_urun_formu_test.dart
//
// İade formunda: mevcut stok → iade sonrası stok ve "bu iadede daha önce N
// adet var → kaydedince toplam M" bilgisi görünür; taşma yok.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/ekranlar/satis/iade/iade_urun_formu.dart';
import 'package:market_plus/modeller/urun_model.dart';

void main() {
  Widget sar({double onceki = 0, double miktar = 4, double stok = 100}) {
    final urun = UrunModel(urunAdi: 'Test Ürün', barkod: '869', stok: stok, satisFiyati: 25);
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: IadeUrunFormu(
            urun: urun,
            miktarCtrl: TextEditingController(text: '$miktar'),
            fiyatCtrl: TextEditingController(text: '25.00'),
            iskontoCtrl: TextEditingController(text: '0'),
            miktar: miktar,
            orijinalFiyat: 25,
            onSifirla: () {},
            onDegisti: () {},
            odemeYontemi: 'Nakit',
            onOdemeYontemiChanged: (_) {},
            oncekiMiktar: onceki,
          ),
        ),
      ),
    );
  }

  testWidgets('daha önce 2 var, 4 eklenince toplam 6 ve stok 100 → 104 görünür', (t) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(sar(onceki: 2, miktar: 4));
    await t.pump();
    expect(t.takeException(), isNull);
    expect(find.textContaining('zaten 2 adet var'), findsOneWidget);
    expect(find.textContaining('toplam 6 adet'), findsOneWidget);
    expect(find.text('100  →  104'), findsOneWidget);
    expect(find.text('iade sonrası'), findsOneWidget);
  });

  testWidgets('önceki iade yoksa bilgi kutusu görünmez; stok yalnız mevcut', (t) async {
    await t.pumpWidget(sar(onceki: 0, miktar: 0));
    await t.pump();
    expect(find.textContaining('zaten'), findsNothing);
    expect(find.text('100'), findsOneWidget);
  });

  testWidgets('ondalıklı miktar (kg) temiz yazılır', (t) async {
    await t.pumpWidget(sar(onceki: 1.5, miktar: 0.25, stok: 10));
    await t.pump();
    expect(find.textContaining('zaten 1.5 adet var'), findsOneWidget);
    expect(find.textContaining('toplam 1.75 adet'), findsOneWidget);
  });
}
