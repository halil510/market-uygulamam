// test/servisler/bulut_senkron_sira_filigran_test.dart
//
// Bulut Veri Güvenliği Raporu (2026-10-07):
//  Bulgu 1 — çekim filigranı sunucu_zamani'ye göre; ilk geçişte eski
//            (last_updated) filigranın 48 saat gerisinden başlar; yalnız
//            buluttan gelen değerle ilerler (cihaz saatiyle değil).
//  Bulgu 7 — tam senkron sırasında her tablonun ebeveynleri önce gelir.
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/servisler/kolon_haritalama.dart';
import 'package:market_plus/servisler/supabase_sync_servisi.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Bulgu 7: tam senkron sırası', () {
    test('her tablonun FK ebeveynleri listede kendisinden önce', () {
      final sira = SupabaseSyncServisi.tabloSirasiTest;
      final yer = <String, int>{};
      for (var i = 0; i < sira.length; i++) {
        yer.putIfAbsent(sira[i], () => i);
      }
      final ihlal = <String>[];
      for (final t in sira) {
        for (final p in KolonHaritalama.ebeveynler(t)) {
          if (p == t) continue;
          final pi = yer[p];
          if (pi == null) {
            ihlal.add('$t → $p: ebeveyn sırada yok');
          } else if (pi > yer[t]!) {
            ihlal.add('$t (#${yer[t]}) → $p (#$pi): ebeveyn SONRA');
          }
        }
      }
      expect(ihlal, isEmpty);
    });
  });

  group('Bulgu 1: sunucu_zamani filigranı', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('ilk geçiş: eski last_updated filigranının 48 saat gerisi', () async {
      SharedPreferences.setMockInitialValues(
          {'mp_sync_al_satislar': '2026-10-07T12:00:00.000Z'});
      final f = await SupabaseSyncServisi.sunucuZamaniFiligraniTest('satislar');
      expect(f, DateTime.utc(2026, 10, 5, 12));
    });

    test('hiç filigran yoksa null (tam çekim)', () async {
      expect(await SupabaseSyncServisi.sunucuZamaniFiligraniTest('satislar'), isNull);
    });

    test('kayıt sonrası filigran en büyük sunucu_zamani olur; geri gitmez', () async {
      await SupabaseSyncServisi.cekimFiligraniKaydetTest('satislar', [
        {'last_updated': '2026-10-07T08:00:00Z', 'sunucu_zamani': '2026-10-07T10:00:00+00:00'},
        // Çevrimdışı kasanın eski damgalı ama SONRADAN yüklenmiş satırı:
        {'last_updated': '2026-10-06T08:00:00Z', 'sunucu_zamani': '2026-10-07T10:05:00+00:00'},
      ]);
      expect(await SupabaseSyncServisi.sunucuZamaniFiligraniTest('satislar'),
          DateTime.utc(2026, 10, 7, 10, 5));
      await SupabaseSyncServisi.cekimFiligraniKaydetTest('satislar', [
        {'last_updated': '2026-10-07T09:00:00Z', 'sunucu_zamani': '2026-10-07T09:00:00+00:00'},
      ]);
      expect(await SupabaseSyncServisi.sunucuZamaniFiligraniTest('satislar'),
          DateTime.utc(2026, 10, 7, 10, 5), reason: 'filigran geri gitmez');
    });

    test('satırlarda sunucu_zamani yoksa (eski bulut) yeni filigran yazılmaz', () async {
      await SupabaseSyncServisi.cekimFiligraniKaydetTest('satislar', [
        {'last_updated': '2026-10-07T08:00:00Z'},
      ]);
      final p = await SharedPreferences.getInstance();
      expect(p.getString('mp_sync_al_sz_satislar'), isNull);
      expect(p.getString('mp_sync_al_satislar'), isNotNull, reason: 'eski filigran sürer');
    });
  });
}
