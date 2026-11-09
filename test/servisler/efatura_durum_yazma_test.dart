// test/servisler/efatura_durum_yazma_test.dart
//
// Derin denetim (2026-11-09) #16, yüksek: GİB durum sorgusundan dönen
// tanınmayan ara durum ('processing', 'queued'…) faturaya yazılıyor, fatura
// "gönderilmemiş" görünüp Durum Sorgula kilitleniyordu. Yalnız kesin
// sonuçlar yazılır.
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/servisler/fatura_ebelge_servisi.dart';

void main() {
  test('kesin sonuçlar yazılabilir', () {
    for (final d in ['onaylandi', 'reddedildi', 'gib_iptal']) {
      expect(eFaturaKesinDurumMu(d), isTrue, reason: d);
    }
  });

  test('entegratörün ara/tanınmayan durumları yazılmaz', () {
    for (final d in ['processing', 'queued', 'waiting', 'Succeed', 'pending', '']) {
      expect(eFaturaKesinDurumMu(d), isFalse, reason: d);
    }
  });
}
