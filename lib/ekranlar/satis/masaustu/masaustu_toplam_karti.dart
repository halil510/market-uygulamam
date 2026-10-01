// lib/ekranlar/satis/masaustu/masaustu_toplam_karti.dart
//
// Masaüstü Hızlı Satış — sağ üst: büyük toplam, müşteri, alınan para / para üstü.
import 'package:flutter/material.dart';
import '../../../cekirdek/utils/para_utils.dart';
import '../../../saglayicilar/riverpod/sepet_provider.dart';
import '../../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../../uygulama/tema/uygulama_temasi.dart';

class MasaustuToplamKarti extends StatelessWidget {
  final SepetDurum sepet;

  /// Sayı tuş takımından girilen "alınan para" (0 = girilmedi).
  final double alinanPara;

  const MasaustuToplamKarti({
    super.key,
    required this.sepet,
    required this.alinanPara,
  });

  @override
  Widget build(BuildContext context) {
    final toplam = sepet.genelToplam;
    final satirIndirimi =
        sepet.kalemler.fold<double>(0, (a, k) => a + k.toplamIndirim);
    final paraUstu = alinanPara - toplam;
    final musteri = sepet.musteri;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      color: const Color(0xFF14213D),
      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Row(children: [
          Icon(musteri == null ? Icons.person_outline : Icons.person,
              size: 16, color: Colors.white70),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              musteri == null
                  ? 'Peşin müşteri'
                  : (musteri.unvan.isNotEmpty ? musteri.unvan : 'Müşteri'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white70, fontSize: 12.5),
            ),
          ),
          Text('${sepet.kalemSayisi} çeşit • ${sepet.toplamAdet} adet',
              style: const TextStyle(color: Colors.white60, fontSize: 12)),
        ]),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: Text(
            ParaUtils.formatla(toplam, simge: ''),
            style: const TextStyle(
                fontSize: 54,
                height: 1.1,
                fontWeight: FontWeight.w800,
                color: Colors.white),
          ),
        ),
        if (sepet.iskontoTutar + satirIndirimi > 0)
          Text('İndirim: -${ParaUtils.formatla(sepet.iskontoTutar + satirIndirimi, simge: '')}',
              style: const TextStyle(color: Color(0xFFFF8A80), fontSize: 12)),
        if (alinanPara > 0) ...[
          const SizedBox(height: 2),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Alınan: ${ParaUtils.formatla(alinanPara, simge: '')}',
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
            Text(
              paraUstu >= 0
                  ? 'Para üstü: ${ParaUtils.formatla(paraUstu, simge: '')}'
                  : 'Eksik: ${ParaUtils.formatla(-paraUstu, simge: '')}',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: paraUstu >= 0 ? const Color(0xFF69F0AE) : const Color(0xFFFF8A80)),
            ),
          ]),
        ],
      ]),
    );
  }
}
