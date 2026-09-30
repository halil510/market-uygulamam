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
    final paraUstu = alinanPara - toplam;
    final musteri = sepet.musteri;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: context.cardBg,
        border: Border(bottom: BorderSide(color: context.borderColor)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Row(children: [
          Icon(musteri == null ? Icons.person_outline : Icons.person,
              size: 16, color: context.textSecondary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              musteri == null
                  ? 'Peşin müşteri'
                  : (musteri.unvan.isNotEmpty ? musteri.unvan : 'Müşteri'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: context.textSecondary, fontSize: 12.5),
            ),
          ),
          Text('${sepet.kalemSayisi} çeşit • ${sepet.toplamAdet} adet',
              style: TextStyle(color: context.textHint, fontSize: 12)),
        ]),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: Text(
            ParaUtils.formatla(toplam, simge: ''),
            style: const TextStyle(
                fontSize: 52,
                height: 1.1,
                fontWeight: FontWeight.w800,
                color: TsRenk.primary),
          ),
        ),
        if (sepet.iskontoTutar > 0)
          Text('İskonto: -${ParaUtils.formatla(sepet.iskontoTutar, simge: '')}',
              style: const TextStyle(color: TsRenk.hata, fontSize: 12)),
        if (alinanPara > 0) ...[
          const SizedBox(height: 2),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Alınan: ${ParaUtils.formatla(alinanPara, simge: '')}',
                style: TextStyle(color: context.textSecondary, fontSize: 13)),
            Text(
              paraUstu >= 0
                  ? 'Para üstü: ${ParaUtils.formatla(paraUstu, simge: '')}'
                  : 'Eksik: ${ParaUtils.formatla(-paraUstu, simge: '')}',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: paraUstu >= 0 ? TsRenk.basarili : TsRenk.hata),
            ),
          ]),
        ],
      ]),
    );
  }
}
