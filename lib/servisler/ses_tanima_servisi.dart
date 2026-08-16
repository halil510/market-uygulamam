// lib/servisler/ses_tanima_servisi.dart
//
// Paylaşılan konuşma-tanıma (speech-to-text) servisi. AI Chat'te soru
// sormak için, Ürün Ekle ekranında ürün adı/fiyat gibi alanları sesle
// doldurmak için kullanılıyor.
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class SesTanimaServisi {
  static final SesTanimaServisi _ornek = SesTanimaServisi._ic();
  factory SesTanimaServisi() => _ornek;
  SesTanimaServisi._ic();

  final stt.SpeechToText _stt = stt.SpeechToText();
  bool _hazir = false;
  bool get dinliyorMu => _stt.isListening;

  /// Cihazın konuşma tanımayı desteklediğini ve izin verildiğini kontrol
  /// eder. İlk çağrıda kullanıcıya mikrofon izni sorar.
  Future<bool> hazirla() async {
    if (_hazir) return true;
    try {
      _hazir = await _stt.initialize(
        onError: (e) { if (kDebugMode) debugPrint('Ses tanıma hatası: $e'); },
        onStatus: (s) { if (kDebugMode) debugPrint('Ses tanıma durumu: $s'); },
      );
      return _hazir;
    } catch (e) {
      if (kDebugMode) debugPrint('Ses tanıma başlatılamadı: $e');
      return false;
    }
  }

  /// Dinlemeyi başlatır. Her ara sonuçta [onSonuc] çağrılır (canlı önizleme
  /// için), konuşma bittiğinde [onBitti] son metinle çağrılır.
  Future<bool> dinlemeyeBasla({
    required void Function(String metin) onSonuc,
    void Function(String metin)? onBitti,
    String localeId = 'tr_TR',
  }) async {
    final ok = await hazirla();
    if (!ok) return false;
    await _stt.listen(
      localeId: localeId,
      onResult: (r) {
        onSonuc(r.recognizedWords);
        if (r.finalResult) onBitti?.call(r.recognizedWords);
      },
      listenFor: const Duration(seconds: 20),
      pauseFor: const Duration(seconds: 3),
    );
    return true;
  }

  Future<void> durdur() async => _stt.stop();
  Future<void> iptal() async => _stt.cancel();

  /// Sesle söylenen bir tutarı (ör. "on iki lira elli" / "12,50" / "12.5")
  /// double'a çevirmeye çalışır. Türkçe konuşma tanıma genelde rakamları
  /// zaten yazıyla değil sayıyla döndürür ("12,50 lira" gibi), bu yüzden
  /// önce metindeki ilk sayısal ifadeyi ayıklıyoruz.
  static double? tutarAyristir(String metin) {
    final temiz = metin
        .toLowerCase()
        .replaceAll('lira', '')
        .replaceAll('tl', '')
        .replaceAll('₺', '')
        .trim();
    final match = RegExp(r'[\d]+([.,]\d+)?').firstMatch(temiz);
    if (match == null) return null;
    return double.tryParse(match.group(0)!.replaceAll(',', '.'));
  }
}
