// lib/ekranlar/rapor/kar_zarar_ekrani.dart  (Riverpod versiyonu)
//
// DEĞIŞIKLIKLER:
//   - StatefulWidget → ConsumerStatefulWidget
//   - KarZararNotifier (ChangeNotifier) → karZararProvider (AsyncNotifier)
//   - Provider.of / context.read kaldırıldı
//   - Dönem seçici modernize edildi (SegmentedButton)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:share_plus/share_plus.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../../saglayicilar/riverpod/kar_zarar_provider.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../servisler/bildirim_servisi.dart';

class KarZararEkrani extends ConsumerStatefulWidget {
  const KarZararEkrani({super.key});

  @override
  ConsumerState<KarZararEkrani> createState() => _KarZararEkraniState();
}

class _KarZararEkraniState extends ConsumerState<KarZararEkrani>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  static const _donemler = [
    ('Bugun',      'Bugün'),
    ('Bu Hafta',   'Bu Hafta'),
    ('Bu Ay',      'Bu Ay'),
    ('Bu Yil',     'Bu Yıl'),
    ('Ozel',       'Özel'),
  ];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _ozelAralikSec() async {
    final filtre = ref.read(karZararFiltresiProvider);
    final secilen = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate:  DateTime.now(),
      initialDateRange: DateTimeRange(
          start: filtre.basTarih, end: filtre.bitTarih),
      locale: const Locale('tr', 'TR'),
    );
    if (secilen != null && mounted) {
      ref.read(karZararFiltresiProvider.notifier)
          .tarihAyarla(secilen.start, secilen.end);
    }
  }

  Future<void> _excelAktar(KarZararVeri veri) async {
    try {
      final excel = Excel.createExcel();
      final sheet = excel['Kar-Zarar'];
      sheet.appendRow([
        TextCellValue('Metrik'), TextCellValue('Değer'),
      ]);
      sheet.appendRow([TextCellValue('Ciro'),          TextCellValue(ParaUtils.formatla(veri.ciro))]);
      sheet.appendRow([TextCellValue('Alış Maliyet'),  TextCellValue(ParaUtils.formatla(veri.alisMaliyeti))]);
      sheet.appendRow([TextCellValue('Brüt Kâr'),      TextCellValue(ParaUtils.formatla(veri.brutKar))]);
      sheet.appendRow([TextCellValue('Gider'),         TextCellValue(ParaUtils.formatla(veri.giderToplam))]);
      sheet.appendRow([TextCellValue('Net Kâr'),       TextCellValue(ParaUtils.formatla(veri.netKar))]);

      final dir  = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/kar_zarar_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      final file = File(path);
      await file.writeAsBytes(excel.encode()!);
      await Share.shareXFiles([XFile(path)], text: 'Kâr-Zarar Raporu');
    } catch (e) {
      if (mounted) {
        BildirimServisi.hata(context, 'Excel hatası: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtre    = ref.watch(karZararFiltresiProvider);
    final karAsync  = ref.watch(karZararProvider);

    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'Kâr - Zarar',
        aksiyonlar: [
          karAsync.whenOrNull(
            data: (veri) => IconButton(
              icon: const Icon(Icons.table_chart_outlined),
              onPressed: () => _excelAktar(veri),
              tooltip: 'Excel',
            ),
          ) ?? const SizedBox.shrink(),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(karZararProvider),
          ),
        ],
        alt: TabBar(
          controller: _tab,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Özet'),
            Tab(text: 'Ödeme Tipi'),
            Tab(text: 'Gider'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Dönem seçici
          _DonemSecici(
            seciliDonem: filtre.donem,
            donemler:    _donemler,
            onSec: (donem) {
              if (donem == 'Ozel') {
                _ozelAralikSec();
              } else {
                ref.read(karZararFiltresiProvider.notifier).donemAyarla(donem);
              }
            },
          ),

          // İçerik
          Expanded(
            child: karAsync.when(
              loading: () => const Center(child: const CircularProgressIndicator(color: TsRenk.primary, strokeWidth: 3)),
              error:   (e, _) => Center(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.error_outline, size: 48, color: context.textSecondary),
                  const SizedBox(height: 12),
                  Text('Veri yüklenemedi', style: TextStyle(color: TsRenk.metinIkincil(context))),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () => ref.invalidate(karZararProvider),
                    child: const Text('Tekrar Dene'),
                  ),
                ]),
              ),
              data: (veri) => TabBarView(
                controller: _tab,
                children: [
                  _OzetTab(veri: veri),
                  _OdemeTab(veri: veri),
                  _GiderTab(veri: veri),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Dönem Seçici ──────────────────────────────────────────────────────────────

class _DonemSecici extends StatelessWidget {
  final String seciliDonem;
  final List<(String, String)> donemler;
  final void Function(String) onSec;

  const _DonemSecici({
    required this.seciliDonem,
    required this.donemler,
    required this.onSec,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: donemler.map((d) {
            final (key, label) = d;
            final secili = seciliDonem == key ||
                (key == 'Ozel' && seciliDonem == 'Ozel');
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(label),
                selected: secili,
                onSelected: (_) => onSec(key),
                selectedColor: AppRenkler.primary,
                labelStyle: TextStyle(
                  color: secili ? Colors.white : context.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                backgroundColor: TsRenk.arkaplan(context),
                checkmarkColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ── Özet Tab ──────────────────────────────────────────────────────────────────

class _OzetTab extends StatelessWidget {
  final KarZararVeri veri;
  const _OzetTab({required this.veri});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Brüt kâr büyük kart
        _BuyukKartRow(
          sol: _MetrikKart(
            baslik: 'Ciro',
            deger:  veri.ciro,
            renk:   const Color(0xFF2196F3),
            ikon:   Icons.trending_up,
          ),
          sag: _MetrikKart(
            baslik: 'Alış Maliyeti',
            deger:  veri.alisMaliyeti,
            renk:   const Color(0xFF795548),
            ikon:   Icons.shopping_cart,
          ),
        ),
        const SizedBox(height: 12),
        _BuyukKartRow(
          sol: _MetrikKart(
            baslik: 'Brüt Kâr',
            deger:  veri.brutKar,
            renk:   const Color(0xFF4CAF50),
            ikon:   Icons.show_chart,
            altMetin: '%${veri.brutKarOrani.toStringAsFixed(1)}',
          ),
          sag: _MetrikKart(
            baslik: 'Gider',
            deger:  veri.giderToplam,
            renk:   const Color(0xFFC62828),
            ikon:   Icons.money_off,
          ),
        ),
        const SizedBox(height: 12),

        // Net kâr büyük kart
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: veri.netKar >= 0
                  ? [const Color(0xFF2E7D32), const Color(0xFF1B5E20)]
                  : [const Color(0xFFC62828), const Color(0xFF7F0000)],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(
              color: Color.fromARGB(76, (veri.netKar >= 0 ? Colors.green : Colors.red).red, (veri.netKar >= 0 ? Colors.green : Colors.red).green, (veri.netKar >= 0 ? Colors.green : Colors.red).blue),
              blurRadius: 16, offset: const Offset(0, 6),
            )],
          ),
          child: Row(children: [
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Net Kâr',
                    style: TextStyle(color: Colors.white70, fontSize: 14)),
                const SizedBox(height: 8),
                Text(ParaUtils.formatla(veri.netKar),
                    style: const TextStyle(
                        color: Colors.white, fontSize: 32,
                        fontWeight: FontWeight.w800)),
                Text('Oran: %${veri.netKarOrani.toStringAsFixed(1)}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            )),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Color(0x26FFFFFF),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                veri.netKar >= 0 ? Icons.thumb_up_outlined : Icons.thumb_down_outlined,
                color: Colors.white, size: 36,
              ),
            ),
          ]),
        ),

        const SizedBox(height: 16),

        // Aylık trend grafiği
        if (veri.aylikVeri.isNotEmpty) _AylikGrafik(aylikVeri: veri.aylikVeri),
      ],
    );
  }
}

class _BuyukKartRow extends StatelessWidget {
  final Widget sol;
  final Widget sag;
  const _BuyukKartRow({required this.sol, required this.sag});

  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(child: sol),
    const SizedBox(width: 12),
    Expanded(child: sag),
  ]);
}

class _MetrikKart extends StatelessWidget {
  final String  baslik;
  final double  deger;
  final Color   renk;
  final IconData ikon;
  final String? altMetin;

  const _MetrikKart({
    required this.baslik,
    required this.deger,
    required this.renk,
    required this.ikon,
    this.altMetin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TsRenk.kart(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Color.fromARGB(26, renk.red, renk.green, renk.blue),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(ikon, color: renk, size: 18),
          ),
        ]),
        const SizedBox(height: 10),
        Text(ParaUtils.formatla(deger),
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w800, color: renk)),
        if (altMetin != null)
          Text(altMetin!,
              style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context))),
        Text(baslik,
            style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context))),
      ]),
    );
  }
}

class _AylikGrafik extends StatelessWidget {
  final List<Map<String, dynamic>> aylikVeri;
  const _AylikGrafik({required this.aylikVeri});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: TsRenk.kart(context),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Aylık Trend',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        SizedBox(
          height: 160,
          child: BarChart(BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: aylikVeri.fold(0.0, (mx, x) {
              final v = (x['ciro'] as num?)?.toDouble() ?? 0;
              return v > mx ? v : mx;
            }) * 1.2,
            barTouchData: BarTouchData(enabled: false),
            titlesData: FlTitlesData(
              leftTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles:  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles:    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (v, _) {
                  final idx = v.toInt();
                  if (idx < 0 || idx >= aylikVeri.length) return const SizedBox.shrink();
                  final ay = aylikVeri[idx]['ay'] as String? ?? '';
                  return Text(ay.length >= 7 ? ay.substring(5) : ay,
                      style: TextStyle(fontSize: 10, color: TsRenk.metinIkincil(context)));
                },
              )),
            ),
            gridData: FlGridData(
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) =>
                  FlLine(color: context.borderColor, strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            barGroups: aylikVeri.asMap().entries.map((e) {
              final ciro = (e.value['ciro'] as num?)?.toDouble() ?? 0;
              return BarChartGroupData(x: e.key, barRods: [
                BarChartRodData(
                  toY: ciro,
                  color: AppRenkler.primary,
                  width: 22,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                ),
              ]);
            }).toList(),
          )),
        ),
      ]),
    );
  }
}

// ── Ödeme Tipi Tab ────────────────────────────────────────────────────────────

class _OdemeTab extends StatelessWidget {
  final KarZararVeri veri;
  const _OdemeTab({required this.veri});

  @override
  Widget build(BuildContext context) {
    if (veri.odemeByTur.isEmpty) {
      return const Center(child: Text('Veri yok'));
    }

    final toplam = veri.ciro;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: TsRenk.kart(context),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(
                color: Color(0x0D000000),
                blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Column(children: [
            const Text('Ödeme Yöntemi Dağılımı',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            ...veri.odemeByTur.map((o) {
              final ad  = o['odeme_yontemi'] as String? ?? 'Diğer';
              final top = (o['toplam'] as num?)?.toDouble() ?? 0;
              final oran = toplam > 0 ? top / toplam : 0.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(child: Text(ad,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w500))),
                      Text(ParaUtils.formatla(top),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 13)),
                      const SizedBox(width: 8),
                      Text('%${(oran * 100).toStringAsFixed(1)}',
                          style: TextStyle(
                              fontSize: 12, color: TsRenk.metinIkincil(context))),
                    ]),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: oran,
                        minHeight: 8,
                        backgroundColor: TsRenk.arkaplan(context),
                        valueColor: const AlwaysStoppedAnimation(AppRenkler.primary),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ]),
        ),
      ],
    );
  }
}

// ── Gider Tab ─────────────────────────────────────────────────────────────────

class _GiderTab extends StatelessWidget {
  final KarZararVeri veri;
  const _GiderTab({required this.veri});

  @override
  Widget build(BuildContext context) {
    if (veri.kategorGider.isEmpty) {
      return const Center(child: Text('Gider kaydı yok'));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: TsRenk.kart(context),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(
                color: Color(0x0D000000),
                blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Text('Kategori Bazlı Giderler',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Toplam: ${ParaUtils.formatla(veri.giderToplam)}',
                    style: TsMetin.kucukVurgu.copyWith(color: Colors.red.shade700),
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              ...veri.kategorGider.map((g) {
                final kat  = g['kategori'] as String? ?? 'Diğer';
                final top  = (g['toplam'] as num?)?.toDouble() ?? 0;
                final oran = veri.giderToplam > 0 ? top / veri.giderToplam : 0.0;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.category_outlined,
                        color: Colors.red.shade400, size: 20),
                  ),
                  title: Text(kat,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  subtitle: LinearProgressIndicator(
                    value: oran,
                    minHeight: 4,
                    backgroundColor: TsRenk.arkaplan(context),
                    valueColor: AlwaysStoppedAnimation(Colors.red.shade400),
                  ),
                  trailing: Text(ParaUtils.formatla(top),
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Colors.red.shade600)),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }
}
