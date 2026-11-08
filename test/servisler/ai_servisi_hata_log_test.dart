// test/servisler/ai_servisi_hata_log_test.dart
//
// CLAUDE.md §5.7 regresyonu (2026-11-08): AiServisi'nin AI Panel metotları
// hatayı yalnız `if (kDebugMode) debugPrint` ile yutuyordu — sürüm
// derlemesinde hiçbir yere yazılmıyordu. Artık LogServisi'ne yazılır; panel
// bölümleri birbirini boşaltmasın diye boş değer dönmeye devam eder.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/servisler/ai_servisi.dart';
import 'package:market_plus/servisler/log_servisi.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

void main() {
  late Database db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await TestVeritabani.olustur();
    Veritabani.testVeritabani = db;
  });
  tearDown(() async {
    Veritabani.testVeritabani = null;
    await db.close();
  });

  test('veritabanı hatasında boş döner ve hata LogServisi\'ne yazılır', () async {
    // satislar tablosu yoksa her AI Panel sorgusu hata verir.
    await db.execute('DROP TABLE satislar');

    expect(await AiServisi().gunlukOzet(), isEmpty);
    expect(await AiServisi().enCokSatanlar(), isEmpty);

    final mesajlar = LogServisi().sonLoglar.map((k) => k.mesaj).toList();
    expect(mesajlar, contains('AiServisi.gunlukOzet'));
    expect(mesajlar, contains('AiServisi.enCokSatanlar'));
  });

  test('sağlıklı veritabanında hata kaydı üretmez', () async {
    final once = LogServisi().sonLoglar.where((k) => k.mesaj == 'AiServisi.gunlukOzet').length;
    final ozet = await AiServisi().gunlukOzet();
    expect(ozet, isNotEmpty);
    final sonra = LogServisi().sonLoglar.where((k) => k.mesaj == 'AiServisi.gunlukOzet').length;
    expect(sonra, once);
  });
}
