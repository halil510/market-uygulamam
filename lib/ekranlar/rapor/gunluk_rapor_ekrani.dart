// lib/ekranlar/rapor/gunluk_rapor_ekrani.dart
// Eski uygulamadan tam gün sonu mantığı, yeni altyapıya adapte edildi

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../widgetlar/ortak/app_widgetlar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:excel/excel.dart' hide Border, BorderStyle;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import 'dart:io';
import '../../modeller/satis_model.dart';
import '../../depolar/satis_deposu.dart';
import '../../depolar/gider_deposu.dart';
import '../../depolar/kasa_deposu.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../cekirdek/utils/excel_guvenlik_utils.dart';

class GunlukRaporEkrani extends ConsumerStatefulWidget {
  const GunlukRaporEkrani({super.key});
  @override
  ConsumerState<GunlukRaporEkrani> createState() => _GunlukRaporEkraniState();
}

class _GunlukRaporEkraniState extends ConsumerState<GunlukRaporEkrani> {
  final _satisDepo = SatisDeposu();
  final _giderDepo = GiderDeposu();
  final _kasaDepo  = KasaDeposu();

  DateTime _baslangic = DateTime.now();
  DateTime _bitis     = DateTime.now();
  String _periyot = 'Günlük';
  final List<String> _periyotSecenekleri = ['Günlük', 'Haftalık', 'Aylık', 'Özel'];

  List<SatisModel> _satislar = [];
  double _toplamTutar     = 0;
  double _nakitToplam     = 0;
  double _kartToplam      = 0;
  double _cariToplam      = 0;
  double _havaleToplam    = 0;
  // 🔴 DÜZELTME (komple derin analizde bulundu): QR ve Karma ödemeli
  // satışlar ÖNCEDEN hiçbir kırılıma dahil edilmiyordu — "Toplam Satış"a
  // giriyor ama Nakit/Kart/Cari/Havale'nin hiçbirine eklenmiyordu, bu da
  // kırılım toplamının genel toplamdan düşük görünmesine yol açıyordu.
  double _digerToplam     = 0;
  double _giderToplam     = 0;
  double _maliyetToplam   = 0;
  double _brutKar         = 0;
  double _kar             = 0;
  bool _yukleniyor = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _baslangic = DateTime(now.year, now.month, now.day);
    _bitis     = DateTime(now.year, now.month, now.day, 23, 59, 59);
    WidgetsBinding.instance.addPostFrameCallback((_) => _yukle());
  }

  Future<void> _yukle() async {
    if (!mounted) return;
    _yukleniyor = true;

    if (mounted) setState(() {});
    try {
      // 🔴 Derin denetimde bulundu (P1): maliyet (COGS) sorgusunda
      // sube_id filtresi yoktu — üstteki tariheGoreGetir() zaten aktif
      // şubeye göre filtrelerken, bu sorgu HER ZAMAN tüm şubelerin
      // maliyetini topluyordu. Çok şubeli kurulumda "Net Kâr" rakamı
      // bu yüzden yanlış hesaplanıyordu (bir şubenin karı, diğer TÜM
      // şubelerin maliyetiyle kirleniyordu). tariheGoreGetir()'deki
      // AYNI desenle hizalandı.
      //
      // 🔴 DÜZELTME (Madde 24 — Raporlar denetimi, 2026-09-20): maliyet
      // HER ZAMAN urunler.alis_fiyat'ın (ürünün GÜNCEL alış fiyatı)
      // kullanıyordu — satış anındaki TARİHSEL maliyeti DEĞİL. Bir
      // ürünün alış fiyatı satıştan SONRA güncellenirse (ör. tedarikçi
      // zammı), bu rapor o tarihe her dönüldüğünde SESSİZCE farklı bir
      // "Net Kâr" göstermeye başlıyordu — Kâr/Zarar raporu (kar_zarar_
      // provider.dart) ise satis_kalem.alis_fiyat'ta (satış anında
      // satır'a kalıcı olarak damgalanan tarihsel maliyet) SAKLANAN
      // değeri doğru kullanıyordu. AYNI tarih için iki rapor farklı
      // Net Kâr gösterebiliyordu. Artık AYNI formül (sk.alis_fiyat
      // varsa o, yoksa — eski/migrasyon-öncesi satırlar için — güncel
      // urunler.alis_fiyat'a düşülür) — bkz. SatisDeposu.maliyetToplami.
      final results = await Future.wait([
        _satisDepo.tariheGoreGetir(_baslangic, _bitis),
        _giderDepo.aralikToplamGider(_baslangic, _bitis),
        _satisDepo.maliyetToplami(_baslangic, _bitis),
      ]);

      final satislar = results[0] as List<SatisModel>;
      final gider    = results[1] as double;
      final maliyet  = results[2] as double;

      double toplam = 0, nakit = 0, kart = 0, cari = 0, havale = 0, diger = 0;
      for (final s in satislar) {
        toplam += s.genelToplam;
        switch (s.odemeYontemi) {
          case 'Nakit':       nakit  += s.odenenTutar; break;
          case 'Kredi Kartı': kart   += s.odenenTutar; break;
          case 'Cari':        cari   += s.genelToplam; break;
          case 'Havale':      havale += s.odenenTutar; break;
          // QR, Karma ve ileride eklenebilecek başka ödeme yöntemleri —
          // kırılım toplamının genel toplamdan eksik görünmemesi için.
          default:            diger  += s.odenenTutar; break;
        }
      }
      if (!mounted) return;
      setState(() {
        _satislar     = satislar;
        _toplamTutar  = toplam;
        _nakitToplam  = nakit;
        _kartToplam   = kart;
        _cariToplam   = cari;
        _havaleToplam = havale;
        _digerToplam  = diger;
        _giderToplam  = gider;
        _maliyetToplam= maliyet;
        _brutKar      = toplam - maliyet;      // Brut kar = ciro - alis maliyeti
        _kar          = toplam - maliyet - gider; // Net kar = brut kar - giderler
        _yukleniyor   = false;
      });
    } catch (e) {
      if (!mounted) return;
      _yukleniyor = false;
      hataMesaji(context, 'Rapor hatası: $e');
    }
  }

  void _periyotDegisti(String? v) {
    if (v == null || v == 'Özel') return;
    final now = DateTime.now();
    DateTime bas, bit;
    if (v == 'Günlük') {
      bas = DateTime(now.year, now.month, now.day);
      bit = DateTime(now.year, now.month, now.day, 23, 59, 59);
    } else if (v == 'Haftalık') {
      bas = now.subtract(Duration(days: now.weekday - 1));
      bas = DateTime(bas.year, bas.month, bas.day);
      bit = DateTime(bas.year, bas.month, bas.day + 6, 23, 59, 59);
    } else {
      bas = DateTime(now.year, now.month, 1);
      bit = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
    }
    if (!mounted) return;
    setState(() { _periyot = v; _baslangic = bas; _bitis = bit; });
    _yukle();
  }

  Future<void> _tarihSec(bool baslangicMi) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: baslangicMi ? _baslangic : _bitis,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year, now.month, now.day, 23, 59),
    );
    if (d == null || !mounted) return;
    setState(() {
      if (baslangicMi) {
        _baslangic = DateTime(d.year, d.month, d.day);
        if (_bitis.isBefore(_baslangic)) _bitis = DateTime(d.year, d.month, d.day, 23, 59, 59);
      } else {
        _bitis = DateTime(d.year, d.month, d.day, 23, 59, 59);
        if (_baslangic.isAfter(_bitis)) _baslangic = DateTime(d.year, d.month, d.day);
      }
      _periyot = 'Özel';
    });
    _yukle();
  }

  Future<void> _exceleAktar() async {
  if (_satislar.isEmpty) {
    hataMesaji(context, 'Aktarılacak veri yok');
    return;
  }

  if (!mounted) return;
  _yukleniyor = true;
  if (mounted) setState(() {});

  try {
    // ★★★★★ DÜZELTİLMİŞ SQL SORGUSU - cari_adi yerine cari.unvan ★★★★★
    // 🔴 Derin denetimde bulundu (P1): burada da sube_id filtresi
    // yoktu — ekrandaki özet doğru şubeye göre filtrelenirken, Excel
    // dışa aktarımı sessizce TÜM şubelerin satış kalemlerini
    // içeriyordu (hem ekranla uyuşmayan bir rapor hem de diğer
    // şubelerin verisinin sızması). Artık SatisDeposu.gunSonuDetayGetir
    // aktif şubeye göre filtreliyor (bkz. o metodun yorumu).
    final sorguSonucu = await _satisDepo.gunSonuDetayGetir(_baslangic, _bitis);

    if (sorguSonucu.isEmpty) {
      if (mounted) {
        hataMesaji(context, 'Bu tarih aralığında satış kalemi bulunamadı');
      }
      _yukleniyor = false;
      if (mounted) setState(() {});
      return;
    }
    
    final excel = Excel.createExcel();
    
    // ---------- 1. ÖZET SAYFASI ----------
    final ozetSayfa = excel['Gun Sonu Ozeti'];
    excel.delete('Sheet1');
    
    ozetSayfa.appendRow([TextCellValue('GUN SONU RAPORU')]);
    ozetSayfa.appendRow([TextCellValue('Tarih Araligi: ${DateFormat('dd.MM.yyyy').format(_baslangic)} - ${DateFormat('dd.MM.yyyy').format(_bitis)}')]);
    ozetSayfa.appendRow([TextCellValue('Olusturma: ${DateFormat('dd.MM.yyyy HH:mm:ss').format(DateTime.now())}')]);
    ozetSayfa.appendRow([TextCellValue('')]);
    
    ozetSayfa.appendRow([TextCellValue('KALEM'), TextCellValue('TUTAR (TL)')]);
    ozetSayfa.appendRow([TextCellValue('Toplam Satis'), DoubleCellValue(_toplamTutar)]);
    ozetSayfa.appendRow([TextCellValue('Nakit'), DoubleCellValue(_nakitToplam)]);
    ozetSayfa.appendRow([TextCellValue('Kredi Karti'), DoubleCellValue(_kartToplam)]);
    ozetSayfa.appendRow([TextCellValue('Cari'), DoubleCellValue(_cariToplam)]);
    ozetSayfa.appendRow([TextCellValue('Havale'), DoubleCellValue(_havaleToplam)]);
    if (_digerToplam > 0)
      ozetSayfa.appendRow([TextCellValue('Diger (QR/Karma)'), DoubleCellValue(_digerToplam)]);
    ozetSayfa.appendRow([TextCellValue('Gider'), DoubleCellValue(_giderToplam)]);
    ozetSayfa.appendRow([TextCellValue('Maliyet (Alis)'), DoubleCellValue(_maliyetToplam)]);
    ozetSayfa.appendRow([TextCellValue('Brut Kar'), DoubleCellValue(_brutKar)]);
    ozetSayfa.appendRow([TextCellValue('Net Kar'), DoubleCellValue(_kar)]);
    
    // ---------- 2. DETAYLI SATIS RAPORU ----------
    final detaySayfa = excel['Satis Detay Raporu'];
    
    final basliklar = [
      'Kod', 'Urun Adi', 'Miktar', 'Birim',
      'Kdv li fiyat', 'Kdv li tutar', 'Indirim', 'Kdv (%)', 'Net Tutar TL',
      'Musteri', 'Tarih', 'Saat'
    ];
    
    detaySayfa.appendRow(basliklar.map((b) => TextCellValue(b)).toList());
    
    int toplamKalemSayisi = 0;
    for (final row in sorguSonucu) {
      String kod = row['barkod']?.toString() ?? '';
      if (kod.isEmpty) kod = row['urun_id']?.toString() ?? '';
      
      String urunAdi = row['urun_adi']?.toString() ?? '-';
      double miktar = _toDouble(row['miktar']);
      String birim = 'ADET';
      double kdvliFiyat = _toDouble(row['birim_fiyat']);
      double kdvliTutar = _toDouble(row['toplam_tutar']);
      double indirimTutari = _toDouble(row['iskonto_tutar']);
      double kdvOrani = _toDouble(row['kdv_oran']);
      double netFiyat = _toDouble(row['net_fiyat']);
      double netTutarTL = netFiyat * miktar;
      
      // ★★★★★ DÜZELTİLDİ: cari_unvan kullanılıyor ★★★★★
      String musteri = row['cari_unvan']?.toString() ?? 'Perakende';
      
      DateTime tarih = DateTime.tryParse(row['tarih']?.toString() ?? '') ?? DateTime.now();
      String tarihStr = DateFormat('dd.MM.yyyy').format(tarih);
      String saatStr = DateFormat('HH:mm:ss').format(tarih);
      
      detaySayfa.appendRow([
        TextCellValue(excelIcinGuvenliMetin(kod)),
        TextCellValue(excelIcinGuvenliMetin(urunAdi)),
        DoubleCellValue(miktar),
        TextCellValue(birim),
        DoubleCellValue(kdvliFiyat),
        DoubleCellValue(kdvliTutar),
        DoubleCellValue(indirimTutari),
        DoubleCellValue(kdvOrani),
        DoubleCellValue(netTutarTL),
        TextCellValue(excelIcinGuvenliMetin(musteri)),
        TextCellValue(tarihStr),
        TextCellValue(saatStr),
      ]);
      
      toplamKalemSayisi++;
    }
    
    // ---------- 3. KDV OZET SAYFASI ----------
    final kdvOzetSayfa = excel['KDV Ozeti'];
    kdvOzetSayfa.appendRow([
      TextCellValue('KDV Orani (%)'), 
      TextCellValue('Matrah (KDV Haric Net Tutar)'), 
      TextCellValue('KDV Tutari (TL)'),
      TextCellValue('Toplam Tutar (KDV Dahil)')
    ]);
    
    Map<double, double> kdvMatrah = {};
    Map<double, double> kdvTutari = {};
    Map<double, double> kdvDahilToplam = {};
    
    for (final row in sorguSonucu) {
      double oran = _toDouble(row['kdv_oran']);
      double net = _toDouble(row['net_fiyat']);
      double miktar = _toDouble(row['miktar']);
      double kdv = _toDouble(row['kdv_tutar']);
      double dahil = _toDouble(row['toplam_tutar']);
      
      kdvMatrah[oran] = (kdvMatrah[oran] ?? 0) + (net * miktar);
      kdvTutari[oran] = (kdvTutari[oran] ?? 0) + kdv;
      kdvDahilToplam[oran] = (kdvDahilToplam[oran] ?? 0) + dahil;
    }
    
    final kdvOranlari = kdvMatrah.keys.toList()..sort();
    for (final oran in kdvOranlari) {
      kdvOzetSayfa.appendRow([
        DoubleCellValue(oran),
        DoubleCellValue(kdvMatrah[oran]!),
        DoubleCellValue(kdvTutari[oran]!),
        DoubleCellValue(kdvDahilToplam[oran]!),
      ]);
    }
    
    // Dosyayi kaydet
    final dir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'gun_sonu_raporu_$timestamp.xlsx';
    final filePath = '${dir.path}/$fileName';
    
    File(filePath).writeAsBytesSync(excel.encode()!);
    
    await Share.shareXFiles(
      [XFile(filePath)], 
      text: 'Gun Sonu Raporu - ${DateFormat('dd.MM.yyyy').format(_baslangic)}',
    );
    
    if (mounted) {
      basariMesaji(context, '$toplamKalemSayisi kalem iceren Excel raporu olusturuldu');
    }
    
  } catch (e, stackTrace) {
    if (kDebugMode) debugPrint('Excel hatasi: $e');
    if (kDebugMode) debugPrint(stackTrace.toString());
    if (mounted) {
      hataMesaji(context, 'Excel olusturulurken hata: $e');
    }
  } finally {
    if (mounted) setState(() => _yukleniyor = false);
  }
  }

// Yardimci metod
double _toDouble(dynamic value) {
  if (value == null) return 0.0;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0.0;
  return 0.0;
}

  Future<void> _pdfOlustur() async {
    final font     = await PdfGoogleFonts.robotoRegular();
    final boldFont = await PdfGoogleFonts.robotoBold();
    final pdf = pw.Document();
    final fmt = DateFormat('dd.MM.yyyy');

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      header: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Center(child: pw.Text('GÜN SONU RAPORU',
              style: pw.TextStyle(font: boldFont, fontSize: 18))),
          pw.SizedBox(height: 6),
          pw.Center(child: pw.Text('${fmt.format(_baslangic)} – ${fmt.format(_bitis)}',
              style: pw.TextStyle(font: font, fontSize: 11))),
          pw.Divider(),
        ],
      ),
      build: (ctx) => [
        pw.Table(border: pw.TableBorder.all(),
          columnWidths: {0: const pw.FlexColumnWidth(3), 1: const pw.FlexColumnWidth(2)},
          children: [
            _pdfSatir('Toplam Satış',   _toplamTutar,  boldFont),
            _pdfSatir('Nakit',           _nakitToplam,  font),
            _pdfSatir('Kredi Kartı',     _kartToplam,   font),
            _pdfSatir('Cari Satış',      _cariToplam,   font),
            _pdfSatir('Havale',          _havaleToplam, font),
            if (_digerToplam > 0)
              _pdfSatir('Diğer (QR/Karma)', _digerToplam, font),
            _pdfSatir('Gider',           _giderToplam,  font),
            _pdfSatir('Net Kar',         _kar,          boldFont),
          ],
        ),
        pw.SizedBox(height: 20),
        pw.Text('Satış Hareketleri', style: pw.TextStyle(font: boldFont, fontSize: 13)),
        pw.SizedBox(height: 8),
        pw.Table(border: pw.TableBorder.all(),
          columnWidths: {
            0: const pw.FlexColumnWidth(1.5),
            1: const pw.FlexColumnWidth(2),
            2: const pw.FlexColumnWidth(2),
            3: const pw.FlexColumnWidth(1.5),
            4: const pw.FlexColumnWidth(2),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.blue700),
              children: [
                _pdfHucre('Fiş No', boldFont, beyaz: true),
                _pdfHucre('Tarih',  boldFont, beyaz: true),
                _pdfHucre('Müşteri', boldFont, beyaz: true),
                _pdfHucre('Ödeme',  boldFont, beyaz: true),
                _pdfHucre('Tutar',  boldFont, beyaz: true),
              ],
            ),
            ..._satislar.map((s) => pw.TableRow(children: [
              _pdfHucre(s.fisNo ?? s.id?.toString() ?? '-', font),
              _pdfHucre(DateFormat('dd.MM HH:mm').format(s.tarih), font),
              _pdfHucre(s.cariAdi ?? 'Perakende', font),
              _pdfHucre(s.odemeYontemi, font),
              _pdfHucre(ParaUtils.formatla(s.genelToplam), font),
            ])),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Align(alignment: pw.Alignment.centerRight,
          child: pw.Text('Toplam ${_satislar.length} satış',
              style: pw.TextStyle(font: font, fontSize: 10))),
      ],
    ));
    await Printing.layoutPdf(onLayout: (_) async => pdf.save());
  }

  pw.TableRow _pdfSatir(String label, double val, pw.Font font) => pw.TableRow(children: [
    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(label, style: pw.TextStyle(font: font))),
    pw.Padding(padding: const pw.EdgeInsets.all(4),
        child: pw.Text(ParaUtils.formatla(val), style: pw.TextStyle(font: font))),
  ]);

  pw.Widget _pdfHucre(String text, pw.Font font, {bool beyaz = false}) =>
      pw.Padding(padding: const pw.EdgeInsets.all(4),
        child: pw.Text(text, style: pw.TextStyle(font: font,
            color: beyaz ? PdfColors.white : PdfColors.black, fontSize: 9)));

  Future<void> _fisDetay(SatisModel s) async {
    // Kalemler henüz yüklenmemişse DB'den çek
    SatisModel detay = s;
    if (s.kalemler.isEmpty && s.id != null) {
      try {
        final loaded = await _satisDepo.idileGetir(s.id!);
        if (loaded != null) detay = loaded;
      } catch (e) { /* ignore */ }
    }
    if (!mounted) return;
    // ignore: use_build_context_synchronously
    showDialog(
      context: context,
      builder: (ctx) {
        final s = detay; // loaded version
        return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        
        titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Fiş: ' + (s.fisNo ?? '-'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: s.odemeYontemi == 'Nakit' ? Colors.green.shade100
                    : s.odemeYontemi == 'Kredi Kartı' ? Colors.blue.shade100
                    : Colors.orange.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(s.odemeYontemi,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 2),
          Text(DateFormat('dd.MM.yyyy HH:mm').format(s.tarih),
              style: TextStyle(fontSize: 11, color: context.textSecondary,
                  fontWeight: FontWeight.normal)),
          if (s.cariAdi != null)
            Text(s.cariAdi!,
                style: const TextStyle(fontSize: 11, color: Colors.blue,
                    fontWeight: FontWeight.normal)),
        ]),
        contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Tablo başlığı
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              decoration: BoxDecoration(
                  color: context.borderColor,
                  borderRadius: BorderRadius.circular(6)),
              child: Row(children: [
                Expanded(flex: 5, child: Text('Ürün Adı',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                        color: context.textSecondary))),
                SizedBox(width: 40, child: Text('Adet',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                        color: context.textSecondary))),
                SizedBox(width: 56, child: Text('B.Fiyat',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                        color: context.textSecondary))),
                SizedBox(width: 60, child: Text('Toplam',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                        color: context.textSecondary))),
              ]),
            ),
            const SizedBox(height: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: s.kalemler.length,
                itemBuilder: (_, i) {
                  final k = s.kalemler[i];
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    child: Row(children: [
                      Expanded(flex: 5, child: Text(k.urunAdi,
                          style: const TextStyle(fontSize: 12,
                              fontWeight: FontWeight.w500),
                          maxLines: 2, overflow: TextOverflow.ellipsis)),
                      SizedBox(width: 40, child: Text(
                          k.miktar % 1 == 0
                              ? k.miktar.toStringAsFixed(0)
                              : k.miktar.toStringAsFixed(2),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12))),
                      SizedBox(width: 56, child: Text(
                          ParaUtils.formatla(k.birimFiyat),
                          textAlign: TextAlign.right,
                          style: TextStyle(fontSize: 11,
                              color: context.textSecondary))),
                      SizedBox(width: 60, child: Text(
                          ParaUtils.formatla(k.toplamTutar),
                          textAlign: TextAlign.right,
                          style: TsMetin.kucukVurgu)),
                    ]),
                  );
                },
              ),
            ),
            const Divider(height: 16),
            if (s.iskonto > 0) Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('İskonto',
                        style: TextStyle(fontSize: 12, color: Colors.orange)),
                    Text('-${ParaUtils.formatla(s.iskonto)}',
                        style: const TextStyle(fontSize: 12,
                            color: Colors.orange, fontWeight: FontWeight.w600)),
                  ]),
            ),
            if (s.kdvTutar > 0) Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('KDV',
                        style: TextStyle(fontSize: 12, color: context.textSecondary)),
                    Text(ParaUtils.formatla(s.kdvTutar),
                        style: TextStyle(
                            fontSize: 12, color: context.textSecondary)),
                  ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12)),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('GENEL TOPLAM',
                        style: TextStyle(fontWeight: FontWeight.w700,
                            fontSize: 13)),
                    Text(ParaUtils.formatla(s.genelToplam),
                        style: const TextStyle(fontWeight: FontWeight.w800,
                            fontSize: 17, color: Colors.green)),
                  ]),
            ),
          ]),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Kapat')),
        ],
      );
      }, // builder
    );
  }

  Widget _bilgiKart(String baslik, double deger, Color renk, {bool bold = false}) {
    Color gosterim = renk;
    if (bold && baslik.contains('Kar')) {
      gosterim = deger > 0 ? Colors.green : deger < 0 ? Colors.red : context.textSecondary;
    }
    return Container(
      decoration: BoxDecoration(
        color: Color.fromARGB(26, gosterim.red, gosterim.green, gosterim.blue),
        borderRadius: BorderRadius.circular(14),
      ),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            if (bold) Icon(Icons.trending_up, color: gosterim, size: 20),
            if (bold) const SizedBox(width: 8),
            Text(baslik, style: TextStyle(
                fontSize: 15, fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          ]),
          Text(ParaUtils.formatla(deger), style: TextStyle(
              fontSize: bold ? 17 : 15,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              color: bold ? gosterim : null)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'Gün Sonu Raporu',
        aksiyonlar: [
          IconButton(icon: Image.asset("assets/images/pdf_icon.png", width: 22, height: 22, errorBuilder: (_, __, ___) => const Icon(Icons.picture_as_pdf, color: Colors.white)), tooltip: 'PDF', onPressed: _pdfOlustur),
          IconButton(icon: Image.asset("assets/images/excel_icon.png", width: 22, height: 22, errorBuilder: (_, __, ___) => const Icon(Icons.table_chart, color: Colors.white)), tooltip: "Excel'e Aktar", onPressed: _exceleAktar),
          IconButton(icon: const Icon(Icons.refresh, color: Colors.white), tooltip: 'Yenile', onPressed: _yukle),
        ],
        geriTusu: false,
      ),
      body: Column(children: [
        // Tarih / periyot seçimi
        Container(
          color: context.borderColor,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(children: [
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today, size: 16),
                label: Text(DateFormat('dd.MM.yyyy').format(_baslangic),
                    style: const TextStyle(fontSize: 13)),
                onPressed: () => _tarihSec(true),
              )),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('–')),
              Expanded(child: OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today, size: 16),
                label: Text(DateFormat('dd.MM.yyyy').format(_bitis),
                    style: const TextStyle(fontSize: 13)),
                onPressed: () => _tarihSec(false),
              )),
            ]),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _periyot,
              isExpanded: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
              ),
              items: _periyotSecenekleri.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: _periyotDegisti,
            ),
          ]),
        ),
        Expanded(child: _yukleniyor
          ? const TsYukleniyor()
          : RefreshIndicator(
              onRefresh: _yukle,
              child: ListView(padding: const EdgeInsets.all(12), children: [
                _bilgiKart('Toplam Satış',   _toplamTutar,  Colors.blue,   bold: true),
                _bilgiKart('Nakit Satış',     _nakitToplam,  Colors.green),
                _bilgiKart('Kredi Kartı',     _kartToplam,   Colors.orange),
                _bilgiKart('Cari Satış',      _cariToplam,   Colors.indigo),
                _bilgiKart('Havale',          _havaleToplam, Colors.teal),
                if (_digerToplam > 0)
                  _bilgiKart('Diğer (QR/Karma)', _digerToplam, Colors.blueGrey),
                _bilgiKart('Gider',           _giderToplam,   Colors.red),
                _bilgiKart('Maliyet (Alis)',  _maliyetToplam, Colors.brown),
                _bilgiKart('Brut Kar',        _brutKar,       Colors.teal, bold: true),
                _bilgiKart('Net Kar',         _kar,           Colors.purple, bold: true),
                const SizedBox(height: 12),
                const Divider(),
                Padding(padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('Satış Hareketleri (${_satislar.length})',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    Text(DateFormat('dd.MM.yyyy').format(_baslangic),
                        style: TextStyle(color: TsRenk.metinIkincil(context), fontSize: 12)),
                  ]),
                ),
                if (_satislar.isEmpty)
                  Center(child: Padding(padding: const EdgeInsets.all(32),
                    child: Column(children: [
                      Icon(Icons.receipt_long, size: 56, color: TsRenk.ayirac(context)),
                      const SizedBox(height: 12),
                      Text('Bu tarih aralığında işlem yok',
                          style: TextStyle(color: context.textSecondary)),
                    ]),
                  ))
                else
                  ..._satislar.map((s) {
                    final idStr = s.fisNo ?? s.id?.toString().padLeft(6, '0') ?? '-';
                    Color odemeRenk = TsRenk.ayirac(context);
                    if (s.odemeYontemi == 'Nakit') odemeRenk = Colors.green.shade100;
                    if (s.odemeYontemi == 'Kredi Kartı') odemeRenk = Colors.blue.shade100;
                    if (s.odemeYontemi == 'Cari') odemeRenk = Colors.orange.shade100;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        color: TsRenk.kart(context),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: TsRenk.ayirac(context)),
                      ),
                      child: ListTile(
                        dense: true,
                        leading: CircleAvatar(radius: 20,
                          backgroundColor: Colors.blue.shade50,
                          child: Text(idStr.length >= 3 ? idStr.substring(idStr.length - 3) : idStr,
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue))),
                        title: Text('Fiş: $idStr',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        subtitle: Row(children: [
                          Text(DateFormat('HH:mm').format(s.tarih),
                              style: TextStyle(color: TsRenk.metinIkincil(context), fontSize: 11)),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(color: odemeRenk, borderRadius: BorderRadius.circular(12)),
                            child: Text(s.odemeYontemi, style: const TextStyle(fontSize: 10))),
                          if (s.cariAdi != null) ...[
                            const SizedBox(width: 6),
                            Expanded(child: Text(s.cariAdi!,
                                style: TextStyle(fontSize: 10, color: TsRenk.metinIkincil(context)),
                                overflow: TextOverflow.ellipsis)),
                          ],
                        ]),
                        trailing: Text(ParaUtils.formatla(s.genelToplam),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        onTap: () => _fisDetay(s),
                      ),
                    );
                  }),
              ]),
            ),
        ),
      ]),
    );
  }
}
