// test/depolar/sube_urun_deposu_test.dart
//
// Derin analizde bulundu (P0): SubeUrunDeposu.transferEt() ÖNCEDEN
// stokDus() + stokGir() çağırıyordu — ikisi de kendi ayrı transaction'ını
// açıyordu. Kaynağı düşüren işlem başarılı olup hedefi artıran işlem
// başarısız olursa ürün miktarı tamamen kaybolabiliyordu (kaynakta
// azalmış, hedefte hiç artmamış). Bu test, artık her iki güncellemenin
// TEK transaction'da olduğunu ve gerçek şemayla doğru çalıştığını
// doğruluyor.
//
// 2026-11-06 (test güvenilirliği, Kademe 1): bu test ÖNCEDEN transferEt()'in
// kopyası olan SubeUrunDeposuTest.transferEt'i çağırıyordu — üretim kodu
// bozulsa bile yeşil kalırdı. Artık GERÇEK SubeUrunDeposu().transferEt()
// çağrılıyor.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/depolar/sube_urun_deposu.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

Future<int> _subeEkle(Database db, String ad) => db.insert('subeler', {
  'sube_adi': ad, 'sube_kodu': ad.replaceAll(' ', '').toUpperCase(),
  'aktif': 1, 'is_deleted': 0,
});

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

  group('SubeUrunDeposu.transferEt', () {
    test('kaynaktan düşer, hedefe eklenir — toplam miktar korunur', () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db);
      final subeA = await _subeEkle(db, 'Şube A');
      final subeB = await _subeEkle(db, 'Şube B');

      await db.insert('sube_urun', {
        'urun_id': urunId, 'sube_id': subeA, 'stok': 50,
        'son_guncelleme': DateTime.now().toIso8601String(),
        'last_updated': DateTime.now().toIso8601String(),
      });

      await SubeUrunDeposu().transferEt(
          urunId: urunId, kaynakSubeId: subeA, hedefSubeId: subeB, miktar: 20);

      final kaynak = (await db.query('sube_urun', where: 'urun_id = ? AND sube_id = ?', whereArgs: [urunId, subeA])).first;
      final hedef = (await db.query('sube_urun', where: 'urun_id = ? AND sube_id = ?', whereArgs: [urunId, subeB])).first;
      expect((kaynak['stok'] as num).toDouble(), equals(30.0));
      expect((hedef['stok'] as num).toDouble(), equals(20.0));
    });

    test('kaynak yetersizse hata fırlatır, HİÇBİR satır değişmez', () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db);
      final subeA = await _subeEkle(db, 'Şube A');
      final subeB = await _subeEkle(db, 'Şube B');
      await db.insert('sube_urun', {
        'urun_id': urunId, 'sube_id': subeA, 'stok': 5,
        'son_guncelleme': DateTime.now().toIso8601String(),
        'last_updated': DateTime.now().toIso8601String(),
      });

      await expectLater(
        SubeUrunDeposu().transferEt(urunId: urunId, kaynakSubeId: subeA, hedefSubeId: subeB, miktar: 10),
        throwsException,
      );

      final kaynak = (await db.query('sube_urun', where: 'urun_id = ? AND sube_id = ?', whereArgs: [urunId, subeA])).first;
      expect((kaynak['stok'] as num).toDouble(), equals(5.0), reason: 'Değişmemeli');
      final hedef = await db.query('sube_urun', where: 'urun_id = ? AND sube_id = ?', whereArgs: [urunId, subeB]);
      expect(hedef, isEmpty, reason: 'Hedefte satır oluşmamalı');
    });

    test('hedefte önceden satır yoksa yeni satır oluşturulur', () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db);
      final subeA = await _subeEkle(db, 'Şube A');
      final subeB = await _subeEkle(db, 'Şube B');
      await db.insert('sube_urun', {
        'urun_id': urunId, 'sube_id': subeA, 'stok': 15,
        'son_guncelleme': DateTime.now().toIso8601String(),
        'last_updated': DateTime.now().toIso8601String(),
      });

      await SubeUrunDeposu().transferEt(
          urunId: urunId, kaynakSubeId: subeA, hedefSubeId: subeB, miktar: 15);

      final hedef = (await db.query('sube_urun', where: 'urun_id = ? AND sube_id = ?', whereArgs: [urunId, subeB])).first;
      expect((hedef['stok'] as num).toDouble(), equals(15.0));
      expect(hedef['global_id'], isNotNull);
    });

    test('DÜZELTME REGRESYONU: her iki taraf için de stok_hareket denetim izi bırakır', () async {
      // Kök neden: transferEt ÖNCEDEN SADECE sube_urun'u güncelliyordu —
      // satış/alış/iade/sayım/lot düzeltme gibi HER DİĞER stok akışının
      // aksine stok_hareket'e hiç kayıt düşmüyordu.
      final urunId = await TestVeritabani.ornekUrunEkle(db);
      final subeA = await _subeEkle(db, 'Şube A');
      final subeB = await _subeEkle(db, 'Şube B');
      await db.insert('sube_urun', {
        'urun_id': urunId, 'sube_id': subeA, 'stok': 40,
        'son_guncelleme': DateTime.now().toIso8601String(),
        'last_updated': DateTime.now().toIso8601String(),
      });

      await SubeUrunDeposu().transferEt(
          urunId: urunId, kaynakSubeId: subeA, hedefSubeId: subeB, miktar: 12);

      final hareketler = await db.query('stok_hareket',
          where: 'urun_id = ? AND referans_turu = ?', whereArgs: [urunId, 'sube_transfer'],
          orderBy: 'hareket_turu');

      expect(hareketler.length, 2, reason: 'kaynak (çıkış) + hedef (giriş) olmak üzere 2 satır olmalı');

      final cikis = hareketler.firstWhere((h) => h['hareket_turu'] == 'Şube Transfer Çıkış');
      expect(cikis['sube_id'], subeA);
      expect((cikis['onceki_stok'] as num).toDouble(), 40.0);
      expect((cikis['sonraki_stok'] as num).toDouble(), 28.0);
      expect((cikis['miktar'] as num).toDouble(), 12.0);

      final giris = hareketler.firstWhere((h) => h['hareket_turu'] == 'Şube Transfer Giriş');
      expect(giris['sube_id'], subeB);
      expect((giris['onceki_stok'] as num).toDouble(), 0.0);
      expect((giris['sonraki_stok'] as num).toDouble(), 12.0);
    });
  });
}
