// lib/servisler/excel_servisi_cari.dart
//
// excel_servisi.dart'ın parçası (part/part of) — cari Excel içe/dışa aktarım.
// Davranış BİREBİR aynı: ExcelServisi üzerine extension; private üyelere
// (_getCellValue vb.) aynı kütüphane olduğu için erişir.
part of 'excel_servisi.dart';

extension ExcelServisiCari on ExcelServisi {
  // ══════════════════════════════════════════════════════════════════════
  // CARİ EXCEL İÇE/DIŞA AKTARIM (kullanıcı isteği, 2026-09-21)
  //
  // Kullanıcının verdiği örnek dosyadaki (cariler.xlsx) başlıklarla
  // birebir eşleşecek şekilde: Cari kod, Ünvan, Adres, Telefon, Borç,
  // Alacak, Bakiye, Cari Türü. Cari kodu zaten kayıtlıysa GÜNCELLEME,
  // değilse YENİ KAYIT yapılır (cari_kodu UNIQUE COLLATE NOCASE).
  //
  // BAKİYE — bilinçli mimari karar: cari.bakiye asla doğrudan
  // yazılabilen bir alan DEĞİLDİR (bkz. CariDeposu.guncelle()'deki
  // "🔴 DÜZELTME (Madde 9)" notu — kanonik bakiye HER ZAMAN
  // cari_hareket toplamından bir trigger/SUM ile hesaplanır). Bu yüzden:
  //   - GÜNCELLENEN (zaten var olan) bir caride Borç/Alacak/Bakiye
  //     sütunları TAMAMEN YOK SAYILIR — bu cari sistemde ZATEN kendi
  //     gerçek hareket geçmişine sahip; eski bir dış-sistem export'unu
  //     tekrar uygulamak mükerrer/çelişkili bakiye üretirdi.
  //   - YENİ EKLENEN bir cari için, Borç/Alacak sütunlarından TEK BİR
  //     "Açılış Bakiyesi" cari_hareket satırı oluşturulur (borc/alacak
  //     aynen Excel'deki gibi) — bakiye bu satırdan doğal olarak
  //     (mevcut trigger/SUM mekanizmasıyla) hesaplanır. Borç/Alacak
  //     sütunları yoksa (sadece Bakiye verilmişse), pozitif bakiye
  //     borca, negatif bakiye alacağa çevrilir.
  // ══════════════════════════════════════════════════════════════════════

  /// Excel'deki ilk 6 satır içinde "Cari kod" başlığını arar — kullanıcının
  /// örnek dosyasında olduğu gibi başlıktan önce süs/başlık satırları
  /// (ör. "Cari listesi", "--") olsa bile doğru satırı bulur. Bulamazsa
  /// 0 (ilk satır) döner.
  int _cariBaslikSatiriBul(List<dynamic> rows) {
    final sinir = rows.length < 6 ? rows.length : 6;
    for (int r = 0; r < sinir; r++) {
      for (final cell in (rows[r] as List)) {
        if (_normalizeString(_getCellValue(cell)).contains('carikod')) return r;
      }
    }
    return 0;
  }

  /// Serbest metni ('Müsteri', 'musteri', 'Tedarikçi', 'Bayi' vb.) geçerli
  /// bir cari_tipi değerine ('Müşteri'|'Tedarikçi'|'Hem Müşteri Hem
  /// Tedarikçi') çevirir — cari.cari_tipi CHECK kısıtı bu üç değer
  /// dışında hiçbir şeyi kabul etmez. Belirsiz/boşsa 'Müşteri' varsayılan.
  String _cariTuruCoz(String ham) {
    final n = _normalizeString(ham);
    final musteriMi = n.contains('musteri') || n.contains('customer') || n.contains('alici');
    final tedarikciMi =
        n.contains('tedarik') || n.contains('supplier') || n.contains('vendor') || n.contains('satici');
    if (musteriMi && tedarikciMi) return 'Hem Müşteri Hem Tedarikçi';
    if (tedarikciMi) return 'Tedarikçi';
    return 'Müşteri';
  }

  /// [cariSatirlari]: CariDeposu.tumunuBorcAlacakAdresIle()'den — çağıran
  /// (UI) tarafın besleyeceği ham satırlar (diğer ...ExcelEAktar()
  /// fonksiyonlarıyla AYNI desen: bu servis DB'ye kendisi gitmez).
  Future<String> carileriExcelEAktar(List<Map<String, dynamic>> cariSatirlari) async {
    final excel = Excel.createExcel();
    final sheet = excel['Cari listesi'];
    excel.delete('Sheet1');

    sheet.appendRow([
      TextCellValue('Cari kod'), TextCellValue('Ünvan'), TextCellValue('Adres'),
      TextCellValue('Telefon'), TextCellValue('Borç'), TextCellValue('Alacak'),
      TextCellValue('Bakiye'), TextCellValue('Cari Türü'),
    ]);

    for (final c in cariSatirlari) {
      final borc = (c['toplam_borc'] as num?)?.toDouble() ?? 0.0;
      final alacak = (c['toplam_alacak'] as num?)?.toDouble() ?? 0.0;
      final bakiye = (c['bakiye'] as num?)?.toDouble() ?? (borc - alacak);
      sheet.appendRow([
        TextCellValue(excelIcinGuvenliMetin(c['cari_kodu']?.toString())),
        TextCellValue(excelIcinGuvenliMetin(c['unvan']?.toString())),
        TextCellValue(excelIcinGuvenliMetin(c['adres']?.toString())),
        TextCellValue(excelIcinGuvenliMetin(c['telefon']?.toString())),
        DoubleCellValue(borc),
        DoubleCellValue(alacak),
        DoubleCellValue(bakiye),
        TextCellValue(excelIcinGuvenliMetin(c['cari_tipi']?.toString())),
      ]);
    }

    final bytes = (await compute(_encodeExcelIsolate, excel))!;
    final dir  = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/cariler_${DateTime.now().millisecondsSinceEpoch}.xlsx';
    await File(path).writeAsBytes(bytes);
    return path;
  }

  Future<CariIceAktarSonuc> exceldenCarileriBytesIceriAl(Uint8List bytes) async {
    final excel = await compute(_decodeExcelIsolate, bytes);
    if (excel.tables.isEmpty) {
      throw Exception('Excel dosyasında sayfa bulunamadı');
    }
    final sheet = excel.tables[excel.tables.keys.first]!;
    if (sheet.rows.isEmpty) {
      return const CariIceAktarSonuc(
          eklenen: 0, guncellenen: 0, hatali: 0, hatalar: [], toplam: 0);
    }

    final baslikSatiri = _cariBaslikSatiriBul(sheet.rows);
    final headerRow = sheet.rows[baslikSatiri];
    final Map<String, int> kolonlar = {};
    for (int i = 0; i < headerRow.length; i++) {
      final baslik = _getCellValue(headerRow[i]);
      if (baslik.isNotEmpty) {
        kolonlar[baslik] = i;
        kolonlar[baslik.toLowerCase()] = i;
        kolonlar[_normalizeString(baslik)] = i;
      }
    }

    final kodIdx     = _findColumn(kolonlar, 'cariKodu');
    final unvanIdx   = _findColumn(kolonlar, 'cariUnvan');
    final adresIdx   = _findColumn(kolonlar, 'cariAdres');
    final telefonIdx = _findColumn(kolonlar, 'cariTelefon');
    final borcIdx    = _findColumn(kolonlar, 'cariBorc');
    final alacakIdx  = _findColumn(kolonlar, 'cariAlacak');
    final bakiyeIdx  = _findColumn(kolonlar, 'cariBakiye');
    final turuIdx    = _findColumn(kolonlar, 'cariTuru');

    if (kodIdx == -1) {
      throw Exception('"Cari kod" sütunu bulunamadı');
    }

    var eklenen = 0, guncellenen = 0, hata = 0, acilisYazilan = 0;
    final hatalar = <String>[];
    final cariDepo = CariDeposu();
    final adresDepo = CariAdresDeposu();

    for (int i = baslikSatiri + 1; i < sheet.rows.length; i++) {
      final row = sheet.rows[i];
      if (row.every((c) => c?.value == null)) continue;
      try {
        final kod = kodIdx < row.length ? _getCellValue(row[kodIdx]) : '';
        if (kod.isEmpty) continue;
        final unvan =
            unvanIdx != -1 && unvanIdx < row.length ? _getCellValue(row[unvanIdx]) : '';
        if (unvan.isEmpty) {
          hata++;
          hatalar.add('Satır ${i + 1} ($kod): Ünvan boş — atlandı');
          continue;
        }
        final adres =
            adresIdx != -1 && adresIdx < row.length ? _getCellValue(row[adresIdx]) : '';
        final telefon = telefonIdx != -1 && telefonIdx < row.length
            ? _getCellValue(row[telefonIdx])
            : '';
        final turuHam =
            turuIdx != -1 && turuIdx < row.length ? _getCellValue(row[turuIdx]) : '';
        final cariTipi = _cariTuruCoz(turuHam);

        var borc = borcIdx != -1 && borcIdx < row.length
            ? (_getCellDouble(row[borcIdx]) ?? 0.0)
            : 0.0;
        var alacak = alacakIdx != -1 && alacakIdx < row.length
            ? (_getCellDouble(row[alacakIdx]) ?? 0.0)
            : 0.0;
        if (borc <= 0.005 && alacak <= 0.005 && bakiyeIdx != -1 && bakiyeIdx < row.length) {
          final bakiye = _getCellDouble(row[bakiyeIdx]) ?? 0.0;
          if (bakiye > 0) {
            borc = bakiye;
          } else if (bakiye < 0) {
            alacak = -bakiye;
          }
        }

        final mevcut = await cariDepo.kodlaGetir(kod);
        if (mevcut != null) {
          // Zaten kayıtlı — sadece profil bilgileri güncellenir, BAKİYEYE
          // dokunulmaz (bkz. dosya başındaki mimari karar notu).
          await cariDepo.guncelle(mevcut.copyWith(
            unvan: unvan,
            telefon: telefon.isEmpty ? null : telefon,
            cariTipi: cariTipi,
          ));
          if (adres.isNotEmpty) {
            await adresDepo.varsayilanAdresKaydet(cariId: mevcut.id!, adres: adres);
          }
          guncellenen++;
        } else {
          // Kod yeni ama aynı unvanlı cari zaten var → büyük olasılıkla aynı
          // Excel/cari ikinci kez aktarılıyor (kod yazımı farklı ya da bulut
          // verisi henüz çekilmedi). İkinci kayıt + ikinci açılış bakiyesi
          // yaratmak yerine atla ve kullanıcıya bildir.
          final ayniUnvanli = await cariDepo.unvanlaGetir(unvan);
          if (ayniUnvanli != null) {
            hata++;
            hatalar.add('Satır ${i + 1} ($kod): "$unvan" zaten ${ayniUnvanli.cariKodu} '
                'koduyla kayıtlı — atlandı. Önce "Buluttan Al" yapıp tekrar deneyin.');
            continue;
          }
          final yeniId = await cariDepo.ekle(CariModel(
            cariKodu: kod,
            unvan: unvan,
            cariTipi: cariTipi,
            telefon: telefon.isEmpty ? null : telefon,
          ));
          if (adres.isNotEmpty) {
            await adresDepo.varsayilanAdresKaydet(cariId: yeniId, adres: adres);
          }
          if (borc > 0.005 || alacak > 0.005) {
            await cariDepo.hareketEkle(CariHareketModel(
              cariId: yeniId,
              tarih: DateTime.now(),
              fisTipi: 'Açılış',
              aciklama: 'Açılış Bakiyesi (Excel içe aktarım)',
              borc: borc,
              alacak: alacak,
              odemeTuru: 'Açılış',
            ));
            acilisYazilan++;
          }
          eklenen++;
        }
      } catch (e) {
        hata++;
        hatalar.add('Satır ${i + 1}: $e');
      }
    }

    return CariIceAktarSonuc(
      eklenen: eklenen,
      guncellenen: guncellenen,
      hatali: hata,
      hatalar: hatalar,
      toplam: sheet.rows.length - baslikSatiri - 1,
      acilisBakiyesiYazilan: acilisYazilan,
    );
  }
}
