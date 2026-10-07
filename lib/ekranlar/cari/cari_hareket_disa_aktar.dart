// ignore_for_file: invalid_use_of_protected_member
// lib/ekranlar/cari/cari_hareket_disa_aktar.dart
//
// cari_hareket_ekrani.dart'ın parçası (part/part of) — Excel / CSV / PDF dışa aktarma.
// Davranış BİREBİR aynı: State üzerine extension (setState aynı State
// örneği üzerinde çağrılır; analizci yalnızca extension içinden "korumalı
// üye" uyarısı verir).
part of 'cari_hareket_ekrani.dart';

extension _CariHareketDisaAktar on _CariHareketEkraniState {
  Future<void> _exportExcel() async {
    if (_filtreli.isEmpty) {
      BildirimServisi.uyari(context, 'Veri yok');
      return;
    }
    try {
      final ex = Excel.createExcel();
      final sh = ex['Cari Hareketler'];
      ex.delete('Sheet1');
      sh.appendRow([
        TextCellValue('Tarih'),
        TextCellValue('Tip'),
        TextCellValue('Fiş No'),
        TextCellValue('Açıklama'),
        TextCellValue('Borç'),
        TextCellValue('Alacak'),
        TextCellValue('Bakiye')
      ]);
      double runBak = _ekstreBaslangic;
      for (final h in _filtreli.reversed.toList()) {
        runBak = ParaUtils.yuvarla(runBak + h.borc - h.alacak);
        sh.appendRow([
          TextCellValue(_fmtT.format(h.tarih)),
          TextCellValue(h.fisTipi),
          TextCellValue(excelIcinGuvenliMetin(h.fisNo)),
          TextCellValue(excelIcinGuvenliMetin(h.aciklama)),
          DoubleCellValue(h.borc),
          DoubleCellValue(h.alacak),
          DoubleCellValue(runBak),
        ]);
      }
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/${_cari?.unvan ?? 'cari'}_hareketler_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      File(path).writeAsBytesSync(ex.encode()!);
      await DosyaPaylasim.paylas(ShareParams(files: [XFile(path)],
          text: '${_cari?.unvan ?? ''} Hareketleri'));
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Excel hatası: $e');
    }
  }

  Future<void> _exportCSV() async {
    if (_filtreli.isEmpty) {
      BildirimServisi.uyari(context, 'Veri yok');
      return;
    }
    try {
      final buf = StringBuffer()..write('\uFEFF');
      buf.writeln('Tarih,Tip,Fiş No,Açıklama,Borç,Alacak,Bakiye');
      double runBak = _ekstreBaslangic;
      for (final h in _filtreli.reversed.toList()) {
        runBak = ParaUtils.yuvarla(runBak + h.borc - h.alacak);
        // 🔴 Derin denetimde bulundu (P2): _exportExcel() bu oturumda
        // excelIcinGuvenliMetin ile korunmuştu ama hemen altındaki
        // _exportCSV() atlanmıştı — CSV enjeksiyonu Excel'deki AYNI
        // risk sınıfı (bir hücre '='/'+'/'-'/'@' ile başlıyorsa CSV'yi
        // açan programda formül olarak çalıştırılabilir).
        final row = [
          _fmtT.format(h.tarih),
          h.fisTipi,
          excelIcinGuvenliMetin(h.fisNo),
          excelIcinGuvenliMetin(h.aciklama),
          h.borc.toStringAsFixed(2),
          h.alacak.toStringAsFixed(2),
          runBak.toStringAsFixed(2)
        ];
        buf.writeln(row.map((v) => v.contains(',') ? '"$v"' : v).join(','));
      }
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/${_cari?.unvan ?? 'cari'}_hareketler.csv';
      File(path).writeAsStringSync(buf.toString());
      await DosyaPaylasim.paylas(ShareParams(files: [XFile(path)], text: 'CSV'));
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'CSV hatası: $e');
    }
  }

  Future<void> _exportPDF() async {
    if (_filtreli.isEmpty) {
      BildirimServisi.uyari(context, 'Veri yok');
      return;
    }
    final font = await PdfFontServisi.normal();
    final boldFont = await PdfFontServisi.kalin();
    final pdf = pw.Document();
    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      build: (ctx) => [
        pw.Text('${_cari?.unvan ?? ''} — Cari Hareket Raporu',
            style: pw.TextStyle(font: boldFont, fontSize: 16)),
        pw.Text('Tarih: ${_fmt.format(DateTime.now())}',
            style:
                pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey)),
        pw.SizedBox(height: 8),
        pw.TableHelper.fromTextArray(
          headers: ['Tarih', 'Tip', 'Açıklama', 'Borç', 'Alacak', 'Bakiye'],
          headerStyle:
              pw.TextStyle(font: boldFont, color: PdfColors.white, fontSize: 9),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey700),
          cellStyle: pw.TextStyle(font: font, fontSize: 8),
          data: () {
            // Yürüyen bakiye devredenden başlar (tarih aralığı seçiliyse);
            // tür filtresinde yalnızca listelenenlerin kümülatifidir.
            // Filtre yokken başlangıç = cari bakiyesi − listenin neti (5000
            // kayıt tavanını aşan caride listeden önceki kısım).
            final baslangic = _ekstreBaslangic;
            double runBak = baslangic;
            final satirlar = <List<String>>[
              if (baslangic.abs() > 0.005)
                [
                  _tarihAralik != null ? _fmt.format(_tarihAralik!.start) : '',
                  'Devreden', 'Önceki dönem bakiyesi', '', '',
                  baslangic.toStringAsFixed(2),
                ],
            ];
            return satirlar..addAll(_filtreli.reversed.map((h) {
              runBak = ParaUtils.yuvarla(runBak + h.borc - h.alacak);
              return [
                _fmtT.format(h.tarih),
                h.fisTipi,
                h.aciklama,
                h.borc > 0 ? h.borc.toStringAsFixed(2) : '',
                h.alacak > 0 ? h.alacak.toStringAsFixed(2) : '',
                runBak.toStringAsFixed(2)
              ];
            }));
          }(),
        ),
        pw.SizedBox(height: 8),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text('Toplam Borç: ${_toplamBorc.toStringAsFixed(2)} ₺',
                style: pw.TextStyle(
                    font: boldFont, fontSize: 10, color: PdfColors.red)),
            pw.Text('Toplam Alacak: ${_toplamAlacak.toStringAsFixed(2)} ₺',
                style: pw.TextStyle(
                    font: boldFont, fontSize: 10, color: PdfColors.green)),
            if (_tarihAralik != null && !_turFiltreli)
              pw.Text('Devreden: ${_devreden.toStringAsFixed(2)} ₺',
                  style: pw.TextStyle(font: font, fontSize: 10)),
            pw.Text('${_turFiltreli ? 'Net' : 'Bakiye'}: ${_bakiye.toStringAsFixed(2)} ₺',
                style: pw.TextStyle(font: boldFont, fontSize: 11)),
          ]),
        ]),
      ],
    ));
    await Printing.layoutPdf(onLayout: (_) async => pdf.save());
  }
}
