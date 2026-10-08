// lib/ekranlar/rapor/masaustu/gunluk_rapor_masaustu_gorunum.dart
//
// Gün Sonu Raporu — masaüstü (geniş pencere) görünümü. Mobildeki tek sütun
// kart listesi geniş ekranda boşluklu ve uzun duruyordu (kullanıcı isteği
// 2026-10-08). Düzen Satış Raporu masaüstü görünümüyle aynı: dönem şeridi,
// KPI şeridi, solda fiş tablosu (çift tık = fiş detayı), sağda ödeme
// dağılımı ve kâr hesabı, altta özet şerit (F5 Yenile / F8 PDF / F9 Excel).
// Veri ve işlemler ekranın kendi durumundan gelir — burada hesap yapılmaz.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../cekirdek/utils/para_utils.dart';
import '../../../modeller/satis_model.dart';
import '../../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../../uygulama/tema/uygulama_temasi.dart';
import '../../../widgetlar/masaustu/masaustu_alt_serit.dart';
import '../../../widgetlar/masaustu/masaustu_tablo.dart';
import '../../../widgetlar/ortak/sync_kopyasi_uyarisi.dart';

/// Ekranın hesapladığı özet rakamlar.
class GunlukRaporOzet {
  final double toplam, nakit, kart, cari, havale, diger;
  final double gider, maliyet, iade, brutKar, netKar;
  const GunlukRaporOzet({
    required this.toplam,
    required this.nakit,
    required this.kart,
    required this.cari,
    required this.havale,
    required this.diger,
    required this.gider,
    required this.maliyet,
    required this.iade,
    required this.brutKar,
    required this.netKar,
  });
}

class GunlukRaporMasaustuGorunum extends StatefulWidget {
  final List<SatisModel> satislar;
  final GunlukRaporOzet ozet;
  final bool yukleniyor;
  final DateTime baslangic, bitis;
  final String periyot;
  final List<String> periyotlar;
  final ValueChanged<String> onPeriyot;
  final VoidCallback onOzelAralik;
  final VoidCallback onYenile, onPdf, onExcel;
  final ValueChanged<SatisModel> onFisDetay;

  const GunlukRaporMasaustuGorunum({
    super.key,
    required this.satislar,
    required this.ozet,
    required this.yukleniyor,
    required this.baslangic,
    required this.bitis,
    required this.periyot,
    required this.periyotlar,
    required this.onPeriyot,
    required this.onOzelAralik,
    required this.onYenile,
    required this.onPdf,
    required this.onExcel,
    required this.onFisDetay,
  });

  @override
  State<GunlukRaporMasaustuGorunum> createState() => _GunlukRaporMasaustuGorunumState();
}

class _GunlukRaporMasaustuGorunumState extends State<GunlukRaporMasaustuGorunum> {
  SatisModel? _secili;
  final _gun = DateFormat('dd.MM.yyyy');
  final _saat = DateFormat('dd.MM.yyyy HH:mm');

  late final List<TabloKolon<SatisModel>> _kolonlar = [
    TabloKolon(
      baslik: 'Fiş No',
      genislik: 160,
      deger: (s) => ParaUtils.kisaFisNo(s.fisNo) != 'FİŞ'
          ? ParaUtils.kisaFisNo(s.fisNo)
          : (s.id?.toString().padLeft(6, '0') ?? '—'),
      sirala: (s) => s.fisNo ?? '',
    ),
    TabloKolon(
      baslik: 'Tarih',
      genislik: 140,
      deger: (s) => _saat.format(s.tarih),
      sirala: (s) => s.tarih.millisecondsSinceEpoch,
    ),
    TabloKolon(
      baslik: 'Müşteri',
      genislik: 200,
      esnek: true,
      deger: (s) => s.cariAdi ?? 'Perakende',
      sirala: (s) => (s.cariAdi ?? '').toLowerCase(),
    ),
    TabloKolon(
      baslik: 'Ödeme',
      genislik: 110,
      deger: (s) => s.odemeYontemi,
      sirala: (s) => s.odemeYontemi,
      renk: (s) => _odemeRengi(s.odemeYontemi),
    ),
    TabloKolon(
      baslik: 'İskonto',
      genislik: 90,
      sagaYasli: true,
      deger: (s) => s.iskonto > 0 ? ParaUtils.formatla(s.iskonto, simge: '') : '',
      sirala: (s) => s.iskonto,
    ),
    TabloKolon(
      baslik: 'Tutar',
      genislik: 120,
      sagaYasli: true,
      deger: (s) => ParaUtils.formatla(s.genelToplam, simge: ''),
      sirala: (s) => s.genelToplam,
    ),
  ];

  static Color _odemeRengi(String y) => switch (y) {
    'Nakit' => const Color(0xFF2E7D32),
    'Kredi Kartı' => const Color(0xFFEF6C00),
    'Cari' => const Color(0xFF3949AB),
    'Havale' => const Color(0xFF00897B),
    _ => const Color(0xFF546E7A),
  };

  Widget _kpi(String baslik, String deger, Color renk, {IconData? ikon}) => Expanded(
    child: Container(
      margin: const EdgeInsets.only(right: 10),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: TsRenk.kart(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.borderColor),
      ),
      // Sol renk şeridi ayrı çizilir: yuvarlak köşeli kenarlık tek renk olmalı.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: renk),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (ikon != null) ...[
                          Icon(ikon, size: 14, color: renk),
                          const SizedBox(width: 4),
                        ],
                        Flexible(
                          child: Text(
                            baslik,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11.5, color: TsRenk.metinIkincil(context)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        deger,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: renk),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Color _karRengi(double v) => v > 0
      ? const Color(0xFF2E7D32)
      : v < 0
      ? TsRenk.hata
      : TsRenk.metinIkincil(context);

  @override
  Widget build(BuildContext context) {
    final o = widget.ozet;
    final fisSayisi = widget.satislar.length;
    return Column(
      children: [
        // Dönem şeridi
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
          child: Row(
            children: [
              for (final p in widget.periyotlar)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(p),
                    selected: widget.periyot == p,
                    onSelected: (_) => p == 'Özel' ? widget.onOzelAralik() : widget.onPeriyot(p),
                  ),
                ),
              const SizedBox(width: 4),
              OutlinedButton.icon(
                icon: const Icon(Icons.date_range, size: 16),
                label: Text(
                  widget.baslangic.year == widget.bitis.year &&
                          widget.baslangic.month == widget.bitis.month &&
                          widget.baslangic.day == widget.bitis.day
                      ? _gun.format(widget.baslangic)
                      : '${_gun.format(widget.baslangic)} – ${_gun.format(widget.bitis)}',
                  style: const TextStyle(fontSize: 13),
                ),
                onPressed: widget.onOzelAralik,
              ),
              const Spacer(),
              if (widget.yukleniyor)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14),
          child: SyncKopyasiUyarisi(
            kart: true,
            mesaj: 'senkron kopyası şüpheli satış bu toplamlara dahil EDİLMEDİ — incelemek için dokunun',
          ),
        ),
        // KPI şeridi
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 4, 10),
          child: Row(
            children: [
              _kpi(
                'Toplam Satış',
                ParaUtils.formatla(o.toplam),
                const Color(0xFF1565C0),
                ikon: Icons.point_of_sale,
              ),
              _kpi('Fiş Sayısı', '$fisSayisi', const Color(0xFF6A1B9A), ikon: Icons.receipt_long),
              _kpi(
                'Ort. Fiş',
                ParaUtils.formatla(fisSayisi > 0 ? o.toplam / fisSayisi : 0),
                const Color(0xFF00838F),
                ikon: Icons.functions,
              ),
              _kpi(
                'İade',
                ParaUtils.formatla(o.iade),
                const Color(0xFFD84315),
                ikon: Icons.assignment_return,
              ),
              _kpi('Gider', ParaUtils.formatla(o.gider), TsRenk.hata, ikon: Icons.money_off),
              _kpi(
                'Brüt Kâr',
                ParaUtils.formatla(o.brutKar),
                _karRengi(o.brutKar),
                ikon: Icons.trending_up,
              ),
              _kpi(
                'Net Kâr',
                ParaUtils.formatla(o.netKar),
                _karRengi(o.netKar),
                ikon: Icons.account_balance_wallet,
              ),
            ],
          ),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 14, bottom: 10),
                  child: widget.satislar.isEmpty
                      ? TsBosDurum(
                          ikon: Icons.receipt_long_outlined,
                          baslik: widget.yukleniyor
                              ? 'Yükleniyor…'
                              : 'Bu tarih aralığında işlem yok',
                        )
                      : MasaustuTablo<SatisModel>(
                          satirlar: widget.satislar,
                          kolonlar: _kolonlar,
                          secili: _secili,
                          onSec: (s) => setState(() => _secili = s),
                          onCift: widget.onFisDetay,
                        ),
                ),
              ),
              SizedBox(
                width: 340,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 0, 14, 12),
                  children: [
                    _Panel(
                      baslik: 'Ödeme Dağılımı',
                      children: [
                        for (final (ad, tutar) in [
                          ('Nakit', o.nakit),
                          ('Kredi Kartı', o.kart),
                          ('Cari', o.cari),
                          ('Havale', o.havale),
                          if (o.diger > 0) ('Diğer (QR/Karma)', o.diger),
                        ])
                          _OdemeSatiri(
                            ad: ad,
                            tutar: tutar,
                            toplam: o.toplam,
                            renk: _odemeRengi(ad),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _Panel(
                      baslik: 'Kâr Hesabı',
                      children: [
                        _HesapSatiri('Toplam Satış', o.toplam),
                        _HesapSatiri('İade', -o.iade, eksi: true),
                        _HesapSatiri('Maliyet (alış, KDV dahil)', -o.maliyet, eksi: true),
                        const Divider(height: 14),
                        _HesapSatiri(
                          'Brüt Kâr',
                          o.brutKar,
                          kalin: true,
                          renk: _karRengi(o.brutKar),
                        ),
                        _HesapSatiri('Gider', -o.gider, eksi: true),
                        const Divider(height: 14),
                        _HesapSatiri('Net Kâr', o.netKar, kalin: true, renk: _karRengi(o.netKar)),
                        if (o.iade > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              'Maliyetten iade edilen malın alış maliyeti düşülmüştür.',
                              style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context)),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        MasaustuAltSerit(
          ozetler: [
            AltOzet('Fiş', '$fisSayisi'),
            AltOzet('Satış', ParaUtils.formatla(o.toplam)),
            AltOzet(
              'Brüt Kâr',
              ParaUtils.formatla(o.brutKar),
              renk: o.brutKar < 0 ? TsRenk.hata : const Color(0xFF2E7D32),
            ),
            AltOzet(
              'Net Kâr',
              ParaUtils.formatla(o.netKar),
              renk: o.netKar < 0 ? TsRenk.hata : const Color(0xFF2E7D32),
            ),
          ],
          tuslar: [
            AltTus('F5', 'Yenile', Icons.refresh, const Color(0xFF1565C0), widget.onYenile),
            AltTus(
              'F8',
              'PDF',
              Icons.picture_as_pdf,
              const Color(0xFFC62828),
              widget.yukleniyor ? null : widget.onPdf,
            ),
            AltTus(
              'F9',
              'Excel',
              Icons.table_view,
              const Color(0xFF2E7D32),
              widget.yukleniyor || widget.satislar.isEmpty ? null : widget.onExcel,
            ),
          ],
        ),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  final String baslik;
  final List<Widget> children;
  const _Panel({required this.baslik, required this.children});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: TsRenk.kart(context),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: context.borderColor),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(baslik, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        ...children,
      ],
    ),
  );
}

class _OdemeSatiri extends StatelessWidget {
  final String ad;
  final double tutar, toplam;
  final Color renk;
  const _OdemeSatiri({
    required this.ad,
    required this.tutar,
    required this.toplam,
    required this.renk,
  });

  @override
  Widget build(BuildContext context) {
    final oran = toplam > 0 ? (tutar / toplam).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: renk, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Expanded(child: Text(ad, style: const TextStyle(fontSize: 13))),
              Text(ParaUtils.formatla(tutar), style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              SizedBox(
                width: 44,
                child: Text(
                  '%${(oran * 100).toStringAsFixed(1)}',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 12, color: TsRenk.metinIkincil(context)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: oran,
              minHeight: 6,
              backgroundColor: TsRenk.arkaplan(context),
              valueColor: AlwaysStoppedAnimation(renk),
            ),
          ),
        ],
      ),
    );
  }
}

class _HesapSatiri extends StatelessWidget {
  final String etiket;
  final double tutar;
  final bool kalin, eksi;
  final Color? renk;
  const _HesapSatiri(this.etiket, this.tutar, {this.kalin = false, this.eksi = false, this.renk});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(
          child: Text(
            etiket,
            style: TextStyle(
              fontSize: kalin ? 14 : 13,
              fontWeight: kalin ? FontWeight.w700 : FontWeight.normal,
              color: eksi ? TsRenk.metinIkincil(context) : null,
            ),
          ),
        ),
        Text(
          // "₺-90,00" yerine okunaklı "−₺90,00".
          tutar < 0 ? '−${ParaUtils.formatla(-tutar)}' : ParaUtils.formatla(tutar),
          style: TextStyle(
            fontSize: kalin ? 15 : 13,
            fontWeight: kalin ? FontWeight.w800 : FontWeight.w500,
            color: renk ?? (eksi && tutar != 0 ? TsRenk.hata : null),
          ),
        ),
      ],
    ),
  );
}
