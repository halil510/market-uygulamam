// lib/ekranlar/masa/masa_rapor_ekrani.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../widgetlar/ortak/app_widgetlar.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../servisler/masa/masa_rapor_servisi.dart';
import 'package:fl_chart/fl_chart.dart';

class MasaRaporEkrani extends ConsumerStatefulWidget {
  const MasaRaporEkrani({super.key});
  
  @override
  ConsumerState<MasaRaporEkrani> createState() => _MasaRaporEkraniState();
}

class _MasaRaporEkraniState extends ConsumerState<MasaRaporEkrani>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _servis = MasaRaporServisi();
  
  List<Map<String, dynamic>> _masaPerformans = [];
  Map<String, double> _dolulukVerisi = {};
  List<Map<String, dynamic>> _gunlukMasaCiro = [];
  double _ortalamaOturmaSuresi = 0;
  double _toplamMasaCiro = 0;
  bool _yukleniyor = true;
  DateTime _seciliTarih = DateTime.now();
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _yukle();
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
  
  Future<void> _yukle() async {
    if (!mounted) return;
    setState(() => _yukleniyor = true);
    try {
      final results = await Future.wait([
        _servis.masaPerformansAnalizi(),
        _servis.dolulukOraniAnalizi(_seciliTarih),
        _servis.gunlukMasaCiro(_seciliTarih),
        _servis.ortalamaOturmaSuresi(),
        _servis.toplamMasaCiro(_seciliTarih),
      ]);
      
      if (!mounted) return;
      setState(() {
        _masaPerformans = results[0] as List<Map<String, dynamic>>;
        _dolulukVerisi = results[1] as Map<String, double>;
        _gunlukMasaCiro = results[2] as List<Map<String, dynamic>>;
        _ortalamaOturmaSuresi = results[3] as double;
        _toplamMasaCiro = results[4] as double;
        _yukleniyor = false;
      });
    } catch (e) {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'Masa Raporları',
        aksiyonlar: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _yukle,
          ),
        ],
        alt: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Performans', icon: Icon(Icons.assessment)),
            Tab(text: 'Doluluk', icon: Icon(Icons.table_chart)),
            Tab(text: 'Ciro Analizi', icon: Icon(Icons.trending_up)),
          ],
        ),
      ),
      body: _yukleniyor
          ? const Center(child: AppYukleniyor())
          : TabBarView(
              controller: _tabController,
              children: [
                _performansTab(),
                _dolulukTab(),
                _ciroTab(),
              ],
            ),
    );
  }
  
  Widget _performansTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
          _ozetKart(
            baslik: 'Toplam Ciro',
            deger: ParaUtils.formatla(_toplamMasaCiro),
            ikon: Icons.attach_money,
            renk: const Color(0xFF2E7D32),
          ),
          const SizedBox(width: 12),
          _ozetKart(
            baslik: 'Ort. Oturma',
            deger: '${_ortalamaOturmaSuresi.toStringAsFixed(0)} dk',
            ikon: Icons.access_time,
            renk: TsRenk.primary,
          ),
        ]),
        const SizedBox(height: 16),
        const Text('Masa Performansı', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        ..._masaPerformans.map((m) => _MasaPerformansKarti(
          masaAdi: m['masa_adi'] as String? ?? '-',
          ciro: (m['ciro'] as num?)?.toDouble() ?? 0,
          siparisSayisi: (m['siparis_sayisi'] as int?)?.toInt() ?? 0,
          ortalamaTutar: (m['ortalama_tutar'] as num?)?.toDouble() ?? 0,
        )),
      ],
    );
  }
  
  Widget _dolulukTab() {
    final entries = _dolulukVerisi.entries.toList();
    if (entries.isEmpty) {
      return const Center(child: Text('Veri bulunamadı'));
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Container(
            height: 200,
            padding: const EdgeInsets.all(16),
            child: PieChart(PieChartData(
              sections: entries.map((e) => PieChartSectionData(
                value: e.value,
                title: '${e.value.toStringAsFixed(0)}%',
                color: e.key == 'Dolu' ? Colors.orange : (e.key == 'Boş' ? Colors.green : context.textSecondary),
                radius: 80,
                titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white),
              )).toList(),
              sectionsSpace: 2,
              centerSpaceRadius: 30,
            )),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            children: entries.map((e) => Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 12, height: 12, decoration: BoxDecoration(
                color: e.key == 'Dolu' ? Colors.orange : (e.key == 'Boş' ? Colors.green : context.textSecondary),
                shape: BoxShape.circle,
              )),
              const SizedBox(width: 4),
              Text('${e.key}: ${e.value.toStringAsFixed(0)}%'),
            ])).toList(),
          ),
        ]),
      ),
    );
  }
  
  Widget _ciroTab() {
    if (_gunlukMasaCiro.isEmpty) {
      return const Center(child: Text('Bu tarihte veri bulunamadı'));
    }
    final toplamCiro = _gunlukMasaCiro.fold<double>(0.0, (s, m) => s + ((m['ciro'] as num?)?.toDouble() ?? 0));
    
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: TsRenk.kart(context),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Color(0x0A000000), blurRadius: 6)],
          ),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () {
                  setState(() => _seciliTarih = _seciliTarih.subtract(const Duration(days: 1)));
                  _yukle();
                },
              ),
              Text('${_seciliTarih.day}.${_seciliTarih.month}.${_seciliTarih.year}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () {
                  setState(() => _seciliTarih = _seciliTarih.add(const Duration(days: 1)));
                  _yukle();
                },
              ),
            ]),
            const SizedBox(height: 8),
            Text('Toplam Ciro: ${ParaUtils.formatla(_toplamMasaCiro)}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: TsRenk.primary)),
          ]),
        ),
        const SizedBox(height: 16),
        const Text('Masa Bazlı Ciro', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        ..._gunlukMasaCiro.map((m) => _MasaCiroKarti(
          masaAdi: m['masa_adi'] as String? ?? '-',
          ciro: (m['ciro'] as num?)?.toDouble() ?? 0,
          siparisSayisi: (m['siparis_sayisi'] as int?)?.toInt() ?? 0,
          toplamCiro: toplamCiro,
        )),
      ],
    );
  }
  
  Widget _ozetKart({required String baslik, required String deger, required IconData ikon, required Color renk}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: renk.withAlpha(26),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: renk.withAlpha(51)),
        ),
        child: Column(children: [
          Icon(ikon, color: renk, size: 24),
          const SizedBox(height: 6),
          Text(deger, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: renk)),
          Text(baslik, style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context))),
        ]),
      ),
    );
  }
}

class _MasaPerformansKarti extends StatelessWidget {
  final String masaAdi;
  final double ciro;
  final int siparisSayisi;
  final double ortalamaTutar;
  
  const _MasaPerformansKarti({
    required this.masaAdi,
    required this.ciro,
    required this.siparisSayisi,
    required this.ortalamaTutar,
  });
  
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TsRenk.kart(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: TsRenk.ayirac(context)),
      ),
      child: Row(children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFF6D4C41).withAlpha(26),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.table_restaurant, color: Color(0xFF6D4C41)),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(masaAdi, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          Text('$siparisSayisi sipariş', style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context))),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(ParaUtils.formatla(ciro), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: TsRenk.primary)),
          Text('ort. ${ParaUtils.formatla(ortalamaTutar)}', style: TextStyle(fontSize: 10, color: TsRenk.metinIkincil(context))),
        ]),
      ]),
    );
  }
}

class _MasaCiroKarti extends StatelessWidget {
  final String masaAdi;
  final double ciro;
  final int siparisSayisi;
  final double toplamCiro;
  
  const _MasaCiroKarti({
    required this.masaAdi,
    required this.ciro,
    required this.siparisSayisi,
    required this.toplamCiro,
  });
  
  @override
  Widget build(BuildContext context) {
    final yuzde = toplamCiro > 0 ? (ciro / toplamCiro * 100) : 0.0;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TsRenk.kart(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: TsRenk.ayirac(context)),
      ),
      child: Column(children: [
        Row(children: [
          Expanded(child: Text(masaAdi, style: const TextStyle(fontWeight: FontWeight.w600))),
          Text(ParaUtils.formatla(ciro), style: const TextStyle(fontWeight: FontWeight.w800, color: TsRenk.primary)),
        ]),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: yuzde / 100,
          backgroundColor: TsRenk.ayirac(context),
          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF6D4C41)),
        ),
        const SizedBox(height: 2),
        Text('$siparisSayisi sipariş • %${yuzde.toStringAsFixed(1)}',
            style: TextStyle(fontSize: 10, color: TsRenk.metinIkincil(context))),
      ]),
    );
  }
}