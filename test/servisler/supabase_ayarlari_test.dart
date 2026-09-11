// test/servisler/supabase_ayarlari_test.dart
//
// Derin analizde bulundu: Supabase URL/anahtarı (kullanıcı isterse RLS'i
// atlayan tam yetkili bir "sb_secret_" anahtarı da girebiliyordu) 9 farklı
// yerde SharedPreferences'tan DÜZ METİN okunuyordu. SupabaseAyarlari artık
// tek okuma/yazma noktası ve flutter_secure_storage kullanıyor; bu test
// eski düz metin değerlerin otomatik ve doğru taşındığını doğruluyor.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:market_plus/servisler/bulut/supabase_ayarlari.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('SupabaseAyarlari', () {
    test('hiç ayar yoksa null döner', () async {
      expect(await SupabaseAyarlari.urlOku(), isNull);
      expect(await SupabaseAyarlari.keyOku(), isNull);
    });

    test('kaydet() sonrası aynı değerler okunur', () async {
      await SupabaseAyarlari.kaydet(url: 'https://x.supabase.co', key: 'sb_publishable_abc');
      expect(await SupabaseAyarlari.urlOku(), equals('https://x.supabase.co'));
      expect(await SupabaseAyarlari.keyOku(), equals('sb_publishable_abc'));
    });

    test('eski düz metin (mp_supabase_*) değerler otomatik taşınır', () async {
      SharedPreferences.setMockInitialValues({
        'mp_supabase_url': 'https://eski.supabase.co',
        'mp_supabase_key': 'sb_secret_eski',
      });

      final url = await SupabaseAyarlari.urlOku();
      final key = await SupabaseAyarlari.keyOku();
      expect(url, equals('https://eski.supabase.co'));
      expect(key, equals('sb_secret_eski'));

      // Düz metin iz bırakmamalı — güvenli depoya taşındıktan sonra silinir.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('mp_supabase_url'), isNull);
      expect(prefs.getString('mp_supabase_key'), isNull);
    });

    test('en eski (mp_supa_*) değerler de taşınır', () async {
      SharedPreferences.setMockInitialValues({
        'mp_supa_url': 'https://cokeski.supabase.co',
        'mp_supa_key': 'sb_secret_cokeski',
      });

      expect(await SupabaseAyarlari.urlOku(), equals('https://cokeski.supabase.co'));
      expect(await SupabaseAyarlari.keyOku(), equals('sb_secret_cokeski'));
    });

    test('temizle() sonrası ayarlar silinir', () async {
      await SupabaseAyarlari.kaydet(url: 'https://x.supabase.co', key: 'k');
      await SupabaseAyarlari.temizle();
      expect(await SupabaseAyarlari.urlOku(), isNull);
      expect(await SupabaseAyarlari.keyOku(), isNull);
    });
  });
}
