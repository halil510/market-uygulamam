// lib/ekranlar/bayi/bayi_fatura_detay_ekrani.dart
//
// Bayi Portalı — bir faturanın kalemlerini gösterir. widget.fatura,
// zaten cari_id filtresiyle gelen BayiFaturalarimEkrani listesinden
// geldiği için burada ayrıca bir yetki kontrolüne gerek yok — ama
// FaturaDeposu().idileGetir(id) ile GÜVENİLİR kaynaktan (kalemler dahil)
// yeniden çekiliyor, listedeki hafif satırla yetinilmiyor.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../depolar/fatura_deposu.dart';
import '../../modeller/fatura_model.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';

class BayiFaturaDetayEkrani extends StatefulWidget {
  final FaturaModel fatura;
  const BayiFaturaDetayEkrani({super.key, required this.fatura});
  @override
  State<BayiFaturaDetayEkrani> createState() => _BayiFaturaDetayEkraniState();
}

class _BayiFaturaDetayEkraniState extends State<BayiFaturaDetayEkrani> {
  FaturaModel? _fatura;
  bool _yukleniyor = true;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    if (widget.fatura.id == null) return;
    final f = await FaturaDeposu().idileGetir(widget.fatura.id!);
    if (mounted) setState(() { _fatura = f ?? widget.fatura; _yukleniyor = false; });
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd.MM.yyyy HH:mm');
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(baslik: widget.fatura.faturaNo ?? 'Fatura', gradyanli: true),
      body: _yukleniyor
          ? const TsYukleniyor()
          : ListView(
              padding: const EdgeInsets.all(TsBosluk.lg),
              children: [
                TsKart(
                  child: Padding(
                    padding: const EdgeInsets.all(TsBosluk.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_fatura!.faturaNo ?? '—', style: TsMetin.baslikM),
                        const SizedBox(height: TsBosluk.xs),
                        Text(fmt.format(_fatura!.tarih),
                            style: TsMetin.kucuk.copyWith(color: TsRenk.metinIkincil(context))),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: TsBosluk.lg),
                Text('Kalemler', style: TsMetin.baslikM.copyWith(color: TsRenk.metinBirincil(context))),
                const SizedBox(height: TsBosluk.sm),
                ..._fatura!.detaylar.map((k) => Padding(
                      padding: const EdgeInsets.only(bottom: TsBosluk.sm),
                      child: TsKart.liste(
                        baslik: k.urunAdi,
                        altBaslik: '${_miktarStr(k.miktar)} x ${ParaUtils.formatla(k.birimFiyat)}',
                        deger: ParaUtils.formatla(k.toplamTutar),
                      ),
                    )),
                const SizedBox(height: TsBosluk.lg),
                TsKart(
                  child: Padding(
                    padding: const EdgeInsets.all(TsBosluk.md),
                    child: Column(children: [
                      // Not: "Ara Toplam" BİLEREK indirim UYGULANMADAN ÖNCEKİ
                      // brüt tutar olarak gösteriliyor (toplamAraToplam
                      // zaten net saklanıyor) — aksi halde alttaki "İskonto"
                      // satırı ikinci kez düşülmüş gibi görünüp toplam
                      // tutmazdı.
                      _ozetSatir(context, 'Ara Toplam', _fatura!.toplamAraToplam + _fatura!.toplamIskonto),
                      if (_fatura!.toplamIskonto > 0)
                        _ozetSatir(context, 'İskonto', -_fatura!.toplamIskonto),
                      _ozetSatir(context, 'KDV', _fatura!.toplamKdv),
                      _ozetSatir(context, 'Genel Toplam', _fatura!.genelToplam, kalin: true),
                    ]),
                  ),
                ),
                const SizedBox(height: TsBosluk.xxxl),
              ],
            ),
    );
  }

  String _miktarStr(double m) => m == m.roundToDouble() ? m.toStringAsFixed(0) : m.toStringAsFixed(2);

  Widget _ozetSatir(BuildContext context, String etiket, double tutar, {bool kalin = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Text(etiket,
              style: kalin
                  ? TsMetin.govdeVurgu.copyWith(color: TsRenk.metinBirincil(context))
                  : TsMetin.govde.copyWith(color: TsRenk.metinIkincil(context))),
          const Spacer(),
          Text(ParaUtils.formatla(tutar),
              style: kalin
                  ? TsMetin.baslikM.copyWith(color: TsRenk.metinBirincil(context))
                  : TsMetin.govde.copyWith(color: TsRenk.metinBirincil(context))),
        ]),
      );
}
