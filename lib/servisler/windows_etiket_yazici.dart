// lib/servisler/windows_etiket_yazici.dart
//
// Windows yazıcısına etiket basma (GDI, kendi FFI tanımlarımızla). Ürün Güncelleme'deki lib/etiket/windows_yazici.dart ile AYNI.
//
// Neden: printing eklentisinin directPrintPdf'i sürücüye içi sıfırlanmış bir DEVMODE verir; etiket yazıcısı
// sürücüleri (ör. Xprinter XP-490B) bu durumda kendi stok ayarlarını kaybedip varsayılan uzun sayfaya
// (4×6 inç) döner: önce birkaç boş etiket akar, yazı sayfanın ortasına basılır.
// Burada sürücünün kendi DEVMODE'u alınır, kâğıt boyutu şöyle seçilir:
//   1) Sürücünün varsayılan sayfası zaten etiket boyundaysa hiç dokunulmaz (BarTender / Barkopos gibi).
//   2) Sürücüde bu boyda tanımlı bir kâğıt (form) varsa o seçilir.
//   3) Yoksa özel boyut (genişlik × uzunluk) verilir.
// Her sayfa yazıcının kendi çözünürlüğünde resme çevrilip siyah-beyaz basılır (barkod çizgileri keskin kalır).

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:printing/printing.dart';

/// Sürücünün sayfa bilgisi (mm).
class YaziciSayfasi {
  final double genislik, uzunluk;
  final double dpi; // yatay çözünürlük
  final String aciklama; // ör. 'sürücü varsayılanı', 'sürücü kâğıdı "80x35"', 'özel boyut'
  const YaziciSayfasi(this.genislik, this.uzunluk, this.aciklama, {this.dpi = 203});

  /// Etiket boyuna (±[pay] mm) uyuyor mu?
  bool uyar(double g, double u, {double pay = 2}) => (genislik - g).abs() <= pay && (uzunluk - u).abs() <= pay;

  String get olcu => '${_mmYaz(genislik)} × ${_mmYaz(uzunluk)} mm';
}

String _mmYaz(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

class WindowsYaziciHatasi implements Exception {
  final String mesaj;
  WindowsYaziciHatasi(this.mesaj);
  @override
  String toString() => mesaj;
}

/// Sürücüde tanımlı bir kâğıt.
class SurucuKagidi {
  final int no;
  final String ad;
  final int genislik, uzunluk; // 0,1 mm
  const SurucuKagidi(this.no, this.ad, this.genislik, this.uzunluk);
}

/// [kagitlar] içinden [g]×[u] mm'ye (±1,5 mm) uyan ilk kâğıt; yoksa null. Saf, testli.
SurucuKagidi? uyanKagit(List<SurucuKagidi> kagitlar, double g, double u) {
  final gg = (g * 10).round(), uu = (u * 10).round();
  for (final k in kagitlar) {
    if ((k.genislik - gg).abs() <= 15 && (k.uzunluk - uu).abs() <= 15) return k;
  }
  return null;
}

/// RGBA pikselleri 32 bit BGRA siyah-beyaza çevirir (eşik: parlaklık < 160 → siyah). Saf, testli.
Uint8List siyahBeyazBgra(Uint8List rgba) {
  final out = Uint8List(rgba.length);
  for (var i = 0; i + 3 < rgba.length; i += 4) {
    final a = rgba[i + 3];
    // Saydam alan beyaz kâğıt sayılır.
    final r = 255 - ((255 - rgba[i]) * a ~/ 255);
    final g = 255 - ((255 - rgba[i + 1]) * a ~/ 255);
    final b = 255 - ((255 - rgba[i + 2]) * a ~/ 255);
    final v = (r * 299 + g * 587 + b * 114) ~/ 1000 < 160 ? 0 : 255;
    out[i] = v;
    out[i + 1] = v;
    out[i + 2] = v;
    out[i + 3] = 255;
  }
  return out;
}

// ───────────────────────── FFI ─────────────────────────

final _ws = DynamicLibrary.open('winspool.drv');
final _gdi = DynamicLibrary.open('gdi32.dll');

final _openPrinter = _ws.lookupFunction<Int32 Function(Pointer<Utf16>, Pointer<IntPtr>, Pointer<Void>),
    int Function(Pointer<Utf16>, Pointer<IntPtr>, Pointer<Void>)>('OpenPrinterW');
final _closePrinter = _ws.lookupFunction<Int32 Function(IntPtr), int Function(int)>('ClosePrinter');
final _documentProperties = _ws.lookupFunction<
    Int32 Function(IntPtr, IntPtr, Pointer<Utf16>, Pointer<Uint8>, Pointer<Uint8>, Uint32),
    int Function(int, int, Pointer<Utf16>, Pointer<Uint8>, Pointer<Uint8>, int)>('DocumentPropertiesW');
final _deviceCapabilities = _ws.lookupFunction<
    Int32 Function(Pointer<Utf16>, Pointer<Utf16>, Uint16, Pointer<Uint8>, Pointer<Uint8>),
    int Function(Pointer<Utf16>, Pointer<Utf16>, int, Pointer<Uint8>, Pointer<Uint8>)>('DeviceCapabilitiesW');

final _createDC = _gdi.lookupFunction<IntPtr Function(Pointer<Utf16>, Pointer<Utf16>, Pointer<Utf16>, Pointer<Uint8>),
    int Function(Pointer<Utf16>, Pointer<Utf16>, Pointer<Utf16>, Pointer<Uint8>)>('CreateDCW');
final _deleteDC = _gdi.lookupFunction<Int32 Function(IntPtr), int Function(int)>('DeleteDC');
final _getDeviceCaps = _gdi.lookupFunction<Int32 Function(IntPtr, Int32), int Function(int, int)>('GetDeviceCaps');
final _startDoc = _gdi.lookupFunction<Int32 Function(IntPtr, Pointer<Uint8>), int Function(int, Pointer<Uint8>)>('StartDocW');
final _startPage = _gdi.lookupFunction<Int32 Function(IntPtr), int Function(int)>('StartPage');
final _endPage = _gdi.lookupFunction<Int32 Function(IntPtr), int Function(int)>('EndPage');
final _endDoc = _gdi.lookupFunction<Int32 Function(IntPtr), int Function(int)>('EndDoc');
final _abortDoc = _gdi.lookupFunction<Int32 Function(IntPtr), int Function(int)>('AbortDoc');
final _stretchDIBits = _gdi.lookupFunction<
    Int32 Function(IntPtr, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Pointer<Uint8>, Pointer<Uint8>, Uint32, Uint32),
    int Function(int, int, int, int, int, int, int, int, int, Pointer<Uint8>, Pointer<Uint8>, int, int)>('StretchDIBits');

// DEVMODEW alanları (bayt konumu)
const _dmFields = 72, _dmOrientation = 76, _dmPaperSize = 78, _dmPaperLength = 80, _dmPaperWidth = 82;
const _dmOrientationBit = 0x1, _dmPaperSizeBit = 0x2, _dmPaperLengthBit = 0x4, _dmPaperWidthBit = 0x8, _dmFormNameBit = 0x10000;
const _dmOutBuffer = 2, _dmInBuffer = 8;
const _dcPapers = 2, _dcPaperSize = 3, _dcPaperNames = 16;
const _logPixelsX = 88, _logPixelsY = 90;
const _physicalWidth = 110, _physicalHeight = 111, _physicalOffsetX = 112, _physicalOffsetY = 113;

extension on Pointer<Uint8> {
  void yaz16(int konum, int v) => (this + konum).cast<Int16>().value = v;
  int oku32(int konum) => (this + konum).cast<Uint32>().value;
  void yaz32(int konum, int v) => (this + konum).cast<Uint32>().value = v;
}

/// Sürücüde tanımlı kâğıtlar.
List<SurucuKagidi> surucuKagitlari(String yazici) {
  final ad = yazici.toNativeUtf16();
  try {
    final n = _deviceCapabilities(ad, nullptr, _dcPapers, nullptr, nullptr);
    if (n <= 0) return const [];
    final nolar = calloc<Uint16>(n);
    final olcu = calloc<Int32>(n * 2);
    final adlar = calloc<Uint16>(n * 64);
    try {
      _deviceCapabilities(ad, nullptr, _dcPapers, nolar.cast(), nullptr);
      _deviceCapabilities(ad, nullptr, _dcPaperSize, olcu.cast(), nullptr);
      final adVar = _deviceCapabilities(ad, nullptr, _dcPaperNames, adlar.cast(), nullptr) == n;
      return [
        for (var i = 0; i < n; i++)
          SurucuKagidi(
            nolar[i],
            adVar ? _wcharOku(adlar + i * 64, 64) : '#${nolar[i]}',
            olcu[i * 2],
            olcu[i * 2 + 1],
          ),
      ];
    } finally {
      calloc.free(nolar);
      calloc.free(olcu);
      calloc.free(adlar);
    }
  } finally {
    calloc.free(ad);
  }
}

String _wcharOku(Pointer<Uint16> p, int en) {
  final b = StringBuffer();
  for (var i = 0; i < en && p[i] != 0; i++) {
    b.writeCharCode(p[i]);
  }
  return b.toString().trim();
}

/// Sürücünün DEVMODE'u (calloc ile ayrılır; çağıran serbest bırakır).
Pointer<Uint8> _devmode(int h, Pointer<Utf16> ad) {
  final boy = _documentProperties(0, h, ad, nullptr, nullptr, 0);
  if (boy <= 0) throw WindowsYaziciHatasi('Yazıcı sürücüsünün ayarları okunamadı');
  final dm = calloc<Uint8>(boy);
  if (_documentProperties(0, h, ad, dm, nullptr, _dmOutBuffer) < 0) {
    calloc.free(dm);
    throw WindowsYaziciHatasi('Yazıcı sürücüsünün ayarları okunamadı');
  }
  return dm;
}

/// [dm] ile oluşan sayfanın ölçüsü (mm) ve çözünürlüğü.
YaziciSayfasi _sayfaOlc(Pointer<Utf16> ad, Pointer<Uint8> dm, String aciklama) {
  final dc = _createDC(nullptr, ad, nullptr, dm);
  if (dc == 0) throw WindowsYaziciHatasi('Yazıcıya bağlanılamadı');
  try {
    final dx = _getDeviceCaps(dc, _logPixelsX), dy = _getDeviceCaps(dc, _logPixelsY);
    if (dx <= 0 || dy <= 0) throw WindowsYaziciHatasi('Yazıcının çözünürlüğü okunamadı');
    return YaziciSayfasi(
      _getDeviceCaps(dc, _physicalWidth) * 25.4 / dx,
      _getDeviceCaps(dc, _physicalHeight) * 25.4 / dy,
      aciklama,
      dpi: dx.toDouble(),
    );
  } finally {
    _deleteDC(dc);
  }
}

/// Yazıcıya [genislik]×[uzunluk] mm sayfa için uygun ayarı hazırlar. Dönen DEVMODE'u çağıran serbest bırakır.
(Pointer<Uint8>, YaziciSayfasi) _ayarla(String yazici, double genislik, double uzunluk) {
  final ad = yazici.toNativeUtf16();
  final hp = calloc<IntPtr>();
  try {
    if (_openPrinter(ad, hp, nullptr) == 0) throw WindowsYaziciHatasi('"$yazici" yazıcısı açılamadı');
    final h = hp.value;
    try {
      final dm = _devmode(h, ad);
      // 1) Varsayılan sayfa zaten etiket boyunda mı?
      final YaziciSayfasi v;
      try {
        v = _sayfaOlc(ad, dm, 'sürücü varsayılanı');
      } catch (_) {
        calloc.free(dm);
        rethrow;
      }
      if (v.uyar(genislik, uzunluk)) return (dm, v);

      // 2) Sürücüde bu boyda kâğıt var mı? 3) Yoksa özel boyut.
      final k = uyanKagit(surucuKagitlari(yazici), genislik, uzunluk);
      var alan = dm.oku32(_dmFields) & ~_dmFormNameBit;
      dm.yaz16(_dmOrientation, 1); // dikey: genişlik yazıcının enine
      if (k != null) {
        dm.yaz16(_dmPaperSize, k.no);
        alan = (alan | _dmOrientationBit | _dmPaperSizeBit) & ~(_dmPaperLengthBit | _dmPaperWidthBit);
      } else {
        dm.yaz16(_dmPaperSize, 256); // DMPAPER_USER
        dm.yaz16(_dmPaperWidth, (genislik * 10).round());
        dm.yaz16(_dmPaperLength, (uzunluk * 10).round());
        alan |= _dmOrientationBit | _dmPaperSizeBit | _dmPaperLengthBit | _dmPaperWidthBit;
      }
      dm.yaz32(_dmFields, alan);
      // Sürücü değişikliği kendi iç ayarlarına da işlesin.
      final boy = _documentProperties(0, h, ad, nullptr, nullptr, 0);
      final son = calloc<Uint8>(boy);
      if (_documentProperties(0, h, ad, son, dm, _dmInBuffer | _dmOutBuffer) < 0) {
        calloc.free(son);
        calloc.free(dm);
        throw WindowsYaziciHatasi('Yazıcı sürücüsü etiket boyutunu kabul etmedi');
      }
      calloc.free(dm);
      try {
        return (son, _sayfaOlc(ad, son, k != null ? 'sürücü kâğıdı "${k.ad}"' : 'özel boyut'));
      } catch (_) {
        calloc.free(son);
        rethrow;
      }
    } finally {
      _closePrinter(h);
    }
  } finally {
    calloc.free(hp);
    calloc.free(ad);
  }
}

/// Basmadan önce yazıcının hangi sayfayı kullanacağını söyler.
YaziciSayfasi windowsSayfaSorgula(String yazici, double genislik, double uzunluk) {
  final (dm, s) = _ayarla(yazici, genislik, uzunluk);
  calloc.free(dm);
  return s;
}

/// [pdf]'in her sayfasını [yazici]ya [genislik]×[uzunluk] mm sayfa olarak basar.
/// Sayfa sayısını döndürür.
Future<int> windowsYazdir(String yazici, Uint8List pdf,
        {required double genislik, required double uzunluk, String belgeAdi = 'Raf etiketleri'}) =>
    windowsResimBas(yazici, (dpi) => Printing.raster(pdf, dpi: dpi).map((r) => (r.pixels, r.width, r.height)),
        genislik: genislik, uzunluk: uzunluk, belgeAdi: belgeAdi);

/// [ciz] yazıcı çözünürlüğünde (dpi) her sayfanın RGBA resmini verir. [cikti] verilirse iş dosyaya yazılır (test).
Future<int> windowsResimBas(String yazici, Stream<(Uint8List, int, int)> Function(double dpi) ciz,
    {required double genislik, required double uzunluk, String belgeAdi = 'Raf etiketleri', String? cikti}) async {
  final (dm, _) = _ayarla(yazici, genislik, uzunluk);
  final ad = yazici.toNativeUtf16();
  final belge = belgeAdi.toNativeUtf16();
  final dosya = cikti?.toNativeUtf16();
  final docInfo = calloc<Uint8>(40); // DOCINFOW (x64)
  final bmi = calloc<Uint8>(44); // BITMAPINFOHEADER + 1 renk
  int dc = 0;
  var basladi = false, sayfa = 0;
  try {
    dc = _createDC(nullptr, ad, nullptr, dm);
    if (dc == 0) throw WindowsYaziciHatasi('"$yazici" yazıcısına bağlanılamadı');
    final dpiX = _getDeviceCaps(dc, _logPixelsX), dpiY = _getDeviceCaps(dc, _logPixelsY);
    final ofsX = _getDeviceCaps(dc, _physicalOffsetX), ofsY = _getDeviceCaps(dc, _physicalOffsetY);

    docInfo.yaz32(0, 40);
    (docInfo + 8).cast<Pointer<Utf16>>().value = belge;
    if (dosya != null) (docInfo + 16).cast<Pointer<Utf16>>().value = dosya;
    if (_startDoc(dc, docInfo) <= 0) throw WindowsYaziciHatasi('Yazdırma işi başlatılamadı');
    basladi = true;

    // Yatay ve dikey çözünürlük farklı olabilir: yatayda yazıcı çözünürlüğünde çiz, dikeyde ölçekle.
    await for (final (rgba, en, boy) in ciz(dpiX.toDouble())) {
      if (rgba.length != en * boy * 4) throw WindowsYaziciHatasi('Etiket resmi hatalı');
      final piksel = siyahBeyazBgra(rgba);
      final hedefY = (boy * dpiY / dpiX).round();
      bmi.yaz32(0, 40);
      bmi.yaz32(4, en);
      bmi.yaz32(8, -boy); // yukarıdan aşağı
      bmi.yaz16(12, 1);
      bmi.yaz16(14, 32);
      bmi.yaz32(16, 0); // BI_RGB
      final veri = calloc<Uint8>(piksel.length);
      try {
        veri.asTypedList(piksel.length).setAll(0, piksel);
        if (_startPage(dc) <= 0) throw WindowsYaziciHatasi('Sayfa başlatılamadı');
        final ok = _stretchDIBits(dc, -ofsX, -ofsY, en, hedefY, 0, 0, en, boy, veri, bmi, 0, 0x00CC0020);
        if (_endPage(dc) <= 0) throw WindowsYaziciHatasi('Sayfa yazıcıya gönderilemedi');
        if (ok == 0) throw WindowsYaziciHatasi('Etiket resmi yazıcıya çizilemedi');
      } finally {
        calloc.free(veri);
      }
      sayfa++;
    }
    if (_endDoc(dc) <= 0) throw WindowsYaziciHatasi('Yazdırma işi bitirilemedi');
    basladi = false;
    return sayfa;
  } finally {
    if (basladi) _abortDoc(dc);
    if (dc != 0) _deleteDC(dc);
    calloc.free(dm);
    calloc.free(ad);
    calloc.free(belge);
    if (dosya != null) calloc.free(dosya);
    calloc.free(docInfo);
    calloc.free(bmi);
  }
}

// ───────────────────────── Ham (RAW) gönderim ─────────────────────────
// TSPL / ESC/POS komutlarını sürücüden geçirmeden yazıcıya aktarır (ör. telefondan ağ üzerinden gelen iş).

final _startDocPrinter = _ws.lookupFunction<Uint32 Function(IntPtr, Uint32, Pointer<Uint8>),
    int Function(int, int, Pointer<Uint8>)>('StartDocPrinterW');
final _startPagePrinter = _ws.lookupFunction<Int32 Function(IntPtr), int Function(int)>('StartPagePrinter');
final _endPagePrinter = _ws.lookupFunction<Int32 Function(IntPtr), int Function(int)>('EndPagePrinter');
final _endDocPrinter = _ws.lookupFunction<Int32 Function(IntPtr), int Function(int)>('EndDocPrinter');
final _writePrinter = _ws.lookupFunction<Int32 Function(IntPtr, Pointer<Uint8>, Uint32, Pointer<Uint32>),
    int Function(int, Pointer<Uint8>, int, Pointer<Uint32>)>('WritePrinter');

/// [veri]yi [yazici]ya RAW iş olarak gönderir. [cikti] verilirse iş dosyaya yazılır (test).
void windowsHamGonder(String yazici, Uint8List veri, {String belgeAdi = 'Etiket (ağdan)', String? cikti}) {
  if (veri.isEmpty) return;
  final ad = yazici.toNativeUtf16();
  final hp = calloc<IntPtr>();
  final belge = belgeAdi.toNativeUtf16();
  final tur = 'RAW'.toNativeUtf16();
  final dosya = cikti?.toNativeUtf16();
  final docInfo = calloc<Uint8>(24); // DOC_INFO_1W (x64)
  final tampon = calloc<Uint8>(veri.length);
  final yazilan = calloc<Uint32>();
  try {
    if (_openPrinter(ad, hp, nullptr) == 0) throw WindowsYaziciHatasi('"$yazici" yazıcısı açılamadı');
    final h = hp.value;
    try {
      docInfo.cast<Pointer<Utf16>>().value = belge;
      (docInfo + 8).cast<Pointer<Utf16>>().value = dosya ?? nullptr;
      (docInfo + 16).cast<Pointer<Utf16>>().value = tur;
      if (_startDocPrinter(h, 1, docInfo) == 0) throw WindowsYaziciHatasi('"$yazici" yazıcısında iş başlatılamadı');
      var tamam = false;
      try {
        if (_startPagePrinter(h) == 0) throw WindowsYaziciHatasi('Yazıcıda sayfa başlatılamadı');
        tampon.asTypedList(veri.length).setAll(0, veri);
        var gonderilen = 0;
        while (gonderilen < veri.length) {
          if (_writePrinter(h, tampon + gonderilen, veri.length - gonderilen, yazilan) == 0 || yazilan.value == 0) {
            throw WindowsYaziciHatasi('"$yazici" yazıcısına veri yazılamadı');
          }
          gonderilen += yazilan.value;
        }
        _endPagePrinter(h);
        tamam = true;
      } finally {
        // Hata olsa da iş kapatılır; aksi hâlde kuyrukta asılı kalır.
        final bitti = _endDocPrinter(h) != 0;
        if (tamam && !bitti) throw WindowsYaziciHatasi('"$yazici" yazıcısında iş bitirilemedi');
      }
    } finally {
      _closePrinter(h);
    }
  } finally {
    calloc.free(ad);
    calloc.free(hp);
    calloc.free(belge);
    calloc.free(tur);
    if (dosya != null) calloc.free(dosya);
    calloc.free(docInfo);
    calloc.free(tampon);
    calloc.free(yazilan);
  }
}
