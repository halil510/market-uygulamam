// test/servisler/ai_intent_yetki_test.dart
//
// DERİN DENETİM (2026-11-09, #75): Global Arama'daki "Yapay Zekaya Sor"
// rapor/kasa/cari verisini yetki kontrolü olmadan gösteriyordu.
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/servisler/ai/ai_modeller.dart';
import 'package:market_plus/servisler/ai/ai_sohbet_servisi.dart';

void main() {
  test('veri gösteren niyetler ilgili ekran yetkisine bağlıdır', () {
    expect(aiIntentYetkisi(AiIntent.netKar), 'rapor');
    expect(aiIntentYetkisi(AiIntent.zRaporu), 'rapor');
    expect(aiIntentYetkisi(AiIntent.kasaDurumu), 'kasa');
    expect(aiIntentYetkisi(AiIntent.cariBorc), 'cari');
    expect(aiIntentYetkisi(AiIntent.stokDeger), 'stok');
    expect(aiIntentYetkisi(AiIntent.urunAra), 'urun');
  });

  test('sohbet yetki gerektirmez', () {
    expect(aiIntentYetkisi(AiIntent.sohbet), isNull);
  });

  test('oturum yokken netKar sorusu veri yerine yetki uyarısı döner', () async {
    final cevap = await AiSohbetServisi().sor('bugünkü net kâr ne kadar');
    expect(cevap.cevap, contains('yetkiniz yok'));
  });
}
