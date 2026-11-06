// test/depolar/veri_sagligi_mutabakat_test.dart
//
// Veri Sağlığı Merkezi'nin (protokol §13) dayandığı yeni mutabakat
// fonksiyonlarını (CariDeposu.bakiyeMutabakatYap, KasaDeposu
// .bakiyeMutabakatYap, BankaHesapDeposu.bakiyeMutabakatYap) gerçek
// .bakiyeMutabakatYap, BankaHesapDeposu.bakiyeMutabakatYap) gerçek
// şemayla doğrular.
//
// 2026-11-06 (test güvenilirliği, Kademe 1): bu test ÖNCEDEN üç depo
// metodunun SQL/algoritmasını KOPYALAYAN yardımcılar çağırıyordu — üretim
// kodu bozulsa bile yeşil kalırdı. Artık GERÇEK depo metotları çağrılıyor
// (Veritabani.testVeritabani seam'i ile bellek-içi gerçek şema).
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/depolar/banka_hesap_deposu.dart';
import 'package:market_plus/depolar/cari_deposu.dart';
import 'package:market_plus/depolar/kasa_deposu.dart';
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

  group('Cari bakiye mutabakatı', () {
    test('bakiye zaten doğruysa uyumsuzluk sayısı 0', () async {
      final cariId = await TestVeritabani.ornekCariEkle(db);
      await db.insert('cari_hareket', {'cari_id': cariId, 'borc': 100, 'alacak': 0, 'is_deleted': 0, 'fis_tipi': 'Test', 'tarih': DateTime.now().toIso8601String()});
      await db.update('cari', {'bakiye': 100}, where: 'id = ?', whereArgs: [cariId]);

      expect(await CariDeposu().bakiyeUyumsuzlukSayisi(), equals(0));
    });

    test('bakiye yanlışsa tespit edilir ve düzeltilince doğrulanır', () async {
      final cariId = await TestVeritabani.ornekCariEkle(db);
      await db.insert('cari_hareket', {'cari_id': cariId, 'borc': 500, 'alacak': 200, 'is_deleted': 0, 'fis_tipi': 'Test', 'tarih': DateTime.now().toIso8601String()});
      // Kasıtlı olarak yanlış bir bakiye yaz (gerçek değer 300 olmalı).
      await db.update('cari', {'bakiye': 999}, where: 'id = ?', whereArgs: [cariId]);

      expect(await CariDeposu().bakiyeUyumsuzlukSayisi(), equals(1));

      final duzeltilen = await CariDeposu().bakiyeMutabakatYap();
      expect(duzeltilen, equals(1));

      final cari = (await db.query('cari', where: 'id = ?', whereArgs: [cariId])).first;
      expect((cari['bakiye'] as num).toDouble(), equals(300.0));
      expect(await CariDeposu().bakiyeUyumsuzlukSayisi(), equals(0));
    });

    // 🔴 Regresyon testi (kullanıcı isteği — "veri sağlığı merkezine
    // düzgün bak"): ÖNCEDEN CariDeposu.bakiyeYenidenHesapla() (bu
    // fonksiyonun dayandığı GERÇEK kod) last_updated'ı hiç bümlemiyordu
    // — düzeltilen bakiye normal "Hızlı Gönder" (delta) senkronuyla
    // ASLA buluta/diğer cihazlara gitmiyordu.
    test('düzeltme sonrası last_updated bümlenir — delta senkron bunu '
        'yakalayabilsin diye', () async {
      final cariId = await TestVeritabani.ornekCariEkle(db);
      await db.update('cari', {'last_updated': '2020-01-01T00:00:00'},
          where: 'id = ?', whereArgs: [cariId]);
      await db.insert('cari_hareket', {'cari_id': cariId, 'borc': 500, 'alacak': 0, 'is_deleted': 0, 'fis_tipi': 'Test', 'tarih': DateTime.now().toIso8601String()});
      await db.update('cari', {'bakiye': 999, 'last_updated': '2020-01-01T00:00:00'}, where: 'id = ?', whereArgs: [cariId]);

      await CariDeposu().bakiyeMutabakatYap();

      final cari = (await db.query('cari', where: 'id = ?', whereArgs: [cariId])).first;
      expect(cari['last_updated'], isNot(equals('2020-01-01T00:00:00')),
          reason: 'düzeltme sonrası last_updated GÜNCEL olmalı, aksi halde '
              'delta senkron bu düzeltmeyi hiç görmez');
    });
  });

  group('Kasa bakiye mutabakatı', () {
    test('sırayla doğru hesaplanmış bakiye_sonrasi değerlerine dokunulmaz', () async {
      await db.insert('kasa_hareketleri', {'hareket_tipi': 'Satış', 'tutar': 100, 'bakiye_sonrasi': 100, 'tarih': '2026-01-01T10:00:00'});
      await db.insert('kasa_hareketleri', {'hareket_tipi': 'Gider', 'tutar': 30, 'bakiye_sonrasi': 70, 'tarih': '2026-01-01T11:00:00'});

      final duzeltilen = await KasaDeposu().bakiyeMutabakatYap();
      expect(duzeltilen, equals(0));
    });

    test('yanlış bakiye_sonrasi tespit edilip zincirleme düzeltilir', () async {
      await db.insert('kasa_hareketleri', {'hareket_tipi': 'Satış', 'tutar': 100, 'bakiye_sonrasi': 999, 'tarih': '2026-01-01T10:00:00'});
      await db.insert('kasa_hareketleri', {'hareket_tipi': 'Gider', 'tutar': 30, 'bakiye_sonrasi': 999, 'tarih': '2026-01-01T11:00:00'});

      final duzeltilen = await KasaDeposu().bakiyeMutabakatYap();
      expect(duzeltilen, equals(2));

      final rows = await db.query('kasa_hareketleri', orderBy: 'tarih ASC');
      expect((rows[0]['bakiye_sonrasi'] as num).toDouble(), equals(100.0));
      expect((rows[1]['bakiye_sonrasi'] as num).toDouble(), equals(70.0));
    });

    test('silinmiş (deleted_at dolu) hareketler hesaba katılmaz', () async {
      await db.insert('kasa_hareketleri', {'hareket_tipi': 'Satış', 'tutar': 100, 'bakiye_sonrasi': 100, 'tarih': '2026-01-01T10:00:00'});
      await db.insert('kasa_hareketleri', {
        'hareket_tipi': 'Satış', 'tutar': 500, 'bakiye_sonrasi': 600,
        'tarih': '2026-01-01T10:30:00', 'deleted_at': '2026-01-02T00:00:00',
      });
      await db.insert('kasa_hareketleri', {'hareket_tipi': 'Gider', 'tutar': 30, 'bakiye_sonrasi': 70, 'tarih': '2026-01-01T11:00:00'});

      final duzeltilen = await KasaDeposu().bakiyeMutabakatYap();
      expect(duzeltilen, equals(0), reason: 'Zaten doğru: silinmiş hareket hesaba katılmamalı');
    });
  });

  group('Banka bakiye mutabakatı', () {
    Future<int> hesapEkle(double bakiye) => db.insert('banka_hesaplar', {
      'banka_id': 1, 'hesap_adi': 'Test', 'hesap_no': '1', 'bakiye': bakiye, 'aktif': 1,
    });

    test('hareket yoksa uyumsuzluk sayılmaz (yeni açılmış hesap)', () async {
      await hesapEkle(500);
      expect(await BankaHesapDeposu().bakiyeUyumsuzlukSayisi(), 0);
    });

    test('bakiye son hareketin sonraki_bakiye değeriyle uyumluysa dokunulmaz', () async {
      final hesapId = await hesapEkle(70);
      await db.insert('banka_hareketler', {
        'banka_hesap_id': hesapId, 'islem_tipi': 'Gelen', 'tutar': 100,
        'onceki_bakiye': 0, 'sonraki_bakiye': 100, 'tarih': '2026-01-01T10:00:00',
      });
      await db.insert('banka_hareketler', {
        'banka_hesap_id': hesapId, 'islem_tipi': 'Giden', 'tutar': 30,
        'onceki_bakiye': 100, 'sonraki_bakiye': 70, 'tarih': '2026-01-01T11:00:00',
      });
      await db.update('banka_hesaplar', {'bakiye': 70}, where: 'id = ?', whereArgs: [hesapId]);

      expect(await BankaHesapDeposu().bakiyeMutabakatYap(), equals(0));
    });

    test('bakiye elle bozulmuşsa (hareketten sapmışsa) düzeltilir', () async {
      final hesapId = await hesapEkle(999); // yanlış — olması gereken 70
      await db.insert('banka_hareketler', {
        'banka_hesap_id': hesapId, 'islem_tipi': 'Gelen', 'tutar': 100,
        'onceki_bakiye': 0, 'sonraki_bakiye': 100, 'tarih': '2026-01-01T10:00:00',
      });
      await db.insert('banka_hareketler', {
        'banka_hesap_id': hesapId, 'islem_tipi': 'Giden', 'tutar': 30,
        'onceki_bakiye': 100, 'sonraki_bakiye': 70, 'tarih': '2026-01-01T11:00:00',
      });

      final duzeltilen = await BankaHesapDeposu().bakiyeMutabakatYap();
      expect(duzeltilen, equals(1));

      final hesap = (await db.query('banka_hesaplar', where: 'id = ?', whereArgs: [hesapId])).first;
      expect((hesap['bakiye'] as num).toDouble(), equals(70.0));
    });

    // 🔴 Regresyon testi (bkz. Cari bölümündeki AYNI not) — banka
    // mutabakatı zaten last_updated bümlüyordu, ama bu davranışın
    // korunduğunu doğrulayan açık bir test yoktu.
    test('düzeltme sonrası last_updated bümlenir', () async {
      final hesapId = await hesapEkle(999);
      await db.update('banka_hesaplar', {'last_updated': '2020-01-01T00:00:00'},
          where: 'id = ?', whereArgs: [hesapId]);
      await db.insert('banka_hareketler', {
        'banka_hesap_id': hesapId, 'islem_tipi': 'Gelen', 'tutar': 100,
        'onceki_bakiye': 0, 'sonraki_bakiye': 100, 'tarih': '2026-01-01T10:00:00',
      });

      await BankaHesapDeposu().bakiyeMutabakatYap();

      final hesap = (await db.query('banka_hesaplar', where: 'id = ?', whereArgs: [hesapId])).first;
      expect(hesap['last_updated'], isNot(equals('2020-01-01T00:00:00')));
    });
  });
}
