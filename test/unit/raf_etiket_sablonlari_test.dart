// test/unit/raf_etiket_sablonlari_test.dart
// Raf etiketi şablonları (BarTender tasarımları): ürün kartından veri, birim fiyat, denetim, YERLEŞİM
// (hiçbir yazı kutusundan / etiketten taşmaz), PDF ve termal yazıcı resmi.
// RAF_ETIKET_CIKTI=<klasör> verilirse her şablonun PDF'i oraya yazılır (gözle kontrol için).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/cekirdek/etiket/raf_etiket_sablonlari.dart';
import 'package:market_plus/modeller/urun_model.dart';
import 'package:market_plus/servisler/raf_etiket_pdf_servisi.dart';

UrunModel _u({
  String ad = 'ABC ÇAMASIR SUYU 4KG',
  double fiyat = 100,
  String birim = 'Adet',
  double agirlik = 0,
  String? barkod = '8690511183754',
  double indirimOrani = 0,
  double indirimliKayitli = 0,
  String? mensei,
  String? tarih,
}) =>
    UrunModel(
      urunAdi: ad,
      birimAdi: birim,
      satisFiyati: fiyat,
      agirlik: agirlik,
      barkod: barkod,
      indirimOrani: indirimOrani,
      indirimliFiyatKayitli: indirimliKayitli,
      mensei: mensei,
      fiyatGuncellemeTarih: tarih,
    );

void main() {
  group('miktar / birim fiyat', () {
    test('adda gramaj', () {
      expect(miktarCoz('ABC ÇAMASIR SUYU 4KG'), const Miktar(4, 'KG'));
      expect(miktarCoz('SÖLEN BOOM STAR 40G'), const Miktar(0.04, 'KG'));
      expect(miktarCoz('PINAR SÜT 1,5 LT'), const Miktar(1.5, 'LT'));
      expect(miktarCoz('SU 500ML'), const Miktar(0.5, 'LT'));
      expect(miktarCoz('KOLA 33 CL'), const Miktar(0.33, 'LT'));
      expect(miktarCoz('YOĞURT 4X125 G'), const Miktar(0.5, 'KG'));
      expect(miktarCoz('un 1 kg'), const Miktar(1, 'KG'));
      expect(miktarCoz('PİRİNÇ 1.000 GR'), const Miktar(1, 'KG')); // binlik ayırıcı
      expect(miktarCoz('ZEYTİNYAĞI 0.5 LT'), const Miktar(0.5, 'LT'));
    });

    test('belirsiz / paket / yok → null (tahmin yok)', () {
      expect(miktarCoz('SÖLEN LUPPO SANDIVIÇ KEK'), isNull);
      expect(miktarCoz('ÇİKOLATA 80 GR + 40 GR HEDİYE'), isNull);
      expect(miktarCoz('B12G VİTAMİN'), isNull);
      expect(miktarCoz('SÖLEN NUTYMAX A.FISTIK 44 GR 3 MP'), isNull); // 3 × 44 g
      expect(miktarCoz('SÖLEN OZMO FARM PARMAK CIK. 11G 4AD 20KT 6STKT'), isNull);
      expect(miktarCoz("YUMURTA 10'LU 600 G"), isNull);
    });

    test('birim fiyat: KG/LT birimi, ürün kartı Ağırlık, ad', () {
      expect(birimFiyatHesapla(ad: 'KIYMA', fiyat: 650, birimAdi: 'KG'), const BirimFiyat(650, 'KG'));
      expect(birimFiyatHesapla(ad: 'SÜT', fiyat: 40, birimAdi: 'Lt'), const BirimFiyat(40, 'LT'));
      // Ağırlık (gr) EtiketYardimci ile aynı: 900 g, 65 TL → 72,22
      expect(birimFiyatHesapla(ad: 'ARAP SABUNU', fiyat: 65, agirlikGr: 900), const BirimFiyat(72.22, 'KG'));
      // Ağırlık addan önce gelir
      expect(birimFiyatHesapla(ad: 'KEK 100 G', fiyat: 20, agirlikGr: 250), const BirimFiyat(80, 'KG'));
      expect(birimFiyatHesapla(ad: 'ABC ÇAMASIR SUYU 4KG', fiyat: 100), const BirimFiyat(25, 'KG'));
      expect(birimFiyatHesapla(ad: 'KEK', fiyat: 20), isNull);
      expect(birimFiyatHesapla(ad: 'SU 5 LT', fiyat: null), isNull);
    });
  });

  test('tarih okuma', () {
    expect(tarihOku('2026-11-12T10:15:00.000'), DateTime(2026, 11, 12));
    expect(tarihOku('2026-11-12'), DateTime(2026, 11, 12));
    expect(tarihOku('24.10.2018'), DateTime(2018, 10, 24));
    expect(tarihOku(''), isNull);
    expect(tarihOku(null), isNull);
    expect(tarihOku('31.13.2020'), isNull);
  });

  test('ürün kartından etiket verisi', () {
    final v = etiketVerisi(_u(indirimOrani: 20, mensei: ' Almanya ', tarih: '2026-11-12T09:00:00'));
    expect(v.ad, 'ABC ÇAMASIR SUYU 4KG');
    expect(v.fiyat, 100);
    expect(v.barkod, '8690511183754');
    expect(v.indirimliFiyat, 80);
    expect(v.indirimOrani, 20);
    expect(v.birimFiyat, const BirimFiyat(25, 'KG'));
    expect(v.tarih, DateTime(2026, 11, 12));
    expect(v.mensei, 'Almanya');

    // kayıtlı indirimli fiyat önce
    expect(etiketVerisi(_u(indirimliKayitli: 75, indirimOrani: 20)).indirimliFiyat, 75);
    // indirim yok / satıştan büyük → null
    expect(etiketVerisi(_u()).indirimliFiyat, isNull);
    expect(etiketVerisi(_u(indirimliKayitli: 120)).indirimliFiyat, isNull);
    // fiyat 0 → fiyatsız; barkodsuz; menşei boş
    final b = etiketVerisi(_u(fiyat: 0, barkod: null, mensei: '  '));
    expect(b.fiyat, isNull);
    expect(b.barkod, '');
    expect(b.mensei, isNull);
  });

  test('menşei: ürün kartındaki öncelikli, yoksa etiket ayarındaki', () {
    const o = TahminiOlcer();
    final s = sablonBul('raf_80x35_birimfiyatli');
    String yazilar(EtiketVeri v) =>
        yerlesim(s, v, olcer: o, mensei: 'Türkiye').whereType<YaziCizimi>().expand((e) => e.satirlar).map((e) => e.metin).join('|');
    expect(yazilar(etiketVerisi(_u(mensei: 'Almanya'))), contains('Menşei :Almanya'));
    expect(yazilar(etiketVerisi(_u())), contains('Menşei :Türkiye'));
  });

  test('denetim: fiyatsız atlanır, indirimli şablonda indirimsiz atlanır, birim fiyatsız uyarılır', () {
    final liste = [
      etiketVerisi(_u(ad: 'A 1 KG', fiyat: 10)),
      etiketVerisi(_u(ad: 'B', fiyat: 0)),
      etiketVerisi(_u(ad: 'C', fiyat: 10, indirimOrani: 20)),
    ];
    final n = etiketDenetle(sablonBul('raf_80x35_birimfiyatli'), liste);
    expect(n.basilacak.map((e) => e.ad), ['A 1 KG', 'C']);
    expect(n.atlanan, ['B — satış fiyatı yok']);
    expect(n.birimFiyatsiz, ['C']);
    final i = etiketDenetle(sablonBul('raf_80x35_indirimli'), liste);
    expect(i.basilacak.map((e) => e.ad), ['C']);
    expect(i.atlanan.length, 2);
  });

  test('8 şablon, kimlikler benzersiz (ayarda saklanır), bilinmeyen kimlik ilk şablona düşer', () {
    expect(sablonlar.length, 8);
    expect(sablonlar.map((s) => s.id).toSet().length, sablonlar.length);
    expect(sablonBul('yok').id, sablonlar.first.id);
  });

  group('yerleşim: taşma yok', () {
    final adlar = [
      'ÜRÜN ADI',
      'ABC ÇAMASIR SUYU 4KG',
      'ÇOK UZUN ÜRÜN ADI ŞEKERSİZ BİTTER ÇİKOLATALI FINDIKLI GOFRET AİLE BOYU 12 Lİ PAKET 480 GR',
      'TEKKELİMELİÇOKUZUNÜRÜNADIBÖLÜNEMEYENYAZIDENEMESİ1234567890',
    ];
    final fiyatlar = [0.5, 20.0, 1234.5, 12345678.0];
    final barkodlar = ['', '8690511183754', '12345670', '036000291452', 'K-5', 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'];
    const olcer = TahminiOlcer();
    for (final s in sablonlar) {
      test(s.id, () {
        for (final ad in adlar) {
          for (final f in fiyatlar) {
            for (final b in barkodlar) {
              final v = EtiketVeri(ad: ad, fiyat: f, barkod: b, indirimliFiyat: f * 0.8, birimFiyat: BirimFiyat(f * 37.5, 'KG'));
              _tasmaYok(s, yerlesim(s, v, olcer: olcer, mensei: 'Türkiye Cumhuriyeti', firma: 'HALK MARKET'), olcer);
            }
          }
        }
      });
    }
  });

  test('kısa yazılar BarTender puntosuyla basılır (kutu yüksekliği yüzünden küçülmez)', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final olcer = await RafEtiketYazilari.yukle(); // Windows'ta gerçek Arial ölçüleri
    const v = EtiketVeri(ad: 'ÜRÜN ADI', fiyat: 20, barkod: '12345670', indirimliFiyat: 10, birimFiyat: BirimFiyat(12, 'KG'));
    for (final s in sablonlar) {
      for (final c in yerlesim(s, v, olcer: olcer, mensei: 'Türkiye', bugun: DateTime(2018, 10, 24)).whereType<YaziCizimi>()) {
        for (final st in c.satirlar) {
          expect(st.punto, c.oge.punto, reason: '${s.id} "${st.metin}"');
        }
      }
    }
  });

  test('Code128 modül sayısı gerçek kodlamadan (rakam çiftleri sıkışır → çubuklar daha kalın)', () {
    expect(barkodModulSayisi('1234567890123'), 123);
    expect(barkodModulSayisi('12345678'), 79);
    expect(barkodModulSayisi('8690511183754'), 95);
  });

  test('her şablonun PDF\'i ve termal resmi (gerçek yazı tipleriyle taşma yok)', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final klasor = Platform.environment['RAF_ETIKET_CIKTI'];
    final liste = [
      etiketVerisi(_u(indirimOrani: 20, tarih: '2026-11-12')),
      etiketVerisi(_u(
          ad: 'ÇOK UZUN ÜRÜN ADI ŞEKERSİZ BİTTER ÇİKOLATALI FINDIKLI GOFRET AİLE BOYU 480 GR',
          fiyat: 1234.5,
          barkod: '12345670',
          indirimliKayitli: 999.9)),
    ];
    for (final sistem in [true, false]) {
      final y = await RafEtiketYazilari.yukle(sistem: sistem);
      for (final s in sablonlar) {
        for (final v in liste) {
          _tasmaYok(s, yerlesim(s, v, olcer: y), y);
        }
        for (final k in RafEtiketKagidi.values) {
          final pdf = await RafEtiketPdfServisi.pdf(liste, s, kagit: k, yazilar: y, firma: 'HALK MARKET', bugun: DateTime(2026, 11, 17));
          expect(pdf.length, greaterThan(1000));
          if (klasor != null && k == RafEtiketKagidi.rulo) File('$klasor/${s.id}${sistem ? '' : '_dejavu'}.pdf').writeAsBytesSync(pdf);
        }
      }
    }
  });
}

void _tasmaYok(EtiketSablonu s, List<Cizim> c, YaziOlcer olcer) {
  const pay = 0.05;
  for (final e in c) {
    switch (e) {
      case YaziCizimi(:final oge, :final satirlar):
        final boy = oge.dikey ? oge.h : oge.g, en = oge.dikey ? oge.g : oge.h;
        final ox = oge.dikey ? 0.0 : oge.x, oy = oge.dikey ? 0.0 : oge.y;
        for (final st in satirlar) {
          final lh = (olcer.ascent(oge.yazi, oge.kalin) + olcer.descent(oge.yazi, oge.kalin)) * st.punto * ptMm;
          expect(st.x, greaterThanOrEqualTo(ox - pay), reason: '${s.id} "${st.metin}" sol');
          expect(st.x + st.genislik, lessThanOrEqualTo(ox + boy + pay), reason: '${s.id} "${st.metin}" sağ');
          // hazır şablonda punto BarTender'daki gibi sabit: tek satırın satır kutusu öğe kutusundan biraz taşabilir
          // ama dikey ortası aynıdır; iki satırlı yazı kutuya sığar; hiçbiri etiketten taşmaz
          if (satirlar.length > 1 || s.kendi) {
            expect(st.y, greaterThanOrEqualTo(oy - pay), reason: '${s.id} "${st.metin}" üst');
            expect(st.y + lh, lessThanOrEqualTo(oy + en + pay), reason: '${s.id} "${st.metin}" alt');
          } else if (!oge.ustten) {
            expect(st.y + lh / 2, closeTo(oy + en / 2, 0.01), reason: '${s.id} "${st.metin}" dikey orta');
          }
          if (!oge.dikey) {
            expect(st.y, greaterThanOrEqualTo(-0.3), reason: '${s.id} "${st.metin}" etiketin üstünden taşıyor');
            expect(st.y + lh, lessThanOrEqualTo(s.yukseklik + 0.3), reason: '${s.id} "${st.metin}" etiketin altından taşıyor');
          }
          expect(st.punto, greaterThan(2.5), reason: '${s.id} "${st.metin}" okunmaz küçüklükte');
        }
        expect(oge.x + oge.g, lessThanOrEqualTo(s.genislik + pay));
        expect(oge.y + oge.h, lessThanOrEqualTo(s.yukseklik + pay));
      case BarkodCizimi(:final oge, :final x, :final genislik):
        expect(x, greaterThanOrEqualTo(oge.x - pay));
        expect(x + genislik, lessThanOrEqualTo(oge.x + oge.g + pay));
        expect(oge.y + oge.h, lessThanOrEqualTo(s.yukseklik + pay));
      case KutuCizimi(:final oge):
        expect(oge.x + oge.g, lessThanOrEqualTo(s.genislik + pay));
      case LogoCizimi(:final oge):
        expect(oge.x + oge.g, lessThanOrEqualTo(s.genislik + pay));
        expect(oge.y + oge.h, lessThanOrEqualTo(s.yukseklik + pay));
      case CizgiCizimi():
        expect([e.x1, e.x2].every((x) => x >= -pay && x <= s.genislik + pay), isTrue, reason: s.id);
    }
  }
}
