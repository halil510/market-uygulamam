// test/ekranlar/banka_kk_vardiya_masaustu_test.dart
//
// Banka hareketleri, Kredi Kartı listesi ve Vardiya geçmişi masaüstü tabloları.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/ekranlar/banka/masaustu/banka_hareket_masaustu_gorunum.dart';
import 'package:market_plus/ekranlar/banka/masaustu/kredi_karti_masaustu_gorunum.dart';
import 'package:market_plus/ekranlar/vardiya/masaustu/vardiya_gecmis_masaustu_gorunum.dart';
import 'package:market_plus/modeller/banka_hareket_model.dart';
import 'package:market_plus/modeller/kredi_karti_model.dart';

void main() {
  Future<void> boyutla(WidgetTester t) async {
    t.view.physicalSize = const Size(1366, 768);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
  }

  group('BankaHareketMasaustuGorunum', () {
    final liste = [
      BankaHareketModel(
          bankaHesapId: 1,
          islemTipi: 'Gelen',
          tutar: 1000,
          aciklama: 'Müşteri havalesi',
          tarih: DateTime(2026, 10, 1, 9, 30)),
      BankaHareketModel(
          bankaHesapId: 1,
          islemTipi: 'Giden',
          tutar: 400,
          aciklama: 'Tedarikçi ödemesi',
          tarih: DateTime(2026, 10, 2, 14, 0)),
    ];

    test('yön kuralı: tutar hep pozitif, yön islemTipi ile belirlenir', () {
      expect(BankaHareketMasaustuGorunum.giris(liste[0]), isTrue);
      expect(BankaHareketMasaustuGorunum.giris(liste[1]), isFalse);
    });

    testWidgets('işaretli tutarlar, özet ve F1/F5', (t) async {
      await boyutla(t);
      final olaylar = <String>[];
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: BankaHareketMasaustuGorunum(
            hareketler: liste,
            onEkle: () => olaylar.add('ekle'),
            onYenile: () async => olaylar.add('yenile'),
          ),
        ),
      ));
      await t.pump();
      expect(t.takeException(), isNull);
      expect(find.text('Müşteri havalesi'), findsOneWidget);
      expect(find.textContaining('+'), findsWidgets);
      expect(find.textContaining('-'), findsWidgets);
      await t.sendKeyEvent(LogicalKeyboardKey.f1);
      await t.sendKeyEvent(LogicalKeyboardKey.f5);
      expect(olaylar, ['ekle', 'yenile']);
    });

    testWidgets('kredi kartı modunda (onEkle null) F1 çalışmaz', (t) async {
      await boyutla(t);
      final olaylar = <String>[];
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: BankaHareketMasaustuGorunum(
            hareketler: liste,
            onYenile: () async => olaylar.add('yenile'),
          ),
        ),
      ));
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.f1);
      expect(olaylar, isEmpty);
    });
  });

  group('KrediKartiMasaustuGorunum', () {
    final liste = [
      const KrediKartiModel(
          id: 1,
          bankaId: 1,
          kartAdi: 'Ticari Kart',
          kartNoMaskeli: '**** **** **** 4242',
          kartLimit: 10000,
          kullanilanLimit: 9000),
      const KrediKartiModel(
          id: 2,
          bankaId: 1,
          kartAdi: 'Yedek Kart',
          kartNoMaskeli: '**** **** **** 1111',
          kartLimit: 0),
    ];

    test('doluluk yüzdesi; limitsiz kartta 0', () {
      expect(KrediKartiMasaustuGorunum.doluluk(liste[0]), 90);
      expect(KrediKartiMasaustuGorunum.doluluk(liste[1]), 0);
    });

    testWidgets('satırlar, F1/F2 ve yetkisizde F1 kapalı', (t) async {
      await boyutla(t);
      final olaylar = <String>[];
      Widget sar(bool yetkili) => MaterialApp(
            home: Scaffold(
              body: KrediKartiMasaustuGorunum(
                kartlar: liste,
                yetkili: yetkili,
                onEkle: () => olaylar.add('ekle'),
                onDetay: (k) => olaylar.add('detay${k.id}'),
              ),
            ),
          );
      await t.pumpWidget(sar(true));
      await t.pump();
      expect(t.takeException(), isNull);
      expect(find.text('Ticari Kart'), findsOneWidget);
      expect(find.text('%90'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.f1);
      await t.tap(find.text('Yedek Kart'));
      await t.pump(const Duration(milliseconds: 400));
      await t.sendKeyEvent(LogicalKeyboardKey.f2);
      expect(olaylar, ['ekle', 'detay2']);

      olaylar.clear();
      await t.pumpWidget(sar(false));
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.f1);
      expect(olaylar, isEmpty);
    });
  });

  group('VardiyaGecmisMasaustuGorunum', () {
    final liste = [
      {
        'id': 1,
        'ad_soyad': 'Ayşe Kasiyer',
        'acilis_tarihi': '2026-10-05T08:00:00',
        'kapanis_tarihi': '2026-10-05T17:00:00',
        'bitis_bakiye': 2500.0,
        'fark': -15.5,
        'onaylayan_adi': 'Müdür Bey',
      },
      {
        'id': 2,
        'ad_soyad': 'Mehmet Kasiyer',
        'acilis_tarihi': '2026-10-06T08:00:00',
        'kapanis_tarihi': '2026-10-06T16:00:00',
        'bitis_bakiye': 1800,
        'fark': 0,
      },
    ];

    testWidgets('satırlar, F2 PDF ve F7 daha fazla', (t) async {
      await boyutla(t);
      final olaylar = <String>[];
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: VardiyaGecmisMasaustuGorunum(
            vardiyalar: liste,
            sureMetni: (b, k) => '9 sa',
            onPdf: (v) => olaylar.add('pdf${v['id']}'),
            dahaVarMi: true,
            dahaYukleniyor: false,
            onDahaFazla: () => olaylar.add('daha'),
          ),
        ),
      ));
      await t.pump();
      expect(t.takeException(), isNull);
      expect(find.text('Ayşe Kasiyer'), findsOneWidget);
      expect(find.text('Müdür Bey'), findsOneWidget);

      await t.tap(find.text('Mehmet Kasiyer'));
      await t.pump(const Duration(milliseconds: 400));
      await t.sendKeyEvent(LogicalKeyboardKey.f2);
      await t.sendKeyEvent(LogicalKeyboardKey.f7);
      expect(olaylar, ['pdf2', 'daha']);
    });

    testWidgets('daha fazla kayıt yoksa F7 çalışmaz', (t) async {
      await boyutla(t);
      final olaylar = <String>[];
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: VardiyaGecmisMasaustuGorunum(
            vardiyalar: liste,
            sureMetni: (b, k) => '',
            onPdf: (v) {},
            dahaVarMi: false,
            dahaYukleniyor: false,
            onDahaFazla: () => olaylar.add('daha'),
          ),
        ),
      ));
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.f7);
      expect(olaylar, isEmpty);
    });
  });
}
