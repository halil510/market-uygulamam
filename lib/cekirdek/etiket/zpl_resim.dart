// lib/cekirdek/etiket/zpl_resim.dart
//
// Etiket resmini ZPL (Zebra) grafiği olarak verir: seçili tasarım hangi yazıcıya gidiyorsa ZPL'de de AYNI görünür
// (eski ZPL çıktısı ayrı, metin tabanlı bir düzen kullanıyordu). SAF Dart, testli.
// Girdi TSPL bit eşlemi (bit 1 = beyaz); ZPL ^GFA'da bit 1 = siyah olduğundan baytlar ters çevrilir.

import 'tspl.dart';

const _hex = '0123456789ABCDEF';

String _onaltilik(TsplResim r) {
  final sb = StringBuffer();
  for (final b in r.veri) {
    final v = (~b) & 0xFF;
    sb
      ..write(_hex[v >> 4])
      ..write(_hex[v & 0x0F]);
  }
  return sb.toString();
}

/// [etiketler] sırayla (203 dpi resim); art arda aynı etiketler tek ^PQ ile.
String zplResimIs(List<TsplResim> etiketler) {
  final sb = StringBuffer();
  var i = 0;
  while (i < etiketler.length) {
    final e = etiketler[i];
    var n = 1;
    while (i + n < etiketler.length && etiketler[i + n].ayni(e)) {
      n++;
    }
    final toplam = e.satirBayt * e.yukseklik;
    sb
      ..write('^XA^CI28^PW${e.satirBayt * 8}^LL${e.yukseklik}^LH0,0')
      ..write('^FO0,0^GFA,$toplam,$toplam,${e.satirBayt},${_onaltilik(e)}^FS')
      ..write('^PQ$n,0,1,Y^XZ\n');
    i += n;
  }
  return sb.toString();
}
