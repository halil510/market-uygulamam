// test/unit/etiket_tasarimi_test.dart
// Kendi etiket tasarımları: JSON saklama (bozuk kayıt atlanır), otomatik yerleşim (taşma yok), ölçekleme, denetim,
// eski serbest-etiket kayıtlarının göçü, yeni alanlar ({kod} {grup} {birim} {skt}), boş alanın başlığıyla basılmaması,
// ZPL grafiği, ayarların kalıcılığı (seçili tasarım / yazıcı) ve basım hazırlığı (adet, denetim).
// ETIKET_TASARIM_CIKTI=<klasör> verilirse otomatik tasarımların PDF'i oraya yazılır (gözle kontrol için).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/cekirdek/etiket/etiket_tasarimi.dart';
import 'package:market_plus/cekirdek/etiket/raf_etiket_sablonlari.dart';
import 'package:market_plus/cekirdek/etiket/tspl.dart';
import 'package:market_plus/cekirdek/etiket/zpl_resim.dart';
import 'package:market_plus/modeller/urun_model.dart';
import 'package:market_plus/servisler/etiket_ayarlari.dart';
import 'package:market_plus/servisler/etiket_baski_servisi.dart';
import 'package:market_plus/servisler/raf_etiket_pdf_servisi.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _olcer = TahminiOlcer();

String _json(EtiketSablonu s) => jsonEncode(tasarimJson(s));

/// Yazı satırları kutusundan, öğeler etiketten taşmaz.
void _tasmaYok(EtiketSablonu s, List<Cizim> c, YaziOlcer olcer) {
  const pay = 0.05;
  for (final e in c) {
    switch (e) {
      case YaziCizimi(:final oge, :final satirlar):
        final boy = oge.dikey ? oge.h : oge.g, en = oge.dikey ? oge.g : oge.h;
        final ox = oge.dikey ? 0.0 : oge.x, oy = oge.dikey ? 0.0 : oge.y;
        for (final st in satirlar) {
          final lh = (olcer.ascent(oge.yazi, oge.kalin) + olcer.descent(oge.yazi, oge.kalin)) * st.punto * ptMm;
          expect(st.x, greaterThanOrEqualTo(ox - pay), reason: '${s.ad} "${st.metin}" sol');
          expect(st.x + st.genislik, lessThanOrEqualTo(ox + boy + pay), reason: '${s.ad} "${st.metin}" sağ');
          expect(st.y, greaterThanOrEqualTo(oy - pay), reason: '${s.ad} "${st.metin}" üst');
          expect(st.y + lh, lessThanOrEqualTo(oy + en + pay), reason: '${s.ad} "${st.metin}" alt');
        }
      case BarkodCizimi(:final oge, :final x, :final genislik):
        expect(x, greaterThanOrEqualTo(oge.x - pay));
        expect(x + genislik, lessThanOrEqualTo(oge.x + oge.g + pay));
      default:
        break;
    }
  }
  for (final o in s.ogeler) {
    expect(o.x, greaterThanOrEqualTo(-pay), reason: '${s.ad} ${ogeAdi(o)} sol');
    expect(o.y, greaterThanOrEqualTo(-pay), reason: '${s.ad} ${ogeAdi(o)} üst');
    expect(o.x + o.g, lessThanOrEqualTo(s.genislik + pay), reason: '${s.ad} ${ogeAdi(o)} sağ');
    expect(o.y + o.h, lessThanOrEqualTo(s.yukseklik + pay), reason: '${s.ad} ${ogeAdi(o)} alt');
  }
}

UrunModel _u({String ad = 'PINAR SÜT 1 LT', double fiyat = 42.5, String? barkod = '8690511183754', int? id}) =>
    UrunModel(id: id, urunAdi: ad, birimAdi: 'Adet', satisFiyati: fiyat, barkod: barkod);

void main() {
  group('JSON', () {
    test('8 hazır şablon JSON\'a yazılıp okununca aynı', () {
      for (final s in sablonlar) {
        final geri = tasarimJsondan(jsonDecode(_json(s)) as Map<String, dynamic>);
        expect(_json(geri), _json(s), reason: s.id);
      }
    });

    test('kendi tasarım: kimlik öneki, kopya ve yer değiştirme', () {
      final s = sablonlar.first.kopya(id: 'k_1', ad: 'Benim', dosya: '');
      expect(s.kendi, isTrue);
      expect(sablonlar.any((e) => e.kendi), isFalse);
      final o = s.ogeler.first;
      final t = o.konumla(x: 5, y: 6);
      expect((t.x, t.y, t.g, t.h), (5.0, 6.0, o.g, o.h));
      expect(t.runtimeType, o.runtimeType);
    });

    test('bozuk kayıtlar atlanır, diğerleri kaybolmaz; aynı kimlik bir kez', () {
      final iyi = tasarimJson(sablonlar[6].kopya(id: 'k_iyi', ad: 'İyi'));
      final l = tasarimlarJsondan([
        iyi,
        {'ad': 'kimliksiz', 'genislik': 40, 'yukseklik': 30},
        {'id': 'k_x', 'ad': 'ölçüsüz'},
        'metin',
        null,
        {
          'id': 'k_garip',
          'ad': '  ',
          'genislik': 9999,
          'yukseklik': 1,
          'tur': 'bilinmeyen',
          'para': 'USD',
          'ogeler': [
            {'t': 'yazi', 'icerik': '{ad}', 'x': 'a', 'punto': -5, 'hiza': 'yok', 'satir': 7},
            {'t': 'gelecekteki_oge', 'x': 1},
            {'t': 'yazi'}, // içeriksiz
            {'t': 'barkod', 'modul': 99},
          ],
        },
        iyi,
      ]);
      expect(l.map((e) => e.id), ['k_iyi', 'k_garip']);
      final g = l[1];
      expect(g.ad, 'Adsız tasarım');
      expect(g.genislik, enBuyukOlcu);
      expect(g.yukseklik, enKucukOlcu);
      expect(g.tur, SablonTuru.normal);
      expect(g.para, '₺');
      expect(g.ogeler.length, 2);
      final y = g.ogeler[0] as YaziOge;
      expect((y.x, y.punto, y.hiza, y.satir), (0.0, 2.0, Hiza.sol, 1));
      expect((g.ogeler[1] as BarkodOge).modul, 2.0);
      expect(tasarimlarJsondan('liste değil'), isEmpty);
    });
  });

  group('otomatik yerleşim', () {
    final alanKumeleri = <Set<OtomatikAlan>>[
      {OtomatikAlan.ad, OtomatikAlan.fiyat, OtomatikAlan.barkod},
      OtomatikAlan.values.toSet(),
      {OtomatikAlan.fiyat},
      {OtomatikAlan.barkod},
      {OtomatikAlan.ad, OtomatikAlan.birimFiyat, OtomatikAlan.tarih, OtomatikAlan.mensei},
    ];
    final veriler = [
      ornekEtiketVerisi(),
      const EtiketVeri(ad: 'ÇOK UZUN ÜRÜN ADI ŞEKERSİZ BİTTER ÇİKOLATALI FINDIKLI GOFRET AİLE BOYU 12 Lİ PAKET 480 GR', fiyat: 12345678, barkod: 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'),
      const EtiketVeri(ad: 'X', fiyat: 0.5, barkod: ''),
    ];
    for (final (g, h) in [...hazirOlculer, (enKucukOlcu, enKucukOlcu), (200.0, 120.0)]) {
      test('${mmYaz(g)} × ${mmYaz(h)}', () {
        for (final a in alanKumeleri) {
          for (final metin in ['', 'Kampanya Ürünü {deneme}']) {
            final s = otomatikTasarim(id: 'k_t', ad: 't', genislik: g, yukseklik: h, alanlar: a, ozelMetin: metin);
            expect(s.ogeler.length, a.length + (metin.isEmpty ? 0 : 1));
            for (final v in veriler) {
              _tasmaYok(s, yerlesim(s, v, olcer: _olcer, firma: 'HALK MARKET'), _olcer);
            }
            // sabit metindeki süslü parantez yer tutucu sanılmaz
            if (metin.isNotEmpty) expect((s.ogeler.last as YaziOge).icerik, isNot(contains('{')));
          }
        }
      });
    }

    test('alan sırası ve içerikleri', () {
      final s = otomatikTasarim(id: 'k_t', ad: 't', genislik: 58, yukseklik: 40, alanlar: {OtomatikAlan.barkod, OtomatikAlan.ad, OtomatikAlan.fiyat});
      expect(s.ogeler.map((o) => o.runtimeType), [YaziOge, YaziOge, BarkodOge]);
      expect((s.ogeler[0] as YaziOge).icerik, '{ad}');
      expect((s.ogeler[1] as YaziOge).icerik, '{fiyat} {para}');
      expect(s.ogeler[0].y, lessThan(s.ogeler[1].y));
      expect(otomatikTasarim(id: 'k_b', ad: 'b', genislik: 58, yukseklik: 40, alanlar: {}).ogeler, isEmpty);
    });
  });

  test('ölçekleme: öğeler yeni boya orantılı, geri ölçeklenince yaklaşık aynı', () {
    for (final s0 in sablonlar) {
      final s = s0.kopya(id: 'k_${s0.id}');
      final b = olcekle(s, s.genislik * 1.5, s.yukseklik * 0.8);
      expect((b.genislik, b.yukseklik), (s.genislik * 1.5, s.yukseklik * 0.8));
      for (var i = 0; i < s.ogeler.length; i++) {
        expect(b.ogeler[i].x, closeTo(s.ogeler[i].x * 1.5, 0.06));
        expect(b.ogeler[i].h, closeTo(s.ogeler[i].h * 0.8, 0.06));
        expect(b.ogeler[i].x + b.ogeler[i].g, lessThanOrEqualTo(b.genislik + 0.1));
      }
      final geri = olcekle(b, s.genislik, s.yukseklik);
      for (var i = 0; i < s.ogeler.length; i++) {
        expect(geri.ogeler[i].x, closeTo(s.ogeler[i].x, 0.15), reason: s.id);
        expect(geri.ogeler[i].g, closeTo(s.ogeler[i].g, 0.15), reason: s.id);
      }
      // sınır dışı ölçü kırpılır
      expect(olcekle(s, 1, 1000).genislik, enKucukOlcu);
    }
  });

  test('denetim: taşan öğe, dar / alçak barkod, fiyatsız ve boş tasarım', () {
    for (final s in sablonlar) {
      expect(tasarimSorunlari(s).where((e) => e.contains('taşıyor')), isEmpty, reason: s.id);
    }
    const bos = EtiketSablonu(id: 'k_b', ad: 'b', dosya: '', genislik: 40, yukseklik: 30, ogeler: []);
    expect(tasarimSorunlari(bos), containsAll([contains('hiç öğe yok'), contains('fiyat yok')]));
    final s = bos.kopya(ogeler: const [
      YaziOge('{fiyat} {para}', x: 30, y: 2, g: 20, h: 5, punto: 10),
      BarkodOge(x: 2, y: 10, g: 15, h: 3, modul: 0.3),
    ]);
    final sorun = tasarimSorunlari(s);
    expect(sorun, contains(contains('1. Satış fiyatı etiketin dışına taşıyor')));
    expect(sorun, contains(contains('2. Barkod dar')));
    expect(sorun, contains(contains('2. Barkod alçak')));
    expect(sorun.where((e) => e.contains('fiyat yok')), isEmpty);
  });

  test('tasarımcı: yeni öğeler etikete sığar, adları anlaşılır', () {
    for (final (g, h) in [(enKucukOlcu, enKucukOlcu), (40.0, 30.0), (100.0, 50.0)]) {
      final s = EtiketSablonu(id: 'k', ad: 'k', dosya: '', genislik: g, yukseklik: h, ogeler: const []);
      final yeni = [
        for (final a in hazirAlanlar) hazirAlanOgesi(a, s),
        yeniBarkodOgesi(s),
        yeniKutuOgesi(s),
        yeniLogoOgesi(s),
      ].map((o) => sigdir(o, s));
      for (final o in yeni) {
        expect(o.x >= 0 && o.y >= 0 && o.x + o.g <= g + 1e-9 && o.y + o.h <= h + 1e-9, isTrue, reason: '${ogeAdi(o)} $g×$h');
      }
    }
    final s = sablonBul('raf_80x35_indirimli');
    expect(ogeAdi(s.ogeler.first), 'Ürün adı');
    expect(ogeAdi(const YaziOge('{fiyat} {para}', x: 0, y: 0, g: 1, h: 1, punto: 1, cizik: Cizik.capraz)), 'Eski fiyat (üstü çizili)');
    expect(ogeAdi(const YaziOge('Kampanya', x: 0, y: 0, g: 1, h: 1, punto: 1)), '“Kampanya”');
    expect(ean13Gecerli(ornekEtiketVerisi().barkod), isTrue);
  });

  group('yeni alanlar ve boş alan', () {
    test('ürün kartından kod / grup / birim / SKT', () {
      final v = etiketVerisi(const UrunModel(
          urunAdi: 'A', birimAdi: 'KG', satisFiyati: 10, kod: ' U-7 ', anaGrup: 'GIDA', sonKullanmaTarihi: '2027-03-05'));
      expect((v.kod, v.grup, v.birim, v.skt), ('U-7', 'GIDA', 'KG', '05.03.2027'));
      expect(etiketVerisi(const UrunModel(urunAdi: 'A', birimAdi: 'Adet', satisFiyati: 1, sonKullanmaTarihi: 'Mart 2027')).skt, 'Mart 2027');
      expect(doldur('{kod}|{grup}|{birim}|{skt}', v, para: '₺', mensei: '', firma: '', bugun: DateTime(2026)), 'U-7|GIDA|KG|05.03.2027');
    });

    test('alanı boş yazı başlığıyla basılmaz ("SKT:" kalmaz); sabit yazı ve tarih basılır', () {
      const s = EtiketSablonu(id: 'k', ad: 'k', dosya: '', genislik: 58, yukseklik: 40, ogeler: [
        YaziOge('SKT: {skt}', x: 1, y: 1, g: 50, h: 4, punto: 8),
        YaziOge('Kod: {kod} / {grup}', x: 1, y: 6, g: 50, h: 4, punto: 8),
        YaziOge('Kampanya', x: 1, y: 11, g: 50, h: 4, punto: 8),
        YaziOge('Tarih: {tarih}', x: 1, y: 16, g: 50, h: 4, punto: 8),
        YaziOge('Menşei: {mensei}', x: 1, y: 21, g: 50, h: 4, punto: 8),
      ]);
      String metin(EtiketVeri v, {String mensei = 'Türkiye'}) => yerlesim(s, v, olcer: _olcer, mensei: mensei, bugun: DateTime(2026, 11, 18))
          .whereType<YaziCizimi>()
          .expand((e) => e.satirlar)
          .map((e) => e.metin)
          .join('|');
      const bos = EtiketVeri(ad: 'A', fiyat: 1, barkod: '');
      expect(metin(bos), 'Kampanya|Tarih: 18.11.2026|Menşei: Türkiye');
      expect(metin(bos, mensei: ''), 'Kampanya|Tarih: 18.11.2026');
      const dolu = EtiketVeri(ad: 'A', fiyat: 1, barkod: '', kod: 'K1', skt: '01.01.2027');
      expect(metin(dolu), 'SKT: 01.01.2027|Kod: K1 /|Kampanya|Tarih: 18.11.2026|Menşei: Türkiye');
    });
  });

  test('eski serbest etiket kayıtları kendi tasarıma çevrilir', () {
    final t = eskiSablondanTasarim({
      'ad': 'Şarküteri',
      'barkod': true,
      'fiyat': true,
      'ad_': 1,
      'firma': true,
      'birimFiyatli': true,
      'anaGrup': false,
      'skt': true,
      'boyutIndex': 0,
      'ozelMetin': 'Taze',
      'fontOlcek': 1.2,
    }, 'k_goc_0')!;
    expect((t.id, t.ad, t.genislik, t.yukseklik), ('k_goc_0', 'Şarküteri', 40.0, 25.0));
    final icerik = t.ogeler.map((o) => o is YaziOge ? o.icerik : o.runtimeType.toString()).toList();
    expect(icerik, ['{firma}', '{ad}', '{fiyat} {para}', 'Birim fiyat: {birimFiyat}', 'BarkodOge', 'SKT: {skt}', 'Taze']);
    final ozel = eskiSablondanTasarim({'ad': 'Ö', 'ozelBoyutAktif': true, 'ozelGenislik': '60,5', 'ozelYukseklik': 'x'}, 'k')!;
    expect((ozel.genislik, ozel.yukseklik), (60.5, 30.0));
    expect(eskiSablondanTasarim({'ad': ''}, 'k'), isNull);
    expect(eskiSablondanTasarim({'boyutIndex': 1}, 'k'), isNull);
  });

  test('ZPL: grafik başlığı, bitler ters (1 = siyah), aynı etiketler tek ^PQ', () {
    // 16 nokta genişlik (2 bayt), 2 satır; TSPL bit 1 = beyaz
    final a = TsplResim(2, 2, Uint8List.fromList([0xFF, 0x00, 0x0F, 0xF0]));
    final b = TsplResim(2, 2, Uint8List.fromList([0xFF, 0xFF, 0xFF, 0xFF]));
    final z = zplResimIs([a, a, a, b]);
    final isler = z.trim().split('\n');
    expect(isler.length, 2);
    expect(isler[0], '^XA^CI28^PW16^LL2^LH0,0^FO0,0^GFA,4,4,2,00FFF00F^FS^PQ3,0,1,Y^XZ');
    expect(isler[1], contains('^GFA,4,4,2,00000000^FS^PQ1,0,1,Y^XZ'));
    expect(zplResimIs([]), isEmpty);
  });

  test('basım hazırlığı: adet kadar çoğaltılır, fiyatsız atlanır, indirimli tasarımda indirimsiz atlanır', () {
    final kalemler = [(_u(ad: 'A'), 3), (_u(ad: 'B', fiyat: 0), 2), (_u(ad: 'C'), 0), (_u(ad: 'D'), 5000)];
    final h = EtiketBaskiServisi.hazirla(kalemler, sablonBul('40x30'));
    expect(h.basilacak.map((e) => e.ad).where((a) => a == 'A').length, 3);
    expect(h.basilacak.where((e) => e.ad == 'C'), isEmpty);
    expect(h.basilacak.where((e) => e.ad == 'D').length, 999); // en fazla 999
    expect(h.denetim.atlanan, ['B — satış fiyatı yok']);
    final ind = EtiketBaskiServisi.hazirla([(_u(ad: 'A'), 1)], sablonBul('40x30_indirimli'));
    expect(ind.basilacak, isEmpty);
    expect(ind.denetim.atlanan.single, contains('indirimli fiyatı yok'));
  });

  group('ayarlar (kalıcı seçim)', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('ilk açılış: ilk hazır şablon; seçim ve kendi tasarım kalıcı; silinen seçiliyse hazıra döner', () async {
      expect((await EtiketAyarlari.seciliTasarim()).id, sablonlar.first.id);
      expect(await EtiketAyarlari.kendiTasarimlar(), isEmpty);

      final t = otomatikTasarim(id: EtiketAyarlari.yeniKimlik(), ad: 'Benim', genislik: 58, yukseklik: 40, alanlar: {OtomatikAlan.fiyat});
      var bildirim = 0;
      void dinle() => bildirim++;
      EtiketAyarlari.degisti.addListener(dinle);
      await EtiketAyarlari.tasarimKaydet(t);
      await EtiketAyarlari.tasarimSec(t.id);
      expect((await EtiketAyarlari.seciliTasarim()).ad, 'Benim');
      final tum = await EtiketAyarlari.tumTasarimlar();
      expect(tum.first.id, t.id);
      expect(tum.length, sablonlar.length + 1);

      // aynı kimlikle güncelleme: çoğalmaz
      await EtiketAyarlari.tasarimKaydet(t.kopya(ad: 'Benim 2'));
      expect((await EtiketAyarlari.kendiTasarimlar()).map((e) => e.ad), ['Benim 2']);
      expect((await EtiketAyarlari.seciliTasarim()).ad, 'Benim 2');

      await EtiketAyarlari.tasarimSil(t.id);
      expect((await EtiketAyarlari.seciliTasarim()).id, sablonlar.first.id);
      expect(bildirim, 4);
      EtiketAyarlari.degisti.removeListener(dinle);

      expect(() => EtiketAyarlari.tasarimKaydet(sablonlar.first), throwsArgumentError);
    });

    test('eski sürüm: serbest etiket seçimi ("") ilk hazıra, kayıtlı serbest şablonlar bir kez çevrilir', () async {
      SharedPreferences.setMockInitialValues({
        RafEtiketAyar.sablon: '',
        RafEtiketAyar.eskiSablonlar: jsonEncode([
          {'ad': 'Eski 1', 'boyutIndex': 2},
          {'ad': 'Eski 2', 'ozelBoyutAktif': true, 'ozelGenislik': '50', 'ozelYukseklik': '30'},
          {'bozuk': true},
        ]),
      });
      expect((await EtiketAyarlari.seciliTasarim()).id, sablonlar.first.id);
      final k = await EtiketAyarlari.kendiTasarimlar();
      expect(k.map((e) => (e.ad, e.genislik, e.yukseklik)), [('Eski 1', 80.0, 40.0), ('Eski 2', 50.0, 30.0)]);
      expect(k.every((e) => e.kendi), isTrue);
      // ikinci okumada tekrar eklenmez
      expect((await EtiketAyarlari.kendiTasarimlar()).length, 2);
    });

    test('bozuk kayıtlı tasarım listesi uygulamayı düşürmez', () async {
      SharedPreferences.setMockInitialValues({RafEtiketAyar.kendiTasarimlar: '{bozuk json', RafEtiketAyar.gocYapildi: true});
      expect(await EtiketAyarlari.kendiTasarimlar(), isEmpty);
      expect((await EtiketAyarlari.seciliTasarim()).id, sablonlar.first.id);
    });

    test('yazıcı ayarı kaydedilip aynen okunur (seçilen yazıcıyla devam)', () async {
      final ilk = await EtiketAyarlari.yaziciYukle();
      expect(ilk.yontem, Platform.isWindows ? RafBasmaYontemi.windows : RafBasmaYontemi.tspl);
      expect(ilk.windowsYazici, '');
      const a = EtiketYaziciAyari(
        yontem: RafBasmaYontemi.tspl,
        windowsYazici: 'Xprinter XP-490B',
        tsplAdres: ' 192.168.1.35:9100 ',
        tspl: TsplAyar(bosluk: 3, ters: true, koyuluk: 10),
        kagit: RafEtiketKagidi.a4,
        mensei: 'Almanya',
      );
      await EtiketAyarlari.yaziciKaydet(a);
      final b = await EtiketAyarlari.yaziciYukle();
      expect((b.yontem, b.windowsYazici, b.tsplAdres, b.tspl.bosluk, b.tspl.ters, b.tspl.koyuluk, b.kagit, b.mensei),
          (RafBasmaYontemi.tspl, 'Xprinter XP-490B', '192.168.1.35:9100', 3.0, true, 10, RafEtiketKagidi.a4, 'Almanya'));
      expect(b.tsplAgda, isTrue);
      expect(b.etkinKagit, RafEtiketKagidi.rulo); // A4 yalnız Windows yazıcısıyla
      expect(b.kopya(yontem: RafBasmaYontemi.windows).etkinKagit, RafEtiketKagidi.a4);
      expect(b.ozet(), contains('192.168.1.35'));
      expect(b.kopya(yontem: RafBasmaYontemi.windows).ozet(), 'Windows: Xprinter XP-490B · A4');
      await EtiketAyarlari.yaziciKaydet(b.kopya(tspl: const TsplAyar(bosluk: 2)));
      expect((await EtiketAyarlari.yaziciYukle()).tspl.koyuluk, isNull);
    });
  });

  test('kendi tasarımın PDF\'i (gerçek yazı tipleriyle taşma yok)', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final klasor = Platform.environment['ETIKET_TASARIM_CIKTI'];
    final y = await RafEtiketYazilari.yukle();
    final veriler = [ornekEtiketVerisi(), etiketVerisi(_u(ad: 'ÇOK UZUN ÜRÜN ADI ŞEKERSİZ BİTTER ÇİKOLATALI FINDIKLI GOFRET 480 GR'))];
    for (final (g, h) in hazirOlculer) {
      final s = otomatikTasarim(id: 'k', ad: 'k', genislik: g, yukseklik: h, alanlar: OtomatikAlan.values.toSet(), ozelMetin: 'Kampanya');
      for (final v in veriler) {
        _tasmaYok(s, yerlesim(s, v, olcer: y, firma: 'HALK MARKET'), y);
      }
      final pdf = await RafEtiketPdfServisi.pdf(veriler, s, yazilar: y, firma: 'HALK MARKET');
      expect(pdf.length, greaterThan(1000));
      if (klasor != null) File('$klasor/otomatik_${mmYaz(g)}x${mmYaz(h)}.pdf').writeAsBytesSync(pdf);
    }
  });
}
