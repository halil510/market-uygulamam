// lib/ekranlar/satis/masaustu/masaustu_sepet_tablosu.dart
//
// Masaüstü Hızlı Satış — tablo görünümlü sepet (BarkoPOS düzeni):
// Kod | Ürün Adı | Miktar | Birim | KDV'li fiyat | KDV'li tutar | İndirim | Net Tutar
// Satıra tek tık = seç, çift tık = miktar düzenle, sağdaki çöp = sil.
import 'package:flutter/material.dart';
import '../../../cekirdek/utils/para_utils.dart';
import '../../../modeller/sepet_model.dart';
import '../../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../../uygulama/tema/uygulama_temasi.dart';

class MasaustuSepetTablosu extends StatelessWidget {
  final List<SepetKalem> kalemler;
  final int? seciliIndex;
  final ScrollController scrollController;
  final ValueChanged<int> onSec;
  final void Function(SepetKalem kalem, int index) onDuzenle;
  final ValueChanged<int> onSil;

  const MasaustuSepetTablosu({
    super.key,
    required this.kalemler,
    required this.seciliIndex,
    required this.scrollController,
    required this.onSec,
    required this.onDuzenle,
    required this.onSil,
  });

  // Sütun genişlik oranları (flex) — başlık ve satırlar aynı oranı kullanır.
  static const _oranlar = [20, 36, 10, 10, 14, 14, 11, 15];

  static String _miktar(double m) =>
      m == m.roundToDouble() ? m.toStringAsFixed(0) : m.toStringAsFixed(3);

  Widget _hucre(int i, Widget child) =>
      Expanded(flex: _oranlar[i], child: child);

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _baslik(),
      Expanded(
        child: kalemler.isEmpty
            ? Center(
                child: Text('Sepet boş — barkod okutun veya aşağıdan ürün seçin',
                    style: TextStyle(color: context.textSecondary)),
              )
            : ListView.builder(
                controller: scrollController,
                itemCount: kalemler.length,
                itemBuilder: (_, i) => _satir(context, kalemler[i], i),
              ),
      ),
    ]);
  }

  Widget _baslik() {
    const adlar = [
      'Kod', 'Ürün Adı', 'Miktar', 'Birim', 'Fiyat',
      'Tutar', 'İndirim', 'Net Tutar',
    ];
    return Container(
      color: const Color(0xFF1F2A5C),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Row(children: [
        for (var i = 0; i < adlar.length; i++)
          _hucre(
            i,
            Text(i == 3 ? '   ${adlar[i]}' : adlar[i],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: i >= 2 && i != 3 ? TextAlign.right : TextAlign.left,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5)),
          ),
        const SizedBox(width: 36),
      ]),
    );
  }

  Widget _satir(BuildContext context, SepetKalem k, int i) {
    final secili = i == seciliIndex;
    final yazi = TextStyle(
        fontSize: 13.5,
        color: context.textPrimary,
        fontWeight: secili ? FontWeight.w700 : FontWeight.w500);
    Widget t(String s, {bool sag = false, TextStyle? stil}) => Text(s,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: sag ? TextAlign.right : TextAlign.left,
        style: stil ?? yazi);

    return Material(
      color: secili
          ? TsRenk.primary.withValues(alpha: 0.14)
          : (i.isEven ? context.cardBg : context.scaffoldBg),
      child: InkWell(
        onTap: () => onSec(i),
        onDoubleTap: () => onDuzenle(k, i),
        child: Container(
          padding: const EdgeInsets.only(left: 10, right: 4, top: 6, bottom: 6),
          decoration: BoxDecoration(
            border: Border(
                left: BorderSide(
                    color: secili ? TsRenk.primary : Colors.transparent,
                    width: 3)),
          ),
          child: Row(children: [
            _hucre(0, t(k.urun.barkod ?? '')),
            _hucre(1, t(k.urun.urunAdi)),
            _hucre(2, t(_miktar(k.miktar), sag: true)),
            _hucre(3, t('   ${k.urun.birimAdi}')),
            _hucre(4, t(ParaUtils.formatla(k.birimFiyat, simge: ''), sag: true)),
            _hucre(5, t(ParaUtils.formatla(k.birimFiyat * k.miktar, simge: ''), sag: true)),
            _hucre(
                6,
                t(k.iskontoTutar > 0 ? ParaUtils.formatla(k.iskontoTutar, simge: '') : '',
                    sag: true)),
            _hucre(
                7,
                t(ParaUtils.formatla(k.toplamTutar, simge: ''),
                    sag: true,
                    stil: yazi.copyWith(
                        fontWeight: FontWeight.w800, color: TsRenk.primary))),
            SizedBox(
              width: 36,
              child: IconButton(
                padding: EdgeInsets.zero,
                iconSize: 18,
                tooltip: 'Sil (Del)',
                icon: Icon(Icons.delete_outline, color: context.textHint),
                onPressed: () => onSil(i),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
