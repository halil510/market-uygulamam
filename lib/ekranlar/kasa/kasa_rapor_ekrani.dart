// lib/ekranlar/kasa/kasa_rapor_ekrani.dart
//
// YENİ EKRAN — Kasa Raporu
// Kasa hareketleri ve bakiye grafikleri

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../widgetlar/ortak/app_widgetlar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import '../../modeller/kasa_hareket_model.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../saglayicilar/riverpod/kasa_rapor_provider.dart' as merkezi;

// ── Provider ─────────────────────────────────────────────────────────────────

// 🔴🔴 KRİTİK DÜZELTME (derin analizde bulundu): bu dosya kendi YEREL
// 'kasaRaporProvider' adında bir FutureProvider.family tanımlıyordu —
// aynı isimde ama TAMAMEN AYRI bir 'kasaRaporProvider'
// (saglayicilar/riverpod/kasa_rapor_provider.dart, @riverpod ile
// üretilmiş) zaten vardı ve virman_ekrani.dart, kasa_hareket_ekrani.dart,
// iade ekranları, masa_detay_ekrani.dart gibi TÜM para hareketi yazan
// ekranlar kasa değiştiğinde O paylaşılan provider'ı invalidate
// ediyordu. Bu ekran hiçbirinden haberdar olmuyor, kullanıcı elle
// yenileyene ya da tarih aralığını değiştirene kadar eski rakamları
// göstermeye devam ediyordu. Artık bu ekran KENDİ hesaplamasını (günlük
// grafik verisi için) paylaşılan provider'ın üzerine inşa ediyor — o
// invalidate edildiğinde bu da otomatik yeniden hesaplanıyor.
final kasaRaporProvider = FutureProvider.family
    .autoDispose<_KasaRaporVeri, DateTimeRange>((ref, aralik) async {
  final ozet       = await ref.watch(merkezi.kasaRaporProvider(aralik).future);
  final hareketler = ozet.hareketler;

  double giris = 0, cikis = 0;
  final gunlukMap = <String, double>{};

  // ÖNCEDEN BURADA KRİTİK BİR HATA VARDI: `h.tutar > 0` her zaman true
  // olduğu için (tutar veritabanında her zaman pozitif kaydediliyor —
  // bkz. kasa_deposu.dart) `||` koşulu her işlemi "giriş" sayıyordu.
  // Sonuç: Kasa Raporu HER ZAMAN "0 çıkış" ve "her şey giriş" olarak
  // gösteriyordu — gerçek nakit akışını tamamen yanlış yansıtıyordu.
  // Artık merkezi kaynak kullanılıyor (bkz. KasaHareketModel) — aynı
  // sınıflandırmanın 4 ayrı dosyada birbirinden bağımsız kopyalanması,
  // birinin unutulup eksik kalmasına yol açmıştı (kasa_hareket_ekrani.dart).
  final girisTipleri = KasaHareketModel.girisTipleri;
  for (final h in hareketler) {
    final gun = DateFormat('dd.MM').format(h.tarih);
    if (girisTipleri.contains(h.hareketTipi)) {
      giris += h.tutar.abs();
      gunlukMap[gun] = (gunlukMap[gun] ?? 0) + h.tutar.abs();
    } else {
      cikis += h.tutar.abs();
      gunlukMap[gun] = (gunlukMap[gun] ?? 0) - h.tutar.abs();
    }
  }

  return _KasaRaporVeri(
    hareketler:  hareketler,
    toplamGiris: giris,
    toplamCikis: cikis,
    netHareket:  giris - cikis,
    guncelBakiye: ozet.guncelBakiye,
    gunlukData:  gunlukMap,
  );
});

class _KasaRaporVeri {
  final List<KasaHareketModel> hareketler;
  final double toplamGiris, toplamCikis, netHareket, guncelBakiye;
  final Map<String, double> gunlukData;

  const _KasaRaporVeri({
    required this.hareketler,
    required this.toplamGiris,
    required this.toplamCikis,
    required this.netHareket,
    required this.guncelBakiye,
    required this.gunlukData,
  });
}

// ── Ekran ─────────────────────────────────────────────────────────────────────

class KasaRaporEkrani extends ConsumerStatefulWidget {
  const KasaRaporEkrani({super.key});

  @override
  ConsumerState<KasaRaporEkrani> createState() => _KasaRaporEkraniState();
}

class _KasaRaporEkraniState extends ConsumerState<KasaRaporEkrani> {
  DateTimeRange _aralik = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 30)),
    end:   DateTime.now(),
  );

  @override
  Widget build(BuildContext context) {
    final raporAsync = ref.watch(kasaRaporProvider(_aralik));

    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'Kasa Raporu',
        aksiyonlar: [
          IconButton(
            icon: const Icon(Icons.date_range),
            onPressed: _tarihSec,
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: () => raporAsync.whenData((d) => _pdfOlustur(d)),
          ),
        ],
      ),
      body: raporAsync.when(
        loading: () => const Center(child: const AppYukleniyor()),
        error:   (e, _) => BosEkran(ikon: Icons.inbox_outlined, baslik: 'Hata: $e'),
        data:    (veri) => _Icerik(
          veri: veri, aralik: _aralik,
          onRefresh: () async => ref.invalidate(kasaRaporProvider(_aralik)),
        ),
      ),
    );
  }

  Future<void> _tarihSec() async {
    try {  
      final secilen = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate:  DateTime.now(),
        initialDateRange: _aralik,
        locale: const Locale('tr', 'TR'),
      );
      if (secilen != null) setState(() => _aralik = secilen);
        } catch (e) {
      if (kDebugMode) if (mounted) debugPrint('Hata: $e');
    }
  }

  Future<void> _pdfOlustur(_KasaRaporVeri veri) async {
    final font     = await PdfGoogleFonts.robotoRegular();
    final boldFont = await PdfGoogleFonts.robotoBold();
    final pdf      = pw.Document();
    final fmt      = DateFormat('dd.MM.yyyy');

    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Center(child: pw.Text('KASA RAPORU',
              style: pw.TextStyle(font: boldFont, fontSize: 20))),
          pw.Center(child: pw.Text(
              '${fmt.format(_aralik.start)} - ${fmt.format(_aralik.end)}',
              style: pw.TextStyle(font: font, fontSize: 12))),
          pw.Divider(),
          pw.SizedBox(height: 12),
          _pdfSatir('Güncel Kasa Bakiyesi', ParaUtils.formatla(veri.guncelBakiye), boldFont),
          _pdfSatir('Toplam Giriş',         ParaUtils.formatla(veri.toplamGiris), font),
          _pdfSatir('Toplam Çıkış',         ParaUtils.formatla(veri.toplamCikis), font),
          _pdfSatir('Net Hareket',           ParaUtils.formatla(veri.netHareket),  font),
          pw.SizedBox(height: 16),
          pw.Text('Hareketler (${veri.hareketler.length} kayıt)',
              style: pw.TextStyle(font: boldFont, fontSize: 14)),
          pw.SizedBox(height: 8),
          ...veri.hareketler.take(50).map((h) => pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(fmt.format(h.tarih),
                  style: pw.TextStyle(font: font, fontSize: 11)),
              pw.Text(h.aciklama ?? h.hareketTipi,
                  style: pw.TextStyle(font: font, fontSize: 11)),
              pw.Text(ParaUtils.formatla(h.tutar),
                  style: pw.TextStyle(font: font, fontSize: 11)),
            ],
          )),
        ],
      ),
    ));
    await Printing.layoutPdf(onLayout: (_) => pdf.save());
  }

  pw.Widget _pdfSatir(String l, String v, pw.Font f) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 3),
    child: pw.Row(children: [
      pw.SizedBox(width: 180, child: pw.Text(l, style: pw.TextStyle(font: f, fontSize: 12))),
      pw.Text(v, style: pw.TextStyle(font: f, fontSize: 12)),
    ]),
  );
}

// ── İçerik ────────────────────────────────────────────────────────────────────

class _Icerik extends StatelessWidget {
  final _KasaRaporVeri veri;
  final DateTimeRange  aralik;
  final Future<void> Function() onRefresh;
  const _Icerik({required this.veri, required this.aralik, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd.MM.yyyy');

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Tarih aralığı
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: TsRenk.kart(context),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.calendar_today, size: 16, color: AppRenkler.primary),
              const SizedBox(width: 8),
              Text(
                '${fmt.format(aralik.start)} – ${fmt.format(aralik.end)}',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ]),
          ),

          const SizedBox(height: 16),

          // Kasa bakiyesi büyük kart
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF2E7D32), Color(0xFF1B5E20)],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(
                  color: Color(0x4C4CAF50),
                  blurRadius: 16, offset: const Offset(0, 6))],
            ),
            child: Row(children: [
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Güncel Kasa Bakiyesi',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 8),
                  Text(ParaUtils.formatla(veri.guncelBakiye),
                      style: const TextStyle(
                          color: Colors.white, fontSize: 30,
                          fontWeight: FontWeight.w800)),
                ],
              )),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Color(0x26FFFFFF),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.account_balance_wallet,
                    color: Colors.white, size: 36),
              ),
            ]),
          ),

          const SizedBox(height: 12),

          // Giriş / Çıkış / Net kartları
          Row(children: [
            Expanded(child: _OzetKart(
              baslik: 'Giriş', deger: veri.toplamGiris,
              ikon: Icons.arrow_downward, renk: Colors.green.shade600)),
            const SizedBox(width: 10),
            Expanded(child: _OzetKart(
              baslik: 'Çıkış', deger: veri.toplamCikis,
              ikon: Icons.arrow_upward, renk: Colors.red.shade600)),
            const SizedBox(width: 10),
            Expanded(child: _OzetKart(
              baslik: 'Net', deger: veri.netHareket,
              ikon: Icons.swap_vert,
              renk: veri.netHareket >= 0
                  ? Colors.blue.shade600 : Colors.orange.shade700)),
          ]),

          const SizedBox(height: 16),

          // Günlük grafik
          if (veri.gunlukData.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: TsRenk.kart(context),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(
                    color: Color(0x0D000000),
                    blurRadius: 10, offset: const Offset(0, 3))],
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Günlük Kasa Hareketi',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                SizedBox(
                  height: 150,
                  child: LineChart(
                    LineChartData(
                      gridData: FlGridData(
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (_) => FlLine(
                            color: context.borderColor, strokeWidth: 1),
                      ),
                      titlesData: FlTitlesData(
                        leftTitles:  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(sideTitles: SideTitles(
                          showTitles: true,
                          interval: veri.gunlukData.length > 10 ? 3 : 1,
                          getTitlesWidget: (v, _) {
                            final idx = v.toInt();
                            final keys = veri.gunlukData.keys.toList();
                            if (idx < 0 || idx >= keys.length) return const SizedBox.shrink();
                            return Text(keys[idx],
                                style: TextStyle(fontSize: 9, color: TsRenk.metinIkincil(context)));
                          },
                        )),
                      ),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: veri.gunlukData.entries.toList().asMap().entries
                              .map((e) => FlSpot(
                                  e.key.toDouble(), e.value.value))
                              .toList(),
                          isCurved:        true,
                          color:           AppRenkler.primary,
                          barWidth:        2.5,
                          dotData:         const FlDotData(show: false),
                          belowBarData:    BarAreaData(
                            show: true,
                            color: Color.fromARGB(20, AppRenkler.primary.red, AppRenkler.primary.green, AppRenkler.primary.blue),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 16),
          ],

          // Hareket Listesi
          Container(
            decoration: BoxDecoration(
              color: TsRenk.kart(context),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(
                  color: Color(0x0D000000),
                  blurRadius: 10, offset: const Offset(0, 3))],
            ),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(children: [
                  const Text('Hareketler',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Text('${veri.hareketler.length} kayıt',
                      style: TextStyle(fontSize: 12, color: TsRenk.metinIkincil(context))),
                ]),
              ),
              if (veri.hareketler.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Bu tarih aralığında hareket yok'),
                )
              else
                ...veri.hareketler.take(50).map((h) => _HareketSatiri(hareket: h)),

              const SizedBox(height: 8),
            ]),
          ),
        ],
      ),
    );
  }
}

class _OzetKart extends StatelessWidget {
  final String baslik;
  final double deger;
  final IconData ikon;
  final Color renk;
  const _OzetKart({required this.baslik, required this.deger,
    required this.ikon, required this.renk});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TsRenk.kart(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(ikon, color: renk, size: 18),
        const SizedBox(height: 8),
        Text(ParaUtils.formatla(deger.abs()),
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w800, color: renk),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        Text(baslik, style: TextStyle(
            fontSize: 11, color: TsRenk.metinIkincil(context))),
      ]),
    );
  }
}

class _HareketSatiri extends StatelessWidget {
  final KasaHareketModel hareket;
  const _HareketSatiri({required this.hareket});

  // ÖNCEDEN BURADA AYNI HATA VARDI (bkz. banka_hareket_ekrani.dart'taki
  // eşdeğer düzeltme): yön `hareket.tutar > 0` ile belirleniyordu ama
  // tutar HER ZAMAN pozitif kaydediliyor (kasa_deposu.dart'ta bakiye
  // hesabı `hareketTipi`'ne göre yapılıyor). Bu yüzden her hareket,
  // gerçekte çıkış olsa bile "giriş" (yeşil) gibi görünüyordu. Artık
  // merkezi kaynak kullanılıyor (bkz. KasaHareketModel.girisTipleri).

  @override
  Widget build(BuildContext context) {
    final giris = KasaHareketModel.girisMi(hareket.hareketTipi);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Color.fromARGB(20, (giris ? Colors.green : Colors.red).red, (giris ? Colors.green : Colors.red).green, (giris ? Colors.green : Colors.red).blue),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            giris ? Icons.arrow_downward : Icons.arrow_upward,
            color: giris ? Colors.green.shade600 : Colors.red.shade600,
            size: 16,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(hareket.aciklama ?? hareket.hareketTipi,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(DateFormat('dd.MM.yyyy HH:mm').format(hareket.tarih),
                style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context))),
          ],
        )),
        Text(
          '${giris ? '+' : ''}${ParaUtils.formatla(hareket.tutar)}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: giris ? Colors.green.shade600 : Colors.red.shade600,
          ),
        ),
      ]),
    );
  }
}
