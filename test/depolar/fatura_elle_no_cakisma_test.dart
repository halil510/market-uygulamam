// test/depolar/fatura_elle_no_cakisma_test.dart
//
// Regresyon (2026-11-06, CLAUDE.md bulgu #3 / §5.4): elle girilen fatura
// numarası mevcut bir faturayla çakışınca FaturaDeposu.ekle() numarayı
// SESSİZCE yerel "en büyük + 1" ile ve sabit 'FAT' serisiyle değiştiriyordu
// (kağıt faturanın numarası değişir, merkezi seri bloğu dışında numara
// üretilir). Artık kayıt yapılmaz, kullanıcıya gösterilecek bir hata döner.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/depolar/fatura_deposu.dart';
import 'package:market_plus/modeller/fatura_model.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (_) async => null);
    SharedPreferences.setMockInitialValues({});
    db = await TestVeritabani.olustur();
    Veritabani.testVeritabani = db;
  });
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    Veritabani.testVeritabani = null;
    await db.close();
  });

  FaturaModel fatura(String no) => FaturaModel(
        faturaNo: no, tarih: DateTime.now(), cariUnvan: 'Test',
        toplamAraToplam: 100, toplamKdv: 20, genelToplam: 120, kalanTutar: 120);

  test('elle girilen numara çakışırsa kayıt yapılmaz ve açık hata döner', () async {
    await FaturaDeposu().ekle(fatura('ABC2026000000007'), const []);

    await expectLater(
      FaturaDeposu().ekle(fatura('ABC2026000000007'), const []),
      throwsA(isA<Exception>().having(
          (e) => e.toString(), 'mesaj', contains('ABC2026000000007'))),
    );

    final hepsi = await db.query('faturalar');
    expect(hepsi, hasLength(1), reason: 'ikinci fatura başka numarayla SESSİZCE kaydedilmemeli');
    expect(hepsi.single['fatura_no'], 'ABC2026000000007');
  });

  test('çakışmayan elle numara olduğu gibi kaydedilir', () async {
    final id = await FaturaDeposu().ekle(fatura('XYZ2026000000001'), const []);
    final f = await FaturaDeposu().idileGetir(id);
    expect(f!.faturaNo, 'XYZ2026000000001');
  });
}
