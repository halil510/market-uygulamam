// lib/ekranlar/rapor/satis_rapor_ekrani.dart — Geliştirilmiş
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:excel/excel.dart' hide Border;
import '../../depolar/satis_deposu.dart';
import '../../modeller/satis_model.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

class _SatisRaporFiltre {
  final DateTime bas, bit;
  final String donem;
  _SatisRaporFiltre({required this.bas, required this.bit, this.donem = 'Bugün'});
  _SatisRaporFiltre.bugun() : bas = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day),
        bit = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day, 23, 59, 59), donem = 'Bugün';
  _SatisRaporFiltre.buAy() :
        bas = DateTime(DateTime.now().year, DateTime.now().month, 1),
        bit = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day, 23, 59, 59),
        donem = 'Bu Ay';
}

final _satisRaporFiltreProvider = StateProvider<_SatisRaporFiltre>(
  (_) => _SatisRaporFiltre.bugun());

final _satisRaporProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final f = ref.watch(_satisRaporFiltreProvider);
  final depo = SatisDeposu();
  final satislar = await depo.tariheGoreGetir(f.bas, f.bit);
  final aktif = satislar.where((s) => !s.iptal).toList();
  // 🔴 Derin analizde bulundu: tariheGoreGetir() zaten SQL seviyesinde
  // iptal edilmiş satışları filtreliyor — bu yüzden "satislar.length -
  // aktif.length" her zaman 0 çıkıyordu, "$X iptal satış" uyarısı
  // ASLA görünmüyordu. Artık gerçek sayı ayrı bir sorgu ile alınıyor.
  final iptalSayisi = await depo.iptalSayisiGetir(f.bas, f.bit);

  // Özet hesapla
  double ciro = 0, iskonto = 0;
  final odemeMap = <String, double>{};
  for (final s in aktif) {
    ciro += s.genelToplam;
    iskonto += s.iskonto ?? 0;
    odemeMap[s.odemeYontemi ?? 'Diğer'] =
        (odemeMap[s.odemeYontemi ?? 'Diğer'] ?? 0) + s.genelToplam;
  }

  // Saat bazında dağılım
  final saatMap = <int, double>{};
  for (final s in aktif) {
    final saat = s.tarih.hour;
    saatMap[saat] = (saatMap[saat] ?? 0) + s.genelToplam;
  }

  // En çok satan ürünler (basit yaklaşım - kalem bazında)
  return {
    'satislar':   satislar,
    'aktif':      aktif,
    'ciro':       ciro,
    'iskonto':    iskonto,
    'sayi':       aktif.length,
    'iptal':      iptalSayisi,
    'odemeMap':   odemeMap,
    'saatMap':    saatMap,
    'ortalamaFis': aktif.isEmpty ? 0.0 : ciro / aktif.length,
  };
});

// ── Ekran ─────────────────────────────────────────────────────────────────────

class SatisRaporEkrani extends ConsumerStatefulWidget {
  const SatisRaporEkrani({super.key});
  @override
  ConsumerState<SatisRaporEkrani> createState() => _SatisRaporEkraniState();
}

class _SatisRaporEkraniState extends ConsumerState<SatisRaporEkrani>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  final _fmt = DateFormat('dd.MM.yyyy');

  static const _donemler = ['Bugün', 'Bu Hafta', 'Bu Ay', 'Özel'];

  @override
  void initState() { super.initState(); _tab = TabController(length: 3, vsync: this); }
  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  void _donemSec(String donem) {
    final now = DateTime.now();
    late DateTime bas, bit;
    switch (donem) {
      case 'Bugün':
        bas = DateTime(now.year, now.month, now.day);
        bit = DateTime(now.year, now.month, now.day, 23, 59, 59);
      case 'Bu Hafta':
        final pzt = now.subtract(Duration(days: now.weekday - 1));
        bas = DateTime(pzt.year, pzt.month, pzt.day);
        bit = DateTime(now.year, now.month, now.day, 23, 59, 59);
      case 'Bu Ay':
        bas = DateTime(now.year, now.month, 1);
        bit = DateTime(now.year, now.month, now.day, 23, 59, 59);
      default: return;
    }
    ref.read(_satisRaporFiltreProvider.notifier).state =
        _SatisRaporFiltre(bas: bas, bit: bit, donem: donem);
  }

  Future<void> _ozelAralik() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020), lastDate: DateTime.now(),
      locale: const Locale('tr', 'TR'),
    );
    if (r != null && mounted) {
      ref.read(_satisRaporFiltreProvider.notifier).state =
          _SatisRaporFiltre(bas: r.start,
              bit: DateTime(r.end.year, r.end.month, r.end.day, 23, 59, 59), donem: 'Özel');
    }
  }

  Future<void> _excelAktar(List<SatisModel> satislar) async {
    try {
      final excel = Excel.createExcel();
      final sheet = excel['Satışlar'];
      sheet.appendRow([
        TextCellValue('Fiş No'), TextCellValue('Tarih'), TextCellValue('Müşteri'),
        TextCellValue('Ödeme'), TextCellValue('Toplam'), TextCellValue('İptal'),
      ]);
      final fmt = DateFormat('dd.MM.yyyy HH:mm');
      for (final s in satislar) {
        sheet.appendRow([
          TextCellValue(s.fisNo ?? ''),
          TextCellValue(fmt.format(s.tarih)),
          TextCellValue(s.cariAdi ?? ''),
          TextCellValue(s.odemeYontemi ?? ''),
          DoubleCellValue(s.genelToplam),
          TextCellValue(s.iptal ? 'Evet' : ''),
        ]);
      }
      final dir  = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/satis_raporu_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      await File(path).writeAsBytes(excel.encode()!);
      await Share.shareXFiles([XFile(path)], text: 'Satış Raporu');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Excel hatası: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtre = ref.watch(_satisRaporFiltreProvider);
    final async  = ref.watch(_satisRaporProvider);

    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'Satış Raporu',
        aksiyonlar: [
          async.whenOrNull(data: (d) => IconButton(
            icon: const Icon(Icons.download_outlined, color: Colors.white),
            onPressed: () => _excelAktar(d['satislar'] as List<SatisModel>),
            tooltip: 'Excel',
          )) ?? const SizedBox.shrink(),
          IconButton(icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: () => ref.invalidate(_satisRaporProvider)),
        ],
        alt: TabBar(
          controller: _tab,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [Tab(text: 'Özet'), Tab(text: 'Liste'), Tab(text: 'Grafik')],
        ),
        geriTusu: false,
      ),
      body: Column(children: [
        // Dönem seçici
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: _donemler.map((d) {
                  final secili = filtre.donem == d;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(d), selected: secili,
                      onSelected: (_) => d == 'Özel' ? _ozelAralik() : _donemSec(d),
                      selectedColor: AppRenkler.primary,
                      labelStyle: TextStyle(
                          color: secili ? Colors.white : context.textSecondary, fontSize: 12),
                      backgroundColor: TsRenk.arkaplan(context), checkmarkColor: Colors.white,
                    ),
                  );
                }).toList()),
              ),
            ),
            if (filtre.donem == 'Özel')
              Text('${_fmt.format(filtre.bas)} – ${_fmt.format(filtre.bit)}',
                  style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context))),
          ]),
        ),

        Expanded(
          child: async.when(
            loading: () => const Center(child: const CircularProgressIndicator(color: TsRenk.primary, strokeWidth: 3)),
            error:   (e, _) => Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.error_outline, size: 48, color: context.textSecondary),
                const SizedBox(height: 8),
                FilledButton(onPressed: () => ref.invalidate(_satisRaporProvider),
                    child: const Text('Tekrar Dene')),
              ])),
            data: (data) => TabBarView(
              controller: _tab,
              children: [
                _OzetTab(data: data),
                _ListeTab(satislar: data['satislar'] as List<SatisModel>),
                _GrafikTab(data: data),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Özet Tab ─────────────────────────────────────────────────────────────────
class _OzetTab extends StatelessWidget {
  final Map<String, dynamic> data;
  const _OzetTab({required this.data});

  @override
  Widget build(BuildContext context) {
    final ciro       = data['ciro'] as double;
    final iskonto    = data['iskonto'] as double;
    final sayi       = data['sayi'] as int;
    final iptal      = data['iptal'] as int;
    final ortalama   = data['ortalamaFis'] as double;
    final odemeMap   = data['odemeMap'] as Map<String, double>;

    return ListView(padding: const EdgeInsets.all(16), children: [
      // KPI grid
      GridView.count(
        shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.6,
        children: [
          _KpiKart('Toplam Ciro', ParaUtils.formatla(ciro), Icons.trending_up, Colors.blue.shade700),
          _KpiKart('Satış Sayısı', '$sayi adet', Icons.receipt_outlined, Colors.green.shade700),
          _KpiKart('Ort. Fiş', ParaUtils.formatla(ortalama), Icons.calculate_outlined, Colors.purple.shade700),
          _KpiKart('İskonto', ParaUtils.formatla(iskonto), Icons.discount_outlined, Colors.orange.shade700),
        ],
      ),
      if (iptal > 0) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
              color: Colors.red.shade50, borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.red.shade200)),
          child: Row(children: [
            const Icon(Icons.cancel_outlined, color: Colors.red, size: 18),
            const SizedBox(width: 8),
            Text('$iptal iptal satış', style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
          ]),
        ),
      ],
      const SizedBox(height: 16),

      // Ödeme dağılımı
      if (odemeMap.isNotEmpty) ...[
        const Text('Ödeme Yöntemi', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: TsRenk.kart(context), borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Color(0x0D000000), blurRadius: 8)]),
          child: Column(children: odemeMap.entries.map((e) {
            final oran = ciro > 0 ? e.value / ciro : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(e.key, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                  const Spacer(),
                  Text(ParaUtils.formatla(e.value),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(width: 8),
                  Text('%${(oran * 100).toStringAsFixed(1)}',
                      style: TextStyle(fontSize: 12, color: TsRenk.metinIkincil(context))),
                ]),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: oran, minHeight: 6,
                    backgroundColor: TsRenk.arkaplan(context),
                    valueColor: const AlwaysStoppedAnimation(AppRenkler.primary),
                  ),
                ),
              ]),
            );
          }).toList()),
        ),
      ],
    ]);
  }
}

class _KpiKart extends StatelessWidget {
  final String baslik, deger; final IconData ikon; final Color renk;
  const _KpiKart(this.baslik, this.deger, this.ikon, this.renk);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: TsRenk.kart(context), borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Color(0x0D000000), blurRadius: 6)]),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: Color.fromARGB(26, renk.red, renk.green, renk.blue), borderRadius: BorderRadius.circular(8)),
          child: Icon(ikon, color: renk, size: 16)),
      ]),
      const Spacer(),
      Text(deger, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: renk)),
      Text(baslik, style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context))),
    ]),
  );
}

// ── Liste Tab ─────────────────────────────────────────────────────────────────
class _ListeTab extends StatelessWidget {
  final List<SatisModel> satislar;
  const _ListeTab({required this.satislar});

  @override
  Widget build(BuildContext context) {
    if (satislar.isEmpty) return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.receipt_long_outlined, size: 64, color: context.textSecondary),
        const SizedBox(height: 12),
        Text('Satış bulunamadı', style: TextStyle(color: context.textSecondary)),
      ]),
    );
    final fmt = DateFormat('dd.MM HH:mm');
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: satislar.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (_, i) {
        final s = satislar[i];
        final iptal = s.iptal;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: iptal ? Colors.red.shade50 : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: iptal ? Colors.red.shade200 : Colors.transparent),
            boxShadow: iptal ? [] : [BoxShadow(color: Color(0x0A000000), blurRadius: 4)],
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: Color.fromARGB(20, (iptal ? Colors.red : AppRenkler.primary).red, (iptal ? Colors.red : AppRenkler.primary).green, (iptal ? Colors.red : AppRenkler.primary).blue),
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(iptal ? Icons.cancel_outlined : Icons.receipt_outlined,
                  color: iptal ? Colors.red : AppRenkler.primary, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.fisNo ?? '—', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              Text('${fmt.format(s.tarih)} · ${s.odemeYontemi ?? ''}',
                  style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context))),
              if (s.cariAdi != null)
                Text(s.cariAdi!, style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context))),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(ParaUtils.formatla(s.genelToplam),
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14,
                      color: iptal ? Colors.red : AppRenkler.primary)),
              if (iptal)
                const Text('İPTAL', style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w700, color: Colors.red)),
            ]),
          ]),
        );
      },
    );
  }
}

// ── Grafik Tab ────────────────────────────────────────────────────────────────
class _GrafikTab extends StatelessWidget {
  final Map<String, dynamic> data;
  const _GrafikTab({required this.data});

  @override
  Widget build(BuildContext context) {
    final saatMap = Map<int, double>.from(data['saatMap'] as Map);
    final odemeMap = Map<String, double>.from(data['odemeMap'] as Map);
    final ciro = data['ciro'] as double;

    return ListView(padding: const EdgeInsets.all(16), children: [
      // Saat bazında grafik
      const Text('Saatlik Satış Dağılımı',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      const SizedBox(height: 12),
      Container(
        height: 200,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: TsRenk.kart(context), borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Color(0x0D000000), blurRadius: 8)]),
        child: saatMap.isEmpty
            ? Center(child: Text('Veri yok', style: TextStyle(color: context.textSecondary)))
            : BarChart(BarChartData(
                alignment: BarChartAlignment.spaceAround,
                barTouchData: BarTouchData(enabled: false),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (v, _) {
                      final h = v.toInt();
                      if (h % 4 != 0) return const SizedBox.shrink();
                      return Text('$h', style: TextStyle(fontSize: 10, color: TsRenk.metinIkincil(context)));
                    },
                  )),
                ),
                borderData: FlBorderData(show: false),
                gridData: FlGridData(drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) =>
                        FlLine(color: context.borderColor, strokeWidth: 1)),
                barGroups: List.generate(24, (h) => BarChartGroupData(
                  x: h,
                  barRods: [BarChartRodData(
                    toY: saatMap[h] ?? 0,
                    color: AppRenkler.primary,
                    width: 10,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                  )],
                )),
              )),
      ),
      const SizedBox(height: 20),

      // Ödeme pasta grafiği
      if (odemeMap.isNotEmpty) ...[
        const Text('Ödeme Dağılımı',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: TsRenk.kart(context), borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Color(0x0D000000), blurRadius: 8)]),
          child: Column(children: [
            SizedBox(
              height: 160,
              child: PieChart(PieChartData(
                sections: _odemeRenkler().entries
                    .where((e) => odemeMap.containsKey(e.key))
                    .map((e) {
                  final val = odemeMap[e.key] ?? 0;
                  return PieChartSectionData(
                    value: val, color: e.value,
                    title: ciro > 0 ? '%${(val / ciro * 100).toStringAsFixed(0)}' : '',
                    titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                    radius: 60,
                  );
                }).toList(),
                sectionsSpace: 2, centerSpaceRadius: 30,
              )),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12, runSpacing: 6,
              children: _odemeRenkler().entries
                  .where((e) => odemeMap.containsKey(e.key))
                  .map((e) => Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 10, height: 10,
                        decoration: BoxDecoration(color: e.value, shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    Text(e.key, style: const TextStyle(fontSize: 11)),
                  ])).toList(),
            ),
          ]),
        ),
      ],
    ]);
  }

  Map<String, Color> _odemeRenkler() => const {
    'Nakit':       Color(0xFF4CAF50),
    'Kredi Kartı': Color(0xFF2196F3),
    'Havale':      Color(0xFF9C27B0),
    'Cari':        Color(0xFFFF9800),
    'QR':          Color(0xFF00BCD4),
    'Karma':       Color(0xFF607D8B),
    'Diğer':       Color(0xFF9E9E9E),
  };
}
