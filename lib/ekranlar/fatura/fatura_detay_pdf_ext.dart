// lib/ekranlar/fatura/fatura_detay_pdf_ext.dart
// fatura_detay_ekrani.dart'ın parçası — PDF/termal fiş üretim mantığı
// (god-class sertleştirmesi, 2026-09-22). Davranış birebir korundu.
part of 'fatura_detay_ekrani.dart';

extension _FaturaDetayPdfExt on _FaturaDetayEkraniState {
  // ── Firma (satıcı) bilgilerini al ───────────────────────────────────────
  Future<Map<String, String>> _firmaBilgileri() async {
    final out = <String, String>{
      'adi': 'MarketPlus', 'adres': '', 'vergiNo': '', 'vergiDairesi': '',
      'logoYolu': '', 'imzaYolu': '', 'imzaGoster': 'true',
    };
    try {
      final prefs = await SharedPreferences.getInstance();
      out['adi']          = prefs.getString('firma_adi') ?? out['adi']!;
      out['adres']        = prefs.getString('firma_adres') ?? '';
      out['vergiNo']      = prefs.getString('firma_vergi_no') ?? '';
      out['vergiDairesi'] = prefs.getString('firma_vergi_dairesi') ?? '';
      out['logoYolu']     = prefs.getBool('fatura_logo') == true
          ? (prefs.getString('fatura_logo_yolu') ?? '') : '';
      out['imzaGoster']   = (prefs.getBool('fatura_imza') ?? true).toString();
      out['imzaYolu']     = prefs.getString('fatura_imza_yolu') ?? '';
      out['qrGoster']     = (prefs.getBool('fatura_barkod') ?? true).toString();
      if (out['vergiNo']!.isEmpty || out['adres']!.isEmpty) {
        final m = await AyarlarDeposu().coguGetir(const [
          'firma_adi', 'firma_adres', 'firma_vergi_no', 'firma_vergi_dairesi',
        ]);
        if (out['adres']!.isEmpty) out['adres'] = m['firma_adres'] ?? '';
        if (out['vergiNo']!.isEmpty) out['vergiNo'] = m['firma_vergi_no'] ?? '';
        if (out['vergiDairesi']!.isEmpty) out['vergiDairesi'] = m['firma_vergi_dairesi'] ?? '';
        if (m['firma_adi'] != null && m['firma_adi']!.isNotEmpty) out['adi'] = m['firma_adi']!;
      }
    } catch (_) {/* varsayılanlarla devam */}
    return out;
  }

  // ── PDF oluştur — GİB e-Fatura/e-Arşiv görünümüne uygun ────────────────
  Future<void> _pdfGoster() async {
    if (_fatura == null || !mounted) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final format = prefs.getString('fatura_yazdirma_format') ?? 'a4';
      if (format == '80mm') {
        await _pdf80mmGoster();
        return;
      }
      final bytes = await _pdfBytes();
      if (!mounted) return;
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'PDF hatasi: $e');
    }
  }

  /// Varsayılan ayar ne olursa olsun A4 yazdırır ("⋮ Diğer" menüsü için).
  Future<void> _pdfGosterA4() async {
    if (_fatura == null || !mounted) return;
    try {
      final bytes = await _pdfBytes();
      if (!mounted) return;
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'PDF hatasi: $e');
    }
  }

  /// PDF'i geçici dosyaya yazıp paylaşım sayfası (e-posta dahil) açar.
  Future<void> _epostaGonder() async {
    if (_fatura == null || !mounted) return;
    try {
      final bytes = await _pdfBytes();
      final dir = await getTemporaryDirectory();
      final dosya = File('${dir.path}/Fatura_${_fatura!.faturaNo ?? "fatura"}.pdf');
      await dosya.writeAsBytes(bytes);
      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(dosya.path, mimeType: 'application/pdf')],
        subject: '${_fatura!.faturaTipi ?? "Fatura"} - ${_fatura!.faturaNo ?? ""}',
        text: 'Sayın ${_fatura!.cariUnvan ?? ""},\n\n'
              '${_fatura!.faturaNo ?? "Fatura"} numaralı faturanız ekte yer almaktadır.\n\n'
              'İyi çalışmalar dileriz.',
      );
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Paylaşım hatası: $e');
    }
  }

  /// 80mm termal yazıcı / fiş yazdırma formatında PDF üretir.
  Future<void> _pdf80mmGoster() async {
    if (_fatura == null || !mounted) return;
    try {
      // Bağlı bir termal yazıcı varsa RAW ESC/POS gönder — PDF'in 80mm
      // sayfası bazı yazıcılarda küçük/yanlış ölçekte basılıyor.
      final yazdirma = YazdirmaServisi();
      if (yazdirma.bagliMi) {
        await yazdirma.faturaYazdir(_fatura!);
        if (mounted) BildirimServisi.basari(context, 'Fatura yazıcıya gönderildi');
        return;
      }
      final bytes = await _pdfBytes80mm();
      if (!mounted) return;
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        format: PdfPageFormat(80 * PdfPageFormat.mm, double.infinity,
            marginAll: 3 * PdfPageFormat.mm),
      );
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'PDF hatasi: $e');
    }
  }

  Future<Uint8List> _pdfBytes80mm() async {
    final f        = _fatura!;
    final font     = await PdfGoogleFonts.robotoRegular();
    final boldFont = await PdfGoogleFonts.robotoBold();
    final fmt      = DateFormat('dd.MM.yyyy HH:mm');
    final firma    = await _firmaBilgileri();
    final genislik = 80 * PdfPageFormat.mm;
    final vkn80    = f.cariVergiNo ?? '';
    final eArsivMi80 = vkn80.length == 11;
    final scale    = (await SharedPreferences.getInstance()).getDouble('fatura_font_olcek') ?? 1.0;

    final doc = pw.Document();
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat(genislik, double.infinity, marginAll: 3 * PdfPageFormat.mm),
      build: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
        if (firma['logoYolu']!.isNotEmpty && File(firma['logoYolu']!).existsSync())
          pw.Container(
            width: 48, height: 48,
            margin: const pw.EdgeInsets.only(bottom: 4),
            decoration: const pw.BoxDecoration(shape: pw.BoxShape.circle),
            child: pw.ClipOval(child: pw.Image(
                pw.MemoryImage(File(firma['logoYolu']!).readAsBytesSync()),
                fit: pw.BoxFit.cover)),
          ),
        pw.Text(firma['adi']!, textAlign: pw.TextAlign.center,
            style: pw.TextStyle(font: boldFont, fontSize: 12 * scale)),
        if (firma['adres']!.isNotEmpty)
          pw.Text(firma['adres']!, textAlign: pw.TextAlign.center,
              style: pw.TextStyle(font: font, fontSize: 7 * scale)),
        if (firma['vergiDairesi']!.isNotEmpty || firma['vergiNo']!.isNotEmpty)
          pw.Text('VD: ${firma['vergiDairesi']}  VKN: ${firma['vergiNo']}',
              style: pw.TextStyle(font: font, fontSize: 7 * scale)),
        pw.SizedBox(height: 4),
        pw.Container(width: double.infinity, height: 0.5, color: PdfColors.black),
        pw.SizedBox(height: 4),
        _gibMuhru(font, boldFont, eArsivMi80, f.faturaTipi ?? 'Fatura'),
        pw.SizedBox(height: 4),
        pw.Text((f.faturaTipi ?? 'Fatura').toUpperCase(),
            style: pw.TextStyle(font: boldFont, fontSize: 11 * scale)),
        pw.Text('No: ${f.faturaNo ?? "-"}', style: pw.TextStyle(font: font, fontSize: 8 * scale)),
        pw.Text(fmt.format(f.duzenlenmeTarihi ?? f.tarih), style: pw.TextStyle(font: font, fontSize: 8 * scale)),
        if (f.eFaturaUuid != null)
          pw.Text('ETTN: ${f.eFaturaUuid}', style: pw.TextStyle(font: font, fontSize: 6 * scale)),
        if (f.odemeSekli != null)
          pw.Text('Ödeme Şekli: ${f.odemeSekli}', style: pw.TextStyle(font: font, fontSize: 6.5 * scale)),
        pw.SizedBox(height: 4),
        pw.Container(width: double.infinity, height: 0.5, color: PdfColors.black),
        pw.SizedBox(height: 4),
        pw.Align(alignment: pw.Alignment.centerLeft, child: pw.Text('SAYIN',
            style: pw.TextStyle(font: boldFont, fontSize: 7 * scale))),
        pw.Align(alignment: pw.Alignment.centerLeft, child: pw.Text(f.cariUnvan ?? '-',
            style: pw.TextStyle(font: boldFont, fontSize: 9 * scale))),
        if (f.cariAdres != null && f.cariAdres!.isNotEmpty)
          pw.Align(alignment: pw.Alignment.centerLeft, child: pw.Text(f.cariAdres!,
              style: pw.TextStyle(font: font, fontSize: 6.5 * scale))),
        pw.Align(alignment: pw.Alignment.centerLeft, child: pw.Text(
            'VD: ${f.cariVergiDairesi ?? "-"}  VKN/TC: ${f.cariVergiNo ?? "-"}',
            style: pw.TextStyle(font: font, fontSize: 6.5 * scale))),
        pw.SizedBox(height: 4),
        pw.Container(width: double.infinity, height: 0.5, color: PdfColors.black),
        pw.SizedBox(height: 4),
        // Kalemler — kompakt
        ...f.detaylar.map((d) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 3),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(d.urunAdi, style: pw.TextStyle(font: font, fontSize: 8 * scale)),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Text(
                '${d.miktar.toStringAsFixed(d.miktar == d.miktar.roundToDouble() ? 0 : 2)} x '
                '${ParaUtils.formatla(d.birimFiyat)} (KDV %${d.kdvOrani.toStringAsFixed(0)})',
                style: pw.TextStyle(font: font, fontSize: 7 * scale, color: PdfColors.grey700)),
              pw.Text(ParaUtils.formatla(d.toplamTutar),
                  style: pw.TextStyle(font: boldFont, fontSize: 8 * scale)),
            ]),
          ]),
        )),
        pw.Container(width: double.infinity, height: 0.5, color: PdfColors.black),
        pw.SizedBox(height: 4),
        _termalToplamSatir('Ara Toplam', f.toplamAraToplam, font, boldFont, scale: scale),
        if (f.toplamIskonto > 0) _termalToplamSatir('İndirim', -f.toplamIskonto, font, boldFont, scale: scale),
        _termalToplamSatir('KDV', f.toplamKdv, font, boldFont, scale: scale),
        pw.SizedBox(height: 2),
        _termalToplamSatir('GENEL TOPLAM', f.genelToplam, font, boldFont, vurgu: true, scale: scale),
        pw.SizedBox(height: 6),
        pw.Text('Yalnız, ${tutariYaziyaCevir(f.genelToplam)}',
            textAlign: pw.TextAlign.center, style: pw.TextStyle(font: font, fontSize: 7 * scale)),
        pw.SizedBox(height: 8),
        if (firma['qrGoster'] == 'true')
          pw.BarcodeWidget(
            barcode: bc.Barcode.qrCode(),
            data: f.eFaturaUuid ?? f.faturaNo ?? 'MarketPlus',
            width: 80, height: 80,
          ),
        pw.SizedBox(height: 6),
        pw.Text('Bizi tercih ettiğiniz için teşekkür ederiz.',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(font: font, fontSize: 7 * scale, color: PdfColors.grey600)),
      ]),
    ));
    return doc.save();
  }

  pw.Widget _termalToplamSatir(String label, double val, pw.Font font, pw.Font boldFont,
      {bool vurgu = false, double scale = 1.0}) =>
    pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
      pw.Text(label, style: pw.TextStyle(font: vurgu ? boldFont : font, fontSize: (vurgu ? 9 : 7.5) * scale)),
      pw.Text('${ParaUtils.formatla(val)} TL',
          style: pw.TextStyle(font: vurgu ? boldFont : font, fontSize: (vurgu ? 9 : 7.5) * scale)),
    ]);


  Future<Uint8List> _pdfBytes() async {
      final f        = _fatura!;
      final font     = await PdfGoogleFonts.robotoRegular();
      final boldFont = await PdfGoogleFonts.robotoBold();
      final pdf      = pw.Document();
      final fmt      = DateFormat('dd-MM-yyyy');
      final fmtSaat  = DateFormat('HH:mm:ss');
      final firma    = await _firmaBilgileri();

      final iadeMi   = (f.faturaTipi ?? '').toLowerCase().contains('iade') ||
                        (f.faturaTipi ?? '').toLowerCase().contains('ade');
      // VKN 10 hane → e-Fatura (kurumsal alıcı), TC 11 hane → e-Arşiv (bireysel)
      // ÖNCEDEN BURADA AYNI YANLIŞ VARSAYIM VARDI (Cari kartındaki sahte
      // rozette bulup düzelttiğim sorunun aynısı): "VKN 10 hane = e-Fatura
      // mükellefi" TAHMİNİ kullanılıyordu. VKN sahibi olmak, GİB'e KAYITLI
      // olmak anlamına gelmez — bu, GERÇEK basılan/PDF belgede yanlış
      // belge türü ("e-Fatura" yazıp aslında e-Arşiv olması gerekirken,
      // ya da tersi) yazılmasına yol açabilirdi, ki bu resmi bir belgede
      // ciddi bir hatadır. Artık ÖNCELİKLE GİB'de gerçekten sorgulanmış
      // sonuç (`cariMukellefDurumu`) kullanılıyor; hiç sorgulanmamışsa
      // (null) VKN uzunluğu SADECE YEDEK tahmin olarak kullanılıyor —
      // ekranda da bu durumda kullanıcı Cari Listesi'nden "Sorgula"
      // yapmaya teşvik ediliyor (bkz. fatura detay ekranındaki uyarı).
      final vkn      = f.cariVergiNo ?? '';
      final eArsivMi = f.cariMukellefDurumu != null
          ? f.cariMukellefDurumu == 'earsiv'
          : vkn.length == 11;
      final belgeAdi = iadeMi
          ? 'İade Faturası'
          : (eArsivMi ? 'e-Arşiv Fatura' : 'e-Fatura');

      // KDV oranlarına göre grupla (Hesaplanan KDV (%X))
      final kdvGruplari = <double, double>{}; // oran -> tutar
      for (final d in f.detaylar) {
        kdvGruplari[d.kdvOrani] = (kdvGruplari[d.kdvOrani] ?? 0) + d.kdvTutari;
      }
      final vergilerHaric = f.toplamAraToplam - f.toplamIskonto;

      // ÖNCEDEN "kdv_musaf" ve "tevkifat" ayarları (Ayarlar > Fatura
      // Ayarları'nda kaydediliyordu) HİÇBİR YERDE okunmuyordu — kullanıcı
      // bu anahtarları açsa bile faturada HİÇBİR etkisi olmuyordu. Artık
      // gerçekten faturaya yansıtılıyor.
      // ⚠️ ÖNEMLİ HUKUKİ NOT: Bu, sadece GÖRÜNÜM/PDF seviyesinde bir
      // düzeltmedir (fatura tutarları/veritabanı değişmiyor). Tevkifat
      // için GİB'in kesin kod listesinde onlarca farklı oran/sektör kodu
      // var (İnşaat, Temizlik, Güvenlik vb. hizmetlere göre değişir) —
      // gerçek GİB gönderiminde (e-Fatura XML) doğru tevkifat kodunun
      // kullanılması İÇİN MALİ MÜŞAVİRİNİZLE DOĞRULAMANIZI ÖNERİRİM.
      final prefsKdv = await SharedPreferences.getInstance();
      final kdvMuaf = prefsKdv.getBool('kdv_musaf') ?? false;
      final tevkifatVar = prefsKdv.getBool('tevkifat') ?? false;
      final tevkifatOrani = prefsKdv.getString('tevkifat_orani') ?? '';
      final scale = prefsKdv.getDouble('fatura_font_olcek') ?? 1.0;

      pdf.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (ctx) => [
          // ── Üst bilgi kutusu: Özelleştirme No / Senaryo / Tip / Fatura No / Tarih ──
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              if (firma['logoYolu']!.isNotEmpty && File(firma['logoYolu']!).existsSync()) ...[
                pw.Container(
                  width: 56, height: 56,
                  alignment: pw.Alignment.center,
                  decoration: pw.BoxDecoration(
                    shape: pw.BoxShape.circle,
                    border: pw.Border.all(width: 0.7, color: PdfColors.grey400),
                  ),
                  child: pw.ClipOval(
                    child: pw.Image(pw.MemoryImage(File(firma['logoYolu']!).readAsBytesSync()),
                        width: 54, height: 54, fit: pw.BoxFit.cover),
                  ),
                ),
                pw.SizedBox(width: 10),
              ],
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(firma['adi']!,
                  style: pw.TextStyle(font: boldFont, fontSize: 16 * scale)),
              if (firma['adres']!.isNotEmpty)
                pw.Text(firma['adres']!,
                    style: pw.TextStyle(font: font, fontSize: 8.5 * scale),
                    maxLines: 2),
              if (firma['vergiDairesi']!.isNotEmpty || firma['vergiNo']!.isNotEmpty)
                pw.Text('Vergi Dairesi: ${firma['vergiDairesi']} | VKN: ${firma['vergiNo']}',
                    style: pw.TextStyle(font: font, fontSize: 8.5 * scale)),
            ]),
            ]),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Text(belgeAdi.toUpperCase(),
                  style: pw.TextStyle(font: boldFont, fontSize: 14 * scale)),
              pw.SizedBox(height: 4),
              pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                if (firma['qrGoster'] == 'true') ...[
                  pw.BarcodeWidget(
                    barcode: bc.Barcode.qrCode(),
                    data: f.eFaturaUuid ?? f.faturaNo ?? 'MarketPlus',
                    width: 56, height: 56,
                  ),
                  pw.SizedBox(width: 6),
                ],
                _gibMuhru(font, boldFont, eArsivMi, belgeAdi),
                pw.SizedBox(width: 6),
                pw.Container(
                padding: const pw.EdgeInsets.all(6),
                decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  _pdfEtiket('Özelleştirme No', 'TR1.2.1', font, boldFont, scale: scale),
                  _pdfEtiket('Fatura Tipi', f.faturaTipi ?? belgeAdi, font, boldFont, scale: scale),
                  _pdfEtiket('Fatura Numarası', f.faturaNo ?? '-', font, boldFont, scale: scale),
                  _pdfEtiket('Düzenlenme Tarihi', fmt.format(f.duzenlenmeTarihi ?? f.tarih), font, boldFont, scale: scale),
                  _pdfEtiket('Düzenlenme Zamanı', fmtSaat.format(f.duzenlenmeTarihi ?? f.tarih), font, boldFont, scale: scale),
                  if (f.eFaturaUuid != null)
                    _pdfEtiket('ETTN', f.eFaturaUuid!, font, boldFont, scale: scale),
                ]),
              ),
              ]),
            ]),
          ]),
          pw.SizedBox(height: 14),
          // ── Toplamlar özeti (üstte, GİB formatına benzer) ──────────────
          pw.Align(alignment: pw.Alignment.centerRight,
            child: pw.Container(
              width: 220,
              padding: const pw.EdgeInsets.all(6),
              decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                _pdfTutarSatir('Ara Toplam', f.toplamAraToplam, font, boldFont, scale: scale),
                if (f.toplamIskonto > 0)
                  _pdfTutarSatir('Toplam İndirim', f.toplamIskonto, font, boldFont, scale: scale),
                _pdfTutarSatir('Vergiler Hariç Toplam', vergilerHaric, font, boldFont, scale: scale),
                if (kdvMuaf)
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 2),
                    child: pw.Text('KDV Muaf', style: pw.TextStyle(font: boldFont, fontSize: 8 * scale)),
                  )
                else ...[
                  for (final entry in kdvGruplari.entries)
                    if (entry.value > 0)
                      _pdfTutarSatir('Hesaplanan KDV (%${entry.key.toStringAsFixed(0)})',
                          entry.value, font, boldFont, scale: scale),
                  if (tevkifatVar && tevkifatOrani.isNotEmpty)
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 2),
                      child: pw.Text('Tevkifat Oranı: $tevkifatOrani',
                          style: pw.TextStyle(font: font, fontSize: 8 * scale)),
                    ),
                ],
                _pdfTutarSatir('Vergiler Dahil Toplam', f.genelToplam, font, boldFont, vurgu: true, scale: scale),
                _pdfTutarSatir('Ödenecek Toplam', f.genelToplam, font, boldFont, vurgu: true, scale: scale),
              ]),
            ),
          ),
          pw.SizedBox(height: 14),
          // ── SAYIN: Alıcı bilgileri ───────────────────────────────────────
          pw.Text('SAYIN', style: pw.TextStyle(font: boldFont, fontSize: 9 * scale)),
          pw.SizedBox(height: 2),
          pw.Text(f.cariUnvan ?? '-',
              style: pw.TextStyle(font: boldFont, fontSize: 11 * scale)),
          if (f.cariAdres != null && f.cariAdres!.isNotEmpty)
            pw.Text(f.cariAdres!, style: pw.TextStyle(font: font, fontSize: 9 * scale)),
          pw.Text(
            'Vergi Dairesi: ${f.cariVergiDairesi ?? "-"}'
            '${vkn.isEmpty ? "" : (eArsivMi ? " | TC Kimlik Numarası: $vkn" : " | Vergi Numarası: $vkn")}',
            style: pw.TextStyle(font: font, fontSize: 9 * scale)),
          pw.SizedBox(height: 12),
          // ── Kalemler tablosu ─────────────────────────────────────────────
          pw.Table(
            border: pw.TableBorder.all(width: 0.5),
            columnWidths: {
              0: const pw.FlexColumnWidth(0.5),
              1: const pw.FlexColumnWidth(3.2),
              2: const pw.FlexColumnWidth(0.8),
              3: const pw.FlexColumnWidth(0.9),
              4: const pw.FlexColumnWidth(1.2),
              5: const pw.FlexColumnWidth(1.1),
              6: const pw.FlexColumnWidth(1.1),
              7: const pw.FlexColumnWidth(0.9),
              8: const pw.FlexColumnWidth(1.2),
            },
            children: [
              pw.TableRow(
                decoration: pw.BoxDecoration(color: PdfColors.grey200),
                children: ['Sıra', 'Açıklama', 'Stok Kodu', 'Miktar', 'Birim Fiyat',
                            'Tutar', 'Net Tutar', 'KDV Oranı', 'Tutar']
                    .map((h) => pw.Padding(
                        padding: const pw.EdgeInsets.all(3),
                        child: pw.Text(h,
                            textAlign: pw.TextAlign.center,
                            style: pw.TextStyle(font: boldFont, fontSize: 8 * scale))))
                    .toList(),
              ),
              ...f.detaylar.asMap().entries.map((e) {
                final i = e.key + 1;
                final d = e.value;
                final netTutar = d.araToplam - d.iskontoTutari;
                return pw.TableRow(children: [
                  _pdfHucre('$i', font, align: pw.TextAlign.center, scale: scale),
                  _pdfHucre(d.urunAdi, font, scale: scale),
                  _pdfHucre(d.barkod ?? '', font, align: pw.TextAlign.center, scale: scale),
                  _pdfHucre('${d.miktar.toStringAsFixed(d.miktar == d.miktar.roundToDouble() ? 0 : 2)} Adet',
                      font, align: pw.TextAlign.center, scale: scale),
                  _pdfHucre(ParaUtils.formatla(d.birimFiyat), font, align: pw.TextAlign.right, scale: scale),
                  _pdfHucre(ParaUtils.formatla(d.araToplam), font, align: pw.TextAlign.right, scale: scale),
                  _pdfHucre(ParaUtils.formatla(netTutar), font, align: pw.TextAlign.right, scale: scale),
                  _pdfHucre('%${d.kdvOrani.toStringAsFixed(d.kdvOrani == d.kdvOrani.roundToDouble() ? 0 : 2)}',
                      font, align: pw.TextAlign.center, scale: scale),
                  _pdfHucre(ParaUtils.formatla(d.toplamTutar), font, align: pw.TextAlign.right, scale: scale),
                ]);
              }),
            ],
          ),
          pw.SizedBox(height: 14),
          // ── Yazıyla tutar ────────────────────────────────────────────────
          pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text('Not:', style: pw.TextStyle(font: boldFont, fontSize: 9 * scale)),
                  pw.Text('Yalniz, ' + tutariYaziyaCevir(f.genelToplam),
                      style: pw.TextStyle(font: font, fontSize: 9 * scale)),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    eArsivMi
                        ? "e-Arsiv izni kapsaminda elektronik ortamda iletilmistir."
                        : "Bu fatura 397 Sira No'lu VUK Genel Tebligi kapsaminda e-Fatura olarak duzenlenmistir.",
                    style: pw.TextStyle(font: font, fontSize: 8 * scale)),
                ]),
              ),
            ),
            if (firma['imzaGoster'] == 'true' && firma['imzaYolu']!.isNotEmpty
                && File(firma['imzaYolu']!).existsSync()) ...[
              pw.SizedBox(width: 10),
              pw.Container(
                width: 130, height: 70,
                padding: const pw.EdgeInsets.all(4),
                decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
                child: pw.Column(children: [
                  pw.Expanded(child: pw.Image(
                      pw.MemoryImage(File(firma['imzaYolu']!).readAsBytesSync()),
                      fit: pw.BoxFit.contain)),
                  pw.Text('Imza / Kase', style: pw.TextStyle(font: font, fontSize: 7 * scale)),
                ]),
              ),
            ],
          ]),
        ],
      ));

    return pdf.save();
  }

  /// GİB (Gelir İdaresi Başkanlığı) tarzı yuvarlak mühür — referans
  /// faturalardaki "T.C. Hazine ve Maliye Bakanlığı / Gelir İdaresi
  /// Başkanlığı" amblemine benzer, jenerik olarak üretilmiş bir rozet.
  /// Gerçek GİB logosu değildir (telif/lisans), ancak resmi belge
  /// görünümünü tamamlar.
  pw.Widget _gibMuhru(pw.Font font, pw.Font boldFont, bool eArsivMi, String belgeAdi) {
    return pw.Container(
      width: 64, height: 64,
      decoration: const pw.BoxDecoration(
        shape: pw.BoxShape.circle,
        border: pw.Border(
          top: pw.BorderSide(width: 1.2, color: PdfColors.red800),
          bottom: pw.BorderSide(width: 1.2, color: PdfColors.red800),
          left: pw.BorderSide(width: 1.2, color: PdfColors.red800),
          right: pw.BorderSide(width: 1.2, color: PdfColors.red800),
        ),
      ),
      padding: const pw.EdgeInsets.all(3),
      child: pw.Container(
        decoration: const pw.BoxDecoration(
          shape: pw.BoxShape.circle,
          border: pw.Border(
            top: pw.BorderSide(width: 0.5, color: PdfColors.red800),
            bottom: pw.BorderSide(width: 0.5, color: PdfColors.red800),
            left: pw.BorderSide(width: 0.5, color: PdfColors.red800),
            right: pw.BorderSide(width: 0.5, color: PdfColors.red800),
          ),
        ),
        alignment: pw.Alignment.center,
        padding: const pw.EdgeInsets.all(3),
        child: pw.Column(mainAxisAlignment: pw.MainAxisAlignment.center, children: [
          pw.Text('T.C.', style: pw.TextStyle(font: boldFont, fontSize: 7, color: PdfColors.red800)),
          pw.Text('HAZİNE ve MALİYE', style: pw.TextStyle(font: font, fontSize: 3.8, color: PdfColors.red800), textAlign: pw.TextAlign.center),
          pw.Text('BAKANLIĞI', style: pw.TextStyle(font: font, fontSize: 3.8, color: PdfColors.red800)),
          pw.SizedBox(height: 2),
          pw.Text('GELİR İDARESİ', style: pw.TextStyle(font: boldFont, fontSize: 4.2, color: PdfColors.red800)),
          pw.Text('BAŞKANLIĞI', style: pw.TextStyle(font: boldFont, fontSize: 4.2, color: PdfColors.red800)),
          pw.SizedBox(height: 2),
          pw.Text(eArsivMi ? 'e-ARŞİV' : 'e-FATURA',
              style: pw.TextStyle(font: boldFont, fontSize: 5, color: PdfColors.red800)),
        ]),
      ),
    );
  }

  pw.Widget _pdfHucre(String text, pw.Font font, {pw.TextAlign align = pw.TextAlign.left, double scale = 1.0}) =>
    pw.Padding(
      padding: const pw.EdgeInsets.all(3),
      child: pw.Text(text, textAlign: align,
          style: pw.TextStyle(font: font, fontSize: 8 * scale)));

  pw.Widget _pdfEtiket(String label, String deger, pw.Font font, pw.Font boldFont, {double scale = 1.0}) =>
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(mainAxisSize: pw.MainAxisSize.min, children: [
        pw.SizedBox(width: 110, child: pw.Text('$label:',
            style: pw.TextStyle(font: font, fontSize: 8 * scale))),
        pw.Text(deger, style: pw.TextStyle(font: boldFont, fontSize: 8 * scale)),
      ]),
    );

  pw.Widget _pdfTutarSatir(String label, double val, pw.Font font, pw.Font boldFont,
      {bool vurgu = false, double scale = 1.0}) =>
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text(label, style: pw.TextStyle(
            font: vurgu ? boldFont : font, fontSize: (vurgu ? 10 : 9) * scale)),
        pw.Text('${ParaUtils.formatla(val)} TL', style: pw.TextStyle(
            font: vurgu ? boldFont : font, fontSize: (vurgu ? 10 : 9) * scale)),
      ]),
    );
}
