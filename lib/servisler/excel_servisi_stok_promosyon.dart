// lib/servisler/excel_servisi_stok_promosyon.dart
//
// excel_servisi.dart'ın parçası (part/part of) — satış/iade listesi dışa aktarım, stok sayım ve promosyon Excel.
// Davranış BİREBİR aynı: ExcelServisi üzerine extension; private üyelere
// (_getCellValue vb.) aynı kütüphane olduğu için erişir.
part of 'excel_servisi.dart';

extension ExcelServisiStokPromosyon on ExcelServisi {
  Future<String> satislariExcelEAktar(List<SatisModel> satislar) async {
    final excel = Excel.createExcel();
    final sheet = excel['Satışlar'];
    excel.delete('Sheet1');
    sheet.appendRow(['Fiş No', 'Tarih', 'Müşteri', 'Toplam'].map((b) => TextCellValue(b)).toList());
    for (final s in satislar) {
      sheet.appendRow([
        TextCellValue(s.fisNo ?? ''),
        TextCellValue(s.tarih.toIso8601String()),
        TextCellValue(excelIcinGuvenliMetin(s.cariAdi ?? 'Perakende')),
        DoubleCellValue(s.genelToplam),
      ]);
    }
    final dir = await getApplicationDocumentsDirectory();
    final yol = '${dir.path}/satislar_${DateTime.now().millisecondsSinceEpoch}.xlsx';
    final bytes = await compute(_encodeExcelIsolate, excel);
    if (bytes != null) {
      await File(yol).writeAsBytes(bytes);
      return yol;
    }
    throw Exception('Excel encode hatası');
  }

  Future<String> iadelerExcelEAktar(List<Map<String, dynamic>> iadeler) async {
    final excel = Excel.createExcel();
    final sheet = excel['İadeler'];
    excel.delete('Sheet1');
    sheet.appendRow(['Tarih', 'Ürün', 'Miktar', 'Toplam'].map((b) => TextCellValue(b)).toList());
    for (final i in iadeler) {
      sheet.appendRow([
        TextCellValue(i['tarih']?.toString() ?? ''),
        TextCellValue(excelIcinGuvenliMetin(i['urun_adi']?.toString())),
        DoubleCellValue((i['miktar'] as num?)?.toDouble() ?? 0),
        DoubleCellValue((i['toplam_tutar'] as num?)?.toDouble() ?? 0),
      ]);
    }
    final dir = await getApplicationDocumentsDirectory();
    final yol = '${dir.path}/iadeler_${DateTime.now().millisecondsSinceEpoch}.xlsx';
    // bkz. dosya başındaki not (FAZ 5) — encode() UI thread'i donduran
    // senkron bir adım, isolate'e taşınıyor.
    final bytes = await compute(_encodeExcelIsolate, excel);
    if (bytes != null) {
      await File(yol).writeAsBytes(bytes);
      return yol;
    }
    throw Exception('Excel encode hatası');
  }

  Future<void> paylasExcel(String yol) async =>
      DosyaPaylasim.paylas(ShareParams(files: [XFile(yol)], text: 'BarkoPro Excel'));


  // ──────────────────────────────────────────────────────────────────────────
  // STOK SAYIM Excel içe/dışa al
  // Başlıklar: Kod | UrunAdi | Ana Miktar | Stok | Fark | DepoAdi
  // DB eşleştirme: Kod=urunler.barkod (önce) veya urunler.kod
  // ──────────────────────────────────────────────────────────────────────────
  // Excel'i okuyup sayım listesi olarak döndürür (stoku GÜNCELLEMEZ)
  Future<List<Map<String, dynamic>>> stokSayimListesiIceAl(Uint8List bytes) async {
    final excel = await compute(_decodeExcelIsolate, bytes);
    final sheet = excel.sheets.values.first;
    if (sheet.rows.isEmpty) return [];

    final headerList = sheet.rows.first.map((c) => c?.value?.toString().trim() ?? '').toList();
    final Map<String, int> kolonlar = {};
    for (int i = 0; i < headerList.length; i++) {
      final h = headerList[i];
      if (h.isNotEmpty) { kolonlar[h] = i; kolonlar[h.toLowerCase()] = i; }
    }
    final kodIdx    = _findColumn(kolonlar, 'stokKod');
    final miktarIdx = _findColumn(kolonlar, 'anaMiktar');

    final db = await Veritabani().db;
    final liste = <Map<String, dynamic>>[];

    for (int i = 1; i < sheet.rows.length; i++) {
      final row = sheet.rows[i];
      if (row.every((c) => c?.value == null)) continue;
      try {
        final kod    = kodIdx != -1 ? _getCellValue(row[kodIdx]) : '';
        final miktar = miktarIdx != -1 ? _getCellDouble(row[miktarIdx]) ?? 0.0 : 0.0;
        if (kod.isEmpty) continue;
        // 🔴 Kullanıcı bulgusu: ürünün alternatif barkodları (`barkodlar`
        // — virgülle ayrılmış) burada da hiç eşleştirilmiyordu (bkz.
        // UrunDeposu.ara()/barkodlaGetir() üzerindeki aynı düzeltme
        // notu). Burası TAM/kesin bir kod eşleştirmesi olduğundan
        // (metin arama kutusu değil), barkodlaGetir()'deki AYNI sıkı
        // virgül-sınırlı desen kullanıldı — serbest LIKE '%kod%' yanlış
        // pozitif üretebilirdi (ör. "12" kodu "5123" içinde eşleşirdi).
        final rows = await db.rawQuery(
          "SELECT id, urun_adi, birim_adi FROM urunler"
          " WHERE (barkod=? OR (',' || barkodlar || ',') LIKE ? OR kod=?)"
          "   AND is_deleted=0 LIMIT 1",
          [kod, '%,$kod,%', kod]);
        if (rows.isNotEmpty) {
          liste.add({'urun_id': rows.first['id'], 'miktar': miktar,
            'urun_adi': rows.first['urun_adi'], 'birim_adi': rows.first['birim_adi']});
        }
      } catch (e) { /* ignore */ }
    }
    return liste;
  }

  Future<Map<String, dynamic>> stokSayimExcelIceAl(Uint8List bytes) async {
    final excel = await compute(_decodeExcelIsolate, bytes);
    final sheet = excel.sheets.values.first;
    if (sheet.rows.isEmpty) return {'basarili': 0, 'hata': 0, 'hatalar': <String>[]};

    final headerList = sheet.rows.first.map((c) => c?.value?.toString().trim() ?? '').toList();
    final Map<String, int> kolonlar = {};
    for (int i = 0; i < headerList.length; i++) {
      final h = headerList[i];
      if (h.isNotEmpty) {
        kolonlar[h] = i;
        kolonlar[h.toLowerCase()] = i;
      }
    }
    final kodIdx      = _findColumn(kolonlar, 'stokKod');
    final miktarIdx   = _findColumn(kolonlar, 'anaMiktar');

    final db = await Veritabani().db;
    int basarili = 0, hata = 0;
    final hatalar = <String>[];

    for (int i = 1; i < sheet.rows.length; i++) {
      final row = sheet.rows[i];
      if (row.every((c) => c?.value == null)) continue;
      try {
        final kodCell    = (kodIdx != -1 && kodIdx < row.length) ? row[kodIdx] : null;
        final miktarCell = (miktarIdx != -1 && miktarIdx < row.length) ? row[miktarIdx] : null;
        final kod    = _getCellValue(kodCell);
        final miktar = _getCellDouble(miktarCell) ?? 0.0;
        if (kod.isEmpty) continue;
        // 🔴 Derin analizde bulundu: negatif bir sayım miktarı (yazım
        // hatası, bozuk export) hiç kontrol edilmeden doğrudan
        // urunler.stok'a yazılıyordu — fiziksel bir sayımda negatif
        // miktar anlamsız olduğu için satır (satisFiyat'taki gibi)
        // reddediliyor, sessizce 0'a çekilmiyor.
        if (miktar < 0) {
          hata++;
          hatalar.add('$kod: negatif miktar ($miktar) — atlandı');
          continue;
        }

        // Önce barkod ile bul, yoksa alternatif barkodlar (`barkodlar`)
        // ile, yoksa kod ile — bkz. yukarıdaki (stokSayimExcelDisaAl)
        // aynı düzeltme notu.
        final rows = await db.rawQuery(
          "SELECT id, stok FROM urunler"
          " WHERE (barkod=? OR (',' || barkodlar || ',') LIKE ? OR kod=?)"
          "   AND is_deleted=0 LIMIT 1",
          [kod, '%,$kod,%', kod],
        );
        if (rows.isNotEmpty) {
          // ÖNCEDEN BURADA stok_hareket HİÇ OLUŞTURULMUYORDU — Excel'den
          // toplu stok güncellemesi tamamen görünmez, izlenemeyen bir
          // değişiklikti; stok mutabakat sistemi bu değişikliği asla
          // göremezdi. Artık her satır için doğru bir hareket kaydı
          // oluşturuluyor.
          final urunId = rows.first['id'] as int;
          final onceki = (rows.first['stok'] as num).toDouble();
          final now = DateTime.now().toIso8601String();
          await db.update('urunler', {'stok': miktar, 'last_updated': now},
              where: 'id=?', whereArgs: [urunId]);
          if (onceki != miktar) {
            final hareketGid = const Uuid().v4();
            await db.insert('stok_hareket', {
              'global_id': hareketGid,
              'urun_id': urunId,
              'hareket_turu': 'Excel Toplu Güncelleme',
              'miktar': (miktar - onceki).abs(),
              'onceki_stok': onceki,
              'sonraki_stok': miktar,
              'tarih': now,
              'last_updated': now,
              'referans_turu': 'excel_import',
              'aciklama': 'Excel\'den toplu stok güncelleme',
            });
            // 🔴 Derin analizde bulundu: bu toplu Excel içe aktarımı
            // (yüzlerce ürünü etkileyebilir) last_updated/global_id
            // atamıyordu, BulutManager hiç çağrılmıyordu.
            final hareketSatir = await db.query('stok_hareket', where: 'global_id = ?', whereArgs: [hareketGid], limit: 1);
            if (hareketSatir.isNotEmpty) {
              BulutManager().upsert('stok_hareket', Map<String, dynamic>.from(hareketSatir.first));
            }
          }
          final urunSatir = await db.query('urunler', where: 'id = ?', whereArgs: [urunId], limit: 1);
          if (urunSatir.isNotEmpty) {
            BulutManager().upsert('urunler', Map<String, dynamic>.from(urunSatir.first));
          }
          basarili++;
        } else {
          hata++;
          hatalar.add('Satır ${i+1}: $kod bulunamadı');
        }
      } catch (e) {
        hata++;
        hatalar.add('Satır ${i+1}: $e');
      }
    }
    return {'basarili': basarili, 'hata': hata, 'hatalar': hatalar};
  }

  Future<String> stokSayimExcelDisaAl(List<Map<String, dynamic>> stoklar) async {
    final excel = Excel.createExcel();
    final sheet = excel['Stok Sayım'];
    excel.delete('Sheet1');

    final basliklar = ['Kod', 'UrunAdi', 'Ana Miktar', 'Stok', 'Fark', 'DepoAdi'];
    final headerStyle = CellStyle(bold: true,
        backgroundColorHex: ExcelColor.fromHexString('#1A237E'),
        fontColorHex: ExcelColor.fromHexString('#FFFFFF'));
    for (int i = 0; i < basliklar.length; i++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = TextCellValue(basliklar[i]);
      cell.cellStyle = headerStyle;
    }

    for (final s in stoklar) {
      // Hem eski (ana_miktar, urun_adi) hem yeni (Ana Miktar, UrunAdi) key destekle
      final miktar = (s['Ana Miktar'] ?? s['ana_miktar'] as num?)?.toDouble() ?? 0.0;
      final stok   = (s['Stok'] ?? s['stok'] as num?)?.toDouble() ?? 0.0;
      final fark   = (s['Fark'] ?? s['fark'] as num?)?.toDouble() ?? (miktar - stok);
      final kod    = s['Kod']?.toString() ?? s['barkod']?.toString() ?? s['kod']?.toString() ?? '';
      final adi    = s['UrunAdi']?.toString() ?? s['urun_adi']?.toString() ?? '';
      final depo   = s['DepoAdi']?.toString() ?? 'Merkez Depo';
      sheet.appendRow([
        TextCellValue(excelIcinGuvenliMetin(kod)),
        TextCellValue(excelIcinGuvenliMetin(adi)),
        DoubleCellValue(miktar),
        DoubleCellValue(stok),
        DoubleCellValue(fark),
        TextCellValue(excelIcinGuvenliMetin(depo)),
      ]);
    }

    final bytes = (await compute(_encodeExcelIsolate, excel))!;
    final dir   = await getTemporaryDirectory();
    final path  = '${dir.path}/stok_sayim_${DateTime.now().millisecondsSinceEpoch}.xlsx';
    await File(path).writeAsBytes(bytes);
    return path;
  }


  // ──────────────────────────────────────────────────────────────────────────
  // PROMOSYON Excel içe/dışa al
  // Başlıklar: Stok Kodu | Ürün Adı | Miktar | Iskonto Oran | Kart Satış Fiyatı | Birim Fiyat | Promosyon Tutar | Üretici | Maliyet
  // DB: promosyonlar(urun_id, promosyon_adi, iskonto_oran, min_miktar, aktif)
  // ──────────────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> promosyonExcelIceAl(Uint8List bytes) async {
    final excel = await compute(_decodeExcelIsolate, bytes);
    final sheet = excel.sheets.values.first;
    if (sheet.rows.isEmpty) return {'basarili': 0, 'hata': 0, 'hatalar': <String>[]};

    final headerList = sheet.rows.first.map((c) => c?.value?.toString().trim() ?? '').toList();
    final Map<String, int> kolonlar = {};
    for (int i = 0; i < headerList.length; i++) {
      final h = headerList[i];
      if (h.isNotEmpty) {
        kolonlar[h] = i;
        kolonlar[h.toLowerCase()] = i;
      }
    }
    final kodIdx    = _findColumn(kolonlar, 'promKod');
    final adIdx     = _findColumn(kolonlar, 'urunAdi');
    final miktarIdx = _findColumn(kolonlar, 'minMiktar');
    final oranIdx   = _findColumn(kolonlar, 'iskontoOran');

    final db = await Veritabani().db;
    int basarili = 0, hata = 0;
    final hatalar = <String>[];

    for (int i = 1; i < sheet.rows.length; i++) {
      final row = sheet.rows[i];
      if (row.every((c) => c?.value == null)) continue;
      try {
        final kodCell    = (kodIdx != -1 && kodIdx < row.length) ? row[kodIdx] : null;
        final adCell     = (adIdx != -1 && adIdx < row.length) ? row[adIdx] : null;
        final miktarCell = (miktarIdx != -1 && miktarIdx < row.length) ? row[miktarIdx] : null;
        final oranCell   = (oranIdx != -1 && oranIdx < row.length) ? row[oranIdx] : null;
        final kod    = _getCellValue(kodCell);
        final ad     = _getCellValue(adCell).isNotEmpty ? _getCellValue(adCell) : 'Promosyon';
        final miktar = _getCellDouble(miktarCell) ?? 1.0;
        final oran   = _getCellDouble(oranCell) ?? 0.0;
        if (kod.isEmpty || oran <= 0) continue;

        // Ürünü bul — alternatif barkodlar (`barkodlar`) dahil, bkz.
        // stokSayimExcelDisaAl üzerindeki aynı düzeltme notu.
        final urunRows = await db.rawQuery(
          "SELECT id FROM urunler"
          " WHERE (barkod=? OR (',' || barkodlar || ',') LIKE ? OR kod=?)"
          "   AND is_deleted=0 LIMIT 1",
          [kod, '%,$kod,%', kod],
        );
        if (urunRows.isEmpty) {
          hata++;
          hatalar.add('Satır ${i+1}: $kod bulunamadı');
          continue;
        }
        final urunId = urunRows.first['id'] as int;

        // 🔴 DÜZELTME: Mevcut promosyon GERÇEK hard-delete ile
        // siliniyordu (tabloda zaten 'deleted_at' vardı, kullanılmıyordu)
        // ve yeni eklenen promosyon global_id/last_updated almıyordu,
        // BulutManager hiç çağrılmıyordu — toplu Excel promosyon
        // içe aktarımı (çok sayıda ürünü etkileyebilir) hiç
        // senkronize olmuyordu.
        final now = DateTime.now().toIso8601String();
        final eskiPromolar = await db.query('promosyonlar',
            where: 'urun_id=? AND deleted_at IS NULL', whereArgs: [urunId]);
        for (final eski in eskiPromolar) {
          await db.update('promosyonlar', {'deleted_at': now, 'last_updated': now},
              where: 'id = ?', whereArgs: [eski['id']]);
          final s = await db.query('promosyonlar', where: 'id = ?', whereArgs: [eski['id']], limit: 1);
          if (s.isNotEmpty) BulutManager().upsert('promosyonlar', Map<String, dynamic>.from(s.first));
        }
        final promoGid = const Uuid().v4();
        final promoId = await db.insert('promosyonlar', {
          'global_id':    promoGid,
          'urun_id':      urunId,
          'promosyon_adi': ad.isNotEmpty ? ad : 'Promosyon',
          'iskonto_oran': oran,
          'iskonto_tutar': 0,
          'min_miktar':   miktar,
          'aktif':        1,
          'last_updated': now,
        });
        final yeniSatir = await db.query('promosyonlar', where: 'id = ?', whereArgs: [promoId], limit: 1);
        if (yeniSatir.isNotEmpty) BulutManager().upsert('promosyonlar', Map<String, dynamic>.from(yeniSatir.first));
        basarili++;
      } catch (e) {
        hata++;
        hatalar.add('Satır ${i+1}: $e');
      }
    }
    return {'basarili': basarili, 'hata': hata, 'hatalar': hatalar};
  }

  Future<String> promosyonExcelDisaAl(List<Map<String, dynamic>> promosyonlar) async {
    final excel = Excel.createExcel();
    final sheet = excel['Promosyon'];
    excel.delete('Sheet1');

    final basliklar = ['Stok Kodu', 'Ürün Adı', 'Miktar', 'Iskonto Oran',
        'Kart Satış Fiyatı', 'Birim Fiyat', 'Promosyon Tutar', 'Üretici', 'Maliyet'];
    final headerStyle = CellStyle(bold: true,
        backgroundColorHex: ExcelColor.fromHexString('#880E4F'),
        fontColorHex: ExcelColor.fromHexString('#FFFFFF'));
    for (int i = 0; i < basliklar.length; i++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = TextCellValue(basliklar[i]);
      cell.cellStyle = headerStyle;
    }

    for (final p in promosyonlar) {
      final iskonto = (p['iskonto_oran'] as num?)?.toDouble() ?? 0.0;
      final satisFiyat = (p['satis_fiyati'] as num?)?.toDouble() ?? 0.0;
      final birimFiyat = satisFiyat * (1 - iskonto / 100);
      final minMiktar  = (p['min_miktar'] as num?)?.toDouble() ?? 1.0;
      sheet.appendRow([
        TextCellValue(excelIcinGuvenliMetin(p['barkod']?.toString() ?? p['urun_kodu']?.toString())),
        TextCellValue(excelIcinGuvenliMetin(p['urun_adi']?.toString())),
        DoubleCellValue(minMiktar),
        DoubleCellValue(iskonto),
        DoubleCellValue(satisFiyat),
        DoubleCellValue(birimFiyat),
        DoubleCellValue(birimFiyat * minMiktar),
        TextCellValue(''),
        DoubleCellValue((p['alis_fiyat'] as num?)?.toDouble() ?? 0.0),
      ]);
    }

    final bytes = (await compute(_encodeExcelIsolate, excel))!;
    final dir   = await getTemporaryDirectory();
    final path  = dir.path + '/promosyon_' + DateTime.now().millisecondsSinceEpoch.toString() + '.xlsx';
    await File(path).writeAsBytes(bytes);
    return path;
  }
}
