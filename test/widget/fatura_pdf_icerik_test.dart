// test/widget/fatura_pdf_icerik_test.dart
//
// Kademe 2 (2026-11-06): Fatura Detay ekranının GERÇEK PDF üreticisi
// (fatura_detay_pdf_ext.dart → _pdfBytes / _pdfBytes80mm) gerçekten PDF
// üretiyor mu, fatura toplamları tutarlı mı?
//
// Ekran gerçek bir faturayla (FaturaDeposu().ekle) açılır, PDF
// @visibleForTesting pdfBytesTestIcin() sarmalayıcısıyla üretilir.
//
// Not (bilinçli sınır): pdf paketi akışları sıkıştırır ve metni gömülü
// TTF'nin glif kimlikleriyle yazar — firma adı / tutar PDF baytlarında düz
// metin olarak ARANAMAZ. Ek paket eklememe kararıyla (görev notu) burada
// içerik yerine geçerli PDF yapısı (%PDF başlığı, %%EOF, sayfa nesnesi)
// ve fatura modelindeki toplam bütünlüğü doğrulanır.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/cekirdek/utils/para_utils.dart';
import 'package:market_plus/depolar/fatura_deposu.dart';
import 'package:market_plus/ekranlar/fatura/fatura_detay_ekrani.dart';
import 'package:market_plus/modeller/fatura_model.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (_) async => null);
    SharedPreferences.setMockInitialValues({'firma_adi': 'Halk Market Test'});
  });

  /// KDV DAHİL kalemlerden (kanonik kural) fatura kurar ve kaydeder.
  Future<int> faturaKaydet(List<FaturaDetayModel> kalemler) async {
    final araToplam = ParaUtils.yuvarla(kalemler.fold(0.0, (s, k) => s + k.araToplam));
    final kdv = ParaUtils.yuvarla(kalemler.fold(0.0, (s, k) => s + k.kdvTutari));
    final iskonto = ParaUtils.yuvarla(kalemler.fold(0.0, (s, k) => s + k.iskontoTutari));
    final genel = ParaUtils.yuvarla(kalemler.fold(0.0, (s, k) => s + k.toplamTutar));
    return FaturaDeposu().ekle(
      FaturaModel(
        faturaNo: 'TST2026000000001',
        tarih: DateTime(2026, 11, 6, 10),
        cariUnvan: 'Örnek Müşteri',
        cariVergiNo: '1234567890',
        toplamAraToplam: araToplam,
        toplamIskonto: iskonto,
        toplamKdv: kdv,
        genelToplam: genel,
        kalanTutar: genel,
        detaylar: kalemler,
      ),
      kalemler,
    );
  }

  Future<dynamic> ekraniAc(WidgetTester tester, int faturaId) async {
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(home: FaturaDetayEkrani(faturaId: faturaId))));
    // Yükleme DB'ye gittiği için gerçek zamanlı beklenir.
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    return tester.state(find.byType(FaturaDetayEkrani));
  }

  void gecerliPdf(Uint8List b) {
    expect(b.length, greaterThan(1000));
    expect(ascii.decode(b.sublist(0, 5)), '%PDF-');
    final metin = latin1.decode(b);
    expect(metin.trimRight().endsWith('%%EOF'), isTrue, reason: 'PDF sonu');
    expect(RegExp(r'/Type\s*/Page\b').hasMatch(metin), isTrue, reason: 'sayfa nesnesi');
  }

  final ikiKalem = [
    FaturaDetayModel.kdvDahilKalemden(
        urunAdi: 'Süt 1L', miktar: 2, birimFiyat: 30, kdvOrani: 1, kdvDahilToplam: 60),
    FaturaDetayModel.kdvDahilKalemden(
        urunAdi: 'Deterjan', miktar: 1, birimFiyat: 120, kdvOrani: 20, kdvDahilToplam: 120),
  ];

  testWidgets('2 kalemli fatura → A4 ve 80 mm geçerli PDF üretilir', (tester) async {
    late int faturaId;
    await tester.runAsync(() async {
      db = await TestVeritabani.olustur();
      Veritabani.testVeritabani = db;
      faturaId = await faturaKaydet(ikiKalem);
    });
    final state = await ekraniAc(tester, faturaId);

    Uint8List? a4, termal;
    await tester.runAsync(() async {
      a4 = await state.pdfBytesTestIcin() as Uint8List;
      termal = await state.pdfBytesTestIcin(termal80mm: true) as Uint8List;
    });
    gecerliPdf(a4!);
    gecerliPdf(termal!);

    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      Veritabani.testVeritabani = null;
      await db.close();
    });
  });

  testWidgets('kayıtlı fatura toplamları tutarlı: araToplam + KDV == genelToplam (§4.4)',
      (tester) async {
    await tester.runAsync(() async {
      db = await TestVeritabani.olustur();
      Veritabani.testVeritabani = db;
      final id = await faturaKaydet(ikiKalem);
      final f = (await FaturaDeposu().idileGetir(id))!;
      expect(ParaUtils.yuvarla(f.toplamAraToplam + f.toplamKdv), f.genelToplam);
      expect(f.genelToplam, 180.0);
      expect(f.detaylar, hasLength(2));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      Veritabani.testVeritabani = null;
      await db.close();
    });
  });

  testWidgets('indirimli kalem: iskonto > 0, toplamlar yine tutar, PDF üretilir', (tester) async {
    final indirimli = [
      FaturaDetayModel.kdvDahilKalemden(
          urunAdi: 'Peynir', miktar: 1, birimFiyat: 200, iskontoOrani: 10,
          kdvDahilIskontoTutari: 20, kdvOrani: 10, kdvDahilToplam: 180),
      ikiKalem.first,
    ];
    late int faturaId;
    await tester.runAsync(() async {
      db = await TestVeritabani.olustur();
      Veritabani.testVeritabani = db;
      faturaId = await faturaKaydet(indirimli);
      final f = (await FaturaDeposu().idileGetir(faturaId))!;
      expect(f.toplamIskonto, greaterThan(0));
      expect(ParaUtils.yuvarla(f.toplamAraToplam + f.toplamKdv), f.genelToplam);
    });
    final state = await ekraniAc(tester, faturaId);
    Uint8List? a4;
    await tester.runAsync(() async {
      a4 = await state.pdfBytesTestIcin() as Uint8List;
    });
    gecerliPdf(a4!);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      Veritabani.testVeritabani = null;
      await db.close();
    });
  });
}
