// test/unit/yazici_paylasimi_test.dart
// USB etiket yazıcısını ağa açma (9100 → RAW) ve raf etiketinin ayrı ağ adresine gönderimi.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/servisler/etiket_ag_gonderici.dart';
import 'package:market_plus/servisler/windows_etiket_yazici.dart';
import 'package:market_plus/servisler/yazici_paylasimi.dart';

void main() {
  late List<Uint8List> gelen;
  late YaziciPaylasimi p;

  Future<YaziciPaylasimi> ac({Duration bekleme = const Duration(milliseconds: 150), int tampon = 4 << 20,
      Future<void> Function(Uint8List)? gonder}) async {
    gelen = [];
    return YaziciPaylasimi.baslat('deneme',
        port: 0,
        adres: InternetAddress.loopbackIPv4,
        bekleme: bekleme,
        enFazlaTampon: tampon,
        gonder: gonder ?? (v) async => gelen.add(v));
  }

  Future<void> bekle(bool Function() kosul) async {
    for (var i = 0; i < 100 && !kosul(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  tearDown(() async => p.kapat());

  test('bağlantı kapanınca gelen veri olduğu gibi tek iş olarak basılır', () async {
    p = await ac(bekleme: const Duration(seconds: 30));
    final veri = Uint8List.fromList(List.generate(300000, (i) => i * 7 % 256));
    final s = await Socket.connect(InternetAddress.loopbackIPv4, p.port);
    s.add(veri);
    await s.flush();
    await s.close();
    await bekle(() => gelen.isNotEmpty);
    await p.bosalt();
    expect(gelen.length, 1);
    expect(gelen.single, veri);
    expect(p.isSayisi, 1);
    expect(p.baytSayisi, veri.length);
    expect(p.sonHata, isNull);
  });

  test('açık kalan bağlantıda (market uygulaması) sessizlikten sonra basılır, sıra korunur', () async {
    p = await ac();
    final s = await Socket.connect(InternetAddress.loopbackIPv4, p.port);
    s.add(latin1.encode('SIZE 80 mm,35 mm\r\n'));
    await s.flush();
    await bekle(() => gelen.isNotEmpty);
    expect(latin1.decode(gelen.single), 'SIZE 80 mm,35 mm\r\n');
    s.add(latin1.encode('PRINT 1,1\r\n'));
    await s.flush();
    await bekle(() => gelen.length == 2);
    expect(latin1.decode(gelen[1]), 'PRINT 1,1\r\n');
    s.destroy();
  });

  test('büyük iş tampon sınırında bölünür, birleşimi aynıdır', () async {
    p = await ac(bekleme: const Duration(seconds: 30), tampon: 10000);
    final veri = Uint8List.fromList(List.generate(55555, (i) => i % 251));
    final s = await Socket.connect(InternetAddress.loopbackIPv4, p.port);
    for (var i = 0; i < veri.length; i += 9000) {
      s.add(veri.sublist(i, i + 9000 > veri.length ? veri.length : i + 9000));
      await s.flush();
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await s.close();
    await bekle(() => gelen.fold<int>(0, (t, e) => t + e.length) == veri.length);
    await p.bosalt();
    expect(gelen.length, greaterThan(1));
    expect(gelen.expand((e) => e).toList(), veri);
  });

  test('iki telefon aynı anda: işler karışmadan sırayla gider', () async {
    final tamamlanan = <String>[];
    p = await ac(
        bekleme: const Duration(seconds: 30),
        gonder: (v) async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          tamamlanan.add(latin1.decode(v));
        });
    final a = await Socket.connect(InternetAddress.loopbackIPv4, p.port);
    final b = await Socket.connect(InternetAddress.loopbackIPv4, p.port);
    a.add(latin1.encode('A' * 1000));
    b.add(latin1.encode('B' * 1000));
    await a.close();
    await b.close();
    await bekle(() => tamamlanan.length == 2);
    expect(tamamlanan.toSet(), {'A' * 1000, 'B' * 1000});
  });

  test('yazıcı hatası kaydedilir, sonraki iş yine basılır', () async {
    var cagri = 0;
    p = await ac(
        bekleme: const Duration(seconds: 30),
        gonder: (v) async {
          if (++cagri == 1) throw WindowsYaziciHatasi('yazıcı kapalı');
          gelen.add(v);
        });
    for (final (i, m) in [(1, 'bir'), (2, 'iki')]) {
      final s = await Socket.connect(InternetAddress.loopbackIPv4, p.port);
      s.add(latin1.encode(m));
      await s.close();
      await bekle(() => cagri == i);
      await p.bosalt();
      if (i == 1) expect(p.sonHata, 'yazıcı kapalı');
    }
    expect(gelen.map(latin1.decode), ['iki']);
    expect(p.isSayisi, 1);
    expect(p.sonHata, isNull); // başarılı iş hatayı temizler
  });

  test('uçtan uca: raf etiketinin TSPL gönderimi (etiketAgaGonder) bilgisayardaki paylaşıma aynen ulaşır', () async {
    p = await ac(bekleme: const Duration(seconds: 30));
    final veri = Uint8List.fromList(List.generate(200000, (i) => i * 13 % 256));
    await etiketAgaGonder('127.0.0.1:${p.port}', veri);
    await bekle(() => gelen.isNotEmpty);
    await p.bosalt();
    expect(gelen.single, veri);
  });

  test('aynı port ikinci kez açılamaz (SocketException)', () async {
    p = await ac();
    await expectLater(
        YaziciPaylasimi.baslat('x', port: p.port, adres: InternetAddress.loopbackIPv4), throwsA(isA<SocketException>()));
  });

  test('kapatınca yeni bağlantı kabul edilmez', () async {
    p = await ac();
    final port = p.port;
    await p.kapat();
    expect(p.kapali, isTrue);
    await expectLater(Socket.connect(InternetAddress.loopbackIPv4, port, timeout: const Duration(seconds: 2)),
        throwsA(isA<SocketException>()));
  });

  test('etiketAdresCoz ve kapalı porta gönderim hatası', () async {
    p = await ac();
    expect(etiketAdresCoz('192.168.1.35'), ('192.168.1.35', 9100));
    expect(etiketAdresCoz(' 10.0.0.5:9101 '), ('10.0.0.5', 9101));
    for (final k in ['', '192.168.1', '300.1.1.1', '1.2.3.4:0', '1.2.3.4:70000', 'yazici']) {
      expect(etiketAdresCoz(k), isNull, reason: k);
    }
    await expectLater(etiketAgaGonder('abc', Uint8List(1)), throwsA(isA<EtiketAgHatasi>()));
    final port = p.port;
    await p.kapat();
    await expectLater(etiketAgaGonder('127.0.0.1:$port', Uint8List(1)), throwsA(isA<EtiketAgHatasi>()));
  });
}
