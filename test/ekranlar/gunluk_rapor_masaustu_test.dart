// test/ekranlar/gunluk_rapor_masaustu_test.dart
//
// Gün Sonu Raporu masaüstü görünümü (2026-10-08): tipik masaüstü pencere
// boyutlarında taşma (overflow) olmadan çizilmeli. GORUNTU_KLASORU ortam
// değişkeni verilirse gerçek yazı tipleriyle ekran görüntüsü de kaydedilir.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/ekranlar/rapor/masaustu/gunluk_rapor_masaustu_gorunum.dart';
import 'package:market_plus/modeller/satis_model.dart';
import 'package:market_plus/uygulama/tema/uygulama_temasi.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

Future<void> _fontYukle(String aile, List<String> yollar) async {
  final y = FontLoader(aile);
  for (final p in yollar) {
    final f = File(p);
    if (f.existsSync()) y.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
  }
  await y.load();
}

void main() {
  final satislar = [
    for (var i = 0; i < 18; i++)
      SatisModel(
        id: i + 1,
        fisNo: 'MKP20261300000${(i + 10).toString().padLeft(2, '0')}',
        tarih: DateTime(2026, 10, 8, 9 + i ~/ 3, (i * 7) % 60),
        toplamTutar: 40.0 + i * 12.5,
        genelToplam: 40.0 + i * 12.5,
        odenenTutar: 40.0 + i * 12.5,
        odemeYontemi: const ['Nakit', 'Kredi Kartı', 'Cari', 'Karma'][i % 4],
        fisTipi: 'Satış',
        cariAdi: i % 4 == 2 ? 'ABDULLAH CANDAN' : null,
      ),
  ];
  const ozet = GunlukRaporOzet(
    toplam: 2812.5, nakit: 1100, kart: 700, cari: 612.5, havale: 0, diger: 400,
    gider: 150, maliyet: 1900, iade: 90, brutKar: 882.5, netKar: 732.5,
  );

  for (final (gen, yuk) in [(1280.0, 800.0), (1920.0, 1080.0)]) {
    testWidgets('taşmadan çizilir ${gen.toInt()}x${yuk.toInt()}', (tester) async {
      final db = await tester.runAsync(() => TestVeritabani.olustur());
      Veritabani.testVeritabani = db;
      final klasor = Platform.environment['GORUNTU_KLASORU'];
      if (klasor != null) {
        await tester.runAsync(() async {
          await _fontYukle('Poppins', [
            'assets/fonts/Poppins-Regular.ttf',
            'assets/fonts/Poppins-Medium.ttf',
            'assets/fonts/Poppins-Bold.ttf',
          ]);
          await _fontYukle('MaterialIcons', [
            '${Platform.environment['FLUTTER_ROOT'] ?? 'C:/src/flutter'}/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
          ]);
        });
      }
      await tester.binding.setSurfaceSize(Size(gen, yuk));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final anahtar = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: UygulamaTemasi.getTema('light'),
        home: RepaintBoundary(
          key: anahtar,
          child: Scaffold(
            appBar: AppBar(title: const Text('Gün Sonu Raporu')),
            body: GunlukRaporMasaustuGorunum(
              satislar: satislar,
              ozet: ozet,
              yukleniyor: false,
              baslangic: DateTime(2026, 10, 8),
              bitis: DateTime(2026, 10, 8, 23, 59, 59),
              periyot: 'Günlük',
              periyotlar: const ['Günlük', 'Haftalık', 'Aylık', 'Özel'],
              onPeriyot: (_) {},
              onOzelAralik: () {},
              onYenile: () {},
              onPdf: () {},
              onExcel: () {},
              onFisDetay: (_) {},
            ),
          ),
        ),
      ));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Kâr Hesabı'), findsOneWidget);
      expect(find.text('Ödeme Dağılımı'), findsOneWidget);

      if (klasor != null) {
        final sinir = anahtar.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final img = await sinir.toImage();
          final png = await img.toByteData(format: ui.ImageByteFormat.png);
          File('$klasor/gunluk_rapor_${gen.toInt()}.png')
              .writeAsBytesSync(png!.buffer.asUint8List());
        });
      }
      Veritabani.testVeritabani = null;
      await tester.runAsync(() => db!.close());
    });
  }
}
