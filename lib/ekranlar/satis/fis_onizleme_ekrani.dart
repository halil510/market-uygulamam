// lib/ekranlar/satis/fis_onizleme_ekrani.dart
// Fiş önizleme + PDF yazdır + BT yazıcıya gönder
import 'package:flutter/foundation.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:barcode/barcode.dart' as bc;
import 'package:barcode_widget/barcode_widget.dart' as bw;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../modeller/satis_model.dart';
import '../../servisler/yazdirma_servisi.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../veri/database/veritabani.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
class FisOnizlemeEkrani extends ConsumerStatefulWidget {
  final SatisModel satis;

  /// 🆕 Cari hesap özeti için — cariye yapılan satışlarda doldurulur.
  /// OPSİYONEL: mevcut çağıranlar geçmese de ekran çalışır, sadece
  /// hesap özeti bloğu görünmez.
  final double? oncekiBakiye;
  final double? sonBakiye;

  const FisOnizlemeEkrani({
    super.key,
    required this.satis,
    this.oncekiBakiye,
    this.sonBakiye,
  });

  @override
  ConsumerState<FisOnizlemeEkrani> createState() => _FisOnizlemeEkraniState();
}

class _FisOnizlemeEkraniState extends ConsumerState<FisOnizlemeEkrani> {
  final _yazdirma = YazdirmaServisi();
  final _fmt = NumberFormat('#,##0.00', 'tr_TR');

  Map<String, String> _ayarlar = {};
  bool _btBagliMi  = false;
  bool _yaziliyor  = false;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    try {  
      final db = await Veritabani().db;
      final rows = await db.query('ayarlar',
          where: "anahtar IN ('firma_adi','firma_adres','firma_telefon','fis_alt_yazi','fis_kdv','fis_fatno',"
                 "'fis_cari_goster','fis_cari_bakiye_goster','fis_alt_barkod_goster')");
      final map = {for (final r in rows) r['anahtar'] as String: r['deger'] as String};
      final bagli = await _yazdirma.btBagliMi;
      if (mounted) setState(() { _ayarlar = map; _btBagliMi = bagli; });
        } catch (e) {
      if (kDebugMode) if (mounted) debugPrint('Hata: $e');
    }
  }

  String get _firmaAdi   => _ayarlar['firma_adi']    ?? 'MarketPlus';
  String get _firmaAdres => _ayarlar['firma_adres']  ?? '';
  String get _firmaTel   => _ayarlar['firma_telefon'] ?? '';
  String get _altYazi    => _ayarlar['fis_alt_yazi'] ?? 'Teşekkür ederiz!';
  bool   get _kdvGoster  => _ayarlar['fis_kdv']    != '0';

  // 🆕 Fiş Tasarım ekranındaki ayarlar — PDF yolu da bunlara uysun.
  // Varsayılan '1' (açık): ayar hiç kaydedilmemişse özellik çalışsın.
  bool get _cariAdiGoster     => (_ayarlar['fis_cari_goster'] ?? '1') != '0';
  bool get _cariBakiyeGoster  => (_ayarlar['fis_cari_bakiye_goster'] ?? '1') != '0';
  bool get _altBarkodGoster   => (_ayarlar['fis_alt_barkod_goster'] ?? '1') != '0';

  /// Bakiyeyi muhasebe biçiminde yazar (yazdirma_servisi._bakiyeYaz ile aynı).
  /// Pozitif = müşteri bize borçlu (B), negatif = biz borçluyuz (A).
  String _bakiyeYaz(double bakiye) {
    if (bakiye.abs() < 0.005) return _fmt.format(0);
    return '${_fmt.format(bakiye.abs())} ${bakiye > 0 ? "B" : "A"}';
  }

  SatisModel get s => widget.satis;

  double get _toplamIskonto =>
      s.kalemler.fold(0.0, (t, k) => t + (k.iskontoTutar));
  double get _toplamKdv =>
      s.kalemler.fold(0.0, (t, k) => t + (k.kdvTutar));
  double get _paraUstu =>
      s.odenenTutar > s.genelToplam ? s.odenenTutar - s.genelToplam : 0;

  // ── BT'ye yazdır ──────────────────────────────────────────────────────────
  /// "Fiş Bas" — bağlı termal yazıcı varsa RAW ESC/POS, yoksa PDF yazdırma
  /// diyaloğunu açar. Kullanıcı tek tuşla "yazdır" niyetini gerçekleştirir.
  Future<void> _fisBas() async {
    if (_btBagliMi) {
      await _btYazdir();
    } else {
      await _pdfYazdir();
    }
  }

  Future<void> _btYazdir() async {
    if (_yaziliyor) return;
    setState(() => _yaziliyor = true);
    try {
      await _yazdirma.fisYazdir(s,
        firmaAdi:   _firmaAdi,
        firmaAdres: _firmaAdres,
        firmaTel:   _firmaTel,
        altYazi:    _altYazi,
      );
      if (mounted) BildirimServisi.basari(context, 'Fiş yazıcıya gönderildi');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Yazıcı hatası: $e');
    } finally {
      if (mounted) setState(() => _yaziliyor = false);
    }
  }

  // ── PDF önizle / paylaş ───────────────────────────────────────────────────
  Future<void> _pdfYazdir() async {
    try {  
      final pdf = await _fisPdfOlustur();
      await Printing.layoutPdf(onLayout: (_) => pdf.save());
        } catch (e) {
      if (kDebugMode) if (mounted) debugPrint('Hata: $e');
    }
  }

  Future<pw.Document> _fisPdfOlustur() async {
    final doc  = pw.Document();
    final font = await PdfGoogleFonts.notoSansRegular();
    final bold = await PdfGoogleFonts.notoSansBold();
    final tarih = DateFormat('dd.MM.yyyy HH:mm').format(s.tarih);

    doc.addPage(pw.Page(
      pageFormat: const PdfPageFormat(58 * PdfPageFormat.mm, double.infinity,
          marginAll: 4 * PdfPageFormat.mm),
      build: (ctx) => pw.DefaultTextStyle(
        style: pw.TextStyle(font: font, fontSize: 8),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(_firmaAdi, style: pw.TextStyle(font: bold, fontSize: 12)),
            if (_firmaAdres.isNotEmpty) pw.Text(_firmaAdres, textAlign: pw.TextAlign.center),
            if (_firmaTel.isNotEmpty) pw.Text('Tel: $_firmaTel'),
            pw.Divider(),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Text('Tarih: $tarih'),
              pw.Text('Fiş: ${s.fisNo ?? "-"}'),
            ]),
            if (_cariAdiGoster && s.cariAdi != null && s.cariAdi!.isNotEmpty)
              pw.Text('Cari: ${s.cariAdi}'),
            pw.Divider(),
            // Kolon başlık
            pw.Row(children: [
              pw.Expanded(flex: 5, child: pw.Text('Ürün', style: pw.TextStyle(font: bold))),
              pw.SizedBox(width: 28, child: pw.Text('Mkt', style: pw.TextStyle(font: bold), textAlign: pw.TextAlign.center)),
              pw.SizedBox(width: 36, child: pw.Text('Tutar', style: pw.TextStyle(font: bold), textAlign: pw.TextAlign.right)),
            ]),
            pw.Divider(),
            ...s.kalemler.map((k) => pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(children: [
                  pw.Expanded(flex: 5, child: pw.Text(k.urunAdi,
                      style: pw.TextStyle(font: font, fontSize: 8),
                      maxLines: 2)),
                  pw.SizedBox(width: 28, child: pw.Text(
                      k.miktar % 1 == 0 ? k.miktar.toInt().toString() : k.miktar.toStringAsFixed(2),
                      textAlign: pw.TextAlign.center)),
                  pw.SizedBox(width: 36, child: pw.Text(_fmt.format(k.toplamTutar),
                      textAlign: pw.TextAlign.right)),
                ]),
                pw.Text('  ${_fmt.format(k.birimFiyat)} / birim',
                    style: pw.TextStyle(font: font, fontSize: 7, color: PdfColors.grey600)),
              ],
            )),
            pw.Divider(),
            if (_toplamIskonto > 0.001)
              _pdfRow('İskonto', '-${_fmt.format(_toplamIskonto)}', bold),
            if (_kdvGoster && _toplamKdv > 0.001)
              _pdfRow('KDV', _fmt.format(_toplamKdv), font),
            _pdfRow('TOPLAM', _fmt.format(s.genelToplam), bold, fontSize: 10),
            _pdfRow('Ödenen (${s.odemeYontemi})', _fmt.format(s.odenenTutar), font),
            if (_paraUstu > 0.01)
              _pdfRow('Para Üstü', _fmt.format(_paraUstu), bold),
            pw.Divider(),

            // ══════════════════════════════════════════════════════════
            // 🆕 CARİ HESAP ÖZETİ (PDF yolu)
            //
            // Termal yazıcı bağlı DEĞİLSE bu PDF yolu kullanılıyor
            // (bkz. _fisBas). ESC/POS tarafına eklenen cari hesap özeti
            // burada YOKTU — kullanıcı termal yazıcısız çalışınca
            // özelliği hiç göremiyordu.
            // ══════════════════════════════════════════════════════════
            if (_cariBakiyeGoster &&
                widget.oncekiBakiye != null && widget.sonBakiye != null) ...[
              pw.Text('CARİ HESAP ÖZETİ',
                  style: pw.TextStyle(font: bold, fontSize: 8)),
              _pdfRow('Eski Bakiye', _bakiyeYaz(widget.oncekiBakiye!), font),
              _pdfRow(
                  (widget.sonBakiye! - widget.oncekiBakiye!) >= 0
                      ? '(+) Bu Fiş' : '(-) Bu Fiş',
                  _fmt.format((widget.sonBakiye! - widget.oncekiBakiye!).abs()),
                  font),
              pw.Divider(),
              _pdfRow('SON BAKİYE', _bakiyeYaz(widget.sonBakiye!), bold, fontSize: 9),
              pw.Divider(),
            ],

            pw.Text(_altYazi, style: pw.TextStyle(font: bold, fontSize: 9),
                textAlign: pw.TextAlign.center),

            // ══════════════════════════════════════════════════════════
            // 🆕 FİŞ BARKODU (PDF yolu)
            //
            // ESC/POS tarafındaki {B kod seti sorunu BURADA YOK —
            // barcode paketi kendi kodlamasını yapıyor, önek gerekmez.
            // Kasiyer bu barkodu Hızlı Satış'ta okutup fişi geri
            // çağırabilir.
            // ══════════════════════════════════════════════════════════
            if (_altBarkodGoster && (s.fisNo ?? '').isNotEmpty) ...[
              pw.SizedBox(height: 6),
              pw.BarcodeWidget(
                barcode: bc.Barcode.code128(),
                data: s.fisNo!,
                width: 140,
                height: 38,
                drawText: false,
              ),
              pw.SizedBox(height: 2),
              pw.Text(s.fisNo!,
                  style: pw.TextStyle(font: font, fontSize: 7),
                  textAlign: pw.TextAlign.center),
            ],

            pw.SizedBox(height: 8),
          ],
        ),
      ),
    ));
    return doc;
  }

  pw.Widget _pdfRow(String l, String v, pw.Font f, {double fontSize = 8}) =>
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text(l, style: pw.TextStyle(font: f, fontSize: fontSize)),
        pw.Text(v, style: pw.TextStyle(font: f, fontSize: fontSize)),
      ]);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F0F0),
      appBar: TsAppBar(
        baslik: 'Fiş Önizleme',
        aksiyonlar: [
          if (_btBagliMi)
            _yaziliyor
                ? const Padding(padding: EdgeInsets.all(14),
                    child: SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)))
                : IconButton(
                    icon: const Icon(Icons.print),
                    tooltip: 'BT Yazıcıya Gönder',
                    onPressed: _btYazdir,
                  ),
          IconButton(
            icon: Image.asset("assets/images/pdf_icon.png", width: 22, height: 22, errorBuilder: (_, __, ___) => const Icon(Icons.picture_as_pdf)),
            tooltip: 'PDF / Paylaş',
            onPressed: _pdfYazdir,
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Container(
            width: 280,
            decoration: BoxDecoration(
              // Gerçek termal kağıt her zaman beyazdır — bu önizleme
              // kutusu bilinçli olarak temadan bağımsız, sabit beyaz
              // tutuluyor (fiş içeriğindeki siyah metinlerle tutarlı
              // kalması için — aksi halde karanlık modda kağıt koyulaşıp
              // metin okunaksız olurdu).
              color: Colors.white,
              boxShadow: [BoxShadow(color: Color(0x26000000),
                  blurRadius: 20, offset: const Offset(0, 4))],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Başlık
                Text(_firmaAdi, style: const TextStyle(
                    fontWeight: FontWeight.w900, fontSize: 16,
                    fontFamily: 'Courier'), textAlign: TextAlign.center),
                if (_firmaAdres.isNotEmpty)
                  Text(_firmaAdres, style: _fisStyle(11), textAlign: TextAlign.center),
                if (_firmaTel.isNotEmpty)
                  Text('Tel: $_firmaTel', style: _fisStyle(11), textAlign: TextAlign.center),
                const SizedBox(height: 6),
                _divider(),

                // Fiş bilgileri
                _satir2('Tarih', DateFormat('dd.MM.yyyy HH:mm').format(s.tarih)),
                _satir2('Fiş No', s.fisNo ?? '-'),
                if (_cariAdiGoster && s.cariAdi != null && s.cariAdi!.isNotEmpty)
                  _satir2('Cari', s.cariAdi!),
                _divider(),

                // Kolon başlıkları
                Row(children: [
                  Expanded(child: Text('Ürün', style: _fisStyleBold(10))),
                  SizedBox(width: 30, child: Text('Mkt', style: _fisStyleBold(10), textAlign: TextAlign.center)),
                  SizedBox(width: 60, child: Text('Tutar', style: _fisStyleBold(10), textAlign: TextAlign.right)),
                ]),
                _divider(dashed: true),

                // Kalemler
                ...s.kalemler.map((k) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(k.urunAdi, style: _fisStyle(10), maxLines: 2)),
                      SizedBox(width: 30, child: Text(
                          k.miktar % 1 == 0 ? '${k.miktar.toInt()}' : k.miktar.toStringAsFixed(2),
                          style: _fisStyle(10), textAlign: TextAlign.center)),
                      SizedBox(width: 60, child: Text(_fmt.format(k.toplamTutar),
                          style: _fisStyle(10), textAlign: TextAlign.right)),
                    ]),
                    if (k.iskontoTutar > 0.001)
                      Padding(
                        padding: const EdgeInsets.only(left: 2),
                        child: Text('  İndirim: -${_fmt.format(k.iskontoTutar)}',
                            style: _fisStyle(9).copyWith(color: Colors.orange.shade700)),
                      ),
                    Text('  ${_fmt.format(k.birimFiyat)} / birim',
                        style: _fisStyle(9).copyWith(color: context.textSecondary)),
                  ]),
                )),
                _divider(),

                // Toplamlar
                if (_toplamIskonto > 0.001)
                  _satir2('İSKONTO', '-${_fmt.format(_toplamIskonto)}',
                      renk: Colors.orange),
                if (_kdvGoster && _toplamKdv > 0.001)
                  _satir2('KDV', _fmt.format(_toplamKdv)),
                _satir2('TOPLAM', _fmt.format(s.genelToplam), bold: true, buyuk: true),
                _satir2('Ödenen (${s.odemeYontemi})', _fmt.format(s.odenenTutar)),
                if (_paraUstu > 0.01)
                  _satir2('PARA ÜSTÜ', _fmt.format(_paraUstu),
                      bold: true, renk: Colors.blue.shade700),
                _divider(),

                // ══════════════════════════════════════════════════════
                // 🆕 CARİ HESAP ÖZETİ (EKRAN ÖNİZLEMESİ)
                //
                // Bu ekran fişin ÜÇÜNCÜ çizim yolu. ESC/POS ve PDF
                // yollarına eklenen özellikler burada YOKTU — kullanıcı
                // önizlemeye bakınca hiçbirini göremiyordu.
                // ══════════════════════════════════════════════════════
                if (_cariBakiyeGoster &&
                    widget.oncekiBakiye != null && widget.sonBakiye != null) ...[
                  Text('CARİ HESAP ÖZETİ',
                      style: _fisStyleBold(10), textAlign: TextAlign.center),
                  const SizedBox(height: 2),
                  _satir2('Eski Bakiye', _bakiyeYaz(widget.oncekiBakiye!)),
                  _satir2(
                      (widget.sonBakiye! - widget.oncekiBakiye!) >= 0
                          ? '(+) Bu Fiş' : '(-) Bu Fiş',
                      _fmt.format((widget.sonBakiye! - widget.oncekiBakiye!).abs())),
                  _divider(dashed: true),
                  _satir2('SON BAKİYE', _bakiyeYaz(widget.sonBakiye!), bold: true),
                  _divider(),
                ],

                // Alt yazı
                const SizedBox(height: 4),
                Text(_altYazi, style: _fisStyleBold(11), textAlign: TextAlign.center),

                // ══════════════════════════════════════════════════════
                // 🆕 FİŞ BARKODU (EKRAN ÖNİZLEMESİ)
                //
                // barcode_widget paketi — projede urun_liste_ekrani ve
                // barkod_ureteci_ekrani'nda kanıtlanmış kalıp.
                // (PDF tarafındaki `bc.Barcode` FARKLI bir paket:
                //  `barcode` → PDF çizimi, `barcode_widget` → ekran.)
                // ══════════════════════════════════════════════════════
                if (_altBarkodGoster && (s.fisNo ?? '').isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Center(
                    child: bw.BarcodeWidget(
                      barcode: bw.Barcode.code128(),
                      data: s.fisNo!,
                      width: 200,
                      height: 50,
                      drawText: false,
                      errorBuilder: (_, __) => Text(s.fisNo!, style: _fisStyle(10)),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(s.fisNo!, style: _fisStyle(9), textAlign: TextAlign.center),
                ],

                const SizedBox(height: 16),

                // Kesik çizgi alt
                Row(children: List.generate(35,
                    (i) => i % 2 == 0
                        ? const Text('-', style: TextStyle(fontFamily: 'Courier', fontSize: 10))
                        : const SizedBox(width: 3))),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: _yaziliyor ? null : _fisBas,
                icon: _yaziliyor
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.print),
                label: Text(_yaziliyor ? 'Yazdırılıyor...' : 'Fiş Bas'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pdfYazdir,
                icon: Image.asset("assets/images/pdf_icon.png", width: 22, height: 22, errorBuilder: (_, __, ___) => const Icon(Icons.picture_as_pdf)),
                label: const Text('PDF / Paylaş'),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Yardımcı widgetlar ─────────────────────────────────────────────────────
  TextStyle _fisStyle(double sz) => TextStyle(
    fontSize: sz, fontFamily: 'Courier', color: Colors.black87);
  TextStyle _fisStyleBold(double sz) => TextStyle(
    fontSize: sz, fontFamily: 'Courier', fontWeight: FontWeight.bold, color: Colors.black);

  Widget _divider({bool dashed = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: dashed
        ? Row(children: List.generate(35,
            (i) => i % 2 == 0
                ? const Text('- ', style: TextStyle(fontFamily: 'Courier', fontSize: 10))
                : const SizedBox()))
        : Container(height: 1, color: Colors.black),
  );

  Widget _satir2(String l, String v,
      {bool bold = false, bool buyuk = false, Color? renk}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 1.5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(l, style: bold ? _fisStyleBold(buyuk ? 12 : 10) : _fisStyle(10)),
            Text(v, style: (bold ? _fisStyleBold(buyuk ? 12 : 10) : _fisStyle(10))
                .copyWith(color: renk)),
          ],
        ),
      );
}
