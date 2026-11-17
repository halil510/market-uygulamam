// lib/cekirdek/etiket/tspl.dart  (Ürün Güncelleme'deki lib/etiket/tspl.dart ile AYNI)
//
// TSPL (TSC / Xprinter etiket yazıcısı dili) komutları — saf Dart, testli.
// Her etiket yazıcı çözünürlüğünde resme çevrilip BITMAP olarak gönderilir; böylece yazı tipleri / tasarım
// önizlemeyle birebir aynı çıkar. Art arda aynı etiketler tek BITMAP + PRINT 1,n ile basılır (Bluetooth'ta hızlı).

import 'dart:convert';
import 'dart:typed_data';

class TsplAyar {
  final double bosluk; // etiketler arası boşluk (mm); 0 = sürekli kâğıt
  final bool ters; // 180° çevir (DIRECTION 1)
  final int? koyuluk; // DENSITY 0-15; null = yazıcının kendi ayarı
  const TsplAyar({this.bosluk = 2, this.ters = false, this.koyuluk});
}

/// Tek renkli resim: her satır [satirBayt] bayt; bit 1 = beyaz (basılmaz), 0 = siyah (TSPL BITMAP biçimi).
class TsplResim {
  final int satirBayt, yukseklik;
  final Uint8List veri;
  const TsplResim(this.satirBayt, this.yukseklik, this.veri);

  bool ayni(TsplResim o) {
    if (o.satirBayt != satirBayt || o.yukseklik != yukseklik || o.veri.length != veri.length) return false;
    for (var i = 0; i < veri.length; i++) {
      if (veri[i] != o.veri[i]) return false;
    }
    return true;
  }
}

/// RGBA resmi TSPL bit eşlemine çevirir (parlaklık < 160 → siyah; saydam → beyaz). Genişlik 8'in katına
/// beyazla tamamlanır.
TsplResim tsplResim(Uint8List rgba, int en, int boy) {
  if (rgba.length != en * boy * 4) throw ArgumentError('Resim boyutu tutmuyor');
  final sb = (en + 7) >> 3;
  final out = Uint8List(sb * boy)..fillRange(0, sb * boy, 0xFF);
  for (var y = 0; y < boy; y++) {
    for (var x = 0; x < en; x++) {
      final i = (y * en + x) * 4;
      final a = rgba[i + 3];
      final r = 255 - ((255 - rgba[i]) * a ~/ 255);
      final g = 255 - ((255 - rgba[i + 1]) * a ~/ 255);
      final b = 255 - ((255 - rgba[i + 2]) * a ~/ 255);
      if ((r * 299 + g * 587 + b * 114) ~/ 1000 < 160) {
        out[y * sb + (x >> 3)] &= ~(0x80 >> (x & 7));
      }
    }
  }
  return TsplResim(sb, boy, out);
}

String _sayi(double v) {
  final s = v.toStringAsFixed(2);
  return s.replaceFirst(RegExp(r'\.?0+$'), '');
}

/// Yazıcıya gönderilecek iş: [etiketler] sırayla basılır.
Uint8List tsplIs(List<TsplResim> etiketler, {required double genislik, required double uzunluk, TsplAyar ayar = const TsplAyar()}) {
  final b = BytesBuilder(copy: false);
  void yaz(String s) => b.add(ascii.encode(s));
  yaz('SIZE ${_sayi(genislik)} mm,${_sayi(uzunluk)} mm\r\n');
  yaz('GAP ${_sayi(ayar.bosluk)} mm,0 mm\r\n');
  yaz('DIRECTION ${ayar.ters ? 1 : 0},0\r\n');
  yaz('REFERENCE 0,0\r\n');
  if (ayar.koyuluk != null) yaz('DENSITY ${ayar.koyuluk!.clamp(0, 15)}\r\n');
  var i = 0;
  while (i < etiketler.length) {
    final e = etiketler[i];
    var n = 1;
    while (i + n < etiketler.length && etiketler[i + n].ayni(e)) {
      n++;
    }
    yaz('CLS\r\n');
    yaz('BITMAP 0,0,${e.satirBayt},${e.yukseklik},0,');
    b.add(e.veri);
    yaz('\r\nPRINT 1,$n\r\n');
    i += n;
  }
  return b.takeBytes();
}
