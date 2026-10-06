// lib/servisler/excel_servisi_iade_gunsonu.dart
//
// excel_servisi.dart'ın parçası (part/part of) — günsonu ve iade Excel içe/dışa aktarım.
// Davranış BİREBİR aynı: ExcelServisi üzerine extension; private üyelere
// (_getCellValue vb.) aynı kütüphane olduğu için erişir.
part of 'excel_servisi.dart';

extension ExcelServisiIadeGunsonu on ExcelServisi {
  // ──────────────────────────────────────────────────────────────────────────
  // GÜNSONU Excel dışa al
  // Başlıklar: Barkod | Ürün Adı | Miktar | Birim | Kdv li fiyat | Kdv li tutar | İndirim | Kdv (%) | Net Tutar TL
  // DB: satislar + satis_kalem JOIN
  // ──────────────────────────────────────────────────────────────────────────
  Future<String> gunsonuExcelDisaAl(
      DateTime tarih, List<Map<String, dynamic>> kalemler) async {
    final excel = Excel.createExcel();
    final sheet = excel['Günsonu'];
    excel.delete('Sheet1');

    final basliklar = ['Barkod', 'Ürün Adı', 'Miktar', 'Birim',
        'Kdv li fiyat', 'Kdv li tutar', 'İndirim', 'Kdv (%)', 'Net Tutar TL'];
    final headerStyle = CellStyle(bold: true,
        backgroundColorHex: ExcelColor.fromHexString('#0D47A1'),
        fontColorHex: ExcelColor.fromHexString('#FFFFFF'));
    for (int i = 0; i < basliklar.length; i++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = TextCellValue(basliklar[i]);
      cell.cellStyle = headerStyle;
    }

    for (final k in kalemler) {
      final birimFiyat   = (k['birim_fiyat'] as num?)?.toDouble() ?? 0.0;
      final miktar       = (k['miktar'] as num?)?.toDouble() ?? 0.0;
      final kdvOran      = (k['kdv_oran'] as num?)?.toDouble() ?? 1.0;
      final iskonto      = (k['iskonto_tutar'] as num?)?.toDouble() ?? 0.0;
      final kdvliFiyat   = birimFiyat;
      final kdvliTutar   = birimFiyat * miktar;
      final netTutar     = (kdvliTutar - iskonto) / (1 + kdvOran / 100);
      sheet.appendRow([
        TextCellValue(excelIcinGuvenliMetin(k['barkod']?.toString())),
        TextCellValue(excelIcinGuvenliMetin(k['urun_adi']?.toString())),
        DoubleCellValue(miktar),
        TextCellValue(k['birim_adi']?.toString() ?? 'ADET'),
        DoubleCellValue(kdvliFiyat),
        DoubleCellValue(kdvliTutar),
        DoubleCellValue(iskonto),
        DoubleCellValue(kdvOran),
        DoubleCellValue(netTutar),
      ]);
    }

    final bytes = (await compute(_encodeExcelIsolate, excel))!;
    final dir   = await getTemporaryDirectory();
    final path  = dir.path + '/gunsonu_' + DateTime.now().millisecondsSinceEpoch.toString() + '.xlsx';
    await File(path).writeAsBytes(bytes);
    return path;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // İADE ALMA Excel dışa al
  // Başlıklar: Kod | Barkod | Ürün Adı | Ana Miktar | Ana birim | Miktar | Birim |
  //            Fiyat | Tutarı | Net Fiyat | Net Tutar | Kdv li fiyat | Kdv li tutar |
  //            Indirim (%) | İndirim | Kdv (%) | Kdv | Sorumluluk Merkezi | Kart Satış Fiyatı
  // ──────────────────────────────────────────────────────────────────────────
  Future<String> iadeExcelDisaAl(List<Map<String, dynamic>> iadeler) async {
    final excel = Excel.createExcel();
    final sheet = excel['İade Alma'];
    excel.delete('Sheet1');

    final basliklar = ['Kod', 'Barkod', 'Ürün Adı', 'Ana Miktar', 'Ana birim',
        'Miktar', 'Birim', 'Fiyat', 'Tutarı', 'Net Fiyat', 'Net Tutar',
        'Kdv li fiyat', 'Kdv li tutar', 'Indirim (%)', 'İndirim',
        'Kdv (%)', 'Kdv', 'Sorumluluk Merkezi', 'Kart Satış Fiyatı'];
    final headerStyle = CellStyle(bold: true,
        backgroundColorHex: ExcelColor.fromHexString('#B71C1C'),
        fontColorHex: ExcelColor.fromHexString('#FFFFFF'));
    for (int i = 0; i < basliklar.length; i++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = TextCellValue(basliklar[i]);
      cell.cellStyle = headerStyle;
    }

    for (final k in iadeler) {
      // Uygulamada birim_fiyat KDV DAHİLdir. Örnek dosyadaki gibi: Fiyat/Tutarı/
      // Net Fiyat/Net Tutar KDV HARİÇ, "Kdv li ..." sütunları KDV dahildir.
      final birimKdvli = (k['birim_fiyat'] as num?)?.toDouble() ?? 0.0;
      final miktar     = (k['miktar'] as num?)?.toDouble() ?? 0.0;
      final kdvOran    = (k['kdv_oran'] as num?)?.toDouble() ?? 0.0;
      final iskontoOr  = (k['iskonto_oran'] as num?)?.toDouble() ?? 0.0;
      final fiyat      = birimKdvli / (1 + kdvOran / 100);
      final tutar      = fiyat * miktar;
      final iskontoTut = tutar * iskontoOr / 100;
      final netFiyat   = fiyat * (1 - iskontoOr / 100);
      final netTutar   = netFiyat * miktar;
      final kdvliF     = birimKdvli * (1 - iskontoOr / 100);
      final kdvliT     = kdvliF * miktar;
      final kdvTutar   = kdvliT - netTutar;
      sheet.appendRow([
        TextCellValue(excelIcinGuvenliMetin(k['kod']?.toString() ?? k['barkod']?.toString())),
        TextCellValue(excelIcinGuvenliMetin(k['barkod']?.toString())),
        TextCellValue(excelIcinGuvenliMetin(k['urun_adi']?.toString())),
        DoubleCellValue(miktar),
        TextCellValue(k['birim_adi']?.toString() ?? 'ADET'),
        DoubleCellValue(miktar),
        TextCellValue(k['birim_adi']?.toString() ?? 'ADET'),
        DoubleCellValue(fiyat),
        DoubleCellValue(tutar),
        DoubleCellValue(netFiyat),
        DoubleCellValue(netTutar),
        DoubleCellValue(kdvliF),
        DoubleCellValue(kdvliT),
        DoubleCellValue(iskontoOr),
        DoubleCellValue(iskontoTut),
        DoubleCellValue(kdvOran),
        DoubleCellValue(kdvTutar),
        TextCellValue(''),
        DoubleCellValue((k['kart_satis_fiyati'] as num?)?.toDouble() ?? birimKdvli),
      ]);
    }

    final bytes = (await compute(_encodeExcelIsolate, excel))!;
    final dir   = await getTemporaryDirectory();
    final path  = dir.path + '/iade_alma_' + DateTime.now().millisecondsSinceEpoch.toString() + '.xlsx';
    await File(path).writeAsBytes(bytes);
    return path;
  }

  /// İADE ALMA Excel içe alma — başlıklar [iadeExcelDisaAl] / örnek "İADE
  /// ALMA.xlsx" ile birebir. Satırları okur, veritabanına DOKUNMAZ; her satır:
  /// {kod, barkod, urun_adi, miktar, birim_fiyat (KDV dahil, indirim sonrası),
  /// kdv_oran, satir}. Ek/eksik sütun sorun değildir; kod ve barkodu boş,
  /// miktarı 0 olan satırlar atlanır. birim_fiyat okunamazsa null döner
  /// (çağıran ürünün güncel fiyatını kullanır).
  Future<List<Map<String, dynamic>>> iadeExcelIceAl(Uint8List bytes) async {
    final excel = await compute(_decodeExcelIsolate, bytes);
    if (excel.tables.isEmpty) throw Exception('Excel dosyasında sayfa bulunamadı');
    final sheet = excel.tables[excel.tables.keys.first]!;
    if (sheet.rows.isEmpty) return [];

    final idx = <String, int>{};
    final baslik = sheet.rows.first;
    for (var i = 0; i < baslik.length; i++) {
      final b = _normalizeString(_getCellValue(baslik[i]));
      if (b.isNotEmpty) idx.putIfAbsent(b, () => i);
    }
    int? bul(List<String> adlar) {
      for (final a in adlar) {
        final i = idx[_normalizeString(a)];
        if (i != null) return i;
      }
      return null;
    }
    final kodI = bul(['Kod', 'Stok Kodu']);
    final barkodI = bul(['Barkod']);
    if (kodI == null && barkodI == null) {
      throw Exception('"Kod" veya "Barkod" sütunu bulunamadı');
    }
    final adI = bul(['Ürün Adı', 'Urun Adi']);
    final miktarI = bul(['Miktar', 'Ana Miktar']);
    final kdvliFiyatI = bul(['Kdv li fiyat']);
    final netFiyatI = bul(['Net Fiyat']);
    final fiyatI = bul(['Fiyat']);
    final iskontoI = bul(['Indirim (%)', 'İndirim (%)']);
    final iskontoTutarI = bul(['İndirim', 'Indirim']);
    final tutariI = bul(['Tutarı', 'Tutari']);
    final kdvI = bul(['Kdv (%)']);

    String metin(List<dynamic> r, int? i) =>
        (i != null && i < r.length) ? _getCellValue(r[i]) : '';
    double? sayi(List<dynamic> r, int? i) =>
        (i != null && i < r.length) ? _getCellDouble(r[i]) : null;

    final sonuc = <Map<String, dynamic>>[];
    for (var s = 1; s < sheet.rows.length; s++) {
      final r = sheet.rows[s];
      final kod = metin(r, kodI), barkod = metin(r, barkodI);
      if (kod.isEmpty && barkod.isEmpty) continue; // boş/toplam satırı
      final miktar = sayi(r, miktarI) ?? 0;
      if (miktar <= 0) continue;
      final kdv = sayi(r, kdvI) ?? 0;
      // İndirim %: sütun boşsa "İndirim" tutarı / "Tutarı"ndan türetilir.
      var isk = sayi(r, iskontoI) ?? 0;
      if (isk <= 0) {
        final it = sayi(r, iskontoTutarI), tt = sayi(r, tutariI);
        if (it != null && tt != null && tt > 0 && it > 0) isk = it / tt * 100;
      }
      final fiyat = iadeFiyatCoz(
        fiyat: sayi(r, fiyatI),
        netFiyat: sayi(r, netFiyatI),
        kdvliFiyat: sayi(r, kdvliFiyatI),
        kdvOran: kdv,
        iskontoOran: isk,
      );
      sonuc.add({
        'kod': kod,
        'barkod': barkod,
        'urun_adi': metin(r, adI),
        'miktar': miktar,
        // KDV dahil, İNDİRİM SONRASI birim fiyat (eski alan; geriye uyumlu)
        'birim_fiyat': fiyat?.indirimli,
        // KDV dahil, İNDİRİMSİZ birim fiyat + indirim oranı: iade ekranı
        // manuel akıştaki gibi brüt fiyat × (1 − indirim) ile kaydeder.
        'brut_fiyat': fiyat?.brut,
        'iskonto_oran': fiyat == null ? 0.0 : (isk > 0 && isk < 100 ? isk : 0.0),
        'kdv_oran': kdv,
        'satir': s + 1,
      });
    }
    return sonuc;
  }

  /// İade Excel satırındaki fiyat sütunlarını çözer — saf, test edilebilir.
  ///
  /// Kaynak programlara göre "Kdv li fiyat" indirimli de indirimsiz de
  /// gelebilir; bu yüzden sütunlar BİRBİRİYLE karşılaştırılarak hangisinin
  /// indirim içerdiği anlaşılır. Dönüş: [brut] KDV dahil indirimsiz birim
  /// fiyat, [indirimli] KDV dahil indirim sonrası birim fiyat. Hiç fiyat
  /// yoksa null (çağıran ürün kartı fiyatını kullanır).
  static ({double brut, double indirimli})? iadeFiyatCoz({
    double? fiyat,
    double? netFiyat,
    double? kdvliFiyat,
    required double kdvOran,
    required double iskontoOran,
  }) {
    final c = 1 + kdvOran / 100;
    final isk = (iskontoOran > 0 && iskontoOran < 100) ? iskontoOran : 0.0;
    final k = 1 - isk / 100;
    bool yakin(double? a, double? b) =>
        a != null && b != null && (a - b).abs() <= 0.02 + b.abs() * 0.001;

    if (isk == 0) {
      // İndirim yok: eski davranış (Kdv li fiyat → Net Fiyat → Fiyat).
      final b = kdvliFiyat ?? (netFiyat != null ? netFiyat * c : null) ??
          (fiyat != null ? fiyat * c : null);
      return b == null ? null : (brut: b, indirimli: b);
    }

    double? brut;
    if (fiyat != null) {
      // "Fiyat" indirimsizdir; Net Fiyat'la aynıysa Fiyat zaten indirimli gelmiştir.
      brut = (netFiyat != null && yakin(netFiyat, fiyat))
          ? fiyat * c / k
          : fiyat * c;
    } else if (kdvliFiyat != null && netFiyat != null) {
      // Kdv li fiyat, Net Fiyat'ın KDV'lisiyle aynıysa indirimlidir → brüte çevir.
      brut = yakin(kdvliFiyat, netFiyat * c) ? kdvliFiyat / k : kdvliFiyat;
    } else if (kdvliFiyat != null) {
      // Tek ipucu: yazılan fiyat ödenecek fiyat kabul edilir (çifte indirim yok).
      brut = kdvliFiyat / k;
    } else if (netFiyat != null) {
      brut = netFiyat * c / k;
    }
    if (brut == null) return null;
    return (brut: brut, indirimli: brut * k);
  }
}
