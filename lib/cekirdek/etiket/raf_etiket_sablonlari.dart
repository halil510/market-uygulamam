// lib/cekirdek/etiket/raf_etiket_sablonlari.dart
//
// Raf etiketi şablonları — işletmenin BarTender şablonlarının (Raf_80x35, BİRİMFİYATLI, Türkiye / Yerli Üretim,
// KARTON, İNDİRİMLİ, Fiş, 40x30, 40x30 İndirimli) uygulamadaki karşılığı. Ölçüler BarTender nesne konumlarından ve
// .btw dosyalarının içindeki önizlemelerden milimetre olarak alındı (Ürün Güncelleme uygulamasıyla AYNI tanımlar).
//
// SAF Dart (Flutter / pdf yok): şablonlar, ürün → etiket verisi, birim fiyat ve YERLEŞİM (yazıyı kutuya sığdırma,
// satır bölme, barkod genişliği). Çizimi RafEtiketPdfServisi yapar.

import 'dart:math' as math;

import 'package:intl/intl.dart';

import '../../modeller/urun_model.dart';
import '../utils/para_utils.dart';

// ───────────────────────── Küçük yardımcılar ─────────────────────────

final _tarihBicim = DateFormat('dd.MM.yyyy');

/// 1234.5 → "1.234,50" (ParaUtils ile aynı biçim, simgesiz)
String paraYaz(double? v) => v == null ? '' : ParaUtils.formatla(v, simge: '');

String _buyukHarf(String s) => s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();

bool _rakamMi(String s) => s.isNotEmpty && RegExp(r'^\d+$').hasMatch(s);

double _yuvarla(double x, int basamak) {
  final k = math.pow(10, basamak).toDouble();
  return (x * k).roundToDouble() / k;
}

DateTime _gun([DateTime? t]) {
  final n = t ?? DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

// ───────────────────────── Etiket verisi ─────────────────────────

/// Bir ürünün etikete basılacak bilgileri.
class EtiketVeri {
  final String ad;
  final double? fiyat; // satış fiyatı (KDV dahil)
  final String barkod;
  final double? indirimliFiyat; // yalnız satıştan küçük ve > 0 ise dolu
  final BirimFiyat? birimFiyat;
  final DateTime? tarih; // fiyat güncelleme tarihi
  final String? mensei; // ürün kartındaki menşei (boşsa etiket ayarındaki)
  const EtiketVeri({
    required this.ad,
    required this.fiyat,
    required this.barkod,
    this.indirimliFiyat,
    this.birimFiyat,
    this.tarih,
    this.mensei,
  });

  /// İndirim oranı (%); indirim yoksa null.
  double? get indirimOrani {
    final f = fiyat, i = indirimliFiyat;
    if (f == null || i == null || f <= 0) return null;
    return _yuvarla((f - i) / f * 100, 3);
  }
}

/// Birim fiyat: 1 KG / 1 LT başına fiyat.
class BirimFiyat {
  final double deger;
  final String birim; // 'KG' | 'LT'
  const BirimFiyat(this.deger, this.birim);
  @override
  bool operator ==(Object other) => other is BirimFiyat && (other.deger - deger).abs() < 1e-9 && other.birim == birim;
  @override
  int get hashCode => Object.hash(deger, birim);
  @override
  String toString() => '$deger/$birim';
}

/// Ürün adındaki miktar: KG veya LT cinsinden.
class Miktar {
  final double deger;
  final String birim; // 'KG' | 'LT'
  const Miktar(this.deger, this.birim);
  @override
  bool operator ==(Object other) => other is Miktar && (other.deger - deger).abs() < 1e-9 && other.birim == birim;
  @override
  int get hashCode => Object.hash(deger, birim);
  @override
  String toString() => '$deger $birim';
}

// sayı (çarpanlı olabilir) + birim; birimden sonra harf gelmemeli ("40G" evet, "4GOLD" hayır).
final _miktarDeseni = RegExp(
  r'(?:(\d{1,3})\s*[X\*]\s*)?(\d+(?:[.,]\d+)?)\s*(KGR|KG|KİLO|KILO|GRAM|GRM|GR|G|LİTRE|LITRE|LT|L|ML|CL|CC)(?![A-ZÇĞİÖŞÜ])',
);

// rakamdan sonra adet / paket sözcüğü: "3 MP", "4AD", "24ADT", "6KT", "24PCS", "6BOX", "12 Lİ", "10'LU"
final _adetDeseni = RegExp(r"\d\s*'?\s*(MP|AD|ADT|ADET|PCS|PC|PK|PAKET|KT|KOLİ|KOLI|BOX|STKT|Lİ|LI|LU|LÜ)(?![A-ZÇĞİÖŞÜ])");

/// Ad içindeki miktarı bulur. Belirsizse (farklı miktarlar, adet / paket bilgisi) ya da yoksa null — TAHMİN ETMEZ.
/// "ABC ÇAMASIR SUYU 4KG" → 4 KG;  "4X500 GR" → 2 KG;  "SÜT 1,5 LT" → 1.5 LT;  "750ML" → 0.75 LT.
Miktar? miktarCoz(String ad) {
  final s = _buyukHarf(ad);
  // Adet / paket bilgisi varsa ("44 GR 3 MP", "11G 4AD") fiyatın tek ürünün mü paketin mi olduğu bilinemez
  // → birim fiyat çıkarılmaz (yanlış birim fiyat basılmasın; ürün kartına Ağırlık girilir).
  if (_adetDeseni.hasMatch(s)) return null;
  final bulunan = <Miktar>{};
  for (final m in _miktarDeseni.allMatches(s)) {
    // önünde harf varsa (ör. "B12G") kelime başı değil → atla
    if (m.start > 0 && RegExp(r'[A-ZÇĞİÖŞÜ]').hasMatch(s[m.start - 1])) continue;
    final carpan = m.group(1) == null ? 1 : int.parse(m.group(1)!);
    final b = m.group(3)!;
    var sayiMetni = m.group(2)!;
    // gram / ml'de "1.000" binlik ayırıcıdır (1 g değil 1000 g)
    if (const {'GR', 'G', 'GRM', 'GRAM', 'ML', 'CC'}.contains(b) && RegExp(r'^\d{1,3}[.,]\d{3}$').hasMatch(sayiMetni)) {
      sayiMetni = sayiMetni.replaceAll(RegExp(r'[.,]'), '');
    }
    // desen yalnız "rakam[ayırıcı rakam]" verir (kullanıcı girdisi değil) → doğrudan çözülür
    final sayi = double.tryParse(sayiMetni.replaceAll(',', '.'));
    if (sayi == null || sayi <= 0 || carpan <= 0) continue;
    final (oran, birim) = switch (b) {
      'KG' || 'KGR' || 'KİLO' || 'KILO' => (1.0, 'KG'),
      'GR' || 'G' || 'GRM' || 'GRAM' => (0.001, 'KG'),
      'LT' || 'L' || 'LİTRE' || 'LITRE' => (1.0, 'LT'),
      'ML' || 'CC' => (0.001, 'LT'),
      'CL' => (0.01, 'LT'),
      _ => (0.0, ''),
    };
    if (oran == 0) continue;
    final d = _yuvarla(carpan * sayi * oran, 6);
    if (d <= 0 || d > 1000) continue;
    bulunan.add(Miktar(d, birim));
  }
  return bulunan.length == 1 ? bulunan.first : null;
}

/// Birim fiyat: ürün KG/LT ile satılıyorsa fiyatın kendisi; ürün kartında Ağırlık (gr) varsa ona göre
/// (EtiketYardimci.birimFiyatMetni ile aynı kural); yoksa ürün adındaki gramaj.
BirimFiyat? birimFiyatHesapla({required String ad, required double? fiyat, String birimAdi = '', double agirlikGr = 0}) {
  if (fiyat == null || fiyat <= 0) return null;
  final ba = _buyukHarf(birimAdi.trim());
  if (const {'KG', 'KGR', 'KİLO', 'KILO', 'KİLOGRAM', 'KILOGRAM'}.contains(ba)) return BirimFiyat(fiyat, 'KG');
  if (const {'LT', 'L', 'LİTRE', 'LITRE'}.contains(ba)) return BirimFiyat(fiyat, 'LT');
  if (agirlikGr > 0) return BirimFiyat(ParaUtils.yuvarla(fiyat / (agirlikGr / 1000)), 'KG');
  final m = miktarCoz(ad);
  if (m == null) return null;
  return BirimFiyat(ParaUtils.yuvarla(fiyat / m.deger), m.birim);
}

/// "2026-11-12T10:15:00" / "2026-11-12" / "12.11.2026" → gün.
DateTime? tarihOku(String? v) {
  if (v == null || v.trim().isEmpty) return null;
  final iso = DateTime.tryParse(v.trim());
  if (iso != null) return DateTime(iso.year, iso.month, iso.day);
  final m = RegExp(r'^\s*(\d{1,2})[./-](\d{1,2})[./-](\d{4})').firstMatch(v);
  if (m != null) {
    final g = int.parse(m.group(1)!), a = int.parse(m.group(2)!), y = int.parse(m.group(3)!);
    if (a >= 1 && a <= 12 && g >= 1 && g <= 31) return DateTime(y, a, g);
  }
  return null;
}

/// Ürün kartından etiket verisi.
EtiketVeri etiketVerisi(UrunModel u) {
  final fiyat = u.satisFiyati > 0 ? u.satisFiyati : null;
  final ind = (u.indirimliFiyatKayitli > 0 || u.indirimOrani > 0) ? ParaUtils.yuvarla(u.indirimliFiyat) : null;
  return EtiketVeri(
    ad: u.urunAdi.trim(),
    fiyat: fiyat,
    barkod: (u.barkod ?? '').trim(),
    indirimliFiyat: (fiyat != null && ind != null && ind > 0 && ind < fiyat - 1e-9) ? ind : null,
    birimFiyat: birimFiyatHesapla(ad: u.urunAdi, fiyat: fiyat, birimAdi: u.birimAdi, agirlikGr: u.agirlik),
    tarih: tarihOku(u.fiyatGuncellemeTarih),
    mensei: (u.mensei ?? '').trim().isEmpty ? null : u.mensei!.trim(),
  );
}

// ───────────────────────── Şablon tanımı ─────────────────────────

enum YaziTipi { arial, arialNarrow, arialBlack, antikva }

enum Hiza { sol, orta, sag }

enum Cizik { yok, duz, capraz }

/// Etiket üzerindeki bir öğe. Tüm ölçüler mm, (0,0) sol üst köşe.
sealed class Oge {
  const Oge();
}

/// Yazı. [icerik] içinde yer tutucular: {ad} {fiyat} {indirimliFiyat} {oran} {birimFiyat} {barkod} {tarih} {mensei} {firma} {para}.
/// Kutu: x, y, g (genişlik), h (yükseklik). Yazı kutuya sığmazsa küçülür ([enKucuk] oranına kadar), sonra
/// [satir] 2 ise iki satıra bölünür; o da sığmazsa tek satırda kutuya sığana kadar küçülür (taşmaz).
class YaziOge extends Oge {
  final String icerik;
  final double x, y, g, h, punto;
  final bool kalin, altiCizili;
  final YaziTipi yazi;
  final Hiza hiza;
  final bool ustten; // true: üste yasla; false: dikeyde ortala
  final int satir;
  final double enKucuk;
  final Cizik cizik;
  final bool dikey; // 90° (aşağıdan yukarı okunur); kutu döndürülmüş hâliyle verilir
  const YaziOge(
    this.icerik, {
    required this.x,
    required this.y,
    required this.g,
    required this.h,
    required this.punto,
    this.kalin = true,
    this.yazi = YaziTipi.arial,
    this.hiza = Hiza.sol,
    this.ustten = false,
    this.satir = 1,
    this.enKucuk = 0.6,
    this.cizik = Cizik.yok,
    this.altiCizili = false,
    this.dikey = false,
  });
}

/// Barkod: kutu içinde yatayda ortalanır; genişlik = modül sayısı × [modul] (kutuyu aşmaz).
class BarkodOge extends Oge {
  final double x, y, g, h, modul, yaziPunto;
  final bool kalinYazi;
  const BarkodOge({required this.x, required this.y, required this.g, required this.h, required this.modul, this.yaziPunto = 8, this.kalinYazi = false});
}

class KutuOge extends Oge {
  final double x, y, g, h, kalinlik;
  const KutuOge({required this.x, required this.y, required this.g, required this.h, this.kalinlik = 0.35});
}

/// "Yerli Üretim" logosu (assets/images/yerli_uretim.png).
class LogoOge extends Oge {
  final double x, y, g, h;
  final bool dikey;
  const LogoOge({required this.x, required this.y, required this.g, required this.h, this.dikey = false});
}

enum SablonTuru { normal, birimFiyatli, indirimli }

class EtiketSablonu {
  final String id; // ayarlarda saklanır — DEĞİŞTİRME
  final String ad;
  final String dosya; // karşılık gelen BarTender şablonu
  final double genislik, yukseklik;
  final SablonTuru tur;
  final String para; // 'TL' | '₺'
  final List<Oge> ogeler;
  const EtiketSablonu({
    required this.id,
    required this.ad,
    required this.dosya,
    required this.genislik,
    required this.yukseklik,
    required this.ogeler,
    this.tur = SablonTuru.normal,
    this.para = '₺',
  });

  bool get indirimli => tur == SablonTuru.indirimli;
  bool get birimFiyatli => tur == SablonTuru.birimFiyatli || ogeler.any((o) => o is YaziOge && o.icerik.contains('{birimFiyat}'));
  String get olcu => '${_mm(genislik)} × ${_mm(yukseklik)} mm';
}

String _mm(double d) => d == d.roundToDouble() ? d.toInt().toString() : d.toString().replaceAll('.', ',');

// ───────────────────────── Şablonlar ─────────────────────────
// Ölçüler: BarTender nesne konumları + önizleme resmi (80 mm = 937 px, 40 mm = 712 px).

const _raf80x35Ortak = <Oge>[
  BarkodOge(x: 20, y: 23.7, g: 31.4, h: 8.7, modul: 0.29, yaziPunto: 9),
  YaziOge('Menşei :{mensei}', x: 1.7, y: 28.3, g: 18, h: 1.8, punto: 6),
  YaziOge('Tarih :  {tarih}', x: 1.7, y: 31.8, g: 18, h: 1.8, punto: 6),
  KutuOge(x: 57.86, y: 19.99, g: 21.41, h: 13.77, kalinlik: 0.3),
  YaziOge('Birim Fiyatı', x: 57.86, y: 22.6, g: 21.41, h: 2.6, punto: 8, hiza: Hiza.orta),
  YaziOge('{birimFiyat}', x: 58.4, y: 28.1, g: 20.3, h: 3.2, punto: 9, hiza: Hiza.orta, enKucuk: 0.4),
];

const sablonlar = <EtiketSablonu>[
  EtiketSablonu(
    id: 'raf_80x35_birimfiyatli',
    ad: 'Raf etiketi — birim fiyatlı (₺)',
    dosya: 'Raf_etiket BİRİMFİYATLI 80x35.btw',
    genislik: 80,
    yukseklik: 35,
    tur: SablonTuru.birimFiyatli,
    ogeler: [
      YaziOge('{ad}', x: 3.1, y: 0.8, g: 74.5, h: 10.5, punto: 18, yazi: YaziTipi.arialNarrow, ustten: true, satir: 2),
      YaziOge('{fiyat} {para}', x: 10.3, y: 12.5, g: 53.7, h: 7.5, punto: 18, hiza: Hiza.orta),
      ..._raf80x35Ortak,
    ],
  ),
  EtiketSablonu(
    id: 'raf_80x35',
    ad: 'Raf etiketi — birim fiyatlı (TL)',
    dosya: 'Raf_80x35.btw',
    genislik: 80,
    yukseklik: 35,
    tur: SablonTuru.birimFiyatli,
    para: 'TL',
    ogeler: [
      YaziOge('{ad}', x: 3.1, y: 0.8, g: 74.5, h: 10.5, punto: 16, yazi: YaziTipi.arialNarrow, ustten: true, satir: 2),
      YaziOge('{fiyat} {para}', x: 10.3, y: 12.5, g: 53.7, h: 7.5, punto: 16, hiza: Hiza.orta),
      ..._raf80x35Ortak,
    ],
  ),
  EtiketSablonu(
    id: 'raf_80x35_turkiye',
    ad: 'Raf etiketi — Yerli Üretim',
    dosya: 'Raf_80x35Turkiye.btw',
    genislik: 80,
    yukseklik: 35,
    para: 'TL',
    ogeler: [
      YaziOge('{ad}', x: 1.9, y: 1.0, g: 76.5, h: 9.0, punto: 18, yazi: YaziTipi.arialNarrow, ustten: true, satir: 2),
      YaziOge('{fiyat} {para}', x: 14, y: 12.6, g: 51, h: 7.6, punto: 20, hiza: Hiza.orta),
      LogoOge(x: 65.1, y: 10.4, g: 13.2, h: 5.2),
      BarkodOge(x: 21, y: 22.1, g: 39.6, h: 10.5, modul: 0.324, yaziPunto: 9),
      YaziOge('Tarih : {tarih}', x: 1.8, y: 31.3, g: 19, h: 2.1, punto: 6.5),
      YaziOge('Menşei :  {mensei}', x: 61, y: 31.3, g: 17.3, h: 2.1, punto: 6.5, hiza: Hiza.sag),
    ],
  ),
  EtiketSablonu(
    id: 'raf_80x35_karton',
    ad: 'Raf etiketi — karton (firma adlı)',
    dosya: 'Raf_etiket_KARTON_80x35.btw',
    genislik: 80,
    yukseklik: 35,
    ogeler: [
      YaziOge('{firma}', x: 2.6, y: 5.0, g: 4.4, h: 22.4, punto: 10, yazi: YaziTipi.arialBlack, hiza: Hiza.orta, dikey: true, altiCizili: true, enKucuk: 0.4),
      YaziOge('{ad}', x: 9.2, y: 4.0, g: 67.5, h: 6.3, punto: 9, yazi: YaziTipi.arialNarrow, ustten: true, satir: 2),
      YaziOge('{fiyat} {para}', x: 9.2, y: 11.8, g: 41.5, h: 8.2, punto: 22),
      BarkodOge(x: 50.5, y: 10.6, g: 27, h: 10.2, modul: 0.25),
      LogoOge(x: 56.9, y: 22.6, g: 14.1, h: 5.7),
      YaziOge('Menşei :{mensei}', x: 9.2, y: 23.4, g: 40, h: 2.6, punto: 8),
      YaziOge('Tarih :  {tarih}', x: 9.2, y: 27.1, g: 30, h: 1.8, punto: 6),
    ],
  ),
  EtiketSablonu(
    id: 'raf_80x35_indirimli',
    ad: 'Raf etiketi — indirimli',
    dosya: 'İNDİRİMLİ halil RAF_etiket 80x35.btw',
    genislik: 80,
    yukseklik: 35,
    tur: SablonTuru.indirimli,
    ogeler: [
      YaziOge('{ad}', x: 7.6, y: 3.6, g: 70, h: 5.3, punto: 13, yazi: YaziTipi.arialNarrow, ustten: true, satir: 2),
      YaziOge('{fiyat}', x: 6.6, y: 13.2, g: 33.4, h: 4.2, punto: 13, hiza: Hiza.orta, cizik: Cizik.capraz),
      YaziOge('İndirimli Fiyat', x: 42, y: 8.8, g: 30, h: 3.6, punto: 11, yazi: YaziTipi.antikva, hiza: Hiza.orta),
      YaziOge('{indirimliFiyat} {para}', x: 40, y: 14.6, g: 39.5, h: 6.0, punto: 20, hiza: Hiza.orta),
      BarkodOge(x: 3, y: 22.1, g: 40, h: 8.4, modul: 0.325, kalinYazi: true),
      YaziOge('Tarih :', x: 40, y: 24.9, g: 11.4, h: 1.9, punto: 5.5, hiza: Hiza.orta),
      YaziOge('{tarih}', x: 40, y: 27.8, g: 13.4, h: 1.9, punto: 6, hiza: Hiza.orta),
      LogoOge(x: 57.1, y: 24.1, g: 15.3, h: 5.9),
    ],
  ),
  EtiketSablonu(
    id: 'fis_turkiye',
    ad: 'Fiş kâğıdına etiket — Yerli Üretim',
    dosya: 'Raf_FisTürkiye.btw',
    genislik: 80,
    yukseklik: 29,
    ogeler: [
      YaziOge('{ad}', x: 1.8, y: 0.6, g: 66, h: 6.2, punto: 8, yazi: YaziTipi.arialNarrow, ustten: true, satir: 2),
      YaziOge('{fiyat} {para}', x: 10, y: 6.8, g: 52, h: 4.4, punto: 12, yazi: YaziTipi.arialBlack, hiza: Hiza.orta),
      BarkodOge(x: 10, y: 11.6, g: 46, h: 10.0, modul: 0.4, yaziPunto: 7),
      LogoOge(x: 70, y: 5.0, g: 5.9, h: 15.3, dikey: true),
      YaziOge('Tarih:{tarih}', x: 1.8, y: 24.0, g: 40, h: 2.6, punto: 8, kalin: false),
      YaziOge('Menşei:{mensei}', x: 50, y: 24.0, g: 28, h: 2.6, punto: 8, kalin: false),
    ],
  ),
  EtiketSablonu(
    id: '40x30',
    ad: 'Küçük etiket 40 × 30',
    dosya: '40x30.btw',
    genislik: 40,
    yukseklik: 30,
    ogeler: [
      YaziOge('{ad}', x: 2.5, y: 2.5, g: 35.5, h: 6.8, punto: 8, kalin: false, ustten: true, satir: 2),
      YaziOge('{fiyat} {para}', x: 1, y: 12.4, g: 38, h: 4.0, punto: 12, kalin: false, hiza: Hiza.orta),
      BarkodOge(x: 1.2, y: 18.1, g: 37.6, h: 11.0, modul: 0.4, yaziPunto: 6),
    ],
  ),
  EtiketSablonu(
    id: '40x30_indirimli',
    ad: 'Küçük etiket 40 × 30 — indirimli',
    dosya: '40x30_İndirimli.btw',
    genislik: 40,
    yukseklik: 30,
    tur: SablonTuru.indirimli,
    ogeler: [
      YaziOge('{ad}', x: 2.9, y: 1.3, g: 35, h: 4.4, punto: 5, ustten: true, satir: 2),
      YaziOge('S.FİYATI', x: 3, y: 8.3, g: 17, h: 2.5, punto: 8),
      YaziOge('İNDİRİM', x: 3, y: 11.5, g: 17, h: 2.5, punto: 8),
      YaziOge('İND. FİYAT', x: 3, y: 15.4, g: 17, h: 2.5, punto: 8),
      YaziOge('{fiyat} {para}', x: 21, y: 7.7, g: 17.5, h: 2.8, punto: 9.5, hiza: Hiza.orta, cizik: Cizik.duz),
      YaziOge('% {oran}', x: 21, y: 11.2, g: 17.5, h: 2.8, punto: 9.5, kalin: false, hiza: Hiza.orta),
      YaziOge('{indirimliFiyat} {para}', x: 20, y: 14.6, g: 19.5, h: 3.3, punto: 11, hiza: Hiza.orta),
      BarkodOge(x: 1, y: 19.0, g: 33.8, h: 8.7, modul: 0.315, yaziPunto: 7, kalinYazi: true),
    ],
  ),
];

EtiketSablonu sablonBul(String? id) => sablonlar.firstWhere((s) => s.id == id, orElse: () => sablonlar.first);

// ───────────────────────── Yer tutucular ─────────────────────────

/// "% 20" / "% 12,5"
String oranMetni(double? o) {
  if (o == null) return '';
  final r = _yuvarla(o, 1);
  return r == r.roundToDouble() ? r.toInt().toString() : r.toString().replaceAll('.', ',');
}

String doldur(String icerik, EtiketVeri v, {required String para, required String mensei, required String firma, required DateTime bugun}) {
  final bf = v.birimFiyat;
  return icerik.replaceAllMapped(RegExp(r'\{(\w+)\}'), (m) {
    return switch (m.group(1)) {
      'ad' => v.ad,
      'fiyat' => v.fiyat == null ? '' : paraYaz(v.fiyat),
      'indirimliFiyat' => v.indirimliFiyat == null ? '' : paraYaz(v.indirimliFiyat),
      'oran' => oranMetni(v.indirimOrani),
      'birimFiyat' => bf == null ? '' : '${paraYaz(bf.deger)} $para/${bf.birim}',
      'barkod' => v.barkod,
      'tarih' => _tarihBicim.format(v.tarih ?? bugun),
      'mensei' => mensei,
      'firma' => firma,
      'para' => para,
      _ => m.group(0)!,
    };
  });
}

// ───────────────────────── Yerleşim ─────────────────────────

/// Yazı ölçer: [s] metninin 1 punto (em) başına genişliği; ve yazı tipinin ascent / descent / büyük harf yüksekliği (em).
abstract class YaziOlcer {
  double genislik(String s, YaziTipi y, bool kalin);
  double ascent(YaziTipi y, bool kalin);
  double descent(YaziTipi y, bool kalin); // pozitif
}

/// Test ve ölçü olmadan tahmin için: Arial'e yakın sabit genişlik.
class TahminiOlcer implements YaziOlcer {
  const TahminiOlcer();
  @override
  double genislik(String s, YaziTipi y, bool kalin) {
    var w = 0.0;
    for (final r in s.runes) {
      final c = String.fromCharCode(r);
      w += c == ' ' ? 0.278 : (RegExp(r'[0-9]').hasMatch(c) ? 0.556 : (RegExp(r'[.,:;İIıil!|]').hasMatch(c) ? 0.278 : (c == 'M' || c == 'W' ? 0.833 : 0.65)));
    }
    final k = switch (y) { YaziTipi.arialNarrow => 0.82, YaziTipi.arialBlack => 1.2, _ => 1.0 };
    return w * k * (kalin ? 1.05 : 1.0);
  }

  @override
  double ascent(YaziTipi y, bool kalin) => 0.905;
  @override
  double descent(YaziTipi y, bool kalin) => 0.212;
}

const ptMm = 25.4 / 72; // 1 punto = 0.3528 mm

/// Çizilecek bir yazı satırı. (x, y) satır kutusunun sol üstü (mm); yazı boyu punto.
class YaziSatiri {
  final String metin;
  final double x, y, genislik, punto;
  const YaziSatiri(this.metin, this.x, this.y, this.genislik, this.punto);
}

sealed class Cizim {
  const Cizim();
}

class YaziCizimi extends Cizim {
  final YaziOge oge;
  final List<YaziSatiri> satirlar;
  const YaziCizimi(this.oge, this.satirlar);
}

class BarkodCizimi extends Cizim {
  final BarkodOge oge;
  final String veri;
  final double x, genislik; // mm (ayrılan alan; çubuklar bunun içinde ortalanır)
  final double modul; // mm; yazıcı noktasının tam katı
  final double nokta; // yazıcının bir noktası (mm)
  const BarkodCizimi(this.oge, this.veri, this.x, this.genislik, {required this.modul, required this.nokta});
}

/// Termal yazıcıların çoğu 203 dpi (8 nokta/mm).
const varsayilanDpi = 203.0;

/// Barkod modülünü yazıcı noktasının tam katına yuvarlar (en az 2 nokta; 1 noktalık çubuk termal kâğıtta silik çıkar),
/// [enFazla] mm'yi aşmayacak şekilde. Kesirli modül 1-2-3 noktalık düzensiz çubuklar verir.
double barkodModulu(double modul, double nokta, {double enFazla = double.infinity}) {
  var k = math.max(2, (modul / nokta).round());
  while (k > 1 && k * nokta > enFazla + 1e-9) {
    k--;
  }
  // Çok uzun barkod 1 noktayla bile sığmıyorsa kutuya sıkıştırılır (eski davranış; okunması zaten zor).
  return k * nokta > enFazla + 1e-9 ? enFazla : k * nokta;
}

/// [v]'yi [nokta] ızgarasına oturtur.
double noktayaOturt(double v, double nokta) => (v / nokta).round() * nokta;

class KutuCizimi extends Cizim {
  final KutuOge oge;
  const KutuCizimi(this.oge);
}

class CizgiCizimi extends Cizim {
  final double x1, y1, x2, y2, kalinlik;
  const CizgiCizimi(this.x1, this.y1, this.x2, this.y2, this.kalinlik);
}

class LogoCizimi extends Cizim {
  final LogoOge oge;
  const LogoCizimi(this.oge);
}

/// Barkod modül sayısı (sessiz bölge hariç) — genişlik hesabı için. Bilinmiyorsa null.
int? barkodModulSayisi(String s) {
  if (s.isEmpty) return null;
  if (_rakamMi(s)) {
    if (s.length == 13 && ean13Gecerli(s)) return 95;
    if (s.length == 8 && ean13Gecerli(s.padLeft(13, '0'))) return 67;
    if (s.length == 12 && ean13Gecerli('0$s')) return 95; // UPC-A
  }
  // Code128 (B): başlangıç 11 + her karakter 11 + sağlama 11 + bitiş 13; çift rakamlar C ile sıkışır ama üst sınır yeter.
  return 11 * (s.length + 2) + 13;
}

/// EAN-13/EAN-8/UPC sağlama (13 hane, baştan sıfırla doldurulmuş).
bool ean13Gecerli(String s) {
  if (s.length != 13 || !_rakamMi(s)) return false;
  var t = 0;
  for (var i = 0; i < 12; i++) {
    t += int.parse(s[i]) * (i.isEven ? 1 : 3);
  }
  return (10 - t % 10) % 10 == int.parse(s[12]);
}

/// Bir etiketin çizim listesi. Hiçbir yazı kutusundan taşmaz (gerekirse küçülür).
List<Cizim> yerlesim(
  EtiketSablonu s,
  EtiketVeri v, {
  required YaziOlcer olcer,
  String mensei = 'Türkiye',
  String firma = 'HALK MARKET',
  DateTime? bugun,
  double dpi = varsayilanDpi,
}) {
  final gun = _gun(bugun);
  final sonuc = <Cizim>[];
  for (final o in s.ogeler) {
    switch (o) {
      case YaziOge():
        final m = doldur(o.icerik, v, para: s.para, mensei: v.mensei ?? mensei, firma: firma, bugun: gun).trim();
        if (m.isEmpty || RegExp(r'^[%\s]*$').hasMatch(m) || m == s.para) continue;
        final satirlar = yaziYerlestir(o, m, olcer);
        sonuc.add(YaziCizimi(o, satirlar));
        if (o.cizik != Cizik.yok && satirlar.isNotEmpty) {
          final st = satirlar.first;
          final asc = olcer.ascent(o.yazi, o.kalin), cap = 0.716;
          final capUst = st.y + (asc - cap) * st.punto * ptMm;
          final capH = cap * st.punto * ptMm;
          final ince = math.max(0.25, st.punto * 0.035);
          if (o.cizik == Cizik.duz) {
            final y = capUst + capH * 0.5;
            sonuc.add(CizgiCizimi(st.x - 0.3, y, st.x + st.genislik + 0.3, y, ince));
          } else {
            sonuc.add(CizgiCizimi(st.x - capH * 0.6, capUst + capH * 1.25, st.x + st.genislik + capH * 0.55, capUst - capH * 0.15, ince));
          }
        }
      case BarkodOge():
        final n = barkodModulSayisi(v.barkod);
        if (n == null) continue;
        final nokta = 25.4 / dpi;
        final m = barkodModulu(o.modul, nokta, enFazla: o.g / n);
        final g = n * m;
        sonuc.add(BarkodCizimi(o, v.barkod, o.x + (o.g - g) / 2, g, modul: m, nokta: nokta));
      case KutuOge():
        sonuc.add(KutuCizimi(o));
      case LogoOge():
        sonuc.add(LogoCizimi(o));
    }
  }
  return sonuc;
}

/// Yazıyı kutuya yerleştirir (koordinatlar etiketin mm'si; dikey öğede döndürülmüş kutunun içi).
List<YaziSatiri> yaziYerlestir(YaziOge o, String m, YaziOlcer olcer) {
  // dikey yazıda uzunluk kutunun yüksekliği, kalınlık genişliği
  final boy = o.dikey ? o.h : o.g;
  final en = o.dikey ? o.g : o.h;
  final asc = olcer.ascent(o.yazi, o.kalin), desc = olcer.descent(o.yazi, o.kalin);
  double satirH(double pt) => (asc + desc) * pt * ptMm;
  double gen(String s, double pt) => olcer.genislik(s, o.yazi, o.kalin) * pt * ptMm;

  // en büyük punto: satır yüksekliği kutuya sığmalı
  var pt = math.min(o.punto, en / ((asc + desc) * ptMm));
  List<String> satirlar = [m];
  final tek = gen(m, pt);
  if (tek > boy) {
    final kucuk = pt * boy / tek;
    if (kucuk >= o.punto * o.enKucuk || o.satir < 2) {
      pt = kucuk;
    } else {
      // iki satır: en dengeli kelime bölünmesi
      final k = m.split(RegExp(r'\s+'));
      double enIyiPt = 0;
      List<String>? enIyi;
      for (var i = 1; i < k.length; i++) {
        final a = k.sublist(0, i).join(' '), b = k.sublist(i).join(' ');
        final p = [o.punto, en / (2 * (asc + desc) * ptMm), o.punto * boy / gen(a, o.punto), o.punto * boy / gen(b, o.punto)].reduce(math.min);
        if (p > enIyiPt) {
          enIyiPt = p;
          enIyi = [a, b];
        }
      }
      if (enIyi != null && enIyiPt > kucuk) {
        pt = enIyiPt;
        satirlar = enIyi;
      } else {
        pt = kucuk;
      }
    }
  }
  final lh = satirH(pt);
  final blok = lh * satirlar.length;
  final ust0 = o.ustten ? 0.0 : (en - blok) / 2;
  return [
    for (var i = 0; i < satirlar.length; i++)
      () {
        final w = gen(satirlar[i], pt);
        final sol = switch (o.hiza) { Hiza.sol => 0.0, Hiza.orta => (boy - w) / 2, Hiza.sag => boy - w };
        // dikey değilse etiket koordinatı; dikeyse döndürülmüş kutunun kendi koordinatı (çizen çevirir)
        return o.dikey ? YaziSatiri(satirlar[i], sol, ust0 + i * lh, w, pt) : YaziSatiri(satirlar[i], o.x + sol, o.y + ust0 + i * lh, w, pt);
      }(),
  ];
}

// ───────────────────────── Etikete uygunluk ─────────────────────────

/// Basılamayacak / eksik çıkacak ürünler için açıklamalar.
class EtiketDenetimi {
  final List<EtiketVeri> basilacak;
  final List<String> atlanan; // "AD — sebep"
  final List<String> birimFiyatsiz; // birim fiyatı boş kalacak ürün adları
  const EtiketDenetimi(this.basilacak, this.atlanan, this.birimFiyatsiz);
}

EtiketDenetimi etiketDenetle(EtiketSablonu s, List<EtiketVeri> liste) {
  final bas = <EtiketVeri>[], atla = <String>[], bfsiz = <String>[];
  for (final v in liste) {
    final ad = v.ad.isEmpty ? '(adsız ${v.barkod})' : v.ad;
    if (v.fiyat == null || v.fiyat! <= 0) {
      atla.add('$ad — satış fiyatı yok');
      continue;
    }
    if (s.indirimli && v.indirimliFiyat == null) {
      atla.add('$ad — indirimli fiyatı yok');
      continue;
    }
    if (s.birimFiyatli && v.birimFiyat == null) bfsiz.add(ad);
    bas.add(v);
  }
  return EtiketDenetimi(bas, atla, bfsiz);
}
