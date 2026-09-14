// test/servisler/ai_vision_pdf_test.dart
//
// Kullanıcı bulgusu — "fatura fotoğrafından textlere düzgün işlemiyor":
// Ürün Ekle > Faturadan Ürün Ekle dosya seçici PDF'e izin veriyordu ama
// AiVisionServisi PDF/Excel byte'larını doğrudan "resim" sanıp hem
// cihaz-üstü OCR'a hem Gemini'nin görsel girişine yanlış MIME tipiyle
// gönderiyordu — PDF faturalar sessizce hiçbir zaman çalışmıyordu.
// Bu test, PDF tespit mantığının (uzantı VE magic-byte imzası) doğru
// çalıştığını DB/platform bağımlılığı olmadan doğrular.
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/servisler/ai/ai_vision_servisi.dart';

void main() {
  group('AiVisionServisi.pdfUzantiliMi', () {
    test('.pdf uzantılı yol PDF sayılır (büyük/küçük harf duyarsız)', () {
      expect(AiVisionServisi.pdfUzantiliMi('fatura.pdf'), isTrue);
      expect(AiVisionServisi.pdfUzantiliMi('FATURA.PDF'), isTrue);
      expect(AiVisionServisi.pdfUzantiliMi('/tmp/x/fatura.Pdf'), isTrue);
    });

    test('resim/diğer uzantılar PDF sayılmaz', () {
      expect(AiVisionServisi.pdfUzantiliMi('fatura.jpg'), isFalse);
      expect(AiVisionServisi.pdfUzantiliMi('fatura.png'), isFalse);
      expect(AiVisionServisi.pdfUzantiliMi('fatura.xlsx'), isFalse);
    });

    test('yol yoksa (null) PDF sayılmaz', () {
      expect(AiVisionServisi.pdfUzantiliMi(null), isFalse);
    });
  });

  group('AiVisionServisi.pdfIcerikliMi', () {
    test('"%PDF" magic-byte imzasıyla başlayan içerik PDF sayılır', () {
      final pdfBytes = Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x34]);
      expect(AiVisionServisi.pdfIcerikliMi(pdfBytes), isTrue);
    });

    test('JPEG magic-byte imzası (0xFFD8) PDF sayılmaz', () {
      final jpegBytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);
      expect(AiVisionServisi.pdfIcerikliMi(jpegBytes), isFalse);
    });

    test('4 byte\'tan kısa içerik güvenli şekilde false döner (çökme yok)', () {
      expect(AiVisionServisi.pdfIcerikliMi(Uint8List.fromList([0x25, 0x50])), isFalse);
      expect(AiVisionServisi.pdfIcerikliMi(Uint8List.fromList([])), isFalse);
    });

    test('null içerik güvenli şekilde false döner', () {
      expect(AiVisionServisi.pdfIcerikliMi(null), isFalse);
    });
  });
}
