// lib/servisler/excel_servisi.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart' hide Border;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../modeller/urun_model.dart';
import '../modeller/satis_model.dart';
import '../depolar/urun_deposu.dart';
import 'excel_urun_birlestirici.dart';
import '../servisler/bulut/bulut_manager.dart';
import '../veri/database/veritabani.dart';
import 'package:uuid/uuid.dart';
import '../cekirdek/utils/excel_guvenlik_utils.dart';

class IceriAktarSonuc {
  final int eklenen;
  final int guncellenen;
  final int hatali;
  final List<String> hatalar;
  final int toplam;
  final int indirimliKaydedilen; // otomatikIndirim=true kaydedilen ürün sayısı

  const IceriAktarSonuc({
    required this.eklenen,
    required this.guncellenen,
    required this.hatali,
    required this.hatalar,
    required this.toplam,
    this.indirimliKaydedilen = 0,
  });

  int get basarili => eklenen + guncellenen;
}

class ExcelServisi {
  static final ExcelServisi _instance = ExcelServisi._internal();
  factory ExcelServisi() => _instance;
  ExcelServisi._internal();

  static final Map<String, List<String>> BASLIK_ESLEME = {
    'barkod': ['Barkod', 'barkod', 'BARKOD', 'Barkod No', 'Barcode'],
    'kod': ['Kod', 'KOD', 'Ürün Kodu', 'Urun Kodu', 'Product Code'],
    'urunAdi': ['Ürün Adı', 'Urun Adi', 'ÜRÜN ADI', 'Product Name', 'Ürün'],
    'alisFiyat': ['Alış fiyat', 'Alis fiyat', 'Alış Fiyatı', 'Cost'],
    'alisFiyatKdvDahil': ['Alış fiyat kdv dahil', 'Alış KDV Dahil', 'Alis KDV Dahil', 'Alış (KDV Dahil)', 'Alış KDVli', 'Alış Fiyatı KDV Dahil'],
    'satisFiyati': ['Satış fiyatı', 'Satış Fiyatı', 'Satis fiyati', 'SATIŞ FİYATI', 'Satış Fiyat TL', 'Price', 'Fiyat'],
    'birimAdi': ['Birim Adı', 'Birim Adi', 'Unit', 'Birim'],
    'stok': ['Stok', 'STOK', 'Stock', 'Quantity', 'Miktar'],
    'kdvOran': ['KDV Oran', 'Kdv Oran', 'KDV', 'Tax Rate', 'VAT', 'Alış KDV%', 'Alış KDV Oran'],
    'anaGrup': ['Ana Grup', 'ANA GRUP', 'Kategori', 'Category', 'Grup'],
    'aktif': ['Aktif', 'AKTİF', 'Active', 'Durum', 'Status'],
    'marka': ['Marka', 'Brand', 'Marka Adı'],
    'indirimOrani': ['Indirim Oranı', 'İndirim Oranı', 'İndirim Oranı %', 'Indirim Oranı %', 'Indirim %', 'İndirim %', 'Discount Rate'],
    'indirimliFiyat': ['İndirimli Fiyatı', 'Indirimli Fiyat', 'İndirimli Fiyat', 'İnd. Fiyat', 'Discount Price'],
    'eskiFiyat': ['Eski Fiyat', 'Eski fiyat'],
    'eskiFiyatTarih': ['Eski Fiyat Tarih', 'Eski fiyat tarih'],
    'promosyonGrup': ['Promosyon Grup', 'Promosyon grup'],
    'promosyonAktif': ['Promosyon Aktif', 'Promosyon aktif'],
    'receteKatsayi': ['Reçete Katsayı', 'Recete Katsayi'],
    'lotAciklama': ['Lot Açıklama', 'Lot Aciklama'],
    'hacim': ['Hacim'],
    'evrakKontrolAktif': ['Evrak Kontrolü Aktif', 'Evrak Kontrol Aktif'],
    'netAlisFiyat': ['Net Alış Fiyat', 'Net Alis Fiyat'],
    'stokKod':       ['Kod', 'Stok Kodu', 'Barkod', 'Ürün Kodu'],
    'anaMiktar':     ['Ana Miktar', 'Sayılan Miktar', 'Miktar'],
    'depoAdi':       ['DepoAdi', 'Depo Adı', 'Depo'],
    'alan1': ['Alan1', 'Alan 1', 'Marka Kodu', 'Marka_Kodu'],
    'promKod':       ['Stok Kodu', 'Kod', 'Barkod'],
    'minMiktar':     ['Miktar', 'Min Miktar', 'Minimum Miktar'],
    'iskontoOran':   ['Iskonto Oran', 'İskonto Oran', 'İndirim Oranı'],
    'birimFiyat':    ['Birim Fiyat', 'Fiyat'],
  };

  String _normalizeString(String str) {
    return str.toLowerCase()
        .replaceAll('ı', 'i').replaceAll('ğ', 'g').replaceAll('ü', 'u')
        .replaceAll('ş', 's').replaceAll('ö', 'o').replaceAll('ç', 'c')
        .replaceAll(' ', '').replaceAll('-', '').replaceAll('_', '');
  }

  int _findColumn(Map<String, int> kolonlar, String alanAdi) {
    final alternatifler = BASLIK_ESLEME[alanAdi] ?? [alanAdi];
    
    for (final alt in alternatifler) {
      if (kolonlar.containsKey(alt)) return kolonlar[alt]!;
      if (kolonlar.containsKey(alt.toLowerCase())) return kolonlar[alt.toLowerCase()]!;
      
      final altNorm = _normalizeString(alt);
      for (final key in kolonlar.keys) {
        final keyNorm = _normalizeString(key);
        if (keyNorm == altNorm || keyNorm.contains(altNorm)) {
          return kolonlar[key]!;
        }
      }
    }
    return -1;
  }

  double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    
    String str = value.toString().trim();
    if (str.isEmpty || str == '-' || str == '') return null;
    
    str = str.replaceAll('₺', '').replaceAll('TL', '').replaceAll(' ', '');
    
    if (str.contains(',') && !str.contains('.')) {
      str = str.replaceAll(',', '.');
    } else if (str.contains(',') && str.contains('.')) {
      final parts = str.split(',');
      str = parts[0].replaceAll('.', '') + '.' + parts[1];
    }
    
    str = str.replaceAll(RegExp(r'[^0-9.-]'), '');
    if (str.isEmpty) return null;
    return double.tryParse(str);
  }

  bool _parseBoolean(dynamic value, {bool defaultValue = true}) {
    if (value == null) return defaultValue;
    final str = value.toString().toLowerCase().trim();
    if (str == 'doğru' || str == 'dogru' || str == 'true' || str == '1' || 
        str == 'evet' || str == 'aktif') return true;
    if (str == 'yanlış' || str == 'yanlis' || str == 'false' || str == '0' || 
        str == 'hayır' || str == 'pasif') return false;
    return defaultValue;
  }

  String _getCellValue(dynamic cell) {
    if (cell == null) return '';
    final val = cell.value;
    if (val == null) return '';
    if (val is String) return val.trim();
    if (val is num) return val.toString();
    return val.toString().trim();
  }

  double? _getCellDouble(dynamic cell) {
    final str = _getCellValue(cell);
    if (str.isEmpty) return null;
    return _parseDouble(str);
  }

  // ── DIŞA AKTAR ────────────────────────────────────────────────────────
  // Excel dışa verme — DByii ile aynı başlık sırası
  Future<String> urunleriExcelEAktar(List<UrunModel> urunler) async {
    final excel = Excel.createExcel();
    final sheet = excel['Ürünler'];
    excel.delete('Sheet1');

    // DByii başlık sırası (birebir aynı)
    final basliklar = [
      'Id', 'Kod', 'Barkod', 'Barkodlar', 'Ürün Adı', 'Alternatif ürün adı',
      'Birim Adı', 'Net Alış Fiyat', 'Alış fiyat', 'Alış fiyat kdv dahil',
      'Satış fiyatı', 'Stok', 'Stok değeri', 'Toplam Maliyet', 'Toplam Stok',
      'Toplam stok değeri', 'Alış KDV Oran', 'KDV Oran', 'Ana Grup', 'Alt Grup',
      'Aktif', 'Seri no takibi', 'Alan1', 'Alan2', 'Para Birimi',
      'Minimum Stok', 'Maximum Stok', 'Alan3', 'Alan4', 'Renk', 'Beden',
      'Şube', 'Üretici', 'Marka', 'Model', 'Raf numarası', 'Raf ömrü',
      'Plu numarası', 'Puan Oranı', 'Indirim Oranı', 'İndirimli Fiyatı',
      'Lot Takibi', 'Lot No', 'Son alım indirim oran', 'Muhasebe Kodu',
      'En', 'Boy', 'Yükseklik', 'Hacim', 'Ağırlık', 'Eski kodu',
      'Kart Tipi', 'Seri numarası', 'Otomatik Indirim', 'Güncelleme tarihi',
      'Kayıt tarihi', 'Resim yolu', 'Grup Sorumlusu', 'Menşei',
      'Barkod Ölçü Birimi', 'Kar oranı', 'Muafiyet Kodu', 'Resmi Bakiye',
      'Net Alış Vergiler Dahil', 'Fiyat Güncelleme Tarih',
      'Fiyat Güncelleyen Kullanıcı', 'Barkod Yazdırma Tarih',
      'Barkod Yazdıran Kullanıcı', 'Maliyet Güncelleme Tarih',
      'Maliyet Güncelleyen Kullanıcı', 'Maksimum Satır Miktarı',
      'Güncelleyen Kullanıcı', 'Kaydeden Kullanıcı', 'Son Kullanma Tarihi',
      'Evrak Kontrolü Aktif', 'Satış Fiyat TL', 'Lot Açıklama',
      'Eski Fiyat', 'Eski Fiyat Tarih', 'Promosyon Grup',
      'Reçete Katsayı', 'Promosyon Aktif',
    ];

    // Başlık satırı — kalın + mavi arka plan
    final headerStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#1A237E'),
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
    );
    for (int i = 0; i < basliklar.length; i++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = TextCellValue(basliklar[i]);
      cell.cellStyle = headerStyle;
    }

    for (final urun in urunler) {
      final stokDegeri = urun.stok * urun.alisFiyat;
      final karOrani   = urun.alisFiyat > 0
          ? ((urun.satisFiyati - urun.alisFiyat) / urun.alisFiyat * 100) : 0.0;

      sheet.appendRow([
        IntCellValue(urun.id ?? 0),
        TextCellValue(excelIcinGuvenliMetin(urun.kod)),
        TextCellValue(excelIcinGuvenliMetin(urun.barkod)),
        TextCellValue(excelIcinGuvenliMetin(urun.barkodlar)),
        TextCellValue(excelIcinGuvenliMetin(urun.urunAdi)),
        TextCellValue(excelIcinGuvenliMetin(urun.alternatifUrunAdi)),
        TextCellValue(urun.birimAdi),
        DoubleCellValue(urun.netAlisFiyat),
        DoubleCellValue(urun.alisFiyat),
        DoubleCellValue(urun.alisFiyatKdvDahil),
        DoubleCellValue(urun.satisFiyati),
        DoubleCellValue(urun.stok),
        DoubleCellValue(stokDegeri),
        DoubleCellValue(urun.toplamMaliyet),
        DoubleCellValue(urun.toplamStok),
        DoubleCellValue(urun.toplamStok * urun.alisFiyat),
        DoubleCellValue(urun.alisKdvOran.toDouble()),
        TextCellValue(urun.kdvOran),
        TextCellValue(excelIcinGuvenliMetin(urun.anaGrup)),
        TextCellValue(excelIcinGuvenliMetin(urun.altGrup)),
        TextCellValue(urun.aktif ? 'DOĞRU' : 'YANLIŞ'),
        TextCellValue(urun.seriNoTakibi ? 'DOĞRU' : 'YANLIŞ'),
        TextCellValue(excelIcinGuvenliMetin(urun.alan1)),
        TextCellValue(excelIcinGuvenliMetin(urun.alan2)),
        TextCellValue(urun.paraBirimi),
        DoubleCellValue(urun.minimumStok),
        DoubleCellValue(urun.maksimumStok),
        TextCellValue(excelIcinGuvenliMetin(urun.alan3)),
        TextCellValue(excelIcinGuvenliMetin(urun.alan4)),
        TextCellValue(''),  // Renk
        TextCellValue(''),  // Beden
        TextCellValue(''),  // Şube
        TextCellValue(''),  // Üretici
        TextCellValue(excelIcinGuvenliMetin(urun.marka)),
        TextCellValue(''),  // Model
        TextCellValue(''),  // Raf numarası
        TextCellValue(''),  // Raf ömrü
        TextCellValue(''),  // Plu numarası
        DoubleCellValue(urun.puanOrani),
        DoubleCellValue(urun.indirimOrani),
        DoubleCellValue(urun.indirimliFiyatKayitli),
        TextCellValue(urun.lotTakibi ? 'DOĞRU' : 'YANLIŞ'),
        TextCellValue(excelIcinGuvenliMetin(urun.lotNo)),
        DoubleCellValue(urun.sonAlimIndirimOran),
        TextCellValue(excelIcinGuvenliMetin(urun.muhasebeKodu)),
        DoubleCellValue(urun.en),
        DoubleCellValue(urun.boy),
        DoubleCellValue(urun.yukseklik),
        DoubleCellValue(urun.hacim),
        DoubleCellValue(urun.agirlik),
        TextCellValue(excelIcinGuvenliMetin(urun.eskiKodu)),
        TextCellValue(urun.kartTipi),
        TextCellValue(excelIcinGuvenliMetin(urun.seriNumarasi)),
        TextCellValue(urun.otomatikIndirim ? 'DOĞRU' : 'YANLIŞ'),
        TextCellValue(urun.guncellemeTarihi ?? ''),
        TextCellValue(urun.kayitTarihi ?? ''),
        TextCellValue(excelIcinGuvenliMetin(urun.resimYolu)),
        TextCellValue(''),  // Grup Sorumlusu
        TextCellValue(''),  // Menşei
        TextCellValue(''),  // Barkod Ölçü Birimi
        DoubleCellValue(karOrani.toDouble()),
        TextCellValue(excelIcinGuvenliMetin(urun.muafiyetKodu)),
        DoubleCellValue(urun.resmiBakiye ?? 0),
        DoubleCellValue(urun.alisFiyatKdvDahil),
        TextCellValue(urun.fiyatGuncellemeTarih ?? ''),
        TextCellValue(urun.fiyatGuncelleyenKullanici ?? ''),
        TextCellValue(urun.barkodYazdirmaTarih ?? ''),
        TextCellValue(urun.barkodYazdiranKullanici ?? ''),
        TextCellValue(urun.maliyetGuncellemeTarih ?? ''),
        TextCellValue(urun.maliyetGuncelleyenKullanici ?? ''),
        DoubleCellValue(0),  // Maksimum Satır Miktarı
        TextCellValue(urun.guncelleyenKullanici ?? ''),
        TextCellValue(urun.kaydedenKullanici ?? ''),
        TextCellValue(urun.sonKullanmaTarihi ?? ''),
        TextCellValue(urun.evrakKontrolAktif ? 'DOĞRU' : 'YANLIŞ'),
        DoubleCellValue(urun.satisFiyati),  // Satış Fiyat TL
        TextCellValue(excelIcinGuvenliMetin(urun.lotAciklama)),
        DoubleCellValue(urun.eskiFiyat),
        TextCellValue(urun.eskiFiyatTarih?.toIso8601String() ?? ''),
        TextCellValue(excelIcinGuvenliMetin(urun.promosyonGrup)),
        DoubleCellValue(urun.receteKatsayi),
        TextCellValue(urun.promosyonAktif ? 'DOĞRU' : 'YANLIŞ'),
      ]);
    }

    final dir = await getApplicationDocumentsDirectory();
    final yol = '${dir.path}/urunler_${DateTime.now().millisecondsSinceEpoch}.xlsx';
    final bytes = excel.encode();
    if (bytes != null) {
      await File(yol).writeAsBytes(bytes);
      return yol;
    }
    throw Exception('Excel encode hatası');
  }

  Future<String> urunleriBarkomatikExcelEAktar(List<UrunModel> urunler) async =>
      urunleriExcelEAktar(urunler);

  // ── İÇE AKTAR (CORE) - KDV HESAPLAMALI ─────────────────────────────────
  Future<IceriAktarSonuc> exceldenurunleriBytesIceriAl(
    List<int> bytes, {
    void Function(int islemde, int toplam)? onProgress,
  }) async {
    final excel = Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) {
      throw Exception('Excel dosyasında sayfa bulunamadı');
    }

    final sheet = excel.tables[excel.tables.keys.first]!;
    if (sheet.rows.length < 2) {
      throw Exception('Excel dosyası en az 2 satır içermeli (başlık + veri)');
    }

    // BAŞLIKLARI OKU
    final headerRow = sheet.rows.first;
    final Map<String, int> kolonlar = {};
    
    for (int i = 0; i < headerRow.length; i++) {
      final cell = headerRow[i];
      final baslik = _getCellValue(cell);
      if (baslik.isNotEmpty) {
        kolonlar[baslik] = i;
        kolonlar[baslik.toLowerCase()] = i;
        kolonlar[_normalizeString(baslik)] = i;
      }
    }

    // ZORUNLU ALANLARI BUL
    final barkodIndex = _findColumn(kolonlar, 'barkod');
    final kodIndex = _findColumn(kolonlar, 'kod');
    final urunAdiIndex = _findColumn(kolonlar, 'urunAdi');
    final satisFiyatIndex = _findColumn(kolonlar, 'satisFiyati');

    if (barkodIndex == -1 && kodIndex == -1) {
      throw Exception('"Barkod" veya "Kod" sütunu bulunamadı');
    }
    if (urunAdiIndex == -1) {
      throw Exception('"Ürün Adı" sütunu bulunamadı');
    }
    if (satisFiyatIndex == -1) {
      throw Exception('"Satış Fiyatı" sütunu bulunamadı');
    }

    // Opsiyonel alanlar
    final alisFiyatIndex = _findColumn(kolonlar, 'alisFiyat');
    final alisFiyatKdvDahilIndex = _findColumn(kolonlar, 'alisFiyatKdvDahil');
    final birimIndex = _findColumn(kolonlar, 'birimAdi');
    final stokIndex = _findColumn(kolonlar, 'stok');
    final kdvIndex = _findColumn(kolonlar, 'kdvOran');
    final kategoriIndex = _findColumn(kolonlar, 'anaGrup');
    final aktifIndex = _findColumn(kolonlar, 'aktif');
    final markaIndex = _findColumn(kolonlar, 'marka');

    // İndirim ve ek sütunlar
    final indirimOraniIndex   = _findColumn(kolonlar, 'indirimOrani');
    final indirimliFiyatIndex = _findColumn(kolonlar, 'indirimliFiyat');
    final alan1Index           = _findColumn(kolonlar, 'alan1');
    final barkodlarIndex       = _findColumn(kolonlar, 'barkodlar');
    final eskiFiyatIndex       = _findColumn(kolonlar, 'eskiFiyat');
    final eskiFiyatTarihIndex  = _findColumn(kolonlar, 'eskiFiyatTarih');
    final promosyonGrupIndex   = _findColumn(kolonlar, 'promosyonGrup');
    final promosyonAktifIndex  = _findColumn(kolonlar, 'promosyonAktif');
    final receteKatsayiIndex   = _findColumn(kolonlar, 'receteKatsayi');
    final lotAciklamaIndex     = _findColumn(kolonlar, 'lotAciklama');
    final hacimIndex           = _findColumn(kolonlar, 'hacim');
    final evrakKontrolIndex    = _findColumn(kolonlar, 'evrakKontrolAktif');
    final netAlisFiyatIndex    = _findColumn(kolonlar, 'netAlisFiyat');

    final depo = UrunDeposu();
    int eklenen = 0, guncellenen = 0, hatali = 0, indirimliKaydedilen = 0;
    final List<String> hataListesi = [];
    final int toplamSatir = sheet.rows.length - 1;
    final bekleyenSatirlar = <({UrunModel urun, int? mevcutId})>[];

    for (int i = 1; i < sheet.rows.length; i++) {
      if (onProgress != null && i % 5 == 0) {
        onProgress(i - 1, toplamSatir);
        await Future.delayed(Duration.zero);
      }

      try {
        final row = sheet.rows[i];
        
        // Boş satır kontrolü
        bool bos = true;
        for (int j = 0; j < row.length; j++) {
          if (_getCellValue(row[j]).isNotEmpty) {
            bos = false;
            break;
          }
        }
        if (bos) continue;

        // ZORUNLU ALANLARI OKU
        final barkod = barkodIndex != -1 ? _getCellValue(row[barkodIndex]) : '';
        final kod = kodIndex != -1 ? _getCellValue(row[kodIndex]) : '';
        final urunAdi = _getCellValue(row[urunAdiIndex]);
        final satisFiyat = _getCellDouble(row[satisFiyatIndex]);

        final gercekKod = kod.isNotEmpty ? kod : barkod;
        if (gercekKod.isEmpty && urunAdi.isEmpty) continue;

        if (urunAdi.isEmpty) {
          hatali++;
          hataListesi.add('Satır ${i + 1}: Ürün Adı boş');
          continue;
        }

        if (satisFiyat == null || satisFiyat <= 0) {
          hatali++;
          hataListesi.add('Satır ${i + 1} (${urunAdi}): Satış Fiyatı geçersiz');
          continue;
        }

        // OPSİYONEL ALANLARI OKU
        double alisFiyat = 0;
        double alisFiyatKdvDahil = 0;
        double kdvOran = 18;
        
        // KDV oranını oku
        if (kdvIndex != -1) {
          final kdvStr = _getCellValue(row[kdvIndex]);
          kdvOran = double.tryParse(kdvStr.replaceAll('%', '')) ?? 18;
        }
        
        // Alış fiyatı (KDV hariç) var mı?
        final alisFiyatVal = alisFiyatIndex != -1 ? _getCellDouble(row[alisFiyatIndex]) : null;
        // KDV'li alış fiyatı var mı?
        final alisKdvliVal = alisFiyatKdvDahilIndex != -1 ? _getCellDouble(row[alisFiyatKdvDahilIndex]) : null;
        
        if (alisKdvliVal != null && alisKdvliVal > 0) {
          // KDV'li alış fiyatı varsa, KDV hariç fiyatı hesapla
          alisFiyatKdvDahil = alisKdvliVal;
          alisFiyat = kdvOran > 0 ? alisKdvliVal / (1 + kdvOran / 100) : alisKdvliVal;
        } else if (alisFiyatVal != null && alisFiyatVal > 0) {
          // KDV hariç alış fiyatı varsa, KDV'li fiyatı hesapla
          alisFiyat = alisFiyatVal;
          alisFiyatKdvDahil = alisFiyatVal * (1 + kdvOran / 100);
        } else {
          // Hiçbiri yoksa varsayılan 0
          alisFiyat = 0;
          alisFiyatKdvDahil = 0;
        }

        // İndirim alanlarını oku
        final indirimVarMi       = indirimOraniIndex != -1 || indirimliFiyatIndex != -1;
        final indirimOraniVal    = indirimOraniIndex != -1 ? _getCellDouble(row[indirimOraniIndex]) ?? 0.0 : 0.0;
        final indirimliFiyatVal  = indirimliFiyatIndex != -1 ? _getCellDouble(row[indirimliFiyatIndex]) ?? 0.0 : 0.0;
        final alan1Val           = alan1Index != -1 ? _getCellValue(row[alan1Index]) : '';
        final eskiFiyatVal       = eskiFiyatIndex != -1 ? _getCellDouble(row[eskiFiyatIndex]) ?? 0.0 : 0.0;
        final eskiFiyatTarihStr  = eskiFiyatTarihIndex != -1 ? _getCellValue(row[eskiFiyatTarihIndex]) : '';
        final promosyonGrupVal   = promosyonGrupIndex != -1 ? _getCellValue(row[promosyonGrupIndex]) : '';
        final promosyonAktifVal  = promosyonAktifIndex != -1 ? _parseBoolean(_getCellValue(row[promosyonAktifIndex])) : false;
        final receteKatsayiVal   = receteKatsayiIndex != -1 ? _getCellDouble(row[receteKatsayiIndex]) ?? 1.0 : 1.0;
        final lotAciklamaVal     = lotAciklamaIndex != -1 ? _getCellValue(row[lotAciklamaIndex]) : '';
        final hacimVal           = hacimIndex != -1 ? _getCellDouble(row[hacimIndex]) ?? 0.0 : 0.0;
        final evrakKontrolVal    = evrakKontrolIndex != -1 ? _parseBoolean(_getCellValue(row[evrakKontrolIndex])) : false;
        final netAlisFiyatVal    = netAlisFiyatIndex != -1 ? _getCellDouble(row[netAlisFiyatIndex]) ?? 0.0 : 0.0;
        final eskiFiyatTarih     = eskiFiyatTarihStr.isNotEmpty ? DateTime.tryParse(eskiFiyatTarihStr) : null;

        // İndirimOranı hesapla (sadece Excel'de indirimle ilgili EN AZ
        // bir sütun varsa — bkz. aşağıdaki GÜNCELLEME notu):
        // - Excel'de oran varsa kullan
        // - Sadece indirimli fiyat varsa → orandan hesapla
        // - İkisi de varsa Excel oranını kullan
        double finalIndirimOrani = 0;
        if (indirimVarMi) {
          if (indirimOraniVal > 0) {
            finalIndirimOrani = indirimOraniVal;
          } else if (indirimliFiyatVal > 0 && satisFiyat > 0 && indirimliFiyatVal < satisFiyat) {
            // İndirimli fiyattan oranı hesapla
            finalIndirimOrani = ((satisFiyat - indirimliFiyatVal) / satisFiyat) * 100;
          }
        }
        final otomatikInd = finalIndirimOrani > 0;
        if (otomatikInd) indirimliKaydedilen++;

        final birim = birimIndex != -1 ? _getCellValue(row[birimIndex]) : '';
        // 🔴 Derin analizde bulundu: satisFiyat geçersizse satır
        // reddediliyor, alisFiyat geçersizse 0'a çekiliyordu — ama stok
        // için HİÇBİR koruma yoktu; negatif bir stok değeri (yazım
        // hatası, bozuk export) sessizce urunler.stok'a yazılıp stok
        // değeri raporlarını ve negatif-stok varsayımı yapan kodu
        // bozabiliyordu. alisFiyat ile aynı desende 0'a çekiliyor.
        final stokHam = stokIndex != -1 ? _getCellDouble(row[stokIndex]) ?? 0.0 : 0.0;
        final stok = stokHam < 0 ? 0.0 : stokHam;
        final kategori = kategoriIndex != -1 ? _getCellValue(row[kategoriIndex]) : '';
        final aktifRaw = aktifIndex != -1 ? _getCellValue(row[aktifIndex]) : '';
        final marka = markaIndex != -1 ? _getCellValue(row[markaIndex]) : '';

        // Mevcut ürünü bul — GÜNCELLEME mi (aşağıdaki kritik düzeltmeye
        // bkz.), yoksa YENİ KAYIT mı olduğunu bilmemiz, satırı nasıl
        // kuracağımızı belirliyor.
        UrunModel? mevcut;
        final aranacakBarkod = barkod.isNotEmpty ? barkod : kod;
        if (aranacakBarkod.isNotEmpty) {
          mevcut = await depo.barkodlaGetirPasifDahil(aranacakBarkod);
        }
        if (mevcut == null && kod.isNotEmpty) {
          mevcut = await depo.kodlaGetir(kod);
        }

        final UrunModel urun;
        if (mevcut != null) {
          // 🔴🔴🔴 KRİTİK KÖK NEDEN DÜZELTMESİ (ürün kaydı derin
          // analizi — kullanıcı isteği: "ürün kaydını detaylı incele,
          // excel içeri alma sıkıntısız olsun"): ÖNCEDEN bu GÜNCELLEME
          // dalında da, Excel'de HİÇ OLMAYAN her alan için VARSAYILAN
          // değerlerle sıfırdan bir UrunModel kurulup mevcut ürünün
          // TÜM satırının üzerine YAZILIYORDU. Sonuç — sırf fiyat/stok
          // güncellemek için hazırlanmış, birkaç sütunlu tipik bir
          // tedarikçi Excel'i yeniden içe aktarıldığında, o üründe daha
          // önce ayarlanmış HER ŞEY sessizce SIFIRLANIYORDU:
          //   • global_id YENİ bir UUID'e değişiyordu → bulut senkron
          //     kimliği kopuyor, bir sonraki gönderimde AYNI ürün
          //     bulutta MÜKERRER bir satır olarak beliriyordu.
          //   • qr_menude (QR Menüde Göster) HER ZAMAN false'a
          //     düşüyordu — "QR menüde ürünler kayboldu" şikayetinin
          //     olası kök nedenlerinden biri tam olarak buydu.
          //   • Stok sütunu OLMAYAN bir fiyat-listesi Excel'i, mevcut
          //     STOĞU SIFIRLIYORDU — sessiz, geri alınamaz envanter
          //     kaybı.
          //   • minimum/maksimum stok eşiği, seri/lot takibi, toptan
          //     satış fiyat/koşulları, puan oranı, resim, muhasebe
          //     kodu, PLU, ölçüler (en/boy/yükseklik/ağırlık) ve
          //     onlarca alan daha aynı şekilde varsayılana dönüyordu.
          // Artık GÜNCELLEME'de sıfırdan bir model KURULMUYOR — mevcut
          // kaydın ÜZERİNE, SADECE Excel satırında GERÇEKTEN VAR OLAN
          // (sütunu bulunan) alanlar copyWith ile uygulanıyor; Excel'de
          // olmayan/boş bırakılmış her şey OLDUĞU GİBİ korunuyor —
          // global_id ve qr_menude dahil (bu ikisi hiç parametre
          // olarak verilmiyor, copyWith otomatik olarak mevcut kaydın
          // değerini korur).
          urun = ExcelUrunBirlestirici.guncellemeIcinBirlestir(
            mevcut: mevcut,
            urunAdi: urunAdi,
            satisFiyat: satisFiyat,
            kod: gercekKod.isNotEmpty ? gercekKod : null,
            barkod: barkod.isNotEmpty ? barkod : (kod.isNotEmpty ? kod : null),
            barkodlar: barkodlarIndex != -1
                ? (row[barkodlarIndex]?.value?.toString()?.trim().isNotEmpty == true
                    ? row[barkodlarIndex]!.value.toString().trim()
                    : null)
                : null,
            birim: birim.isNotEmpty ? birim : null,
            alisFiyat: (alisFiyatIndex != -1 || alisFiyatKdvDahilIndex != -1) ? alisFiyat : null,
            alisFiyatKdvDahil: (alisFiyatIndex != -1 || alisFiyatKdvDahilIndex != -1) ? alisFiyatKdvDahil : null,
            stok: stokIndex != -1 ? stok : null,
            kdvOran: kdvIndex != -1 ? kdvOran : null,
            anaGrup: kategori.isNotEmpty ? kategori : null,
            aktif: aktifIndex != -1 ? _parseBoolean(aktifRaw, defaultValue: true) : null,
            marka: marka.isNotEmpty ? marka : null,
            alan1: alan1Val.isNotEmpty ? alan1Val : null,
            indirimOrani: indirimVarMi ? finalIndirimOrani : null,
            otomatikIndirim: indirimVarMi ? otomatikInd : null,
            indirimliFiyatKayitli: indirimVarMi ? (indirimliFiyatVal > 0 ? indirimliFiyatVal : 0) : null,
            eskiFiyat: eskiFiyatIndex != -1 ? eskiFiyatVal : null,
            eskiFiyatTarih: eskiFiyatTarih,
            promosyonGrup: promosyonGrupVal.isNotEmpty ? promosyonGrupVal : null,
            promosyonAktif: promosyonAktifIndex != -1 ? promosyonAktifVal : null,
            receteKatsayi: receteKatsayiIndex != -1 ? receteKatsayiVal : null,
            lotAciklama: lotAciklamaVal.isNotEmpty ? lotAciklamaVal : null,
            hacim: hacimIndex != -1 ? hacimVal : null,
            evrakKontrolAktif: evrakKontrolIndex != -1 ? evrakKontrolVal : null,
            netAlisFiyat: netAlisFiyatIndex != -1 ? netAlisFiyatVal : null,
            lastUpdated: DateTime.now().toIso8601String(),
          );
        } else {
          // YENİ KAYIT: bu ürün lokalde hiç yok — kaybedecek eski veri
          // olmadığı için tüm alanlar (Excel'de yoksa makul
          // varsayılanlarla) sıfırdan kuruluyor, eskisi gibi.
          urun = UrunModel(
            id: null,
            kod: gercekKod.isNotEmpty ? gercekKod : null,
            barkod: barkod.isNotEmpty ? barkod : (kod.isNotEmpty ? kod : null),
            barkodlar: barkodlarIndex != -1
                ? (row[barkodlarIndex]?.value?.toString()?.trim().isNotEmpty == true
                    ? row[barkodlarIndex]!.value.toString().trim()
                    : null)
                : null,
            urunAdi: urunAdi,
            alternatifUrunAdi: null,
            birimAdi: birim.isNotEmpty ? birim : 'Adet',
            alisFiyat: alisFiyat,
            alisFiyatKdvDahil: alisFiyatKdvDahil,
            satisFiyati: satisFiyat,
            stok: stok,
            toplamMaliyet: 0,
            toplamStok: 0,
            alisKdvOran: kdvOran,
            kdvOran: kdvOran.toStringAsFixed(0),
            anaGrup: kategori.isNotEmpty ? kategori : null,
            altGrup: null,
            aktif: _parseBoolean(aktifRaw, defaultValue: true),
            seriNoTakibi: false,
            lotTakibi: false,
            lotNo: null,
            sonKullanmaTarihi: null,
            alan1: alan1Val.isNotEmpty ? alan1Val : null,
            alan2: null,
            alan3: null,
            alan4: null,
            paraBirimi: 'TRY',
            indirimOrani: finalIndirimOrani,
            otomatikIndirim: otomatikInd,
            indirimliFiyatKayitli: indirimliFiyatVal > 0 ? indirimliFiyatVal : 0,
            eskiFiyat: eskiFiyatVal,
            eskiFiyatTarih: eskiFiyatTarih,
            promosyonGrup: promosyonGrupVal.isNotEmpty ? promosyonGrupVal : null,
            promosyonAktif: promosyonAktifVal,
            receteKatsayi: receteKatsayiVal,
            lotAciklama: lotAciklamaVal.isNotEmpty ? lotAciklamaVal : null,
            hacim: hacimVal,
            evrakKontrolAktif: evrakKontrolVal,
            netAlisFiyat: netAlisFiyatVal,
            sonAlimIndirimOran: 0,
            minimumStok: 0,
            maksimumStok: 0,
            maksimumSatirMiktari: 0,
            renk: null,
            beden: null,
            sube: null,
            resimYolu: null,
            uretici: null,
            marka: marka.isNotEmpty ? marka : null,
            model: null,
            grupSorumlusu: null,
            mensei: null,
            rafNumarasi: null,
            rafOmru: null,
            pluNumarasi: null,
            puanOrani: 0,
            muhasebeKodu: null,
            muafiyetKodu: null,
            resmiBakiye: 0,
            barkodOlcuBirimi: null,
            en: 0,
            boy: 0,
            yukseklik: 0,
            agirlik: 0,
            eskiKodu: null,
            kartTipi: 'Standart',
            seriNumarasi: null,
            fiyatGuncellemeTarih: null,
            fiyatGuncelleyenKullanici: null,
            barkodYazdirmaTarih: null,
            barkodYazdiranKullanici: null,
            maliyetGuncellemeTarih: null,
            maliyetGuncelleyenKullanici: null,
            guncellemeTarihi: null,
            kayitTarihi: null,
            guncelleyenKullanici: null,
            kaydedenKullanici: null,
            lastUpdated: DateTime.now().toIso8601String(),
            syncStatus: 'synced',
            isDeleted: false,
          );
        }

        // ÖNCEDEN BURADA HER SATIR İÇİN AYRI AYRI await depo.ekle()/
        // guncelle() ÇAĞRILIYORDU — kullanıcının bildirdiği gibi 4000
        // satırlık bir Excel için bu ÇOK YAVAŞ oluyordu (binlerce ayrı
        // veritabanı işlemi). Artık sadece LİSTEYE ekleniyor, gerçek
        // veritabanı yazma işlemi döngü BİTTİKTEN SONRA TEK bir
        // transaction içinde topluca yapılıyor — büyük bir hız artışı.
        bekleyenSatirlar.add((urun: urun, mevcutId: mevcut?.id));
      } catch (e) {
        hatali++;
        hataListesi.add('Satır ${i + 1}: $e');
      }
    }

    // Gerçek veritabanı yazma işlemi burada, TEK bir transaction
    // içinde topluca yapılıyor (bkz. yukarıdaki not).
    if (bekleyenSatirlar.isNotEmpty) {
      final sonuc = await depo.topluEkleGuncelle(bekleyenSatirlar);
      eklenen = sonuc['eklenen'] ?? 0;
      guncellenen = sonuc['guncellenen'] ?? 0;
    }

    return IceriAktarSonuc(
      eklenen: eklenen,
      guncellenen: guncellenen,
      hatali: hatali,
      hatalar: hataListesi,
      toplam: toplamSatir,
      indirimliKaydedilen: indirimliKaydedilen,
    );
  }

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
    final bytes = excel.encode();
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
    final bytes = excel.encode();
    if (bytes != null) {
      await File(yol).writeAsBytes(bytes);
      return yol;
    }
    throw Exception('Excel encode hatası');
  }

  Future<void> paylasExcel(String yol) async =>
      Share.shareXFiles([XFile(yol)], text: 'MarketPlus Excel');


  // ──────────────────────────────────────────────────────────────────────────
  // STOK SAYIM Excel içe/dışa al
  // Başlıklar: Kod | UrunAdi | Ana Miktar | Stok | Fark | DepoAdi
  // DB eşleştirme: Kod=urunler.barkod (önce) veya urunler.kod
  // ──────────────────────────────────────────────────────────────────────────
  // Excel'i okuyup sayım listesi olarak döndürür (stoku GÜNCELLEMEZ)
  Future<List<Map<String, dynamic>>> stokSayimListesiIceAl(Uint8List bytes) async {
    final excel = Excel.decodeBytes(bytes);
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
        final rows = await db.rawQuery(
          'SELECT id, urun_adi, birim_adi FROM urunler WHERE (barkod=? OR kod=?) AND is_deleted=0 LIMIT 1',
          [kod, kod]);
        if (rows.isNotEmpty) {
          liste.add({'urun_id': rows.first['id'], 'miktar': miktar,
            'urun_adi': rows.first['urun_adi'], 'birim_adi': rows.first['birim_adi']});
        }
      } catch (e) { /* ignore */ }
    }
    return liste;
  }

  Future<Map<String, dynamic>> stokSayimExcelIceAl(Uint8List bytes) async {
    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.sheets.values.first;
    if (sheet.rows.isEmpty) return {'basarili': 0, 'hata': 0, 'hatalar': <String>[]};

    final headerList = sheet.rows.first.map((c) => c?.value?.toString()?.trim() ?? '').toList();
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

        // Önce barkod ile bul, yoksa kod ile
        final rows = await db.rawQuery(
          "SELECT id, stok FROM urunler WHERE (barkod=? OR kod=?) AND is_deleted=0 LIMIT 1",
          [kod, kod],
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

    final bytes = excel.encode()!;
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
    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.sheets.values.first;
    if (sheet.rows.isEmpty) return {'basarili': 0, 'hata': 0, 'hatalar': <String>[]};

    final headerList = sheet.rows.first.map((c) => c?.value?.toString()?.trim() ?? '').toList();
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

        // Ürünü bul
        final urunRows = await db.rawQuery(
          "SELECT id FROM urunler WHERE (barkod=? OR kod=?) AND is_deleted=0 LIMIT 1",
          [kod, kod],
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

    final bytes = excel.encode()!;
    final dir   = await getTemporaryDirectory();
    final path  = dir.path + '/promosyon_' + DateTime.now().millisecondsSinceEpoch.toString() + '.xlsx';
    await File(path).writeAsBytes(bytes);
    return path;
  }

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

    final bytes = excel.encode()!;
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
      final fiyat      = (k['birim_fiyat'] as num?)?.toDouble() ?? 0.0;
      final miktar     = (k['miktar'] as num?)?.toDouble() ?? 0.0;
      final kdvOran    = (k['kdv_oran'] as num?)?.toDouble() ?? 0.0;
      final iskontoOr  = (k['iskonto_oran'] as num?)?.toDouble() ?? 0.0;
      final tutar      = fiyat * miktar;
      final iskontoTut = tutar * iskontoOr / 100;
      final netFiyat   = fiyat * (1 - iskontoOr / 100);
      final netTutar   = netFiyat * miktar;
      final kdvliF     = netFiyat * (1 + kdvOran / 100);
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
        DoubleCellValue(fiyat),
      ]);
    }

    final bytes = excel.encode()!;
    final dir   = await getTemporaryDirectory();
    final path  = dir.path + '/iade_alma_' + DateTime.now().millisecondsSinceEpoch.toString() + '.xlsx';
    await File(path).writeAsBytes(bytes);
    return path;
  }

}