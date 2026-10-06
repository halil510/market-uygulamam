// test/widget/ai_oneri_karti_test.dart
//
// Asistanın işlem önizleme kartı: taşma yok (dar/geniş, açık/koyu tema),
// Onayla/Vazgeç çalışır, kullanılmış kartta düğmeler kalkar.
// Ayrıca AiAnlayici'nin takip-cümlesi ayrımı (eski "her şeyi önceki niyetle
// yanıtla" hatasının regresyonu).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/ekranlar/ai/ai_panel_ekrani.dart';
import 'package:market_plus/servisler/ai/ai_anlayici.dart';
import 'package:market_plus/servisler/ai/ai_modeller.dart';
import 'package:market_plus/servisler/ai/ai_sohbet_servisi.dart';
import 'package:market_plus/servisler/ai/eylem/ai_eylem_modeli.dart';

AiEylemOnerisi _oneri({bool kritik = false}) => AiEylemOnerisi(
      id: 't',
      tur: AiEylemTuru.fiyatGuncelle,
      baslik: 'Fiyat Güncelle',
      kritik: kritik,
      satirlar: const [
        'Ürün: Ülker Çikolatalı Gofret Büyük Boy 36 G Kutu  (8690504012345)',
        'Satış fiyatı: 25,00 ₺ → 30,00 ₺  (+%20,0)',
      ],
      uyarilar: const [
        'Üründeki kayıtlı indirim sıfırlanacak (eski indirim yeni fiyata miras kalmaz).',
        'Yeni satış fiyatı alış (KDV dahil) 31,00 ₺ değerinin ALTINDA — zararına satış.',
      ],
      uygula: () async => 'ok',
    );

void main() {
  Future<void> boyutla(WidgetTester t, Size s) async {
    t.view.physicalSize = s;
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
  }

  for (final tema in [ThemeData.light(), ThemeData.dark()]) {
    for (final boyut in [const Size(320, 640), const Size(1366, 768)]) {
      testWidgets('kart taşmaz — ${tema.brightness.name} ${boyut.width.toInt()}px', (t) async {
        await boyutla(t, boyut);
        var onay = 0, vazgec = 0;
        await t.pumpWidget(MaterialApp(
          theme: tema,
          home: Scaffold(
            body: ListView(children: [
              AiOneriKarti(
                oneri: _oneri(kritik: true),
                durum: 'bekliyor',
                onOnayla: () => onay++,
                onVazgec: () => vazgec++,
              ),
            ]),
          ),
        ));
        await t.pump();
        expect(t.takeException(), isNull);
        expect(find.text('Fiyat Güncelle'), findsOneWidget);
        expect(find.text('Para hareketi'), findsOneWidget);
        expect(find.text('Onayla'), findsOneWidget);

        await t.tap(find.text('Onayla'));
        await t.tap(find.text('Vazgeç'));
        expect(onay, 1);
        expect(vazgec, 1);
      });
    }
  }

  testWidgets('uygulanıyor: ilerleme çubuğu, düğme yok', (t) async {
    await boyutla(t, const Size(400, 700));
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AiOneriKarti(oneri: _oneri(), durum: 'uygulaniyor', onOnayla: () {}, onVazgec: () {}),
      ),
    ));
    await t.pump();
    expect(find.text('Onayla'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('tamamlanan / yazıyla iptal edilen kartta düğmeler kalkar', (t) async {
    await boyutla(t, const Size(400, 700));
    final o = _oneri();
    await o.calistir(); // kullanıldı
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AiOneriKarti(oneri: o, durum: 'bekliyor', onOnayla: () {}, onVazgec: () {}),
      ),
    ));
    await t.pump();
    expect(find.text('Onayla'), findsNothing);
    expect(find.textContaining('tamamlandı'), findsOneWidget);

    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AiOneriKarti(oneri: _oneri(), durum: 'tamam', onOnayla: () {}, onVazgec: () {}),
      ),
    ));
    await t.pump();
    expect(find.textContaining('İşlendi'), findsOneWidget);
  });

  group('Uyandırma kelimesi (Barkopro)', () {
    String a(String s) => AiSohbetServisi.uyandirmaKelimesiniAt(s);
    test('baştaki "Barkopro" atılır, komut kalır', () {
      expect(a('Barkopro, kolanın fiyatını 35 yap'), 'kolanın fiyatını 35 yap');
      expect(a('hey barkopro bugünkü ciro'), 'bugünkü ciro');
      expect(a('barko pro kritik stoklar'), 'kritik stoklar');
      expect(a('Barkoprö: kasa durumu'), 'kasa durumu');
      expect(a('asistan, z raporu'), 'z raporu');
    });
    test('yalnız uyandırma kelimesi → boş', () {
      expect(a('barkopro'), '');
      expect(a('Hey Barkopro!'), '');
    });
    test('normal cümleye dokunmaz', () {
      expect(a('kolanın fiyatını 35 yap'), 'kolanın fiyatını 35 yap');
      expect(a('asistanlık maliyeti ne kadar'), 'asistanlık maliyeti ne kadar');
    });
  });

  group('AiAnlayici takip cümlesi', () {
    test('gerçek takip cümleleri bağlamı sürdürür', () {
      for (final s in ['peki geçen ay', 'ya dün', 'bir de bu hafta', 'geçen hafta']) {
        expect(AiAnlayici.devamCumlesiMi(s), isTrue, reason: s);
      }
    });
    test('tanınmayan serbest cümle önceki niyeti TEKRARLAMAZ', () {
      for (final s in [
        'asdf qwer',
        'bunu çok beğendim ama olmadı bence',
        'kola kaç para',
        'yarın hava nasıl olacak',
      ]) {
        expect(AiAnlayici.devamCumlesiMi(s), isFalse, reason: s);
      }
    });
    test('stok sorusundan sonra anlamsız cümle bilinmiyor döner', () {
      AiAnlayici.anla('kritik stoklar'); // bağlamı kur
      expect(AiAnlayici.anla('asdf qwer zxcv').intent, AiIntent.bilinmiyor);
    });
  });
}
