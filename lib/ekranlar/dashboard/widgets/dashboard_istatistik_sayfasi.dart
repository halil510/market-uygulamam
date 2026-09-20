// lib/ekranlar/dashboard/widgets/dashboard_istatistik_sayfasi.dart
//
// Dashboard'un "İstatistik" sekmesi (ciro/kâr/marj kartları, haftalık
// satış grafiği, kritik stok listesi, ürün/cari sayaçları) — önceden
// dashboard_ekrani.dart'ın (1663 satır) İÇİNDE, _DashboardEkraniState
// sınıfının bir parçası olarak yaşıyordu. Mimari denetim: dosya boyutu
// azaltmak için ayrı, kendi başına yeten bir StatelessWidget'a taşındı.
// DAVRANIŞ DEĞİŞMEDİ — saf bir extract-widget refactor'ü (her metod
// birebir aynı, sadece `context` artık bu widget'ın kendi build()
// parametresinden geliyor — go_router'ın `context.push` uzantısı router
// kapsamındaki HER context'te aynı şekilde çalışır).
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../cekirdek/utils/para_utils.dart';
import '../../../uygulama/tema/uygulama_temasi.dart';
import '../../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../../saglayicilar/riverpod/dashboard_provider.dart';
import '../../../widgetlar/ortak/tap_scale.dart';

class DashboardIstatistikSayfasi extends StatelessWidget {
  final DashboardVeri data;
  const DashboardIstatistikSayfasi({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final d = data;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [TsRenk.primaryKoyu, TsRenk.primary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.shade900.withAlpha(30),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Genel Bakış',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              Text(ParaUtils.formatla(d.gunlukCiro),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5)),
              const Text('Bugünkü Ciro',
                  style: TextStyle(color: Colors.white60, fontSize: 11)),
            ]),
          ),
          const SizedBox(height: 14),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.4,
            children: [
              _statKart('Günlük Ciro', ParaUtils.formatla(d.gunlukCiro),
                  Icons.today, const Color(0xFF1565C0)),
              _statKart('Haftalık Ciro', ParaUtils.formatla(d.haftalikCiro),
                  Icons.date_range, const Color(0xFF2E7D32)),
              _statKart('Aylık Ciro', ParaUtils.formatla(d.aylikCiro),
                  Icons.calendar_month, const Color(0xFF6A1B9A)),
              _statKart('Günlük Gider', ParaUtils.formatla(d.gunlukGider),
                  Icons.money_off, const Color(0xFFC62828)),
            ],
          ),
          const SizedBox(height: 12),
          // 🔴 EKLENDİ (Madde 31 — Dashboard denetimi, 2026-09-20): doküman
          // "sadece toplam satış göstermemeli" diyor — bugüne kadar kâr,
          // marj ve cari alacak/borç HİÇ gösterilmiyordu.
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.4,
            children: [
              _statKart('Bugünkü Kâr', ParaUtils.formatla(d.netKar),
                  Icons.trending_up, const Color(0xFF00695C)),
              _statKart('Brüt Marj', '%${d.brutMarjOrani.toStringAsFixed(1)}',
                  Icons.percent, const Color(0xFF00838F)),
              _statKart('Toplam Alacak', ParaUtils.formatla(d.toplamAlacak),
                  Icons.arrow_downward, const Color(0xFF2E7D32)),
              _statKart('Toplam Borç', ParaUtils.formatla(d.toplamBorc),
                  Icons.arrow_upward, const Color(0xFFD84315)),
            ],
          ),
          if (d.onayBekleyen > 0 || d.syncBekleyen > 0 || d.riskliCariSayisi > 0) ...[
            const SizedBox(height: 12),
            _bekleyenlerSatiri(context, d),
          ],
          const SizedBox(height: 12),
          if (d.haftaData.isNotEmpty) _grafikBolumu(context, d),
          const SizedBox(height: 12),
          if (d.kritikUrunler.isNotEmpty) _kritikStokBolumu(context, d),
          _istatistikKartlar(context, d),
        ],
      ),
    );
  }

  // ── Yardımcı Widget'lar ────────────────────────────────────────────────────
  Widget _statKart(String baslik, String deger, IconData ikon, Color renk) =>
      TsKpiKart(baslik: baslik, deger: deger, ikon: ikon, renk: renk);

  // 🔴 EKLENDİ (Madde 31 — Dashboard denetimi, 2026-09-20): "Onay bekleyen
  // işlemler / Sync bekleyen / Riskli cariler" — dokümanın istediği
  // "dikkat gerektiren" sayaçlar. Sadece sayı > 0 iken görünür (0 iken
  // dashboard'u gereksiz uyarı rozetleriyle kirletmesin diye).
  Widget _bekleyenlerSatiri(BuildContext context, DashboardVeri d) => Row(children: [
        if (d.onayBekleyen > 0)
          Expanded(child: _uyariRozeti(context,
              '${d.onayBekleyen} onay bekliyor', Icons.verified_user_outlined,
              Colors.deepOrange, () => context.push('/onay-merkezi'))),
        if (d.onayBekleyen > 0 && (d.syncBekleyen > 0 || d.riskliCariSayisi > 0))
          const SizedBox(width: 8),
        if (d.syncBekleyen > 0)
          Expanded(child: _uyariRozeti(context,
              '${d.syncBekleyen} sync bekliyor', Icons.cloud_sync_outlined,
              Colors.blueGrey, () => context.push('/ayarlar/bulut-sync'))),
        if (d.syncBekleyen > 0 && d.riskliCariSayisi > 0) const SizedBox(width: 8),
        if (d.riskliCariSayisi > 0)
          Expanded(child: _uyariRozeti(context,
              '${d.riskliCariSayisi} riskli cari', Icons.shield_outlined,
              Colors.red, () => context.push('/risk-merkezi'))),
      ]);

  Widget _uyariRozeti(BuildContext context, String metin, IconData ikon, Color renk, VoidCallback onTap) =>
      TapScale(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: Color.fromARGB(20, renk.red, renk.green, renk.blue),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Color.fromARGB(60, renk.red, renk.green, renk.blue)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(ikon, size: 16, color: renk),
            const SizedBox(width: 6),
            Flexible(
              child: Text(metin,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: renk),
                  overflow: TextOverflow.ellipsis),
            ),
          ]),
        ),
      );

  Widget _grafikBolumu(BuildContext context, DashboardVeri d) {
    if (d.haftaData.isEmpty) return const SizedBox.shrink();
    const gunler = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
    final maxY = d.haftaData.fold(0.0, (mx, x) {
          final v = (x['ciro'] as num?)?.toDouble() ?? 0;
          return v > mx ? v : mx;
        }) *
        1.2;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 14,
            offset: Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Haftalık Satış',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2)),
          const SizedBox(height: 4),
          Text(
              'Grafikteki sütunlara dokunarak günlük ciro detayını görebilirsiniz',
              style: TextStyle(
                  fontSize: 10.5, color: TsRenk.metinIkincil(context))),
          const SizedBox(height: 12),
          SizedBox(
            height: 140,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxY <= 0 ? 1 : maxY,
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final idx = group.x.toInt();
                      final gun =
                          idx >= 0 && idx < gunler.length ? gunler[idx] : '';
                      return BarTooltipItem(
                        '$gun\n${ParaUtils.formatla(rod.toY)}',
                        const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 11),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (val, _) {
                        final idx = val.toInt();
                        if (idx < 0 || idx >= gunler.length)
                          return const SizedBox.shrink();
                        return Text(gunler[idx],
                            style: TextStyle(
                                fontSize: 9,
                                color: context.textSecondary,
                                fontWeight: FontWeight.w500));
                      },
                    ),
                  ),
                ),
                gridData: FlGridData(
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) =>
                      FlLine(color: context.borderColor, strokeWidth: 0.5),
                ),
                borderData: FlBorderData(show: false),
                barGroups: d.haftaData.asMap().entries.map((e) {
                  final ciro = (e.value['ciro'] as num?)?.toDouble() ?? 0;
                  return BarChartGroupData(
                    x: e.key,
                    barRods: [
                      BarChartRodData(
                        toY: ciro,
                        width: 18,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(6)),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            AppRenkler.primary,
                            AppRenkler.primary.withAlpha(102),
                          ],
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kritikStokBolumu(BuildContext context, DashboardVeri d) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 14,
            offset: Offset(0, 4),
          )
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Kritik Stok',
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.2)),
        const SizedBox(height: 12),
        ...d.kritikUrunler.take(3).map((u) {
          final stok = u['stok'] as double;
          final min = u['min'] as double;
          final oran = min > 0 ? (stok / min).clamp(0.0, 1.0) : 0.0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Expanded(
                    child: Text(u['ad'] as String,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis)),
                Text('$stok / $min',
                    style: TextStyle(
                        fontSize: 11,
                        color: context.textSecondary,
                        fontWeight: FontWeight.w500)),
              ]),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: oran,
                minHeight: 5,
                backgroundColor: context.borderColor,
                valueColor: AlwaysStoppedAnimation(
                  oran < 0.3 ? Colors.red.shade600 : Colors.orange.shade700,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
            ]),
          );
        }),
        if (d.kritikUrunler.length > 3)
          TextButton(
            onPressed: () => context.push('/stok'),
            child: const Text('Tümünü Gör →',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          ),
      ]),
    );
  }

  Widget _istatistikKartlar(BuildContext context, DashboardVeri d) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(children: [
        Expanded(
            child: _sayacKart(context, 'Ürün', d.toplamUrun, Icons.inventory_2,
                const Color(0xFF3F51B5),
                onTap: () => context.push('/urun'))),
        const SizedBox(width: 10),
        Expanded(
            child: _sayacKart(context, 'Kritik', d.kritikStok, Icons.warning_amber,
                const Color(0xFFE65100),
                onTap: () => context.push('/stok'))),
        const SizedBox(width: 10),
        Expanded(
            child: _sayacKart(
                context, 'Cari', d.toplamMusteri, Icons.people, const Color(0xFF00695C),
                onTap: () => context.push('/cari'))),
      ]),
    );
  }

  Widget _sayacKart(BuildContext context, String baslik, int deger, IconData ikon, Color renk,
      {VoidCallback? onTap}) {
    return TapScale(
      onTap: onTap,
      child: TsKart(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(children: [
          Icon(ikon, color: renk, size: 22),
          const SizedBox(height: 6),
          TweenAnimationBuilder<int>(
            tween: IntTween(begin: 0, end: deger),
            duration: const Duration(milliseconds: 800),
            builder: (_, v, __) => Text('$v',
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800, color: renk)),
          ),
          Text(baslik,
              style: TextStyle(
                  fontSize: 9,
                  color: context.textSecondary,
                  fontWeight: FontWeight.w500),
              textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}
