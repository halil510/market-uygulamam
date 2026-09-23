// lib/servisler/barkod_servisi.dart
//
// GS1-TR Türkiye standardına tam uyum:
//  - EAN-13 check digit doğrulama
//  - GS1-TR tartım barkodu (prefix 20-29): 5 haneli ağırlık (gram)
//  - GS1-128 / GS1-DataMatrix Application Identifier desteği
//  - ITF-14 lojistik barkod tanıma
//  - Türkiye'ye özel prefix'ler (868-869)
//  - PLU kodu tanıma (4-5 haneli, 0xxxx ile başlayan)
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';

/// GS1-TR Türkiye Barkod Standardı
/// Kaynak: GS1 Türkiye (gs1tr.org)
class BarkodServisi {
  static final BarkodServisi _instance = BarkodServisi._internal();
  factory BarkodServisi() => _instance;
  BarkodServisi._internal();

  final AudioPlayer _audio = AudioPlayer();

  // ── Ses & Titreşim ────────────────────────────────────────────────────

  Future<void> sesCardir() async {
    try {
      await _audio.play(AssetSource('sounds/bip.mp3'));
    } catch (e) { if (kDebugMode) debugPrint('[HATA] ' + e.toString()); }
  }

  Future<void> titret() async {
    try {
      if ((await Vibration.hasVibrator())) {
        Vibration.vibrate(duration: 80);
      }
    } catch (e) { if (kDebugMode) debugPrint('[HATA] ' + e.toString()); }
  }

  Future<void> barkodOkundu() async {
    await sesCardir();
    await titret();
  }

  // ── Temel doğrulama ───────────────────────────────────────────────────

  /// Genel geçerli barkod karakterleri
  static bool gecerliBarkodMu(String barkod) {
    if (barkod.isEmpty) return false;
    return RegExp(r'^[0-9A-Za-z\-\.\/\+\s]+$').hasMatch(barkod.trim());
  }

  /// EAN-13 kontrol basamağı doğrulama (GS1 algoritması)
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

  /// EAN-8 kontrol basamağı doğrulama
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

  /// ITF-14 kontrol basamağı doğrulama (lojistik/koli barkodu)
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

  // ── GS1-TR Barkod Türü Tespiti ────────────────────────────────────────

  /// Barkod türünü tespit eder
  static BarkodTuru barkodTurunuBul(String barkod) {
    final b = barkod.trim();
    if (b.isEmpty) return BarkodTuru.bilinmiyor;

    // ITF-14 (14 hane) — lojistik/koli
    if (b.length == 14 && RegExp(r'^\d{14}$').hasMatch(b)) {
      return BarkodTuru.itf14;
    }

    // EAN-13
    if (b.length == 13 && RegExp(r'^\d{13}$').hasMatch(b)) {
      final prefix2 = int.tryParse(b.substring(0, 2)) ?? 0;
      // GS1-TR Tartım (20-29): işletme içi tartımlı ürün
      if (prefix2 >= 20 && prefix2 <= 29) return BarkodTuru.tartimEan13;
      // Türkiye GS1 prefix (868-869)
      final prefix3 = int.tryParse(b.substring(0, 3)) ?? 0;
      if (prefix3 == 868 || prefix3 == 869) return BarkodTuru.ean13Turkiye;
      return BarkodTuru.ean13;
    }

    // EAN-8 (kısa ürün)
    if (b.length == 8 && RegExp(r'^\d{8}$').hasMatch(b)) {
      return BarkodTuru.ean8;
    }

    // PLU (Price Look-Up) — 4-5 haneli, kasalarda kullanılan
    if (b.length >= 4 && b.length <= 5 && RegExp(r'^\d+$').hasMatch(b)) {
      return BarkodTuru.plu;
    }

    // GS1-128 / GS1-DataMatrix (Application Identifier ile başlar)
    if (b.startsWith('(01)') || b.startsWith('01') ||
        RegExp(r'^\(?\d{2}\)?').hasMatch(b)) {
      return BarkodTuru.gs1128;
    }

    // QR / DataMatrix (alfanümerik, uzun)
    if (b.length > 20) return BarkodTuru.qrDataMatrix;

    return BarkodTuru.serbest;
  }

  // ── GS1-TR Tartım Barkodu Çözme ──────────────────────────────────────

  /// GS1-TR EAN-13 tartım barkodunu çözümler.
  ///
  /// Türkiye standardı (GS1 Türkiye):
  ///   Pozisyon 0-1  : prefix (20-29)
  ///   Pozisyon 2-6  : ürün kodu (5 hane)
  ///   Pozisyon 7-11 : ağırlık/miktar (5 hane, gram cinsinden)
  ///   Pozisyon 12   : kontrol basamağı
  ///
  /// Örnek: 2 1 2345 01234 5  → prefix=21, ürün=12345, ağırlık=1234g=1.234kg
  static TartimBarkodSonuc? tartimBarkodCoz(String barkod) {
    if (barkod.length != 13) return null;
    if (!RegExp(r'^\d{13}$').hasMatch(barkod)) return null;

    final prefix = int.parse(barkod.substring(0, 2));
    if (prefix < 20 || prefix > 29) return null;

    // Kontrol basamağı doğrula
    if (!ean13Gecerli(barkod)) return null;

    // GS1-TR Standart: 2 prefix + 5 ürün kodu + 5 miktar + 1 kontrol
    final urunKodu  = barkod.substring(2, 7);   // 5 hane
    final miktarStr = barkod.substring(7, 12);  // 5 hane

    final miktarGram = int.tryParse(miktarStr);
    if (miktarGram == null || miktarGram <= 0) return null;

    return TartimBarkodSonuc(
      urunKodu:    urunKodu,
      miktarGram:  miktarGram,
      miktarKg:    miktarGram / 1000.0,
      prefix:      prefix,
      tamBarkod:   barkod,
    );
  }

  // ── GS1-128 Application Identifier Çözme ─────────────────────────────

  /// GS1-128 barkodundan GTIN ve diğer alanları ayıklar
  static Map<String, String> gs1128Coz(String barkod) {
    final sonuc = <String, String>{};
    // Parantezleri kaldır, AI'ları işle
    var b = barkod.replaceAll('(', '').replaceAll(')', '');

    final ailar = <String, int>{
      '01': 14, '02': 14, '10': -1, '11': 6,  '13': 6,  '15': 6,
      '17': 6,  '20': 2,  '21': -1, '30': -1, '310': 6, '311': 6,
      '37': -1, '90': -1, '91': -1, '92': -1,
    };

    int i = 0;
    while (i < b.length) {
      bool bulundu = false;
      // Önce 3 haneli AI dene, sonra 2 haneli
      for (final uzunluk in [3, 2]) {
        if (i + uzunluk > b.length) continue;
        final ai = b.substring(i, i + uzunluk);
        if (ailar.containsKey(ai)) {
          i += uzunluk;
          final sabitUzunluk = ailar[ai]!;
          String deger;
          if (sabitUzunluk > 0) {
            deger = b.substring(i, (i + sabitUzunluk).clamp(0, b.length));
            i += sabitUzunluk;
          } else {
            // Değişken uzunluk — FNC1 veya sonraki AI'ya kadar
            final sonraki = b.indexOf(RegExp(r'(?=0[12]\d|10\d|17\d|21\d|30\d|37\d)'), i);
            deger = sonraki > i ? b.substring(i, sonraki) : b.substring(i);
            i += deger.length;
          }
          sonuc['AI_$ai'] = deger;
          bulundu = true;
          break;
        }
      }
      if (!bulundu) i++; // Bilinmeyen karakter, atla
    }

    return sonuc;
  }

  // ── Barkod temizle ────────────────────────────────────────────────────

  String duzeltBarkod(String barkod) =>
      barkod.trim().replaceAll(RegExp(r'\s+'), '');

  // ── Barkod tarama dialog ──────────────────────────────────────────────

  Future<String?> barkodTara(BuildContext context) async {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _BarkodTaramaDialog(),
    );
  }
}

// ── Veri modelleri ────────────────────────────────────────────────────────

enum BarkodTuru {
  ean13,          // Standart EAN-13
  ean13Turkiye,   // Türkiye prefix (868-869)
  tartimEan13,    // GS1-TR tartım (prefix 20-29)
  ean8,           // EAN-8 kısa ürün
  itf14,          // ITF-14 lojistik/koli
  plu,            // PLU (4-5 haneli fiyat kodu)
  gs1128,         // GS1-128 / DataMatrix
  qrDataMatrix,   // QR Code / Data Matrix (URL veya serbest metin)
  serbest,        // Serbest metin barkod
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

// ── Barkod Tarama Dialog ──────────────────────────────────────────────────

class _BarkodTaramaDialog extends StatefulWidget {
  const _BarkodTaramaDialog();
  @override
  State<_BarkodTaramaDialog> createState() => _BarkodTaramaDialogState();
}

class _BarkodTaramaDialogState extends State<_BarkodTaramaDialog> {
  MobileScannerController? _ctrl;
  bool _flash = false;
  bool _taramaTamamlandi = false;
  String? _sonBarkod;
  DateTime? _sonZaman;

  @override
  void initState() {
    super.initState();
    _ctrl = MobileScannerController(facing: CameraFacing.back);
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  void _barkodBulundu(String barkod) {
    if (_taramaTamamlandi) return;
    // 1 saniye debounce — aynı barkod tekrar işlenmesin
    if (_sonBarkod == barkod &&
        _sonZaman != null &&
        DateTime.now().difference(_sonZaman!) <
            const Duration(milliseconds: 1000)) return;
    _sonBarkod  = barkod;
    _sonZaman   = DateTime.now();
    _taramaTamamlandi = true;

    BarkodServisi().barkodOkundu();
    Navigator.pop(context, barkod);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.65,
      decoration: const BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(children: [
        Container(
          margin: const EdgeInsets.only(top: 12),
          width: 40, height: 4,
          decoration: BoxDecoration(
              color: Colors.white38,
              borderRadius: BorderRadius.circular(2)),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Barkod Tara',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                Row(children: [
                  IconButton(
                    icon: Icon(
                        _flash ? Icons.flash_on : Icons.flash_off,
                        color: Colors.white),
                    onPressed: () {
                      setState(() => _flash = !_flash);
                      _ctrl?.toggleTorch();
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ]),
              ]),
        ),
        Expanded(
          child: Stack(children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: MobileScanner(
                controller: _ctrl!,
                onDetect: (capture) {
                  final barcode = capture.barcodes.firstOrNull;
                  if (barcode?.rawValue != null) {
                    _barkodBulundu(barcode!.rawValue!);
                  }
                },
              ),
            ),
            // Hedef çerçevesi
            Center(
              child: Container(
                width: 250, height: 120,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.green, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ]),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('Barkodu yeşil çerçeve içine getirin',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
        ),
        Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              left: 16, right: 16),
          child: _ManuelBarkodGirisi(onBarkod: _barkodBulundu),
        ),
      ]),
    );
  }
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
  void dispose() { _ctrl.dispose(); super.dispose(); }

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
          filled: true, fillColor: Colors.white12,
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
        if (_ctrl.text.trim().isNotEmpty) widget.onBarkod(_ctrl.text.trim());
      },
      style: FilledButton.styleFrom(
        foregroundColor: Colors.white,
          backgroundColor: const Color(0xFF4361EE),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10)),
        padding:
            const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      ),
      child: const Text('Ara', style: TextStyle(color: Colors.white)),
    ),
  ]);
}
