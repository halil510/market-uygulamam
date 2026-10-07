// test/servisler/sync_istemci_zaman_asimi_test.dart
//
// Derin analiz 2026-10-07 (C1): WiFi senkron istemcisi, bağlantıyı kabul
// edip hiç yanıt vermeyen bir cihazda artık sonsuza dek beklemiyor.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/servisler/sync_servisi.dart';

void main() {
  late HttpServer sunucu;
  late String adres;

  setUp(() async {
    sunucu = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    adres = 'http://127.0.0.1:${sunucu.port}';
  });
  tearDown(() => sunucu.close(force: true));

  test('yanıt vermeyen sunucuda ping zaman aşımıyla başarısız döner', () async {
    sunucu.listen((_) {/* isteği al, hiç yanıtlama */});
    final sw = Stopwatch()..start();
    final sonuc = await SyncServisi().sunucuyaPingAt(adres);
    expect(sonuc.basarili, isFalse);
    expect(sw.elapsed, lessThan(const Duration(seconds: 15)));
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('normal yanıtta ping başarılı', () async {
    sunucu.listen((req) {
      req.response
        ..headers.contentType = ContentType.json
        ..write('{"cihaz":"test","version":"1"}')
        ..close();
    });
    final sonuc = await SyncServisi().sunucuyaPingAt(adres);
    expect(sonuc.basarili, isTrue);
    expect(sonuc.cihaz, 'test');
  });
}
