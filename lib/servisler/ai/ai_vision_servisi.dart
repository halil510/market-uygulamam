// lib/servisler/ai/ai_vision_servisi.dart
// SADECE GEMINI KULLANAN VERSİYON – Diğer parse yöntemleri devre dışı

import 'dart:io';
import 'ai_model_secici.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:printing/printing.dart';
import '../../modeller/ocr_urun_model.dart';

class AiVisionServisi {
  static final AiVisionServisi _i = AiVisionServisi._();
  factory AiVisionServisi() => _i;
  AiVisionServisi._();

  static const _guvenliDepo = FlutterSecureStorage();
  static const _kApiKey = 'gemini_api_key';

  final TextRecognizer _recognizer =
      TextRecognizer(script: TextRecognitionScript.latin);

  // ---- API Anahtarını yönet ----
  String? _cachedApiKey;

  // 🔴 DÜZELTME: API anahtarı düz metin SharedPreferences'ta
  // saklanıyordu — GİB ve mail kimlik bilgileri (aynı hassasiyet
  // düzeyinde) zaten cihazın güvenli deposunda (Keychain/Keystore)
  // saklanıyor, bu tutarsızdı. Artık güvenli depoya taşındı; eski
  // konumda kayıtlı bir anahtar varsa (geriye dönük uyumluluk için)
  // otomatik olarak göç ettirilip eski konumdan silinir.
  Future<String?> _getApiKey() async {
    if (_cachedApiKey != null && _cachedApiKey!.isNotEmpty) {
      return _cachedApiKey;
    }
    var key = await _guvenliDepo.read(key: _kApiKey);
    if (key == null || key.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final eskiKey = prefs.getString(_kApiKey);
      if (eskiKey != null && eskiKey.isNotEmpty) {
        key = eskiKey;
        await _guvenliDepo.write(key: _kApiKey, value: eskiKey);
        await prefs.remove(_kApiKey);
      }
    }
    if (key != null && key.isNotEmpty) {
      _cachedApiKey = key;
      return key;
    }
    return null;
  }

  /// Aynı Gemini API anahtarı diğer AI özellikleri (sohbet asistanı gibi)
  /// tarafından da kullanılabilsin diye genel erişime açık.
  Future<String?> apiKeyGetir() => _getApiKey();
  Future<bool> apiKeyVarMi() async => (await _getApiKey())?.isNotEmpty ?? false;

  Future<void> setApiKey(String key) async {
    await _guvenliDepo.write(key: _kApiKey, value: key);
    _cachedApiKey = key;
  }

  // ---- ANA METOT (SADECE GEMINI) ----
  Future<List<OcrUrunModel>> faturaFotografindanUrunCikar(dynamic kaynak) async {
    try {
      // 🔴🔴🔴 KRİTİK "EKSİKLİK" DÜZELTMESİ (kullanıcı isteği — "asistanları
      // derinlemesine test et"): Bu dosyanın adı "Vision Servisi" ama
      // GERÇEK Gemini vision (görüntü) yeteneği HİÇ KULLANILMIYORDU —
      // sadece cihaz-üstü OCR (Google ML Kit) ile metin çıkarılıp o metin
      // Gemini'ye gönderiliyordu. OCR boş/anlamsız sonuç verdiğinde
      // (bulanık, eğik, soluk termal yazıcı çıktısı gibi ÇOK yaygın
      // fatura fotoğrafı sorunlarında), Gemini'ye HİÇ ŞANS VERİLMEDEN
      // doğrudan boş liste dönülüyordu — oysa Gemini'nin gerçek görsel
      // anlama yeteneği, OCR'ın tamamen başarısız olduğu bulanık/eğik
      // fotoğraflarda bile genellikle metni okuyabilir.
      //
      // Yeni akış: önce (hızlı, ucuz) cihaz-üstü OCR + metin tabanlı
      // yapılandırma denenir; SONUÇ BOŞ/YETERSİZSE, aynı fotoğraf
      // doğrudan (OCR atlanarak) Gemini'nin görsel girişine gönderilir.
      // Kullanıcı iki kat daha güvenilir bir sonuç alır, hız/maliyet
      // avantajı olan yol çoğu net fotoğrafta zaten yeterli olacaktır.
      final apiKey = await _getApiKey();
      if (apiKey == null || apiKey.isEmpty) {
        if (kDebugMode) debugPrint('Gemini API anahtarı eksik!');
        return [];
      }

      // 1. Önce (hızlı/ucuz) cihaz-üstü OCR + metin yapılandırma dene
      final ocrResult = await _ocrKoordinatliCikar(kaynak);
      if (ocrResult != null && ocrResult.text.trim().length >= 8) {
        final hamMetin = ocrResult.text;
        if (kDebugMode) {
          debugPrint('===== OCR HAM METİN =====');
          debugPrint(hamMetin);
          debugPrint('==========================');
        }
        final llmSonuc = await _llmIleYapilandir(hamMetin, apiKey);
        if (llmSonuc != null && llmSonuc.isNotEmpty) {
          return llmSonuc.map((json) => OcrUrunModel.fromJson(json)
            ..guven = 0.95).toList();
        }
      } else if (kDebugMode) {
        debugPrint('OCR metin boş/çok kısa — doğrudan Gemini görsel analizine geçiliyor');
      }

      // 2. OCR başarısız/yetersiz OLDUYSA ya da metinden hiç ürün
      // çıkmadıysa: aynı fotoğrafı DOĞRUDAN Gemini'nin görsel girişine
      // gönder (gerçek vision — OCR'ı tamamen atlar).
      final gorselYolu = await _gorselYoluAl(kaynak);
      if (gorselYolu == null) return [];
      final gorselSonuc = await _llmIleGorseldenCikar(gorselYolu, apiKey);
      if (gorselSonuc != null && gorselSonuc.isNotEmpty) {
        return gorselSonuc.map((json) => OcrUrunModel.fromJson(json)
          ..guven = 0.85).toList();
      }

      return [];
    } catch (e, st) {
      if (kDebugMode) debugPrint('Fatura okuma hatası: $e\n$st');
      return [];
    }
  }

  // ---- OCR'den koordinatlı sonuç al ----
  Future<RecognizedText?> _ocrKoordinatliCikar(dynamic kaynak) async {
    final path = await _gorselYoluAl(kaynak);
    if (path == null) return null;
    final inputImage = InputImage.fromFilePath(path);
    return await _recognizer.processImage(inputImage);
  }

  // ---- GEMINI FALLBACK (Ana yöntem) ----
  Future<List<Map<String, dynamic>>?> _llmIleYapilandir(String hamMetin, String apiKey) async {
    try {
      final model = GenerativeModel(
        // 'gemini-1.5-flash' kapatıldı (tüm 1.x serisi, 404 hatası
        // veriyordu). 🔴 PROFESYONELLEŞTİRME DÜZELTMESİ: bir süre
        // 'gemini-flash-latest' takma adı kullanıldı ama Google'ın
        // kendisi bunu "genellikle production için uygun değil,
        // deneysel, daha kısıtlı rate limit" diye tanımlıyor. Kararlı
        // 'gemini-2.5-flash' sürümüne geçildi (bkz. ai_genel_asistan.dart).
        model: await AiModelSecici.ilkAday(),
        apiKey: apiKey,
        // 🔴 KÖK NEDEN DÜZELTMESİ (kullanıcı bulgusu — "fatura
        // fotoğrafından textlere düzgün işlemiyor"): ÖNCEDEN bu model
        // JSON zorunluluğu OLMADAN çağrılıyordu — "Sadece JSON çıktısı
        // ver" talimatına RAĞMEN Gemini sık sık JSON'un öncesine/
        // sonrasına açıklama metni ("İşte çıkardığım ürünler:" gibi)
        // ekliyordu. Aşağıdaki ```/``` temizleme regex'i SADECE markdown
        // kod bloğu kalıbını temizliyordu — blok DIŞINDAKİ serbest metni
        // temizlemiyordu, bu da jsonDecode()'un ATMASINA ve TÜM
        // faturanın sessizce "çıkarılamadı" sayılmasına yol açıyordu.
        // responseMimeType: 'application/json' Gemini'yi SADECE geçerli
        // JSON döndürmeye zorluyor (ai_urun_ekle_servisi.dart'taki diğer
        // tüm Gemini çağrılarında zaten kullanılan, kanıtlanmış desen).
        generationConfig: GenerationConfig(responseMimeType: 'application/json'),
      );

      final prompt = '''
Aşağıda bir faturadan OCR ile okunmuş ham metin var. Bu metni analiz et ve içindeki tüm ürünleri bir JSON listesi olarak çıkar.

Ham metin:
---
$hamMetin
---

Ürünleri aşağıdaki JSON formatında çıkar. **Tüm sayısal değerleri (miktar, fiyat, KDV) mutlaka sayı olarak ver, yanlarına TL veya virgül koyma. Örneğin "49,90" yerine 49.90 yaz.**
{
  "urunler": [
    {
      "urun_adi": "string",
      "miktar": number,
      "birim_adi": "string",
      "birim_fiyat": number,
      "toplam_tutar": number,
      "kdv_orani": number,
      "iskonto_orani": number,
      "kod": "string"
    }
  ]
}

Sadece JSON çıktısı ver, başka bir şey yazma. Emin olmadığın alanları null veya 0 bırak.
''';

      final response = await model.generateContent([Content.text(prompt)]);
      final jsonStr = response.text?.trim() ?? '';

      if (kDebugMode) {
        debugPrint('===== GEMİNİ YANITI =====');
        debugPrint(jsonStr);
        debugPrint('==========================');
      }

      // JSON'u temizle
      final cleanedJson = jsonStr
          .replaceAll(RegExp(r'```json\n?'), '')
          .replaceAll(RegExp(r'\n?```'), '')
          .trim();

      final decoded = jsonDecode(cleanedJson);
      if (decoded is Map<String, dynamic> && decoded.containsKey('urunler')) {
        return List<Map<String, dynamic>>.from(decoded['urunler']);
      }
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('Gemini hatası: $e');
      return null;
    }
  }

  // ---- GEMINI GÖRSEL ANALİZİ (GERÇEK VISION — OCR'sız) ----
  // 🔴🔴🔴 Bu fonksiyon, cihaz-üstü OCR'ın tamamen atlanıp fotoğrafın
  // BİREBİR görüntü verisi olarak Gemini'ye gönderildiği tek yer. Bulanık,
  // eğik, soluk veya küçük punto yazılı faturalar için OCR'dan çok daha
  // güvenilir — Gemini'nin kendi görsel-metin anlama yeteneği, ışık/açı
  // sorunlarını OCR'dan çok daha iyi tolere eder.
  Future<List<Map<String, dynamic>>?> _llmIleGorseldenCikar(String gorselYolu, String apiKey) async {
    try {
      final dosya = File(gorselYolu);
      if (!await dosya.exists()) return null;
      final bytes = await dosya.readAsBytes();
      if (bytes.isEmpty) return null;

      final mimeType = gorselYolu.toLowerCase().endsWith('.png')
          ? 'image/png'
          : 'image/jpeg';

      final model = GenerativeModel(
        model: await AiModelSecici.ilkAday(),
        apiKey: apiKey,
        // Bkz. _llmIleYapilandir'daki AYNI düzeltme notu — JSON modu
        // zorunlu kılınmazsa Gemini görsel yanıtın etrafına açıklama
        // metni ekleyebiliyor, bu da jsonDecode()'u sessizce bozuyordu.
        generationConfig: GenerationConfig(responseMimeType: 'application/json'),
      );

      const prompt = '''
Bu bir marketin/dükkanın tedarikçiden aldığı faturanın veya fiş/irsaliyenin
fotoğrafıdır. Fotoğrafı dikkatle incele (bulanık, eğik veya soluk olsa
bile elinden geleni yap) ve içindeki TÜM ürün satırlarını bir JSON listesi
olarak çıkar.

Aşağıdaki JSON formatında çıkar. **Tüm sayısal değerleri (miktar, fiyat,
KDV) mutlaka sayı olarak ver, yanlarına TL veya virgül koyma. Örneğin
"49,90" yerine 49.90 yaz.**
{
  "urunler": [
    {
      "urun_adi": "string",
      "miktar": number,
      "birim_adi": "string",
      "birim_fiyat": number,
      "toplam_tutar": number,
      "kdv_orani": number,
      "iskonto_orani": number,
      "kod": "string"
    }
  ]
}

Sadece JSON çıktısı ver, başka bir şey yazma. Emin olmadığın alanları
null veya 0 bırak. Fotoğrafta hiçbir ürün satırı okunamıyorsa
{"urunler": []} döndür.
''';

      final content = Content.multi([
        TextPart(prompt),
        DataPart(mimeType, bytes),
      ]);
      final response = await model.generateContent([content])
          .timeout(const Duration(seconds: 25));
      final jsonStr = response.text?.trim() ?? '';

      if (kDebugMode) {
        debugPrint('===== GEMİNİ GÖRSEL YANITI =====');
        debugPrint(jsonStr);
        debugPrint('==================================');
      }

      final cleanedJson = jsonStr
          .replaceAll(RegExp(r'```json\n?'), '')
          .replaceAll(RegExp(r'\n?```'), '')
          .trim();

      final decoded = jsonDecode(cleanedJson);
      if (decoded is Map<String, dynamic> && decoded.containsKey('urunler')) {
        return List<Map<String, dynamic>>.from(decoded['urunler']);
      }
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('Gemini görsel analizi hatası: $e');
      return null;
    }
  }

  // ---- YARDIMCI METOTLAR ----
  // 🔴🔴🔴 KÖK NEDEN DÜZELTMESİ (kullanıcı bulgusu — "fatura
  // fotoğrafından textlere düzgün işlemiyor"): Ürün Ekle ekranındaki
  // "Faturadan Ürün Ekle" dosya seçici PDF'e (ve xlsx/xls'e) İZİN
  // VERİYORDU — tedarikçi faturaları gerçek hayatta çok sık PDF
  // olarak gelir. Ama bu fonksiyon PDF/Excel byte'larını DOĞRUDAN
  // "resim" sanıp hem cihaz-üstü OCR'a (ML Kit — sadece gerçek
  // raster görsel formatlarını tanır) hem Gemini'nin görsel girişine
  // "image/jpeg" etiketiyle gönderiyordu. Sonuç: PDF faturalar SESSİZCE
  // hiçbir zaman çalışmıyordu (OCR aşamasında hata fırlatıp doğrudan
  // boş listeye düşülüyordu, görsel yedek yoluna hiç ULAŞILAMIYORDU).
  // Artık: kaynak bir PDF ise, ürünün İLK SAYFASI gerçek bir rastere
  // (PNG) çevrilip AYNI, kanıtlanmış OCR+görsel işlem hattına
  // veriliyor — printing paketi zaten projede (PDF yazdırma için)
  // kullanılıyor, ek bağımlılık gerekmedi.
  /// Dosya yoluna bakarak PDF olup olmadığını belirler — DB/platform
  /// bağımlılığı olmadan izole test edilebilsin diye ayrı bir fonksiyon
  /// (bkz. sync_cakisma_tespit.dart'taki aynı desen).
  static bool pdfUzantiliMi(String? path) =>
      path?.toLowerCase().endsWith('.pdf') ?? false;

  /// Dosya UZANTISI yanlış/eksik olsa bile (ör. bazı dosya seçicilerin
  /// uzantısız geçici kopyaları), gerçek PDF magic-byte imzasına ("%PDF")
  /// bakarak içeriğin PDF olup olmadığını belirler.
  static bool pdfIcerikliMi(Uint8List? bytes) =>
      bytes != null &&
      bytes.length >= 4 &&
      bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46; // "%PDF"

  Future<String?> _gorselYoluAl(dynamic kaynak) async {
    String? path;
    Uint8List? bytes;
    if (kaynak is XFile) {
      path = kaynak.path;
    } else if (kaynak is File) {
      path = kaynak.path;
    } else if (kaynak is PlatformFile) {
      path = kaynak.path;
      bytes = kaynak.bytes;
    } else if (kaynak is Uint8List) {
      bytes = kaynak;
    }

    final uzantiPdfMi = pdfUzantiliMi(path);
    bytes ??= (uzantiPdfMi && path != null) ? await File(path).readAsBytes() : null;
    if (uzantiPdfMi || pdfIcerikliMi(bytes)) {
      final pdfBytes = bytes ?? (path != null ? await File(path).readAsBytes() : null);
      if (pdfBytes == null) return null;
      return _pdfIlkSayfayiResmeCevir(pdfBytes);
    }

    if (path != null) return path;
    if (bytes != null) {
      final tmpDir = Directory.systemTemp;
      final tmpFile = File('${tmpDir.path}/ocr_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await tmpFile.writeAsBytes(bytes);
      return tmpFile.path;
    }
    return null;
  }

  /// PDF'in ilk sayfasını, mevcut OCR/Gemini görsel hattının işleyebildiği
  /// bir PNG dosyasına çevirir. 200 DPI, hem OCR okunabilirliği hem
  /// makul dosya boyutu için dengeli bir değer.
  Future<String?> _pdfIlkSayfayiResmeCevir(Uint8List pdfBytes) async {
    try {
      await for (final sayfa in Printing.raster(pdfBytes, pages: [0], dpi: 200)) {
        final png = await sayfa.toPng();
        final tmpDir = Directory.systemTemp;
        final tmpFile = File(
            '${tmpDir.path}/ocr_pdf_${DateTime.now().millisecondsSinceEpoch}.png');
        await tmpFile.writeAsBytes(png);
        return tmpFile.path;
      }
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('PDF -> görsel dönüşümü başarısız: $e');
      return null;
    }
  }

  void dispose() => _recognizer.close();
}