// test/uygulama/acilis_koruma_test.dart
//
// Elektrik kesintisi (2026-10-08) sonrası uygulamanın açılmaması:
// yarım/NUL dolu ayar dosyası ve gün aşırı alınan otomatik yedek.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/servisler/yedekleme_servisi.dart';
import 'package:market_plus/uygulama/acilis_koruma.dart';

void main() {
  late Directory dizin;
  late File ayar;

  setUp(() {
    dizin = Directory.systemTemp.createTempSync('acilis_koruma_');
    ayar = File('${dizin.path}/shared_preferences.json');
  });
  tearDown(() => dizin.deleteSync(recursive: true));

  group('ayar dosyası onarımı', () {
    test('sağlam dosyaya dokunmaz', () async {
      ayar.writeAsStringSync('{"flutter.tema_adi":"dark"}');
      await ayarDosyasiOnar(ayar);
      expect(ayar.readAsStringSync(), '{"flutter.tema_adi":"dark"}');
      expect(dizin.listSync(), hasLength(1));
    });

    test('NUL dolu dosya (kesinti) son sağlam kopyadan onarılır', () async {
      ayar.writeAsStringSync('{"flutter.tema_adi":"dark","flutter.sube":"1"}');
      await ayarDosyasiYedekle(ayar);
      // Elektrik yazım sırasında gitti: dosya boyutu duruyor, içerik sıfır.
      ayar.writeAsBytesSync(List.filled(64, 0));

      await ayarDosyasiOnar(ayar);

      expect(ayar.readAsStringSync(),
          '{"flutter.tema_adi":"dark","flutter.sube":"1"}');
      final bozuklar = dizin
          .listSync()
          .where((f) => f.path.contains('.bozuk_'))
          .toList();
      expect(bozuklar, hasLength(1), reason: 'bozuk dosya silinmez, kenara alınır');
    });

    test('yarım JSON + sağlam kopya yoksa dosya kenara alınır (varsayılan ayar)', () async {
      ayar.writeAsStringSync('{"flutter.tema_adi":"da');
      await ayarDosyasiOnar(ayar);
      expect(ayar.existsSync(), isFalse,
          reason: 'SharedPreferences boş ayarla açılır, hata vermez');
    });

    test('bozuk dosyanın sağlam kopyası alınmaz', () async {
      ayar.writeAsStringSync('{"a":1}');
      await ayarDosyasiYedekle(ayar);
      ayar.writeAsStringSync('{bozuk');
      await ayarDosyasiYedekle(ayar);
      expect(File('${ayar.path}.son_saglam').readAsStringSync(), '{"a":1}');
    });
  });

  group('otomatik yedek günü', () {
    test('dün 10:16 yedek, bugün 10:10 açılış → yedek alınır', () {
      expect(
          YedeklemeServisi.yedekGunuGeldiMi(
              DateTime(2026, 10, 9, 10, 16), DateTime(2026, 10, 10, 10, 10)),
          isTrue,
          reason: 'önceden 23 sa 54 dk < 1 gün sayılıp atlanıyordu');
    });

    test('aynı gün ikinci açılış → yedek alınmaz', () {
      expect(
          YedeklemeServisi.yedekGunuGeldiMi(
              DateTime(2026, 10, 10, 9, 0), DateTime(2026, 10, 10, 23, 30)),
          isFalse);
    });

    test('haftalık: 6 gün sonra alınmaz, 7. gün alınır', () {
      final son = DateTime(2026, 10, 1, 22, 0);
      expect(YedeklemeServisi.yedekGunuGeldiMi(son, DateTime(2026, 10, 7, 23, 0), gunAralik: 7), isFalse);
      expect(YedeklemeServisi.yedekGunuGeldiMi(son, DateTime(2026, 10, 8, 8, 0), gunAralik: 7), isTrue);
    });
  });
}
