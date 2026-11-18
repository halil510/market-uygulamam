// lib/cekirdek/etiket/etiket_tasarimi.dart
//
// Kullanıcının KENDİ etiket tasarımları (hazır BarTender şablonlarının yanında). SAF Dart, testli:
//   • tasarım ↔ JSON (cihazda saklanır; bozuk kayıt uygulamayı düşürmez, atlanır),
//   • seçilen alanlardan otomatik yerleşim ("Yeni tasarım" ve eski serbest-etiket ayarlarının göçü),
//   • etiket boyu değişince öğeleri orantılı ölçekleme,
//   • tasarım denetimi (etiket dışına taşan, çok küçük öğe, dar barkod alanı),
//   • tasarımcının öğe menüsü (hazır alanlar) ve önizleme için örnek ürün.
// Çizim / yerleşim kuralları hazır şablonlarla AYNI (raf_etiket_sablonlari.dart → yerlesim).

import 'dart:math' as math;

import '../utils/para_utils.dart';
import 'raf_etiket_sablonlari.dart';

// ───────────────────────── JSON ─────────────────────────

const _surum = 1;

double _sayi(Object? v, double varsayilan, {double min = -1e9, double max = 1e9}) {
  final d = v is num ? v.toDouble() : varsayilan;
  if (d.isNaN || d.isInfinite) return varsayilan;
  return d.clamp(min, max).toDouble();
}

T _enumOku<T extends Enum>(List<T> degerler, Object? ad, T varsayilan) =>
    degerler.where((e) => e.name == ad).firstOrNull ?? varsayilan;

Map<String, dynamic> ogeJson(Oge o) => switch (o) {
      YaziOge() => {
          't': 'yazi',
          'icerik': o.icerik,
          'x': o.x,
          'y': o.y,
          'g': o.g,
          'h': o.h,
          'punto': o.punto,
          'kalin': o.kalin,
          'yazi': o.yazi.name,
          'hiza': o.hiza.name,
          'ustten': o.ustten,
          'satir': o.satir,
          'enKucuk': o.enKucuk,
          'cizik': o.cizik.name,
          'altiCizili': o.altiCizili,
          'dikey': o.dikey,
          if (o.genis != 1) 'genis': o.genis,
          if (o.sikistir) 'sikistir': true,
        },
      BarkodOge() => {
          't': 'barkod',
          'x': o.x,
          'y': o.y,
          'g': o.g,
          'h': o.h,
          'modul': o.modul,
          'yaziPunto': o.yaziPunto,
          'kalinYazi': o.kalinYazi,
        },
      KutuOge() => {'t': 'kutu', 'x': o.x, 'y': o.y, 'g': o.g, 'h': o.h, 'kalinlik': o.kalinlik},
      LogoOge() => {'t': 'logo', 'x': o.x, 'y': o.y, 'g': o.g, 'h': o.h, 'dikey': o.dikey},
    };

/// JSON'dan öğe; tanınmayan tür → null (yeni sürümde eklenmiş öğe eski uygulamayı bozmasın).
Oge? ogeJsondan(Map<String, dynamic> j) {
  final x = _sayi(j['x'], 0, min: -500, max: 500), y = _sayi(j['y'], 0, min: -500, max: 500);
  final g = _sayi(j['g'], 10, min: 0.5, max: 500), h = _sayi(j['h'], 5, min: 0.5, max: 500);
  switch (j['t']) {
    case 'yazi':
      final icerik = j['icerik'];
      if (icerik is! String) return null;
      return YaziOge(
        icerik,
        x: x,
        y: y,
        g: g,
        h: h,
        punto: _sayi(j['punto'], 10, min: 2, max: 200),
        kalin: j['kalin'] != false,
        yazi: _enumOku(YaziTipi.values, j['yazi'], YaziTipi.arial),
        hiza: _enumOku(Hiza.values, j['hiza'], Hiza.sol),
        ustten: j['ustten'] == true,
        satir: j['satir'] == 2 ? 2 : 1,
        enKucuk: _sayi(j['enKucuk'], 0.6, min: 0.2, max: 1),
        cizik: _enumOku(Cizik.values, j['cizik'], Cizik.yok),
        altiCizili: j['altiCizili'] == true,
        dikey: j['dikey'] == true,
        genis: _sayi(j['genis'], 1, min: 0.3, max: 3),
        sikistir: j['sikistir'] == true,
      );
    case 'barkod':
      return BarkodOge(
        x: x,
        y: y,
        g: g,
        h: h,
        modul: _sayi(j['modul'], 0.33, min: 0.1, max: 2),
        yaziPunto: _sayi(j['yaziPunto'], 8, min: 0, max: 40),
        kalinYazi: j['kalinYazi'] == true,
      );
    case 'kutu':
      return KutuOge(x: x, y: y, g: g, h: h, kalinlik: _sayi(j['kalinlik'], 0.35, min: 0.1, max: 5));
    case 'logo':
      return LogoOge(x: x, y: y, g: g, h: h, dikey: j['dikey'] == true);
  }
  return null;
}

Map<String, dynamic> tasarimJson(EtiketSablonu s) => {
      'v': _surum,
      'id': s.id,
      'ad': s.ad,
      'dosya': s.dosya,
      'genislik': s.genislik,
      'yukseklik': s.yukseklik,
      'tur': s.tur.name,
      'para': s.para,
      'ogeler': [for (final o in s.ogeler) ogeJson(o)],
    };

/// JSON'dan tasarım. Kimliği / adı / ölçüsü olmayan kayıt → [FormatException].
EtiketSablonu tasarimJsondan(Map<String, dynamic> j) {
  final id = j['id'], ad = j['ad'];
  if (id is! String || id.isEmpty) throw const FormatException('Tasarım kimliği yok');
  if (ad is! String) throw const FormatException('Tasarım adı yok');
  if (j['genislik'] is! num || j['yukseklik'] is! num) throw const FormatException('Etiket ölçüsü yok');
  final ogeler = <Oge>[];
  final liste = j['ogeler'];
  if (liste is List) {
    for (final e in liste) {
      if (e is Map) {
        final o = ogeJsondan(e.cast<String, dynamic>());
        if (o != null) ogeler.add(o);
      }
    }
  }
  return EtiketSablonu(
    id: id,
    ad: ad.trim().isEmpty ? 'Adsız tasarım' : ad.trim(),
    dosya: j['dosya'] is String ? j['dosya'] as String : '',
    genislik: _sayi(j['genislik'], 80, min: enKucukOlcu, max: enBuyukOlcu),
    yukseklik: _sayi(j['yukseklik'], 35, min: enKucukOlcu, max: enBuyukOlcu),
    tur: _enumOku(SablonTuru.values, j['tur'], SablonTuru.normal),
    para: j['para'] == 'TL' ? 'TL' : '₺',
    ogeler: ogeler,
  );
}

/// Bozuk kayıtları atlayarak liste okur (biri bozulsa diğerleri kaybolmaz).
List<EtiketSablonu> tasarimlarJsondan(Object? liste) {
  if (liste is! List) return const [];
  final sonuc = <EtiketSablonu>[];
  final gorulen = <String>{};
  for (final e in liste) {
    if (e is! Map) continue;
    try {
      final t = tasarimJsondan(e.cast<String, dynamic>());
      if (gorulen.add(t.id)) sonuc.add(t);
    } on FormatException {
      continue;
    }
  }
  return sonuc;
}

// ───────────────────────── Ölçüler ─────────────────────────

const enKucukOlcu = 15.0; // mm
const enBuyukOlcu = 200.0; // mm

/// Hazır ölçüler (genişlik × yükseklik, mm).
const hazirOlculer = <(double, double)>[
  (40, 30),
  (40, 25),
  (50, 30),
  (58, 30),
  (58, 40),
  (60, 40),
  (80, 35),
  (80, 40),
  (100, 50),
];

String mmYaz(double d) {
  final r = (d * 10).roundToDouble() / 10;
  return r == r.roundToDouble() ? r.toInt().toString() : r.toStringAsFixed(1).replaceAll('.', ',');
}

/// 0,1 mm'ye yuvarlar (tasarımcıda konumlar bu hassasiyette).
double mm1(double v) => (v * 10).roundToDouble() / 10;

// ───────────────────────── Otomatik yerleşim ─────────────────────────

/// Otomatik tasarımda kullanılabilen alanlar (yukarıdan aşağı bu sırayla dizilir).
enum OtomatikAlan { firma, ad, grup, fiyat, birimFiyat, barkod, kod, skt, tarih, mensei }

const otomatikAlanAdlari = {
  OtomatikAlan.firma: 'Firma adı',
  OtomatikAlan.ad: 'Ürün adı',
  OtomatikAlan.grup: 'Ana grup',
  OtomatikAlan.fiyat: 'Satış fiyatı',
  OtomatikAlan.birimFiyat: 'Birim fiyat (KG / LT)',
  OtomatikAlan.barkod: 'Barkod',
  OtomatikAlan.kod: 'Ürün kodu',
  OtomatikAlan.skt: 'Son kullanma tarihi',
  OtomatikAlan.tarih: 'Fiyat tarihi',
  OtomatikAlan.mensei: 'Menşei',
};

/// Seçilen alanları etikete alt alta, yükseklik paylarına göre yerleştirir. [olcek] yazıları büyütür / küçültür.
/// [ozelMetin] boş değilse en alta sabit yazı olarak eklenir.
EtiketSablonu otomatikTasarim({
  required String id,
  required String ad,
  required double genislik,
  required double yukseklik,
  required Set<OtomatikAlan> alanlar,
  String ozelMetin = '',
  double olcek = 1.0,
  String para = '₺',
}) {
  final g = genislik.clamp(enKucukOlcu, enBuyukOlcu).toDouble();
  final h = yukseklik.clamp(enKucukOlcu, enBuyukOlcu).toDouble();
  final kenar = math.max(1.0, math.min(g, h) * 0.04);
  final sira = [for (final a in OtomatikAlan.values) if (alanlar.contains(a)) a];
  final metin = ozelMetin.trim();
  // yükseklik payları
  double pay(OtomatikAlan a) => switch (a) {
        OtomatikAlan.ad => 2.6,
        OtomatikAlan.fiyat => 2.6,
        OtomatikAlan.barkod => 3.6,
        OtomatikAlan.firma => 1.2,
        _ => 1.0,
      };
  final toplamPay = sira.fold<double>(0, (t, a) => t + pay(a)) + (metin.isEmpty ? 0 : 1.0);
  final ogeler = <Oge>[];
  if (toplamPay > 0) {
    final kullanilir = h - 2 * kenar;
    final birim = kullanilir / toplamPay;
    var y = kenar;
    final w = g - 2 * kenar;
    // satır yüksekliğinden punto: yazı kutunun ~%80'i (ascent+descent ≈ 1,12 em)
    double pt(double kutu, {double carpan = 1}) => (kutu / (1.12 * ptMm) * carpan * olcek).clamp(3.0, 72.0).toDouble();
    for (final a in sira) {
      final kh = birim * pay(a);
      switch (a) {
        case OtomatikAlan.ad:
          ogeler.add(YaziOge('{ad}', x: kenar, y: y, g: w, h: kh, punto: pt(kh / 2), yazi: YaziTipi.arialNarrow, hiza: Hiza.orta, ustten: true, satir: 2));
        case OtomatikAlan.fiyat:
          ogeler.add(YaziOge('{fiyat} {para}', x: kenar, y: y, g: w, h: kh, punto: pt(kh), hiza: Hiza.orta));
        case OtomatikAlan.barkod:
          final yaziPt = (kh * 0.22 / ptMm).clamp(5.0, 10.0).toDouble();
          ogeler.add(BarkodOge(x: kenar, y: y, g: w, h: kh, modul: math.min(0.375, w / 95), yaziPunto: yaziPt));
        case OtomatikAlan.firma:
          ogeler.add(YaziOge('{firma}', x: kenar, y: y, g: w, h: kh, punto: pt(kh), hiza: Hiza.orta));
        case OtomatikAlan.birimFiyat:
          ogeler.add(YaziOge('Birim fiyat: {birimFiyat}', x: kenar, y: y, g: w, h: kh, punto: pt(kh, carpan: 0.9), kalin: false, hiza: Hiza.orta));
        case OtomatikAlan.grup:
          ogeler.add(YaziOge('{grup}', x: kenar, y: y, g: w, h: kh, punto: pt(kh, carpan: 0.9), kalin: false, hiza: Hiza.orta));
        case OtomatikAlan.kod:
          ogeler.add(YaziOge('Kod: {kod}', x: kenar, y: y, g: w, h: kh, punto: pt(kh, carpan: 0.9), kalin: false, hiza: Hiza.orta));
        case OtomatikAlan.skt:
          ogeler.add(YaziOge('SKT: {skt}', x: kenar, y: y, g: w, h: kh, punto: pt(kh, carpan: 0.9), kalin: false, hiza: Hiza.orta));
        case OtomatikAlan.tarih:
          ogeler.add(YaziOge('Tarih: {tarih}', x: kenar, y: y, g: w, h: kh, punto: pt(kh, carpan: 0.9), kalin: false, hiza: Hiza.orta));
        case OtomatikAlan.mensei:
          ogeler.add(YaziOge('Menşei: {mensei}', x: kenar, y: y, g: w, h: kh, punto: pt(kh, carpan: 0.9), kalin: false, hiza: Hiza.orta));
      }
      y += kh;
    }
    if (metin.isNotEmpty) {
      ogeler.add(YaziOge(metin.replaceAll('{', '(').replaceAll('}', ')'), x: kenar, y: y, g: w, h: birim, punto: pt(birim, carpan: 0.9), kalin: false, hiza: Hiza.orta));
    }
  }
  return EtiketSablonu(
    id: id,
    ad: ad,
    dosya: '',
    genislik: g,
    yukseklik: h,
    para: para,
    ogeler: [for (final o in ogeler) _yuvarlaOge(o)],
  );
}

Oge _yuvarlaOge(Oge o) => o.konumla(x: mm1(o.x), y: mm1(o.y), g: mm1(o.g), h: mm1(o.h));

// ───────────────────────── Ölçekleme ─────────────────────────

/// Etiket boyu değişince öğeleri orantılı taşır / büyütür. Yazı puntosu ve barkod çubuğu küçük orana göre.
EtiketSablonu olcekle(EtiketSablonu s, double genislik, double yukseklik) {
  final g = genislik.clamp(enKucukOlcu, enBuyukOlcu).toDouble();
  final h = yukseklik.clamp(enKucukOlcu, enBuyukOlcu).toDouble();
  final sx = g / s.genislik, sy = h / s.yukseklik;
  final sp = math.min(sx, sy);
  Oge yeni(Oge o) {
    final k = o.konumla(x: mm1(o.x * sx), y: mm1(o.y * sy), g: mm1(o.g * sx), h: mm1(o.h * sy));
    return switch (k) {
      YaziOge() => k.kopya(punto: (k.punto * sp * 10).roundToDouble() / 10),
      BarkodOge() => k.kopya(modul: k.modul * sx, yaziPunto: (k.yaziPunto * sp * 10).roundToDouble() / 10),
      _ => k,
    };
  }

  return s.kopya(genislik: g, yukseklik: h, ogeler: [for (final o in s.ogeler) yeni(o)]);
}

// ───────────────────────── Denetim ─────────────────────────

/// Tasarımdaki sorunlar (kaydetmeyi engellemez; tasarımcıda uyarı olarak gösterilir).
List<String> tasarimSorunlari(EtiketSablonu s) {
  final sorun = <String>[];
  if (s.ogeler.isEmpty) sorun.add('Etikette hiç öğe yok — boş etiket basılır.');
  for (var i = 0; i < s.ogeler.length; i++) {
    final o = s.ogeler[i];
    final ad = '${i + 1}. ${ogeAdi(o)}';
    const pay = 0.05;
    if (o.x < -pay || o.y < -pay || o.x + o.g > s.genislik + pay || o.y + o.h > s.yukseklik + pay) {
      sorun.add('$ad etiketin dışına taşıyor (taşan kısım basılmaz).');
    }
    if (o is YaziOge && o.h < 1.2) sorun.add('$ad çok alçak — yazı okunmayacak kadar küçük çıkar.');
    if (o is BarkodOge) {
      // EAN-13: 95 modül; 2 noktalık (0,25 mm) çubuktan dar alan okunmaz.
      if (o.g < 95 * 0.25 - 0.01) sorun.add('$ad dar (${mmYaz(o.g)} mm) — EAN-13 için en az 24 mm önerilir, okuyucu okumayabilir.');
      if (o.h < 5) sorun.add('$ad alçak (${mmYaz(o.h)} mm) — en az 5 mm önerilir.');
    }
  }
  if (!s.ogeler.any((o) => o is YaziOge && (o.icerik.contains('{fiyat}') || o.icerik.contains('{indirimliFiyat}')))) {
    sorun.add('Etikette fiyat yok.');
  }
  return sorun;
}

// ───────────────────────── Tasarımcı öğe menüsü ─────────────────────────

/// Tasarımcıda "Öğe ekle" menüsündeki hazır yazı alanları.
class HazirAlan {
  final String ad;
  final String icerik;
  final bool kalin;
  final Cizik cizik;
  final double payH; // etiket yüksekliğinin kaçta kaçı (başlangıç kutusu)
  const HazirAlan(this.ad, this.icerik, {this.kalin = true, this.cizik = Cizik.yok, this.payH = 0.16});
}

const hazirAlanlar = <HazirAlan>[
  HazirAlan('Ürün adı', '{ad}', payH: 0.26),
  HazirAlan('Satış fiyatı', '{fiyat} {para}', payH: 0.24),
  HazirAlan('İndirimli fiyat', '{indirimliFiyat} {para}', payH: 0.24),
  HazirAlan('Eski fiyat (üstü çizili)', '{fiyat} {para}', cizik: Cizik.capraz),
  HazirAlan('İndirim oranı', '% {oran}'),
  HazirAlan('Birim fiyat (KG / LT)', '{birimFiyat}', payH: 0.12),
  HazirAlan('Barkod numarası', '{barkod}', kalin: false, payH: 0.1),
  HazirAlan('Ürün kodu', 'Kod: {kod}', kalin: false, payH: 0.1),
  HazirAlan('Ana grup', '{grup}', kalin: false, payH: 0.1),
  HazirAlan('Birim', '{birim}', kalin: false, payH: 0.1),
  HazirAlan('Son kullanma tarihi', 'SKT: {skt}', kalin: false, payH: 0.1),
  HazirAlan('Fiyat tarihi', 'Tarih: {tarih}', kalin: false, payH: 0.08),
  HazirAlan('Menşei', 'Menşei: {mensei}', kalin: false, payH: 0.08),
  HazirAlan('Firma adı', '{firma}', payH: 0.12),
];

/// Yazı içeriğinde kullanılabilecek yer tutucular (tasarımcıda "Alan ekle" düğmeleri).
const yerTutucular = <(String, String)>[
  ('{ad}', 'Ürün adı'),
  ('{fiyat}', 'Fiyat'),
  ('{indirimliFiyat}', 'İnd. fiyat'),
  ('{oran}', 'İnd. %'),
  ('{birimFiyat}', 'Birim fiyat'),
  ('{para}', '₺ / TL'),
  ('{barkod}', 'Barkod no'),
  ('{kod}', 'Ürün kodu'),
  ('{grup}', 'Grup'),
  ('{birim}', 'Birim'),
  ('{skt}', 'SKT'),
  ('{tarih}', 'Tarih'),
  ('{mensei}', 'Menşei'),
  ('{firma}', 'Firma'),
];

/// Öğenin listede görünen adı.
String ogeAdi(Oge o) {
  switch (o) {
    case BarkodOge():
      return 'Barkod';
    case KutuOge():
      return 'Çerçeve';
    case LogoOge():
      return 'Yerli Üretim logosu';
    case YaziOge():
      for (final a in hazirAlanlar) {
        if (a.icerik == o.icerik && a.cizik == o.cizik) return a.ad;
      }
      // yer tutucular okunur adlarıyla: "Menşei :{mensei}" → "Menşei :[Menşei]"
      final adlar = {for (final (yt, ad) in yerTutucular) yt: ad};
      final t = o.icerik.trim().replaceAllMapped(RegExp(r'\{\w+\}'), (m) => '[${adlar[m.group(0)] ?? m.group(0)}]');
      return t.isEmpty ? 'Yazı' : (t.length > 28 ? '“${t.substring(0, 28)}…”' : '“$t”');
  }
}

/// Yeni öğenin başlangıç kutusu: etiketin ortasında, genişliğin ~%80'i.
YaziOge hazirAlanOgesi(HazirAlan a, EtiketSablonu s) {
  final h = mm1(math.max(2.5, s.yukseklik * a.payH));
  final g = mm1(s.genislik * 0.8);
  return YaziOge(
    a.icerik,
    x: mm1((s.genislik - g) / 2),
    y: mm1((s.yukseklik - h) / 2),
    g: g,
    h: h,
    punto: ((h / (1.12 * ptMm)) * 10).roundToDouble() / 10,
    kalin: a.kalin,
    cizik: a.cizik,
    hiza: Hiza.orta,
    satir: a.icerik == '{ad}' ? 2 : 1,
    ustten: a.icerik == '{ad}',
    yazi: a.icerik == '{ad}' ? YaziTipi.arialNarrow : YaziTipi.arial,
  );
}

BarkodOge yeniBarkodOgesi(EtiketSablonu s) {
  final g = mm1(math.min(s.genislik * 0.8, 40));
  final h = mm1(math.max(6, s.yukseklik * 0.32));
  return BarkodOge(x: mm1((s.genislik - g) / 2), y: mm1((s.yukseklik - h) / 2), g: g, h: h, modul: 0.33, yaziPunto: 8);
}

KutuOge yeniKutuOgesi(EtiketSablonu s) =>
    KutuOge(x: 1, y: 1, g: mm1(s.genislik - 2), h: mm1(s.yukseklik - 2), kalinlik: 0.3);

LogoOge yeniLogoOgesi(EtiketSablonu s) {
  final g = mm1(math.min(14, s.genislik * 0.3));
  return LogoOge(x: mm1(s.genislik - g - 1), y: 1, g: g, h: mm1(g * 0.4));
}

/// Yeni öğeyi etiketin içine sığdırır (küçük etikette taşmasın).
Oge sigdir(Oge o, EtiketSablonu s) {
  final g = math.min(o.g, s.genislik), h = math.min(o.h, s.yukseklik);
  final x = o.x.clamp(0.0, s.genislik - g).toDouble();
  final y = o.y.clamp(0.0, s.yukseklik - h).toDouble();
  return o.konumla(x: mm1(x), y: mm1(y), g: mm1(g), h: mm1(h));
}

// ───────────────────────── Örnek ürün ─────────────────────────

/// Sağlama hanesi doğru EAN-13 (12 haneden).
String ean13Tamamla(String on12) {
  var t = 0;
  for (var i = 0; i < 12; i++) {
    t += int.parse(on12[i]) * (i.isEven ? 1 : 3);
  }
  return '$on12${(10 - t % 10) % 10}';
}

/// Tasarımcı / ayarlar önizlemesi için örnek ürün (gerçek ürün seçilmemişse).
EtiketVeri ornekEtiketVerisi() => EtiketVeri(
      ad: 'ÖRNEK ÜRÜN ADI ÇİKOLATALI GOFRET 500 GR',
      fiyat: 49.90,
      barkod: ean13Tamamla('869123456789'),
      indirimliFiyat: 39.90,
      birimFiyat: const BirimFiyat(99.80, 'KG'),
      kod: 'U-1024',
      grup: 'GIDA',
      birim: 'Adet',
      skt: '31.12.2027',
    );

// ───────────────────────── Eski serbest etiket ayarlarının göçü ─────────────────────────

const _eskiBoyutlar = <(double, double)>[(40, 25), (58, 30), (80, 40), (100, 50)];

/// Eski "Kayıtlı Şablonlarım" kaydını (anahtarlar + boyut) kendi tasarıma çevirir; çevrilemezse null.
EtiketSablonu? eskiSablondanTasarim(Map<String, dynamic> a, String id) {
  final ad = a['ad'];
  if (ad is! String || ad.trim().isEmpty) return null;
  double g, h;
  if (a['ozelBoyutAktif'] == true) {
    g = _metinSayi(a['ozelGenislik']) ?? 58;
    h = _metinSayi(a['ozelYukseklik']) ?? 30;
  } else {
    final bi = a['boyutIndex'];
    final b = bi is int && bi >= 0 && bi < _eskiBoyutlar.length ? _eskiBoyutlar[bi] : _eskiBoyutlar[1];
    (g, h) = b;
  }
  bool ac(String k, bool v) => a[k] is bool ? a[k] as bool : v;
  final alanlar = <OtomatikAlan>{
    if (ac('firma', false)) OtomatikAlan.firma,
    if (ac('ad', true)) OtomatikAlan.ad,
    if (ac('anaGrup', false)) OtomatikAlan.grup,
    if (ac('fiyat', true)) OtomatikAlan.fiyat,
    if (ac('fiyat', true) && ac('birimFiyatli', false)) OtomatikAlan.birimFiyat,
    if (ac('barkod', true)) OtomatikAlan.barkod,
    if (ac('skt', false)) OtomatikAlan.skt,
  };
  final olcek = a['fontOlcek'] is num ? (a['fontOlcek'] as num).toDouble().clamp(0.7, 1.6).toDouble() : 1.0;
  return otomatikTasarim(
    id: id,
    ad: ad.trim(),
    genislik: g,
    yukseklik: h,
    alanlar: alanlar,
    ozelMetin: a['ozelMetin'] is String ? a['ozelMetin'] as String : '',
    olcek: olcek,
  );
}

double? _metinSayi(Object? v) {
  if (v is num) return v.toDouble();
  if (v is! String) return null;
  return ParaUtils.sayiCoz(v);
}
