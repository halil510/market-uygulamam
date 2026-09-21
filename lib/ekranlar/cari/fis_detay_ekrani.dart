// lib/ekranlar/cari/fis_detay_ekrani.dart
//
// DÜZELTMELER:
//  - KRİTİK: Yanlış tablo adları düzeltildi
//    'satis'       → 'satislar'
//    'satis_urun'  → 'satis_kalem'
//    'urun'        → 'urunler'
//  - KRİTİK: Yanlış kolon adları düzeltildi
//    'adet'        → 'miktar'
//    'birim'       → 'birim_adi' (urunler JOIN ile)
//    'kdv_orani'   → 'kdv_oran'
//    'iskonto'     → 'iskonto_oran'
//    'tutar'       → 'toplam_tutar'
//    'kdv_tutari'  → 'kdv_tutar'
//  - KRİTİK: Alım için doğru tablo: tedarikci_siparisler + tedarikci_siparis_kalem
//  - KRİTİK: İade için doğru tablo: iade + iade_kalem
//  - EKLEME: mounted kontrolü (geri tuşu crash önlendi)
//  - EKLEME: Hata ekranı
//  - EKLEME: PDF export
//  - EKLEME: RepaintBoundary

import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart' hide Border, TextSpan;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../cekirdek/utils/excel_guvenlik_utils.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../depolar/fis_detay_deposu.dart';
import '../../depolar/satis_deposu.dart';

class FisDetayEkrani extends ConsumerStatefulWidget {
  final int fisId;
  final String fisTipi;
  final String cariUnvan;

  const FisDetayEkrani({
    super.key,
    required this.fisId,
    required this.fisTipi,
    required this.cariUnvan,
  });

  @override
  ConsumerState<FisDetayEkrani> createState() => _FisDetayEkraniState();
}

class _FisDetayEkraniState extends ConsumerState<FisDetayEkrani> {
  final _depo = FisDetayDeposu();
  final _fmt = DateFormat('dd.MM.yyyy HH:mm');

  Map<String, dynamic>? _fis;
  List<Map<String, dynamic>> _kalemler = [];
  bool _yukleniyor = true;
  String? _hata;

  // Kullanıcı isteği (2026-09-21): Satış Detayı'ndaki Karma ödeme kırılımı
  // (Nakit/Kart/Cari ne kadar) Cari Fiş Detayı'nda hiç yoktu — burada
  // "Ödeme" alanı sadece düz "Karma" yazıyordu, hangi yöntemden ne kadar
  // ödendiği görünmüyordu (bkz. SatisDetayEkrani._odemeDagilimi — AYNI
  // desen, SatisDeposu.odemeDagilimiGetir üzerinden).
  List<Map<String, dynamic>>? _odemeDagilimi;

  static const _satisFisTipleri = {
    'Satış', 'Toptan Satış', 'Toptan Satış (Sipariş)', 'Masa Satış',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _yukle());
  }

  Future<void> _yukle() async {
    if (!mounted) return;
    setState(() { _yukleniyor = true; _hata = null; });

    try {
      final sonuc = await _depo.getir(fisId: widget.fisId, fisTipi: widget.fisTipi);
      if (!mounted) return;
      _fis = sonuc.fis;
      _kalemler = sonuc.kalemler;

      if (_satisFisTipleri.contains(widget.fisTipi) &&
          _fis?['odeme_yontemi'] == 'Karma') {
        SatisDeposu().odemeDagilimiGetir(widget.fisId).then((v) {
          if (mounted) setState(() => _odemeDagilimi = v);
        });
      }

      if (!mounted) return;
      // 🔴🔴 KRİTİK DÜZELTME: Bu, başarılı yükleme yolundaki TEK
      // durum güncellemesiydi ve setState() İÇİNDE DEĞİLDİ — sadece
      // catch (hata) bloğu setState() çağırıyordu. Sonuç: veri
      // BAŞARIYLA çekilse bile ekran hiçbir zaman yeniden çizilmiyordu,
      // kullanıcı sonsuza kadar "yükleniyor" döngüsünde kalıyordu.
      setState(() => _yukleniyor = false);

    } catch (e) {
      if (kDebugMode) debugPrint('FisDetay hata (${widget.fisTipi} id=${widget.fisId}): $e');
      if (mounted) {
          _yukleniyor = false;
          _hata = 'Fiş detayı yüklenemedi.\n$e';
        if (mounted) setState(() {});
      }
    }
  }

  // ── Toplamlar ──────────────────────────────────────────────────────────
  double get _araToplam => _kalemler.fold(0.0,
      (s, k) => s + ((k['toplam_tutar'] as num?)?.toDouble() ?? 0));

  double get _kdvToplam => _kalemler.fold(0.0,
      (s, k) => s + ((k['kdv_tutar'] as num?)?.toDouble() ?? 0));

  double get _genelToplam {
    if (_fis != null) {
      final gt = _fis!['genel_toplam'] ?? _fis!['toplam_tutar'];
      if (gt != null) return (gt as num).toDouble();
    }
    return _araToplam + _kdvToplam;
  }

  String _tarihFormatla(dynamic val) {
    if (val == null) return '-';
    final dt = val is DateTime ? val : DateTime.tryParse(val.toString());
    return dt != null ? _fmt.format(dt) : val.toString();
  }

  // ── Excel ──────────────────────────────────────────────────────────────
  Future<void> _exportExcel() async {
    if (!mounted) return;
    try {
      final ex = Excel.createExcel();
      final sh = ex['Fiş Detayı'];
      ex.delete('Sheet1');

      void baslikHucresi(int col, int row, String val) {
        final c = sh.cell(
            CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
        c.value = TextCellValue(val);
        c.cellStyle = CellStyle(
          bold: true,
          backgroundColorHex: ExcelColor.fromHexString('#1A237E'),
          fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
        );
      }

      sh.appendRow([TextCellValue('FİŞ DETAYI')]);
      sh.appendRow([TextCellValue('Cari:'), TextCellValue(excelIcinGuvenliMetin(widget.cariUnvan))]);
      sh.appendRow([TextCellValue('Fiş Tipi:'), TextCellValue(widget.fisTipi)]);
      sh.appendRow([
        TextCellValue('Fiş No:'),
        TextCellValue(_fis?['fis_no']?.toString() ??
            _fis?['siparis_no']?.toString() ?? widget.fisId.toString())
      ]);
      sh.appendRow([
        TextCellValue('Tarih:'),
        TextCellValue(_tarihFormatla(_fis?['tarih'] ?? _fis?['siparis_tarihi']))
      ]);
      sh.appendRow([TextCellValue('')]);

      if (_kalemler.isNotEmpty) {
        final headers = [
          'Ürün Adı', 'Barkod', 'Miktar', 'Birim',
          'Birim Fiyat', 'İskonto %', 'KDV %', 'KDV Tutarı', 'Toplam'
        ];
        final hRow = sh.maxRows;
        for (int i = 0; i < headers.length; i++) {
          baslikHucresi(i, hRow, headers[i]);
        }

        for (final k in _kalemler) {
          sh.appendRow([
            TextCellValue(excelIcinGuvenliMetin(k['urun_adi']?.toString() ?? '-')),
            TextCellValue(k['barkod']?.toString() ?? ''),
            DoubleCellValue((k['miktar'] as num?)?.toDouble() ?? 0),
            TextCellValue(k['birim_adi']?.toString() ?? ''),
            DoubleCellValue((k['birim_fiyat'] as num?)?.toDouble() ?? 0),
            DoubleCellValue((k['iskonto_oran'] as num?)?.toDouble() ?? 0),
            DoubleCellValue((k['kdv_oran'] as num?)?.toDouble() ?? 0),
            DoubleCellValue((k['kdv_tutar'] as num?)?.toDouble() ?? 0),
            DoubleCellValue((k['toplam_tutar'] as num?)?.toDouble() ?? 0),
          ]);
        }

        sh.appendRow([TextCellValue('')]);
        sh.appendRow([
          TextCellValue('GENEL TOPLAM'), TextCellValue(''),
          TextCellValue(''), TextCellValue(''), TextCellValue(''),
          TextCellValue(''), TextCellValue(''), TextCellValue(''),
          DoubleCellValue(_genelToplam),
        ]);
      }

      final dir  = await getTemporaryDirectory();
      final path = '${dir.path}/fis_${widget.fisId}_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      File(path).writeAsBytesSync(ex.encode()!);
      await Share.shareXFiles([XFile(path)],
          text: 'Fiş Detayı — ${widget.fisTipi} / ${widget.cariUnvan}');
      if (mounted) BildirimServisi.basari(context, 'Excel oluşturuldu');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Excel hatası: $e');
    }
  }

  // ── PDF ────────────────────────────────────────────────────────────────
  Future<void> _exportPdf() async {
    if (!mounted) return;
    try {
      final font     = await PdfGoogleFonts.robotoRegular();
      final boldFont = await PdfGoogleFonts.robotoBold();
      final pdf = pw.Document();

      pdf.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (ctx) => [
          pw.Center(child: pw.Text('FİŞ DETAYI',
              style: pw.TextStyle(font: boldFont, fontSize: 18))),
          pw.SizedBox(height: 8),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('Cari: ${widget.cariUnvan}',
                  style: pw.TextStyle(font: boldFont, fontSize: 11)),
              pw.Text(
                'Fiş No: ${_fis?['fis_no'] ?? _fis?['siparis_no'] ?? widget.fisId}',
                style: pw.TextStyle(font: font, fontSize: 10)),
              pw.Text('Tür: ${widget.fisTipi}',
                  style: pw.TextStyle(font: font, fontSize: 10)),
            ]),
            pw.Text(
              _tarihFormatla(_fis?['tarih'] ?? _fis?['siparis_tarihi']),
              style: pw.TextStyle(font: font, fontSize: 10)),
          ]),
          pw.Divider(),
          pw.SizedBox(height: 6),
          if (_kalemler.isNotEmpty) ...[
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300),
              columnWidths: {
                0: const pw.FlexColumnWidth(3),
                1: const pw.FlexColumnWidth(1),
                2: const pw.FlexColumnWidth(1.5),
                3: const pw.FlexColumnWidth(1),
                4: const pw.FlexColumnWidth(1.5),
              },
              children: [
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: PdfColors.grey700),
                  children: ['Ürün', 'Miktar', 'Birim Fiyat', 'İsk.%', 'Toplam']
                      .map((h) => pw.Padding(
                            padding: const pw.EdgeInsets.all(4),
                            child: pw.Text(h,
                                style: pw.TextStyle(font: boldFont, fontSize: 9, color: PdfColors.white)),
                          ))
                      .toList(),
                ),
                ..._kalemler.map((k) {
                  final m  = (k['miktar']      as num?)?.toDouble() ?? 0;
                  final bp = (k['birim_fiyat'] as num?)?.toDouble() ?? 0;
                  final is_= (k['iskonto_oran'] as num?)?.toDouble() ?? 0;
                  final tt = (k['toplam_tutar'] as num?)?.toDouble() ??
                      (m * bp * (1 - is_ / 100));
                  return pw.TableRow(children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(4),
                        child: pw.Text(k['urun_adi']?.toString() ?? '-',
                            style: pw.TextStyle(font: font, fontSize: 8))),
                    pw.Padding(padding: const pw.EdgeInsets.all(4),
                        child: pw.Text(m.toStringAsFixed(m % 1 == 0 ? 0 : 3),
                            style: pw.TextStyle(font: font, fontSize: 8))),
                    pw.Padding(padding: const pw.EdgeInsets.all(4),
                        child: pw.Text(ParaUtils.formatla(bp),
                            style: pw.TextStyle(font: font, fontSize: 8))),
                    pw.Padding(padding: const pw.EdgeInsets.all(4),
                        child: pw.Text(is_ > 0 ? '%${is_.toStringAsFixed(0)}' : '-',
                            style: pw.TextStyle(font: font, fontSize: 8))),
                    pw.Padding(padding: const pw.EdgeInsets.all(4),
                        child: pw.Text(ParaUtils.formatla(tt),
                            style: pw.TextStyle(font: boldFont, fontSize: 8))),
                  ]);
                }),
              ],
            ),
            pw.SizedBox(height: 8),
          ],
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(color: PdfColors.grey100),
              child: pw.Text(
                'GENEL TOPLAM: ${ParaUtils.formatla(_genelToplam)}',
                style: pw.TextStyle(font: boldFont, fontSize: 14)),
            ),
          ),
        ],
      ));
      await Printing.layoutPdf(onLayout: (_) async => pdf.save());
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'PDF hatası: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: '${widget.fisTipi} Detayı',
        aksiyonlar: [
          if (!_yukleniyor && _hata == null) ...[
            IconButton(icon: Image.asset("assets/images/pdf_icon.png", width: 22, height: 22, errorBuilder: (_, __, ___) => const Icon(Icons.picture_as_pdf)), tooltip: 'PDF', onPressed: _exportPdf),
            IconButton(icon: const Icon(Icons.download), tooltip: 'Excel', onPressed: _exportExcel),
          ],
          IconButton(icon: const Icon(Icons.refresh), onPressed: _yukle),
        ],
        gradyanli: false,
      ),
      body: _yukleniyor
          ? const TsYukleniyor()
          : _hata != null
              ? _hataEkrani()
              : _icerik(),
    );
  }

  Widget _hataEkrani() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, size: 56, color: Colors.red),
            const SizedBox(height: 12),
            const Text('Fiş yüklenemedi',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(_hata!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: TsRenk.metinIkincil(context))),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _yukle,
              icon: const Icon(Icons.refresh),
              label: const Text('Tekrar Dene'),
            ),
          ]),
        ),
      );

  Widget _icerik() {
    final fisNo = _fis?['fis_no']?.toString() ??
        _fis?['siparis_no']?.toString() ??
        widget.fisId.toString();
    final tarih = _tarihFormatla(
        _fis?['tarih'] ?? _fis?['siparis_tarihi'] ?? _fis?['created_at']);
    final odeme = _fis?['odeme_yontemi']?.toString();

    return Column(children: [
      // ── Fiş başlık kartı ─────────────────────────────────────────────
      Container(
        margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Color.fromARGB(102, Theme.of(context).colorScheme.primaryContainer.red, Theme.of(context).colorScheme.primaryContainer.green, Theme.of(context).colorScheme.primaryContainer.blue),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: Color.fromARGB(76, Theme.of(context).colorScheme.primary.red, Theme.of(context).colorScheme.primary.green, Theme.of(context).colorScheme.primary.blue)),
        ),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _infoCol('Fiş No', fisNo),
            _infoCol('Tarih', tarih, right: true),
          ]),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Expanded(child: _infoCol('Cari', widget.cariUnvan)),
            const SizedBox(width: 12),
            _infoCol('Tür', widget.fisTipi, right: true),
          ]),
          if (odeme != null) ...[
            const SizedBox(height: 6),
            Row(children: [_infoCol('Ödeme', odeme)]),
            if (odeme == 'Karma') ...[
              const SizedBox(height: 4),
              if (_odemeDagilimi == null)
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: SizedBox(
                      width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _odemeDagilimi!
                      .map((d) => Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Row(children: [
                              Icon(Icons.subdirectory_arrow_right,
                                  size: 14, color: TsRenk.metinIkincil(context)),
                              const SizedBox(width: 4),
                              Text(
                                  '${d['yontem']}: ${ParaUtils.formatla(d['tutar'] as double)}',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: TsRenk.metinIkincil(context))),
                            ]),
                          ))
                      .toList(),
                ),
            ],
          ],
        ]),
      ),

      // ── Kalem listesi ─────────────────────────────────────────────────
      Expanded(
        child: _kalemler.isEmpty
            ? Center(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.receipt_long_outlined, size: 56, color: TsRenk.ayirac(context)),
                  const SizedBox(height: 12),
                  Text(
                    widget.fisTipi == 'Satış' || widget.fisTipi == 'Toptan Satış' ||
                            widget.fisTipi == 'Toptan Satış (Sipariş)' ||
                            widget.fisTipi == 'Masa Satış' ||
                            widget.fisTipi == 'İade' || widget.fisTipi == 'Alım'
                        ? 'Bu fişe ait kalem bulunamadı'
                        : 'Bu hareket için kalem detayı gösterilmiyor',
                    style: TextStyle(color: TsRenk.metinIkincil(context)),
                    textAlign: TextAlign.center,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: TextButton.icon(
                      onPressed: _yukle,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Yenile'),
                    ),
                  ),
                ]),
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                itemCount: _kalemler.length,
                itemBuilder: (_, i) =>
                    RepaintBoundary(child: _kalemKarti(_kalemler[i], i)),
              ),
      ),

      // ── Toplam bar ────────────────────────────────────────────────────
      _toplamBar(),
    ]);
  }

  Widget _kalemKarti(Map<String, dynamic> k, int idx) {
    final urunAdi    = k['urun_adi']?.toString() ?? '-';
    final barkod     = k['barkod']?.toString();
    final birimAdi   = k['birim_adi']?.toString() ?? '';
    final miktar     = (k['miktar']      as num?)?.toDouble() ?? 0;
    final birimFiyat = (k['birim_fiyat'] as num?)?.toDouble() ?? 0;
    final iskontoOran= (k['iskonto_oran'] as num?)?.toDouble() ?? 0;
    final kdvOran    = (k['kdv_oran']    as num?)?.toDouble() ?? 0;
    final kdvTutar   = (k['kdv_tutar']   as num?)?.toDouble() ?? 0;
    final toplamTutar= (k['toplam_tutar'] as num?)?.toDouble() ??
        (miktar * birimFiyat * (1 - iskontoOran / 100));
    final ondalik    = miktar != miktar.roundToDouble();

    return Container(
          decoration: BoxDecoration(color: TsRenk.kart(context), borderRadius: BorderRadius.circular(12), border: Border.all(color: TsRenk.ayirac(context))),
      margin: const EdgeInsets.only(bottom: 8),
      
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: Color.fromARGB(26, Theme.of(context).colorScheme.primary.red, Theme.of(context).colorScheme.primary.green, Theme.of(context).colorScheme.primary.blue),
                borderRadius: BorderRadius.circular(12)),
              child: Center(
                child: Text('${idx + 1}',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.primary)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(urunAdi,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                if (barkod != null && barkod.isNotEmpty)
                  Text(barkod, style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context))),
              ]),
            ),
            Text(
              ParaUtils.formatla(toplamTutar),
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15,
                  color: Theme.of(context).colorScheme.primary),
            ),
          ]),
          const Divider(height: 12),
          Row(children: [
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: TextStyle(fontSize: 12, color: context.textSecondary),
                  children: [
                    TextSpan(text: ondalik ? miktar.toStringAsFixed(3) : miktar.toInt().toString()),
                    if (birimAdi.isNotEmpty)
                      TextSpan(text: ' $birimAdi',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    const TextSpan(text: '  ×  '),
                    TextSpan(text: ParaUtils.formatla(birimFiyat),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
            if (iskontoOran > 0)
              _badge('%${iskontoOran.toStringAsFixed(0)} ind.', Colors.orange),
            if (kdvOran > 0) ...[
              const SizedBox(width: 4),
              _badge('KDV %${kdvOran.toStringAsFixed(0)}', context.textSecondary),
            ],
            if (kdvTutar > 0.001) ...[
              const SizedBox(width: 4),
              _badge('+${ParaUtils.formatla(kdvTutar)}', TsRenk.metinIkincil(context)),
            ],
          ]),
        ]),
      ),
    );
  }

  Widget _toplamBar() => Container(
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            Theme.of(context).colorScheme.primary,
            Color.fromARGB(204, Theme.of(context).colorScheme.primary.red, Theme.of(context).colorScheme.primary.green, Theme.of(context).colorScheme.primary.blue),
          ]),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: Color.fromARGB(76, Theme.of(context).colorScheme.primary.red, Theme.of(context).colorScheme.primary.green, Theme.of(context).colorScheme.primary.blue),
                blurRadius: 8, offset: const Offset(0, 4)),
          ],
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('GENEL TOPLAM',
                style: TextStyle(color: Colors.white70, fontSize: 11)),
            Text('${_kalemler.length} kalem',
                style: const TextStyle(color: Colors.white54, fontSize: 10)),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(ParaUtils.formatla(_genelToplam),
                style: const TextStyle(color: Colors.white, fontSize: 22,
                    fontWeight: FontWeight.w900)),
            if (_kdvToplam > 0.001)
              Text('KDV: ${ParaUtils.formatla(_kdvToplam)}',
                  style: const TextStyle(color: Colors.white60, fontSize: 10)),
          ]),
        ]),
      );

  Widget _infoCol(String label, String val, {bool right = false}) => Column(
        crossAxisAlignment:
            right ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context))),
          Text(val, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      );

  Widget _badge(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Color.fromARGB(26, color.red, color.green, color.blue),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Color.fromARGB(76, color.red, color.green, color.blue)),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
      );
}
