// test/widget/etiket_tasarimci_test.dart
// Etiket tasarımcısı: geniş / dar ekranda taşma hatası yok; öğe ekle, sürükle (etiket içinde kalır), boyutlandır,
// sil, geri al / yinele, kaydet (cihaza yazılır, seçili olur). Önizleme resmi testte üretilemez (yazdırma eklentisi yok) —
// ekran bunu hata ikonu ile karşılar, çökmez.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/cekirdek/etiket/etiket_tasarimi.dart';
import 'package:market_plus/cekirdek/etiket/raf_etiket_sablonlari.dart';
import 'package:market_plus/ekranlar/barkod/etiket_tasarimci_ekrani.dart';
import 'package:market_plus/servisler/etiket_ayarlari.dart';
import 'package:market_plus/widgetlar/masaustu/ekran_ustte.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<EtiketSablonu?> _ac(WidgetTester t, EtiketSablonu s, Size boyut) async {
  t.view.physicalSize = boyut;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  EtiketSablonu? sonuc;
  await t.pumpWidget(MaterialApp(
    home: Builder(
      builder: (c) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              sonuc = await Navigator.of(c).push<EtiketSablonu>(
                MaterialPageRoute(builder: (_) => EtiketTasarimciEkrani(tasarim: s, firma: 'HALK MARKET')),
              );
            },
            child: const Text('aç'),
          ),
        ),
      ),
    ),
  ));
  await t.tap(find.text('aç'));
  await t.pumpAndSettle();
  return sonuc;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final boyut in [const Size(1400, 900), const Size(420, 860)]) {
    testWidgets('düzenle, sürükle, geri al, kaydet — ${boyut.width.toInt()} px', (t) async {
      final s = otomatikTasarim(
          id: 'k_test', ad: 'Deneme', genislik: 58, yukseklik: 40, alanlar: {OtomatikAlan.ad, OtomatikAlan.fiyat, OtomatikAlan.barkod});
      EtiketSablonu? kaydedilen;
      await t.pumpWidget(const SizedBox());
      t.view.physicalSize = boyut;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (c) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  kaydedilen = await Navigator.of(c).push<EtiketSablonu>(
                    MaterialPageRoute(builder: (_) => EtiketTasarimciEkrani(tasarim: s, firma: 'HALK MARKET')),
                  );
                },
                child: const Text('aç'),
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.text('aç'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      final panel = find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first;
      // Öğe sayısı başlığı (seçili öğe paneli üstte olduğundan başlık aşağıda kalabilir: baştan kaydırarak bulunur)
      Future<void> ogeSayisi(int n) async {
        t.state<ScrollableState>(panel).position.jumpTo(0);
        await t.pumpAndSettle();
        await t.scrollUntilVisible(find.text('Öğeler ($n)'), 100, scrollable: panel);
      }

      await ogeSayisi(3);

      // Öğe ekle → Sabit yazı (menü öğesi listenin sonunda; kaydırarak görünür yapılır)
      await t.ensureVisible(find.text('Öğe ekle'));
      await t.pumpAndSettle();
      await t.tap(find.text('Öğe ekle'));
      await t.pumpAndSettle();
      final sabit = find.text('Sabit yazı (kendi metniniz)');
      await t.scrollUntilVisible(sabit, 60, scrollable: find.byType(Scrollable).last);
      await t.tap(sabit);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      // yeni öğe seçili: ayarları panelin en üstünde
      expect(find.text('Seçili: “Yazı”'), findsOneWidget);
      await ogeSayisi(4);

      // geri al → 3 öğe, yinele → 4
      await t.tap(find.byTooltip('Geri al (Ctrl+Z)'));
      await t.pumpAndSettle();
      await ogeSayisi(3);
      await t.tap(find.byTooltip('Yinele (Ctrl+Y)'));
      await t.pumpAndSettle();
      await ogeSayisi(4);

      // Geri al seçimi kaldırır; öğe listeden seçilip silinir
      final satir = find.text('“Yazı”');
      await t.scrollUntilVisible(satir, 80, scrollable: panel);
      await t.ensureVisible(satir);
      await t.pumpAndSettle();
      await t.tap(satir);
      await t.pumpAndSettle();
      final sil = find.byTooltip('Sil (Delete)');
      await t.ensureVisible(sil);
      await t.pumpAndSettle();
      await t.tap(sil);
      await t.pumpAndSettle();
      expect(find.byTooltip('Sil (Delete)'), findsNothing); // seçim kalktı
      await ogeSayisi(3);

      // İlk öğeyi (ürün adı) tuvalde çok uzağa sürükle: etiketin içinde kalmalı
      final kutu = find.byType(MouseRegion).evaluate().where((e) {
        final w = e.widget as MouseRegion;
        return w.cursor == SystemMouseCursors.move;
      }).first;
      await t.drag(find.byWidget(kutu.widget), const Offset(5000, 5000));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);

      await t.tap(find.text('Kaydet'));
      await t.pumpAndSettle();
      expect(kaydedilen, isNotNull);
      final k = kaydedilen!;
      expect(k.ogeler.length, 3);
      final ad = k.ogeler.first;
      expect(ad.x + ad.g, lessThanOrEqualTo(k.genislik + 0.05));
      expect(ad.y + ad.h, lessThanOrEqualTo(k.yukseklik + 0.05));
      expect(ad.y, greaterThan(s.ogeler.first.y)); // gerçekten taşındı
      expect((await EtiketAyarlari.kendiTasarimlar()).single.id, 'k_test');
    });
  }

  testWidgets('kaydedilmemiş değişiklikle çıkışta sorar', (t) async {
    final s = otomatikTasarim(id: 'k_c', ad: 'C', genislik: 40, yukseklik: 30, alanlar: {OtomatikAlan.fiyat});
    await _ac(t, s, const Size(1400, 900));
    await t.tap(find.byTooltip('Öğe ekle'));
    await t.pumpAndSettle();
    await t.tap(find.text('Barkod').last);
    await t.pumpAndSettle();
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    expect(find.text('Değişiklikler kaydedilmedi'), findsOneWidget);
    await t.tap(find.text('Kaydetmeden çık'));
    await t.pumpAndSettle();
    expect(find.text('aç'), findsOneWidget);
    expect(await EtiketAyarlari.kendiTasarimlar(), isEmpty);
  });

  testWidgets('masaüstü Esc / Geri (IcGeri): önce seçimi kaldırır, kaydedilmemişse sorar; değişiklik yoksa engellemez', (t) async {
    final s = otomatikTasarim(id: 'k_e', ad: 'E', genislik: 40, yukseklik: 30, alanlar: {OtomatikAlan.fiyat});
    await _ac(t, s, const Size(1400, 900));
    expect(IcGeri.dene(), isFalse); // değişiklik yok: genel geri çalışsın
    await t.tap(find.text('Satış fiyatı'));
    await t.pumpAndSettle();
    expect(find.textContaining('Seçili:'), findsOneWidget);
    expect(IcGeri.dene(), isTrue); // seçimi kaldırdı
    await t.pumpAndSettle();
    expect(find.textContaining('Seçili:'), findsNothing);
    await t.tap(find.byTooltip('Öğe ekle'));
    await t.pumpAndSettle();
    await t.tap(find.text('Barkod').last);
    await t.pumpAndSettle();
    expect(IcGeri.dene(), isTrue); // seçimi kaldırdı
    await t.pumpAndSettle();
    expect(IcGeri.dene(), isTrue); // kaydedilmemiş: sorar
    await t.pumpAndSettle();
    expect(find.text('Değişiklikler kaydedilmedi'), findsOneWidget);
    await t.tap(find.text('Vazgeç'));
    await t.pumpAndSettle();
    expect(find.byType(EtiketTasarimciEkrani), findsOneWidget); // açık kaldı
  });
}
