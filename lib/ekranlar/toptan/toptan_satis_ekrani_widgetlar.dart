// ignore_for_file: invalid_use_of_protected_member
//
// toptan_satis_ekrani.dart parçası (god-class bölme, 2026-09-29) — kod
// birebir taşındı, davranış değişmedi. setState extension içinden
// çağrıldığı için protected uyarısı dosya bazında muaf (bkz.
// fatura_detay_islemler_ext.dart'taki açıklama).
// Izgara hücreleri, özet widget'ları ve miktar/birim diyaloğu.
part of 'toptan_satis_ekrani.dart';

extension _ToptanSatisHucreExt on _ToptanSatisEkraniState {
  String _birimEtiket(String birim) => switch (birim) {
        'koli' => 'Koli',
        'kg' => 'Kg',
        _ => 'Adet',
      };

  /// Fatura ızgarası başlık hücresi (ÜRÜN/MİKTAR/TUTAR gibi).
  Widget _gridBaslikHucre(String metin,
          {required int flex, bool ortala = false, bool sagaYasla = false}) =>
      Expanded(
        flex: flex,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
          child: Text(metin,
              textAlign: ortala
                  ? TextAlign.center
                  : (sagaYasla ? TextAlign.right : TextAlign.left),
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                  color: TsRenk.metinIkincil(context))),
        ),
      );

  /// Fatura ızgarası veri hücresi — rakamlar hizalı (FontFeature.tabularFigures).
  Widget _gridHucre(String metin,
          {required int flex,
          bool ortala = false,
          bool sagaYasla = false,
          bool kalin = false,
          bool sonuk = false}) =>
      Expanded(
        flex: flex,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(metin,
              textAlign: ortala
                  ? TextAlign.center
                  : (sagaYasla ? TextAlign.right : TextAlign.left),
              style: TextStyle(
                fontSize: 12,
                fontWeight: kalin ? FontWeight.w700 : FontWeight.w500,
                color: sonuk
                    ? TsRenk.metinIkincil(context)
                    : TsRenk.metinBirincil(context),
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
        ),
      );
}

/// Bayi kartındaki küçük istatistik (bakiye/limit) gösterimi.
class _MiniIstatistik extends StatelessWidget {
  final String baslik;
  final String deger;
  final Color renk;
  const _MiniIstatistik(
      {required this.baslik, required this.deger, required this.renk});

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(baslik.toUpperCase(),
            style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: TsRenk.metinIkincil(context),
                letterSpacing: 0.5)),
        Text(deger,
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, color: renk)),
      ]);
}

/// Fatura-önizleme tarzı özet satırı (Ürün Toplamı / KDV bilgisi gibi).
class _OzetSatiri extends StatelessWidget {
  final String baslik;
  final double deger;
  final bool vurgusuz; // true ise daha soluk/bilgilendirme amaçlı gösterilir
  const _OzetSatiri(
      {required this.baslik, required this.deger, this.vurgusuz = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(baslik,
              style: TextStyle(
                  fontSize: vurgusuz ? 11.5 : 13,
                  color: vurgusuz
                      ? TsRenk.metinIkincil(context)
                      : TsRenk.metinIkincil(context),
                  fontStyle: vurgusuz ? FontStyle.italic : FontStyle.normal)),
          Text(ParaUtils.formatla(deger),
              style: TextStyle(
                  fontSize: vurgusuz ? 11.5 : 13,
                  fontWeight: vurgusuz ? FontWeight.w400 : FontWeight.w600,
                  color: vurgusuz
                      ? TsRenk.metinIkincil(context)
                      : TsRenk.metinBirincil(context))),
        ]),
      );
}

/// Miktar ve birim (adet/koli/kg) seçim dialogu.
class _MiktarBirimDialog extends StatefulWidget {
  final UrunModel urun;
  final String baslangicBirim;
  final double baslangicMiktar;
  const _MiktarBirimDialog(
      {required this.urun,
      required this.baslangicBirim,
      required this.baslangicMiktar});

  @override
  State<_MiktarBirimDialog> createState() => _MiktarBirimDialogState();
}

class _MiktarBirimDialogState extends State<_MiktarBirimDialog> {
  late String _birim;
  final _miktarCtrl = TextEditingController();
  String? _hata;

  @override
  void initState() {
    super.initState();
    _birim = widget.baslangicBirim;
    _miktarCtrl.text = widget.baslangicMiktar.toStringAsFixed(0);
  }

  @override
  void dispose() {
    _miktarCtrl.dispose();
    super.dispose();
  }

  /// Girilen miktarı ürünün TEMEL birimine (adet/kg) çevirir — koli
  /// seçiliyse koli içi adede göre büyütür. Asgari sipariş miktarı hep
  /// temel birim üzerinden tanımlı olduğu için karşılaştırma bununla
  /// yapılmalı, ekrandaki ham miktarla değil.
  double _temelBirimMiktar(double miktar) =>
      (_birim == 'koli' && widget.urun.koliIciMiktar > 0)
          ? miktar * widget.urun.koliIciMiktar
          : miktar;

  @override
  Widget build(BuildContext context) {
    final koliVar = widget.urun.koliIciMiktar > 0;
    final kgUrunu = widget.urun.satisBirimiTipi == 'kg';
    final asgari = widget.urun.asgariSiparisMiktari;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(widget.urun.urunAdi),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: _miktarCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Miktar',
            border: const OutlineInputBorder(),
            errorText: _hata,
          ),
          onChanged: (_) {
            if (_hata != null) setState(() => _hata = null);
          },
        ),
        const SizedBox(height: 12),
        if (!kgUrunu)
          SegmentedButton<String>(
            segments: [
              const ButtonSegment(value: 'adet', label: Text('Adet')),
              if (koliVar)
                ButtonSegment(
                    value: 'koli', label: Text(widget.urun.koliBirimAdi)),
            ],
            selected: {_birim == 'kg' ? 'adet' : _birim},
            onSelectionChanged: (s) => setState(() {
              _birim = s.first;
              _hata = null;
            }),
          )
        else
          Text('Bu ürün Kg bazında satılıyor',
              style:
                  TextStyle(fontSize: 12, color: TsRenk.metinIkincil(context))),
        if (koliVar && _birim == 'koli')
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
                '1 ${widget.urun.koliBirimAdi} = ${widget.urun.koliIciMiktar.toStringAsFixed(0)} ${widget.urun.birimAdi}',
                style: TextStyle(
                    fontSize: 11, color: TsRenk.metinIkincil(context))),
          ),
        // Profesyonel B2B kuralı: asgari sipariş miktarı (MOQ) tanımlıysa
        // kullanıcıya baştan göster — sürpriz hata yerine önceden bilgi.
        if (asgari > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              Icon(Icons.info_outline,
                  size: 14, color: TsRenk.metinIkincil(context)),
              const SizedBox(width: 4),
              Text(
                  'Asgari sipariş: ${asgari.toStringAsFixed(asgari == asgari.roundToDouble() ? 0 : 1)} ${widget.urun.birimAdi}',
                  style: TextStyle(
                      fontSize: 11.5, color: TsRenk.metinIkincil(context))),
            ]),
          ),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Vazgeç')),
        FilledButton(
          onPressed: () {
            final miktar =
                ParaUtils.sayiCoz(_miktarCtrl.text) ?? 0;
            if (miktar <= 0) {
              setState(() => _hata = 'Geçerli bir miktar girin');
              return;
            }
            final temelMiktar = _temelBirimMiktar(miktar);
            if (asgari > 0 && temelMiktar < asgari) {
              setState(() => _hata =
                  'Asgari sipariş miktarı ${asgari.toStringAsFixed(asgari == asgari.roundToDouble() ? 0 : 1)} ${widget.urun.birimAdi}');
              return;
            }
            Navigator.pop(context, (miktar, kgUrunu ? 'kg' : _birim));
          },
          child: const Text('Ekle'),
        ),
      ],
    );
  }
}
