// lib/ekranlar/rapor/masaustu/satis_rapor_masaustu_gorunum.dart
//
// Satış Raporu — masaüstü (geniş pencere) görünümü: dönem seçici, KPI
// şeridi, fiş tablosu (çift tık = satış detayı), sağda ödeme dağılımı ve
// saatlik satış grafiği, altta özet şerit (F5 Yenile / F9 Excel).
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../cekirdek/utils/para_utils.dart';
import '../../../modeller/satis_model.dart';
import '../../../servisler/bildirim_servisi.dart';
import '../../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../../uygulama/tema/uygulama_temasi.dart';
import '../../../widgetlar/masaustu/masaustu_alt_serit.dart';
import '../../../widgetlar/masaustu/masaustu_tablo.dart';
import '../satis_rapor_ortak.dart';

class SatisRaporMasaustuGorunum extends ConsumerStatefulWidget {
  const SatisRaporMasaustuGorunum({super.key});

  @override
  ConsumerState<SatisRaporMasaustuGorunum> createState() =>
      _SatisRaporMasaustuGorunumState();
}

class _SatisRaporMasaustuGorunumState
    extends ConsumerState<SatisRaporMasaustuGorunum> {
  SatisModel? _secili;
  final _gun = DateFormat('dd.MM.yyyy');
  final _saat = DateFormat('dd.MM.yyyy HH:mm');

  late final List<TabloKolon<SatisModel>> _kolonlar = [
    TabloKolon(
        baslik: 'Fiş No',
        genislik: 150,
        deger: (s) => s.fisNo ?? '—',
        sirala: (s) => s.fisNo ?? ''),
    TabloKolon(
        baslik: 'Tarih',
        genislik: 130,
        deger: (s) => _saat.format(s.tarih),
        sirala: (s) => s.tarih.millisecondsSinceEpoch),
    TabloKolon(
        baslik: 'Cari',
        genislik: 200,
        esnek: true,
        deger: (s) => s.cariAdi ?? '',
        sirala: (s) => (s.cariAdi ?? '').toLowerCase()),
    TabloKolon(
        baslik: 'Ödeme',
        genislik: 100,
        deger: (s) => s.odemeYontemi,
        sirala: (s) => s.odemeYontemi),
    TabloKolon(
        baslik: 'İskonto',
        genislik: 90,
        sagaYasli: true,
        deger: (s) => s.iskonto > 0 ? ParaUtils.formatla(s.iskonto, simge: '') : '',
        sirala: (s) => s.iskonto),
    TabloKolon(
        baslik: 'Tutar',
        genislik: 110,
        sagaYasli: true,
        deger: (s) => ParaUtils.formatla(s.genelToplam, simge: ''),
        sirala: (s) => s.genelToplam),
  ];

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_tus);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_tus);
    super.dispose();
  }

  bool _tus(KeyEvent e) {
    if (e is! KeyDownEvent || !mounted) return false;
    if (ModalRoute.of(context)?.isCurrent == false) return false;
    if (e.logicalKey == LogicalKeyboardKey.f5) {
      ref.invalidate(satisRaporProvider);
    } else if (e.logicalKey == LogicalKeyboardKey.f9) {
      final d = ref.read(satisRaporProvider).value;
      if (d != null) _excel(satisRaporSatislar(d));
    } else {
      return false;
    }
    return true;
  }

  Future<void> _excel(List<SatisModel> satislar) async {
    try {
      await satisRaporExcelAktar(satislar);
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Excel hatası: $e');
    }
  }

  Future<void> _donem(String d) async {
    final n = ref.read(satisRaporFiltreProvider.notifier);
    if (d != 'Özel') {
      final f = satisRaporDonemFiltresi(d);
      if (f != null) n.state = f;
      return;
    }
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      locale: const Locale('tr', 'TR'),
    );
    if (r != null && mounted) {
      n.state = SatisRaporFiltre(
          bas: r.start,
          bit: DateTime(r.end.year, r.end.month, r.end.day, 23, 59, 59),
          donem: 'Özel');
    }
  }

  Widget _kpi(String baslik, String deger, Color renk) => Expanded(
        child: Container(
          margin: const EdgeInsets.only(right: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: TsRenk.kart(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: context.borderColor),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(baslik,
                style: TextStyle(fontSize: 11.5, color: TsRenk.metinIkincil(context))),
            const SizedBox(height: 2),
            Text(deger,
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w800, color: renk)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final filtre = ref.watch(satisRaporFiltreProvider);
    final async = ref.watch(satisRaporProvider);
    final d = async.value;

    final ciro = (d?['ciro'] as double?) ?? 0;
    final iade = (d?['iade'] as double?) ?? 0;
    final brutKar = (d?['brutKar'] as double?) ?? 0;

    return Column(children: [
      // Dönem şeridi
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
        child: Row(children: [
          for (final p in satisRaporDonemler)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(p),
                selected: filtre.donem == p,
                onSelected: (_) => _donem(p),
              ),
            ),
          const SizedBox(width: 8),
          Text('${_gun.format(filtre.bas)} – ${_gun.format(filtre.bit)}',
              style: TextStyle(color: TsRenk.metinIkincil(context), fontSize: 12.5)),
        ]),
      ),
      // KPI şeridi
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 4, 8),
        child: Row(children: [
          _kpi('Toplam Ciro', ParaUtils.formatla(ciro), Colors.blue.shade700),
          _kpi('Satış Sayısı', '${(d?['sayi'] as int?) ?? 0}', Colors.green.shade700),
          _kpi('Ort. Fiş', ParaUtils.formatla((d?['ortalamaFis'] as double?) ?? 0),
              Colors.purple.shade700),
          _kpi('İskonto', ParaUtils.formatla((d?['iskonto'] as double?) ?? 0),
              Colors.orange.shade700),
          _kpi('İade', ParaUtils.formatla(iade), Colors.red.shade700),
          _kpi('Net Ciro', ParaUtils.formatla((d?['netCiro'] as double?) ?? 0),
              Colors.teal.shade700),
          _kpi('Brüt Kâr', ParaUtils.formatla(brutKar),
              brutKar >= 0 ? Colors.green.shade800 : Colors.red.shade700),
        ]),
      ),
      if (((d?['iptal'] as int?) ?? 0) > 0)
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('${d!['iptal']} iptal satış (toplamlara dahil değil)',
                style: TextStyle(color: Colors.red.shade700, fontSize: 12.5)),
          ),
        ),
      Expanded(
        child: async.when(
          loading: () => const TsYukleniyor(),
          error: (e, _) => TsBosDurum(
              ikon: Icons.error_outline,
              baslik: 'Yüklenemedi: $e',
              renk: TsRenk.hata,
              aksiyonMetni: 'Tekrar dene',
              aksiyon: () => ref.invalidate(satisRaporProvider)),
          data: (data) {
            final satislar = satisRaporSatislar(data);
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: satislar.isEmpty
                    ? const TsBosDurum(
                        ikon: Icons.receipt_long_outlined,
                        baslik: 'Bu dönemde satış bulunamadı')
                    : MasaustuTablo<SatisModel>(
                        satirlar: satislar,
                        kolonlar: _kolonlar,
                        secili: _secili,
                        onSec: (s) => setState(() => _secili = s),
                        onCift: (s) {
                          if (s.id != null) context.push('/satis/detay/${s.id}');
                        },
                      ),
              ),
              SizedBox(
                width: 340,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 0, 14, 12),
                  children: [
                    _OdemeDagilimi(
                        odemeMap: data['odemeMap'] as Map<String, double>,
                        ciro: data['ciro'] as double),
                    const SizedBox(height: 12),
                    _SaatGrafigi(saatMap: data['saatMap'] as Map<int, double>),
                  ],
                ),
              ),
            ]);
          },
        ),
      ),
      MasaustuAltSerit(
        ozetler: [
          AltOzet('Fiş', '${(d?['sayi'] as int?) ?? 0}'),
          AltOzet('Ciro', ParaUtils.formatla(ciro)),
          AltOzet('Net Ciro', ParaUtils.formatla((d?['netCiro'] as double?) ?? 0)),
          AltOzet('Brüt Kâr', ParaUtils.formatla(brutKar),
              renk: brutKar < 0 ? TsRenk.hata : const Color(0xFF2E7D32)),
        ],
        tuslar: [
          AltTus('F5', 'Yenile', Icons.refresh, const Color(0xFF1565C0),
              () => ref.invalidate(satisRaporProvider)),
          AltTus('F9', 'Excel', Icons.table_view, const Color(0xFF2E7D32),
              d == null ? null : () => _excel(satisRaporSatislar(d))),
        ],
      ),
    ]);
  }
}

class _OdemeDagilimi extends StatelessWidget {
  final Map<String, double> odemeMap;
  final double ciro;
  const _OdemeDagilimi({required this.odemeMap, required this.ciro});

  @override
  Widget build(BuildContext context) {
    final girdiler = odemeMap.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TsRenk.kart(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Ödeme Yöntemi',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        if (girdiler.isEmpty)
          Text('Veri yok', style: TextStyle(color: TsRenk.metinIkincil(context))),
        for (final e in girdiler)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                        color: satisRaporOdemeRengi(e.key), shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(e.key, style: const TextStyle(fontSize: 13)),
                const Spacer(),
                Text(ParaUtils.formatla(e.value),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Text('%${(ciro > 0 ? e.value / ciro * 100 : 0).toStringAsFixed(1)}',
                    style: TextStyle(
                        fontSize: 12, color: TsRenk.metinIkincil(context))),
              ]),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: ciro > 0 ? (e.value / ciro).clamp(0.0, 1.0) : 0,
                  minHeight: 6,
                  backgroundColor: TsRenk.arkaplan(context),
                  valueColor:
                      AlwaysStoppedAnimation(satisRaporOdemeRengi(e.key)),
                ),
              ),
            ]),
          ),
      ]),
    );
  }
}

class _SaatGrafigi extends StatelessWidget {
  final Map<int, double> saatMap;
  const _SaatGrafigi({required this.saatMap});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 230,
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
      decoration: BoxDecoration(
        color: TsRenk.kart(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Saatlik Satış',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Expanded(
          child: saatMap.isEmpty
              ? Center(
                  child: Text('Veri yok',
                      style: TextStyle(color: TsRenk.metinIkincil(context))))
              : BarChart(BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (g, _, rod, __) => BarTooltipItem(
                          '${g.x}:00\n${ParaUtils.formatla(rod.toY)}',
                          const TextStyle(color: Colors.white, fontSize: 11)),
                    ),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (v, _) => v.toInt() % 4 != 0
                          ? const SizedBox.shrink()
                          : Text('${v.toInt()}',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: TsRenk.metinIkincil(context))),
                    )),
                  ),
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (_) =>
                          FlLine(color: context.borderColor, strokeWidth: 1)),
                  barGroups: List.generate(
                      24,
                      (h) => BarChartGroupData(x: h, barRods: [
                            BarChartRodData(
                              toY: saatMap[h] ?? 0,
                              color: AppRenkler.primary,
                              width: 8,
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(3)),
                            )
                          ])),
                )),
        ),
      ]),
    );
  }
}
