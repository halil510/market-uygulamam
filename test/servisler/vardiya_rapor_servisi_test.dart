// test/servisler/vardiya_rapor_servisi_test.dart
//
// Vardiya ekranından ayrılan süre metni kuralı (2026-10-07 refactor).
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/servisler/vardiya/vardiya_rapor_servisi.dart';

void main() {
  test('kapanmış vardiya süresi saat ve dakika olarak yazılır', () {
    expect(
        VardiyaRaporServisi.sureMetni('2026-10-07T08:00:00', '2026-10-07T11:25:00'), '3s 25dk');
  });

  test('açık vardiya şu ana kadar sayılır, başlangıç yoksa tire', () {
    expect(
        VardiyaRaporServisi.sureMetni('2026-10-07T08:00:00', null,
            simdi: DateTime.parse('2026-10-07T09:05:00')),
        '1s 5dk');
    expect(VardiyaRaporServisi.sureMetni(null, null), '—');
    expect(VardiyaRaporServisi.sureMetni('bozuk', null), '—');
  });
}
