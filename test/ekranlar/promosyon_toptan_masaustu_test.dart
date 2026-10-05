// test/ekranlar/promosyon_toptan_masaustu_test.dart
//
// Promosyon ve Toptan masaüstü tablo görünümleri: satırlar görünür, taşma yok,
// kısayol/buton geri çağrıları çalışır, durum etiketi doğru.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/ekranlar/promosyon/masaustu/promosyon_masaustu_gorunum.dart';
import 'package:market_plus/ekranlar/toptan/masaustu/toptan_masaustu_gorunum.dart';
import 'package:market_plus/modeller/cari_model.dart';
import 'package:market_plus/modeller/promosyon_model.dart';

void main() {
  Future<void> boyutla(WidgetTester t) async {
    t.view.physicalSize = const Size(1366, 768);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
  }

  group('PromosyonMasaustuGorunum', () {
    final bugun = DateTime.now();
    final liste = [
      PromosyonModel(id: 1, urunId: 1, urunAdi: 'Süt', promosyonAdi: 'Süt %10', iskontoOran: 10),
      PromosyonModel(
          id: 2, urunId: 2, urunAdi: 'Ekmek', promosyonAdi: 'Pasif', iskontoOran: 5, aktif: false),
      PromosyonModel(
          id: 3,
          urunId: 3,
          urunAdi: 'Çay',
          promosyonAdi: 'Dün bitti',
          iskontoOran: 20,
          bitisTarihi: bugun.subtract(const Duration(days: 2))),
      PromosyonModel(
          id: 4,
          urunId: 4,
          urunAdi: 'Şeker',
          promosyonAdi: 'Bugün bitiyor',
          iskontoOran: 15,
          bitisTarihi: DateTime(bugun.year, bugun.month, bugun.day)),
    ];

    test('durum etiketi: bitiş günü TAM gün geçerli, geçmiş bitiş dolmuş, pasif pasif', () {
      expect(PromosyonMasaustuGorunum.durumEtiketi(liste[0]), 'Aktif');
      expect(PromosyonMasaustuGorunum.durumEtiketi(liste[1]), 'Pasif');
      expect(PromosyonMasaustuGorunum.durumEtiketi(liste[2]), 'Süresi Doldu');
      expect(PromosyonMasaustuGorunum.durumEtiketi(liste[3]), 'Aktif');
    });

    testWidgets('satırlar, özet ve F-tuşu geri çağrıları (yetkili)', (t) async {
      await boyutla(t);
      final olaylar = <String>[];
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PromosyonMasaustuGorunum(
            promosyonlar: liste,
            yetkili: true,
            onEkle: () => olaylar.add('ekle'),
            onDuzenle: (p) => olaylar.add('duzenle${p.id}'),
            onToggle: (p) => olaylar.add('toggle${p.id}'),
            onSil: (p) => olaylar.add('sil${p.id}'),
          ),
        ),
      ));
      await t.pump();
      expect(t.takeException(), isNull);
      expect(find.text('Süt %10'), findsOneWidget);
      expect(find.text('Süresi Doldu'), findsOneWidget);

      await t.sendKeyEvent(LogicalKeyboardKey.f1);
      expect(olaylar, ['ekle']);

      await t.tap(find.text('Süt %10'));
      await t.pump(const Duration(milliseconds: 400)); // çift tık bekleme süresi
      await t.sendKeyEvent(LogicalKeyboardKey.f2);
      await t.sendKeyEvent(LogicalKeyboardKey.f3);
      await t.sendKeyEvent(LogicalKeyboardKey.f4);
      expect(olaylar, ['ekle', 'duzenle1', 'toggle1', 'sil1']);
    });

    testWidgets('yetkisiz kullanıcıda düzenleme tuşları/kısayolları çalışmaz', (t) async {
      await boyutla(t);
      final olaylar = <String>[];
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PromosyonMasaustuGorunum(
            promosyonlar: liste,
            yetkili: false,
            onEkle: () => olaylar.add('ekle'),
            onDuzenle: (p) => olaylar.add('duzenle'),
            onToggle: (p) => olaylar.add('toggle'),
            onSil: (p) => olaylar.add('sil'),
          ),
        ),
      ));
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.f1);
      await t.tap(find.text('Süt %10'));
      await t.sendKeyEvent(LogicalKeyboardKey.f4);
      expect(olaylar, isEmpty);
      expect(find.textContaining('Ekle'), findsNothing);
    });
  });

  group('ToptanMasaustuGorunum', () {
    final bayiler = [
      CariModel(
          id: 1,
          unvan: 'Bayi A',
          cariTipi: 'Müşteri',
          musteriTipi: 'Bayi',
          bakiye: 1500,
          limitTutari: 1000),
      CariModel(
          id: 2,
          unvan: 'Toptan B',
          cariTipi: 'Müşteri',
          musteriTipi: 'Toptan',
          bakiye: 200,
          limitTutari: 5000),
    ];

    testWidgets('bayiler, limit aşımı özeti ve F-tuşları', (t) async {
      await boyutla(t);
      final olaylar = <String>[];
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ToptanMasaustuGorunum(
            bayiler: bayiler,
            bugunkuCiro: 123,
            onPanel: (c) => olaylar.add('panel${c.id}'),
            onHizliSatis: () => olaylar.add('satis'),
            onUrunler: () => olaylar.add('urunler'),
            onBekleyenSiparisler: () => olaylar.add('siparis'),
            onFiyatGruplari: () => olaylar.add('fiyat'),
          ),
        ),
      ));
      await t.pump();
      expect(t.takeException(), isNull);
      expect(find.text('Bayi A'), findsOneWidget);
      expect(find.text('Toptan B'), findsOneWidget);
      expect(ToptanMasaustuGorunum.limitAsildi(bayiler[0]), isTrue);
      expect(ToptanMasaustuGorunum.limitAsildi(bayiler[1]), isFalse);

      await t.sendKeyEvent(LogicalKeyboardKey.f1);
      await t.sendKeyEvent(LogicalKeyboardKey.f3);
      await t.sendKeyEvent(LogicalKeyboardKey.f4);
      await t.sendKeyEvent(LogicalKeyboardKey.f5);
      await t.sendKeyEvent(LogicalKeyboardKey.f2); // seçim yok → bir şey olmaz
      await t.tap(find.text('Bayi A'));
      await t.pump(const Duration(milliseconds: 400)); // çift tık bekleme süresi
      await t.sendKeyEvent(LogicalKeyboardKey.f2);
      expect(olaylar, ['satis', 'urunler', 'siparis', 'fiyat', 'panel1']);
    });
  });
}
