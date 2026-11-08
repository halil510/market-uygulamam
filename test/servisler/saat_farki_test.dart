// test/servisler/saat_farki_test.dart
//
// Çoklu cihaz analizi (2026-11-08): senkron "hangi kayıt daha yeni"
// kararını kayıt saatine göre verir; cihaz saati yanlışsa eski değişiklik
// yeniyi ezebilir. Fark sunucunun HTTP Date başlığından ölçülüp eşiği
// aşınca bulut ikonunun yanında uyarı gösterilir.
import 'dart:io' show HttpDate;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/servisler/bulut/bulut_manager.dart';
import 'package:market_plus/servisler/bulut/saat_farki.dart';
import 'package:market_plus/widgetlar/ortak/bulut_durum_widget.dart';

void main() {
  group('SaatFarki.hesapla', () {
    final bas = DateTime.utc(2026, 11, 8, 12, 0, 0);
    final son = bas.add(const Duration(seconds: 2));

    test('sunucu ile aynı saat → fark ~0, uyarı yok', () {
      final f = SaatFarki.hesapla(HttpDate.format(bas.add(const Duration(seconds: 1))), bas, son)!;
      expect(f.inSeconds.abs(), lessThanOrEqualTo(1));
      expect(SaatFarki.sapmaVar(f), isFalse);
    });

    test('cihaz 30 dk geride → pozitif fark, uyarı var', () {
      final sunucu = bas.add(const Duration(minutes: 30, seconds: 1));
      final f = SaatFarki.hesapla(HttpDate.format(sunucu), bas, son)!;
      expect(f.inMinutes, 30);
      expect(SaatFarki.sapmaVar(f), isTrue);
      expect(SaatFarki.metin(f), 'Cihaz saati sunucudan 30 dk geride');
    });

    test('cihaz 3 saat ileride (saat dilimi hatası) → negatif fark', () {
      final sunucu = bas.subtract(const Duration(hours: 3));
      final f = SaatFarki.hesapla(HttpDate.format(sunucu), bas, son)!;
      expect(f.isNegative, isTrue);
      expect(SaatFarki.metin(f), 'Cihaz saati sunucudan 3 saat ileride');
    });

    test('eşik altı fark (4 dk) uyarı vermez', () {
      final sunucu = bas.add(const Duration(minutes: 4));
      expect(SaatFarki.sapmaVar(SaatFarki.hesapla(HttpDate.format(sunucu), bas, son)), isFalse);
    });

    test('başlık yok/bozuk → null, uyarı yok', () {
      expect(SaatFarki.hesapla(null, bas, son), isNull);
      expect(SaatFarki.hesapla('dün öğlen', bas, son), isNull);
      expect(SaatFarki.sapmaVar(null), isFalse);
    });
  });

  testWidgets('saat farkı eşiği aşınca bulut ikonunda saat uyarısı görünür', (t) async {
    BulutManager().durum.value = BulutDurum.bagli;
    BulutManager().saatFarki.value = const Duration(minutes: 20);
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: BulutDurumIkonu())));
    expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);

    BulutManager().saatFarki.value = const Duration(seconds: 30);
    await t.pump();
    expect(find.byIcon(Icons.schedule_rounded), findsNothing);
    BulutManager().saatFarki.value = null;
    BulutManager().durum.value = BulutDurum.bagliDegil;
  });
}
