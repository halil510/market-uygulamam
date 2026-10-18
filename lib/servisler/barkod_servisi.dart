// lib/servisler/barkod_servisi.dart
//
// GS1-TR Türkiye standardına tam uyum:
//  - EAN-13 / EAN-8 / UPC-A / ITF-14 check digit doğrulama
//  - GS1-TR tartım barkodu (prefix 20-29): 5 haneli ağırlık (gram)
//  - GS1-128 / GS1-DataMatrix Application Identifier çözümleme
//    (FNC1/GS ayırıcılı, parantezli, 4 haneli 31xx-36xx AI'ları dahil)
//  - ITF-14 lojistik barkod tanıma
//  - Türkiye'ye özel prefix'ler (868-869)
//  - PLU kodu tanıma (4-5 haneli)
//
// KAMERA (mobile_scanner 7.4.2)
//  • BarkodServisi.tarayiciOlustur(): TEK noktadan controller ayarı
//    (9 market formatı, 1920×1080, normal hız + 200 ms zaman aşımı).
//    Hızlı satış ekranı ve tarama dialog'u aynı ayarı kullanır.
//  • 🔴 Zoom düzeltmesi: setZoomScale 0.0–1.0 aralığı bekler. Önceki
//    sürüm 1.0–4.0 gönderiyordu → 1.0 üstü değerler hata verip sessizce
//    yutuluyor, zoom hiç çalışmıyordu. Artık 0.0–1.0 kaydırıcı + iki
//    parmakla kıstırma.
//  • Işık ikonu kameranın gerçek torch durumunu gösterir.
//  • Kamera izni reddedilince "Ayarları Aç" butonu çıkar.
//  • 🔴 Eski 12 haneli UPC-A kodları GS1-128 sanılıyordu → artık EAN-13
//    olarak sınıflanır. UPC-A ↔ EAN-13 eşleşmesi için aramaKodlari()
//    eklendi (iOS UPC-A'yı başına 0 ekleyip 13 hane döndürür, Android 12
//    hane döndürür; ürün veritabanında hangisi kayıtlıysa bulunur).
import '../cekirdek/utils/denetleyici_birak.dart';
import 'dart:async' show Timer;
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import 'package:permission_handler/permission_handler.dart'
    show openAppSettings;

/// GS1-TR Türkiye Barkod Standardı
class BarkodServisi {
  static final BarkodServisi _instance = BarkodServisi._internal();
  factory BarkodServisi() => _instance;
  BarkodServisi._internal();

  final AudioPlayer _audio = AudioPlayer();
  bool _sesHazir = false;

  // Hata sesi (Windows_Error) için AYRI oynatıcı: bip ile çakışmaz,
  // lowLatency değil normal modda çalar (bip'in modu etkilenmez).
  final AudioPlayer _hataAudio = AudioPlayer();
  Timer? _hataDurdurTimer;
  String? _hataSesYolu; // çalışan dosya yolu bulununca hatırlanır

  /// assets/sounds/ içindeki dosyanın uzantısı bilinmediği için sırayla
  /// denenir; ilk çalışan hatırlanır. Kesin uzantıyı bilirseniz listeyi
  /// tek elemana indirebilirsiniz.
  static const List<String> _hataSesAdaylari = [
    'sounds/Windows_Error.wav',
    'sounds/Windows_Error.mp3',
    'sounds/Windows_Error.ogg',
    'sounds/Windows_Error.m4a',
  ];

  /// Hata sesinin en fazla çalacağı süre (uzun bir dosya olsa bile kesilir).
  static const Duration hataSesiSuresi = Duration(milliseconds: 900);

  // ── Kamera / tarayıcı ayarı (tek merkez) ───────────────────────────────

  /// Market barkodlarının %99'u bu 9 formattan birindedir. Diğerlerini
  /// (Aztec, PDF417, Codabar…) taramak hem yavaşlatır hem yanlış okuma
  /// riskini artırır. Kısıtlanınca native tarayıcı motoru yalnız bu 9
  /// formatı dener.
  static const List<BarcodeFormat> marketFormatlari = [
    BarcodeFormat.ean13,
    BarcodeFormat.ean8,
    BarcodeFormat.upcA,
    BarcodeFormat.upcE,
    BarcodeFormat.code128,
    BarcodeFormat.code39,
    BarcodeFormat.itf,
    BarcodeFormat.qrCode,
    BarcodeFormat.dataMatrix,
  ];

  /// Tüm kamera ekranlarının kullandığı controller fabrikası.
  /// noDuplicates KULLANILMAZ: kasiyer aynı ürünü art arda okutabilmeli;
  /// çift okuma koruması arayüz katmanında (SatisKameraPaneli) yapılır.
  static MobileScannerController tarayiciOlustur({bool autoStart = true}) {
    return MobileScannerController(
      facing: CameraFacing.back,
      formats: marketFormatlari,
      // 1920×1080 — küçük barkodlar da net okunur
      cameraResolution: const Size(1920, 1080),
      detectionSpeed: DetectionSpeed.normal,
      // 7.4.2'de 'detectionTimeoutMs' (int)
      detectionTimeoutMs: 200,
      autoStart: autoStart,
      torchEnabled: false,
    );
  }

  // ── Ses & Titreşim ────────────────────────────────────────────────────

  Future<void> _sesiHazirla() async {
    if (_sesHazir) return;
    _sesHazir = true;
    try {
      await _audio.setPlayerMode(PlayerMode.lowLatency);
    } catch (e) {
      if (kDebugMode) debugPrint('[HATA] $e');
    }
  }

  /// Bip sesi. hizli_satis_ekrani_barkod.dart'taki _bipSes() ile AYNI kalıp
  /// (sahada çalışan): lowLatency modunda her çalmadan ÖNCE stop() şart —
  /// önceki ses bitmeden/bitmiş olarak kalan oynatıcıda play() tekrar
  /// çalmayabiliyor. (Önceki sürümde stop() yoktu → ilk bip sonrası
  /// sessiz kalma riski.)
  Future<void> sesCardir() async {
    try {
      await _sesiHazirla();
      await _audio.stop();
      await _audio.play(AssetSource('sounds/bip.mp3'), volume: 1.0);
    } catch (e) {
      if (kDebugMode) debugPrint('[BIP HATA] $e');
    }
  }

  /// Hata sesi (ör. ürün bulunamadı). Kısa çalar: [hataSesiSuresi] sonunda
  /// dosya daha bitmemiş olsa bile durdurulur. Asla exception fırlatmaz.
  Future<void> hataSesiCal() async {
    try {
      _hataDurdurTimer?.cancel();
      await _hataAudio.stop();
      final adaylar =
          _hataSesYolu != null ? [_hataSesYolu!] : _hataSesAdaylari;
      for (final yol in adaylar) {
        try {
          // Dosya pubspec'te kayıtlı değilse / uzantı yanlışsa burada
          // exception atar → sıradaki aday denenir.
          await _hataAudio.play(AssetSource(yol), volume: 1.0);
        } catch (e) {
          if (kDebugMode) debugPrint('[HATA SESİ] $yol çalınamadı: $e');
          continue;
        }
        _hataSesYolu = yol;
        _hataDurdurTimer = Timer(hataSesiSuresi, () {
          _hataAudio.stop().catchError((_) {});
        });
        return;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[HATA SESİ] $e');
    }
  }

  /// Çift kısa titreşim (bip'in tek uzun titreşiminden ayırt edilir).
  Future<void> hataTitret() async {
    try {
      if ((await Vibration.hasVibrator())) {
        Vibration.vibrate(pattern: [0, 90, 70, 90]);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[HATA] $e');
    }
  }

  /// Ürün bulunamadı gibi durumlarda: hata sesi + çift titreşim birlikte.
  Future<void> hataBildir() async {
    await Future.wait([hataSesiCal(), hataTitret()]);
  }

  Future<void> titret() async {
    try {
      if ((await Vibration.hasVibrator())) {
        Vibration.vibrate(duration: 80);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[HATA] $e');
    }
  }

  /// Ses ve titreşim aynı anda başlar (öncekinde sıralıydı → gecikme).
  Future<void> barkodOkundu() async {
    await Future.wait([sesCardir(), titret()]);
  }

  /// Bir metin kutusuna "yazılan" değer barkod gibi mi? USB okuyucu / el
  /// terminali barkodu klavye gibi yazıp Enter basar; bu yolda kamera
  /// penceresi olmadığı için bip hiçbir yerden gelmiyordu.
  /// 6+ hane rakam, parantezli GS1 ya da GS (FNC1) ayırıcılı veri → barkod.
  /// Ürün adı yazıp Enter'a basan kullanıcıya bip çalmaz.
  static bool barkodaBenzer(String metin) {
    final b = normalizeEt(metin);
    if (b.isEmpty) return false;
    if (RegExp(r'^\d{6,}$').hasMatch(b)) return true;
    if (RegExp(r'^\(\d{2,4}\)').hasMatch(b)) return true;
    return b.contains('\u001D');
  }

  /// Metin kutusunun onSubmitted / onFieldSubmitted'ında çağırın:
  /// değer barkoda benziyorsa bip + titreşim verir, değilse hiçbir şey yapmaz.
  Future<void> girisOkunduBip(String metin) async {
    if (barkodaBenzer(metin)) await barkodOkundu();
  }

  // ── Temel doğrulama ───────────────────────────────────────────────────

  static bool gecerliBarkodMu(String barkod) {
    if (barkod.isEmpty) return false;
    return RegExp(r'^[0-9A-Za-z\-\.\/\+\s]+$').hasMatch(barkod.trim());
  }

  static bool ean13Gecerli(String barkod) {
    if (barkod.length != 13) return false;
    if (!RegExp(r'^\d{13}$').hasMatch(barkod)) return false;
    int toplam = 0;
    for (int i = 0; i < 12; i++) {
      final rakam = int.parse(barkod[i]);
      toplam += i.isEven ? rakam : rakam * 3;
    }
    final beklenen = (10 - (toplam % 10)) % 10;
    return beklenen == int.parse(barkod[12]);
  }

  /// UPC-A (12 hane) = başına 0 eklenmiş EAN-13.
  static bool upcAGecerli(String barkod) {
    if (barkod.length != 12) return false;
    if (!RegExp(r'^\d{12}$').hasMatch(barkod)) return false;
    return ean13Gecerli('0$barkod');
  }

  static bool ean8Gecerli(String barkod) {
    if (barkod.length != 8) return false;
    if (!RegExp(r'^\d{8}$').hasMatch(barkod)) return false;
    int toplam = 0;
    for (int i = 0; i < 7; i++) {
      final rakam = int.parse(barkod[i]);
      toplam += i.isEven ? rakam * 3 : rakam;
    }
    final beklenen = (10 - (toplam % 10)) % 10;
    return beklenen == int.parse(barkod[7]);
  }

  static bool itf14Gecerli(String barkod) {
    if (barkod.length != 14) return false;
    if (!RegExp(r'^\d{14}$').hasMatch(barkod)) return false;
    int toplam = 0;
    for (int i = 0; i < 13; i++) {
      final rakam = int.parse(barkod[i]);
      toplam += i.isEven ? rakam * 3 : rakam;
    }
    final beklenen = (10 - (toplam % 10)) % 10;
    return beklenen == int.parse(barkod[13]);
  }

  // ── Normalizasyon & ürün arama kodları ────────────────────────────────

  /// Okuyucudan/kameradan gelen ham değerin başındaki/sonundaki boşluk ve
  /// kontrol karakterlerini (CR, LF, TAB, GS…) temizler.
  static String normalizeEt(String ham) {
    return ham
        .replaceAll(RegExp(r'^[\u0000- \u007F]+'), '')
        .replaceAll(RegExp(r'[\u0000- \u007F]+$'), '');
  }

  /// Ürün veritabanında denenecek eşdeğer kodlar (ilki okunan değerdir).
  ///  • 12 hane (UPC-A)            → '0' + kod
  ///  • 13 hane ve 0 ile başlıyor → baştaki 0 atılmış hali (UPC-A)
  ///  • 14 hane ve 0 ile başlıyor → GTIN-14'ün EAN-13 karşılığı
  /// iOS UPC-A'yı 13 hane, Android 12 hane döndürür; depoda hangisi
  /// kayıtlıysa bulunsun diye hepsi denenmelidir.
  static List<String> aramaKodlari(String barkod) {
    final b = normalizeEt(barkod);
    final sonuc = <String>[];
    void ekle(String s) {
      if (s.isNotEmpty && !sonuc.contains(s)) sonuc.add(s);
    }

    ekle(b);
    if (RegExp(r'^\d+$').hasMatch(b)) {
      if (b.length == 12) ekle('0$b');
      if ((b.length == 13 || b.length == 14) && b.startsWith('0')) {
        ekle(b.substring(1));
      }
    }
    return sonuc;
  }

  // ── GS1-TR Barkod Türü Tespiti ────────────────────────────────────────

  static BarkodTuru barkodTurunuBul(String barkod) {
    final b = normalizeEt(barkod);
    if (b.isEmpty) return BarkodTuru.bilinmiyor;

    final sadeceRakam = RegExp(r'^\d+$').hasMatch(b);

    if (sadeceRakam) {
      if (b.length == 14) return BarkodTuru.itf14;

      if (b.length == 13) {
        final prefix2 = int.tryParse(b.substring(0, 2)) ?? 0;
        if (prefix2 >= 20 && prefix2 <= 29) return BarkodTuru.tartimEan13;
        final prefix3 = int.tryParse(b.substring(0, 3)) ?? 0;
        if (prefix3 == 868 || prefix3 == 869) return BarkodTuru.ean13Turkiye;
        return BarkodTuru.ean13;
      }

      // UPC-A (12 hane) EAN-13 ailesindendir
      if (b.length == 12) return BarkodTuru.ean13;

      if (b.length == 8) return BarkodTuru.ean8;

      if (b.length >= 4 && b.length <= 5) return BarkodTuru.plu;

      // Ayırıcısız GS1-128 (ör. 01 + GTIN-14 + 17 + tarih ...)
      if (b.length >= 16 &&
          (b.startsWith('01') || b.startsWith('02') || b.startsWith('00'))) {
        return BarkodTuru.gs1128;
      }
    }

    // Parantezli veya FNC1/GS ayırıcılı GS1 verisi
    if (b.startsWith('(') || b.contains('\u001D')) return BarkodTuru.gs1128;

    if (b.length > 20) return BarkodTuru.qrDataMatrix;

    return BarkodTuru.serbest;
  }

  // ── GS1-TR Tartım Barkodu Çözme ──────────────────────────────────────

  static TartimBarkodSonuc? tartimBarkodCoz(String barkod) {
    if (barkod.length != 13) return null;
    if (!RegExp(r'^\d{13}$').hasMatch(barkod)) return null;

    final prefix = int.parse(barkod.substring(0, 2));
    if (prefix < 20 || prefix > 29) return null;

    if (!ean13Gecerli(barkod)) return null;

    final urunKodu = barkod.substring(2, 7);
    final miktarStr = barkod.substring(7, 12);

    final miktarGram = int.tryParse(miktarStr);
    if (miktarGram == null || miktarGram <= 0) return null;

    return TartimBarkodSonuc(
      urunKodu: urunKodu,
      miktarGram: miktarGram,
      miktarKg: miktarGram / 1000.0,
      prefix: prefix,
      tamBarkod: barkod,
    );
  }

  // ── GS1-128 Application Identifier Çözme ─────────────────────────────

  /// Sabit uzunluklu AI'lar (AI → veri uzunluğu)
  static const Map<String, int> _sabitAi = {
    '00': 18, '01': 14, '02': 14,
    '11': 6, '12': 6, '13': 6, '15': 6, '16': 6, '17': 6,
    '20': 2,
    '410': 13, '411': 13, '412': 13, '413': 13,
    '414': 13, '415': 13, '416': 13, '417': 13,
  };

  /// Değişken uzunluklu AI'lar (AI → azami veri uzunluğu)
  static const Map<String, int> _degiskenAi = {
    '10': 20, '21': 20, '22': 20,
    '30': 8, '37': 8,
    '240': 30, '241': 30,
    '90': 30, '91': 90, '92': 90, '93': 90, '94': 90,
    '95': 90, '96': 90, '97': 90, '98': 90, '99': 90,
  };

  /// Çıktı anahtarları: 'AI_01', 'AI_10', 'AI_17', 'AI_3103' ...
  /// Ayrıştırma:
  ///  • "(01)0868...(17)261231(10)LOT1" parantezli biçim
  ///  • FNC1/GS (\x1D) ayırıcılı ham biçim
  ///  • Ayırıcısız ham biçim (değişken AI'da azami uzunluğa kadar okur)
  static Map<String, String> gs1128Coz(String barkod) {
    final sonuc = <String, String>{};
    final giris = barkod.trim();
    if (giris.isEmpty) return sonuc;

    // Parantezli biçim — kesin ayrım
    if (giris.contains('(')) {
      for (final m in RegExp(r'\((\d{2,4})\)([^(]*)').allMatches(giris)) {
        sonuc['AI_${m.group(1)}'] = m.group(2)!.replaceAll('\u001D', '');
      }
      return sonuc;
    }

    final b = giris;
    int i = 0;
    while (i < b.length) {
      if (b[i] == '\u001D') {
        i++;
        continue;
      }

      // AI'yı bul: 4 haneli (31xx–36xx) → 3 haneli → 2 haneli
      String? ai;
      int? sabit;
      int? azami;

      if (i + 4 <= b.length) {
        final iki = b.substring(i, i + 2);
        if (RegExp(r'^3[1-6]$').hasMatch(iki)) {
          ai = b.substring(i, i + 4);
          sabit = 6; // ağırlık / boyut / hacim değerleri 6 hane
        }
      }
      if (ai == null && i + 3 <= b.length) {
        final uc = b.substring(i, i + 3);
        if (_sabitAi.containsKey(uc)) {
          ai = uc;
          sabit = _sabitAi[uc];
        } else if (_degiskenAi.containsKey(uc)) {
          ai = uc;
          azami = _degiskenAi[uc];
        }
      }
      if (ai == null && i + 2 <= b.length) {
        final iki = b.substring(i, i + 2);
        if (_sabitAi.containsKey(iki)) {
          ai = iki;
          sabit = _sabitAi[iki];
        } else if (_degiskenAi.containsKey(iki)) {
          ai = iki;
          azami = _degiskenAi[iki];
        }
      }

      // Bilinmeyen AI → daha fazla tahmin yürütmeden dur
      if (ai == null) break;

      i += ai.length;
      String deger;
      if (sabit != null) {
        final son = (i + sabit).clamp(0, b.length).toInt();
        deger = b.substring(i, son);
        i = son;
      } else {
        final gs = b.indexOf('\u001D', i);
        final sinir = (i + azami!).clamp(0, b.length).toInt();
        final son = (gs != -1 && gs < sinir) ? gs : sinir;
        deger = b.substring(i, son);
        i = son;
      }
      sonuc['AI_$ai'] = deger;
    }

    return sonuc;
  }

  String duzeltBarkod(String barkod) =>
      barkod.trim().replaceAll(RegExp(r'\s+'), '');

  // ── Barkod tarama dialog ──────────────────────────────────────────────

  Future<String?> barkodTara(BuildContext context) async {
    // Windows: kamera yok — USB okuyucu klavye gibi yazar; metin kutusu açılır.
    // Kamera penceresindeki bip burada devrede olmadığı için okutma sonucu
    // dönünce bip BURADA çalınır (önceden bu yolda hiç ses yoktu).
    if (Platform.isWindows) {
      final sonuc = await _masaustuBarkodSor(context);
      if (sonuc != null && sonuc.trim().isNotEmpty) barkodOkundu();
      return sonuc;
    }
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const BarkodTaramaDialog(),
    );
  }
}

Future<String?> _masaustuBarkodSor(BuildContext context) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Barkod'),
      content: SizedBox(
        width: 360,
        child: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Barkodu okutun veya yazın',
            prefixIcon: Icon(Icons.qr_code_scanner),
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) =>
              Navigator.pop(ctx, v.trim().isEmpty ? null : v.trim()),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
        FilledButton(
          onPressed: () => Navigator.pop(
              ctx, ctrl.text.trim().isEmpty ? null : ctrl.text.trim()),
          child: const Text('Tamam'),
        ),
      ],
    ),
  ).whenComplete(() => dialogSonrasiBirak([ctrl]));
}

// ── Veri modelleri ────────────────────────────────────────────────────────

enum BarkodTuru {
  ean13,
  ean13Turkiye,
  tartimEan13,
  ean8,
  itf14,
  plu,
  gs1128,
  qrDataMatrix,
  serbest,
  bilinmiyor,
}

class TartimBarkodSonuc {
  final String urunKodu;
  final int miktarGram;
  final double miktarKg;
  final int prefix;
  final String tamBarkod;

  const TartimBarkodSonuc({
    required this.urunKodu,
    required this.miktarGram,
    required this.miktarKg,
    required this.prefix,
    required this.tamBarkod,
  });

  @override
  String toString() =>
      'TartimBarkod(urun=$urunKodu, miktar=${miktarKg}kg, prefix=$prefix)';
}

// ── Barkod Tarama Dialog (public) ────────────────────────────────────────

class BarkodTaramaDialog extends StatefulWidget {
  const BarkodTaramaDialog({super.key});

  @override
  State<BarkodTaramaDialog> createState() => _BarkodTaramaDialogState();
}

class _BarkodTaramaDialogState extends State<BarkodTaramaDialog> {
  MobileScannerController? _ctrl;
  bool _taramaTamamlandi = false;
  bool _kameraHatasi = false;
  String? _hataMesaji;

  // Zoom: 0.0 = 1x, 1.0 = cihazın azami yakınlaştırması
  // (mobile_scanner setZoomScale 0.0–1.0 aralığını bekler)
  double _zoom = 0.0;
  double _zoomBaslangic = 0.0;

  @override
  void initState() {
    super.initState();
    _controllerOlustur();
  }

  void _controllerOlustur() {
    try {
      _ctrl = BarkodServisi.tarayiciOlustur();
    } catch (e) {
      _kameraHatasi = true;
      _hataMesaji = 'Kamera başlatılamadı: $e';
      if (kDebugMode) debugPrint('[KAMERA HATA] $e');
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  void _barkodBulundu(String barkod) {
    if (_taramaTamamlandi) return;
    final temiz = BarkodServisi.normalizeEt(barkod);
    if (temiz.isEmpty) return;
    _taramaTamamlandi = true;
    BarkodServisi().barkodOkundu();
    Navigator.pop(context, temiz);
  }

  void _algilandi(BarcodeCapture capture) {
    for (final b in capture.barcodes) {
      final raw = b.rawValue;
      if (raw != null && raw.trim().isNotEmpty) {
        _barkodBulundu(raw);
        return;
      }
    }
  }

  Future<void> _zoomAyarla(double yeni) async {
    final ctrl = _ctrl;
    if (ctrl == null) return;
    final z = yeni.clamp(0.0, 1.0).toDouble();
    if ((z - _zoom).abs() < 0.001) return;
    setState(() => _zoom = z);
    try {
      await ctrl.setZoomScale(z);
    } catch (_) {
      // Kamera hazır değil / cihaz zoom desteklemiyor → yoksay
    }
  }

  Future<void> _yenidenDene() async {
    try {
      await _ctrl?.start();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final yukseklik = MediaQuery.of(context).size.height;
    return Container(
      height: yukseklik * 0.75,
      decoration: const BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(children: [
        // Üst sap
        Container(
          margin: const EdgeInsets.only(top: 12),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.white38,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        // Başlık + aksiyonlar
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Barkod Tara',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              Row(children: [
                // Işık — kameranın gerçek torch durumunu gösterir
                _isikButonu(),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                  tooltip: 'Kapat',
                ),
              ]),
            ],
          ),
        ),
        // Kamera alanı
        Expanded(
          child: _kameraHatasi
              ? _hataEkrani()
              : LayoutBuilder(builder: (context, c) {
                  // scanWindow ekranın ortasında; hedef çerçevesi de
                  // AYNI dikdörtgen — kullanıcı gerçek tarama alanını görür.
                  final scanRect = Rect.fromCenter(
                    center: Offset(c.maxWidth / 2, c.maxHeight / 2),
                    width: c.maxWidth * 0.85,
                    height: c.maxHeight * 0.38,
                  );
                  return Stack(children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(16)),
                      // İki parmakla kıstırarak zoom
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onScaleStart: (_) => _zoomBaslangic = _zoom,
                        onScaleUpdate: (d) {
                          if (d.pointerCount < 2) return;
                          _zoomAyarla(_zoomBaslangic + (d.scale - 1.0) * 0.5);
                        },
                        child: MobileScanner(
                          controller: _ctrl,
                          scanWindow: scanRect,
                          onDetect: _algilandi,
                          errorBuilder: (context, error) => _hataEkrani(
                              hata: error),
                        ),
                      ),
                    ),
                    // 🎯 Hedef çerçevesi — scanWindow ile bire bir hizalı
                    Positioned.fromRect(
                      rect: scanRect,
                      child: IgnorePointer(
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: Colors.greenAccent, width: 2.5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    // 🎯 Köşelerde kısa kılavuz çizgiler (görsel vurgu)
                    Positioned.fromRect(
                      rect: scanRect,
                      child: const IgnorePointer(child: _TaramaKoseleri()),
                    ),
                    // Zoom kaydırıcısı
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Row(children: [
                          const Icon(Icons.zoom_out,
                              color: Colors.white70, size: 20),
                          Expanded(
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor: Colors.greenAccent,
                                inactiveTrackColor: Colors.white24,
                                thumbColor: Colors.greenAccent,
                                overlayColor: Colors.greenAccent.withAlpha(40),
                              ),
                              child: Slider(
                                value: _zoom,
                                onChanged: _zoomAyarla,
                              ),
                            ),
                          ),
                          const Icon(Icons.zoom_in,
                              color: Colors.white70, size: 20),
                        ]),
                      ),
                    ),
                  ]);
                }),
        ),
        // Alt ipucu + manuel giriş
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('Barkodu yeşil çerçeve içine getirin',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
        ),
        Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              left: 16,
              right: 16),
          child: _ManuelBarkodGirisi(onBarkod: _barkodBulundu),
        ),
      ]),
    );
  }

  Widget _isikButonu() {
    final ctrl = _ctrl;
    if (ctrl == null) {
      return const IconButton(
        icon: Icon(Icons.flash_off, color: Colors.white24),
        onPressed: null,
      );
    }
    return ValueListenableBuilder<MobileScannerState>(
      valueListenable: ctrl,
      builder: (_, durum, _) {
        final acik = durum.torchState == TorchState.on;
        return IconButton(
          icon: Icon(acik ? Icons.flash_on : Icons.flash_off,
              color: acik ? Colors.amber : Colors.white),
          tooltip: 'Işık',
          onPressed: () async {
            try {
              await ctrl.toggleTorch();
            } catch (_) {
              // Cihazın torch'u yoksa sessizce yoksay
            }
          },
        );
      },
    );
  }

  Widget _hataEkrani({MobileScannerException? hata}) {
    final izinYok = hata?.errorCode == MobileScannerErrorCode.permissionDenied;
    final mesaj = izinYok
        ? 'Kamera izni verilmedi. Barkod okutmak için izin vermelisiniz.'
        : hata != null
            ? 'Kamera hatası: ${hata.errorCode.name}'
            : (_hataMesaji ?? 'Kamera kullanılamıyor');
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_outlined,
                color: Colors.white54, size: 64),
            const SizedBox(height: 16),
            Text(
              mesaj,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              alignment: WrapAlignment.center,
              children: [
                if (izinYok)
                  FilledButton.tonal(
                    onPressed: () => openAppSettings(),
                    child: const Text('Ayarları Aç'),
                  ),
                if (_ctrl != null)
                  OutlinedButton(
                    onPressed: _yenidenDene,
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70),
                    child: const Text('Tekrar Dene'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Manuel giriş kutusuna barkodu yazabilirsiniz.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tarama çerçevesinin 4 köşesinde kısa, kalın çizgiler — görsel vurgu.
class _TaramaKoseleri extends StatelessWidget {
  const _TaramaKoseleri();

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      _kose(Alignment.topLeft),
      _kose(Alignment.topRight),
      _kose(Alignment.bottomLeft),
      _kose(Alignment.bottomRight),
    ]);
  }

  Widget _kose(Alignment hizala) {
    final ustMu = hizala.y < 0;
    final solMu = hizala.x < 0;
    return Align(
      alignment: hizala,
      child: SizedBox(
        width: 24,
        height: 24,
        child: CustomPaint(
          painter: _KoseBoyaci(ust: ustMu, sol: solMu),
        ),
      ),
    );
  }
}

class _KoseBoyaci extends CustomPainter {
  final bool ust;
  final bool sol;
  _KoseBoyaci({required this.ust, required this.sol});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.greenAccent
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final x = sol ? 0.0 : size.width;
    final y = ust ? 0.0 : size.height;
    // Yatay çizgi (köşeden içeriye)
    canvas.drawLine(
      Offset(x, y),
      Offset(sol ? size.width / 2 : size.width / 2, y),
      paint,
    );
    // Dikey çizgi (köşeden içeriye)
    canvas.drawLine(
      Offset(x, y),
      Offset(x, ust ? size.height / 2 : size.height / 2),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _KoseBoyaci old) =>
      old.ust != ust || old.sol != sol;
}

class _ManuelBarkodGirisi extends StatefulWidget {
  final void Function(String) onBarkod;
  const _ManuelBarkodGirisi({required this.onBarkod});
  @override
  State<_ManuelBarkodGirisi> createState() => _ManuelBarkodGirisiState();
}

class _ManuelBarkodGirisiState extends State<_ManuelBarkodGirisi> {
  final _ctrl = TextEditingController();
  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
          child: TextField(
            controller: _ctrl,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Barkod numarası gir...',
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: Colors.white12,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onSubmitted: (v) {
              if (v.trim().isNotEmpty) widget.onBarkod(v.trim());
            },
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: () {
            if (_ctrl.text.trim().isNotEmpty) {
              widget.onBarkod(_ctrl.text.trim());
            }
          },
          style: FilledButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: const Color(0xFF4361EE),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          ),
          child: const Text('Ara', style: TextStyle(color: Colors.white)),
        ),
      ]);
}
