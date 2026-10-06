// test/ekranlar/gider_personel_masaustu_test.dart
//
// Gider ve Personel masaüstü tablo görünümleri: satırlar görünür, taşma yok,
// kısayol geri çağrıları çalışır, yetkisiz kullanıcıda ekle/sil kapalıdır.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/ekranlar/gider/masaustu/gider_masaustu_gorunum.dart';
import 'package:market_plus/ekranlar/personel/masaustu/personel_masaustu_gorunum.dart';
import 'package:market_plus/modeller/gider_model.dart';
import 'package:market_plus/modeller/personel_model.dart';

void main() {
  Future<void> boyutla(WidgetTester t) async {
    t.view.physicalSize = const Size(1366, 768);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
  }

  group('GiderMasaustuGorunum', () {
    final liste = [
      GiderModel(
          id: 1,
          kategoriId: 1,
          kategoriAdi: 'Kira',
          tutar: 5000,
          aciklama: 'Ekim kirası',
          tarih: DateTime(2026, 10, 1)),
      GiderModel(
          id: 2,
          kategoriId: 0,
          tutar: 250,
          aciklama: 'Temizlik malzemesi',
          tarih: DateTime(2026, 10, 3)),
    ];

    Widget sar({required bool yetkili, required List<String> olaylar, List<GiderModel>? l}) =>
        MaterialApp(
          home: Scaffold(
            body: GiderMasaustuGorunum(
              giderler: l ?? liste,
              yetkili: yetkili,
              onEkle: () => olaylar.add('ekle'),
              onDuzenle: (g) => olaylar.add('duzenle${g.id}'),
              onSil: (g) => olaylar.add('sil${g.id}'),
            ),
          ),
        );

    testWidgets('satırlar, boş kategori "Genel" ve F-tuşları (yetkili)', (t) async {
      await boyutla(t);
      final olaylar = <String>[];
      await t.pumpWidget(sar(yetkili: true, olaylar: olaylar));
      await t.pump();
      expect(t.takeException(), isNull);
      expect(find.text('Ekim kirası'), findsOneWidget);
      expect(find.text('Genel'), findsOneWidget);

      await t.sendKeyEvent(LogicalKeyboardKey.f1);
      await t.tap(find.text('Ekim kirası'));
      await t.pump(const Duration(milliseconds: 400));
      await t.sendKeyEvent(LogicalKeyboardKey.f2);
      await t.sendKeyEvent(LogicalKeyboardKey.f4);
      expect(olaylar, ['ekle', 'duzenle1', 'sil1']);
    });

    testWidgets('yetkisizde F1/F4 çalışmaz, F2 düzenleme çalışır', (t) async {
      await boyutla(t);
      final olaylar = <String>[];
      await t.pumpWidget(sar(yetkili: false, olaylar: olaylar));
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.f1);
      await t.tap(find.text('Ekim kirası'));
      await t.pump(const Duration(milliseconds: 400));
      await t.sendKeyEvent(LogicalKeyboardKey.f4);
      await t.sendKeyEvent(LogicalKeyboardKey.f2);
      expect(olaylar, ['duzenle1']);
    });

    testWidgets('boş listede mesaj, yetkiliye F1 ipucu', (t) async {
      await boyutla(t);
      await t.pumpWidget(sar(yetkili: true, olaylar: [], l: const []));
      await t.pump();
      expect(find.textContaining('F1 ile ekleyin'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  group('PersonelMasaustuGorunum', () {
    final liste = [
      PersonelModel(
          id: 1,
          adSoyad: 'Ayşe Yılmaz',
          pozisyon: 'Kasiyer',
          telefon: '05321112233',
          maas: 20000,
          iseBaslama: DateTime(2025, 1, 15)),
      PersonelModel(id: 2, adSoyad: 'Mehmet Demir', pozisyon: 'Depo', aktif: false),
    ];

    Widget sar({required bool yetkili, required List<String> olaylar, List<PersonelModel>? l}) =>
        MaterialApp(
          home: Scaffold(
            body: PersonelMasaustuGorunum(
              personeller: l ?? liste,
              yetkili: yetkili,
              onEkle: () => olaylar.add('ekle'),
              onDetay: (p) => olaylar.add('detay${p.id}'),
            ),
          ),
        );

    testWidgets('satırlar, durum etiketleri ve kısayollar', (t) async {
      await boyutla(t);
      final olaylar = <String>[];
      await t.pumpWidget(sar(yetkili: true, olaylar: olaylar));
      await t.pump();
      expect(t.takeException(), isNull);
      expect(find.text('Ayşe Yılmaz'), findsOneWidget);
      expect(find.text('Aktif'), findsWidgets);
      expect(find.text('Pasif'), findsOneWidget);

      await t.sendKeyEvent(LogicalKeyboardKey.f1);
      await t.tap(find.text('Mehmet Demir'));
      await t.pump(const Duration(milliseconds: 400));
      await t.sendKeyEvent(LogicalKeyboardKey.f2);
      expect(olaylar, ['ekle', 'detay2']);
    });

    testWidgets('yetkisizde F1 Ekle çalışmaz', (t) async {
      await boyutla(t);
      final olaylar = <String>[];
      await t.pumpWidget(sar(yetkili: false, olaylar: olaylar));
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.f1);
      expect(olaylar, isEmpty);
      expect(t.takeException(), isNull);
    });
  });
}
