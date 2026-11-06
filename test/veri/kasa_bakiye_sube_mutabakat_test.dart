// test/veri/kasa_bakiye_sube_mutabakat_test.dart
//
// FAZ 1 — DEEP_AUDIT_REPORT_2026-09-20.md madde 2 ("[HIGH] Çok şubeli
// kasa mutabakat düzeltmesi şube karıştırıyor"):
// KasaDeposu.hareketSil() / bakiyeMutabakatYap() / bakiyeUyumsuzlukSayisi()
// ÖNCEDEN 'bakiye_sonrasi' zincirini TÜM şubelerin hareketlerini TEK bir
// sırada karıştırarak yeniden hesaplıyordu — "düzelt" aksiyonu aslında
// farklı şubelerin bakiyelerini birbirine karıştırarak veriyi BOZUYORDU.
// Düzeltme: her şube (ve sube_id NULL olan eski kayıtlar) KENDİ bağımsız
// zincirinde, sıfırdan yeniden hesaplanıyor.
//
// 2026-11-06 (test güvenilirliği + CLAUDE.md §4.2): bu test ÖNCEDEN
// mutabakat algoritmasının kopyalarını çağırıyordu. Algoritma artık
// KasaDeposu içinde tek fonksiyonda (_zincirSapanlariBulTxn); test GERÇEK
// KasaDeposu().bakiyeMutabakatYap() / bakiyeUyumsuzlukSayisi() çağırıyor.
// Hiç çağrılmayan ve tüm geçmişi yeniden yazan hareketSil() silindi; onun
// senaryosu gerçek karşılığıyla (soft-delete + mutabakat) korunuyor.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/depolar/kasa_deposu.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

Future<int> _bakiyeMutabakatYap() => KasaDeposu().bakiyeMutabakatYap();

Future<double?> _bakiyeSonrasi(Database db, int id) async {
  final rows = await db.query('kasa_hareketleri',
      columns: ['bakiye_sonrasi'], where: 'id = ?', whereArgs: [id]);
  return (rows.first['bakiye_sonrasi'] as num?)?.toDouble();
}

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

  group('KasaDeposu şube bazlı bakiye mutabakatı (Madde 2 regresyonu)', () {
    test(
        'bakiyeMutabakatYap — 2 şubenin hareketleri interleaved eklenince '
        'BİRBİRİNE KARIŞMADAN, her şube kendi bağımsız zincirinde hesaplanır',
        () async {
      final t0 = DateTime(2026, 9, 21, 9, 0);
      // Interleaved id sırası: Şube1(+100), Şube2(+50), Şube1(+30) —
      // eski (buggy) kod TEK zincirde 100 → 150 → 180 üretirdi.
      final id1 = await db.insert('kasa_hareketleri', {
        'hareket_tipi': 'Satış', 'tutar': 100, 'sube_id': 1,
        'tarih': t0.toIso8601String(),
      });
      final id2 = await db.insert('kasa_hareketleri', {
        'hareket_tipi': 'Satış', 'tutar': 50, 'sube_id': 2,
        'tarih': t0.add(const Duration(minutes: 1)).toIso8601String(),
      });
      final id3 = await db.insert('kasa_hareketleri', {
        'hareket_tipi': 'Tahsilat', 'tutar': 30, 'sube_id': 1,
        'tarih': t0.add(const Duration(minutes: 2)).toIso8601String(),
      });

      final duzeltilen = await _bakiyeMutabakatYap();
      expect(duzeltilen, 3);

      // Şube 1 KENDİ zincirinde: 100 → 130 (Şube 2'nin 50'si karışmıyor).
      expect(await _bakiyeSonrasi(db, id1), 100);
      expect(await _bakiyeSonrasi(db, id3), 130);
      // Şube 2 KENDİ zincirinde: sadece 50.
      expect(await _bakiyeSonrasi(db, id2), 50);
    });

    test(
        'silme — Şube 2 hareketi silinip mutabakat çalışınca Şube 1 zinciri ETKİLENMEZ',
        () async {
      final t0 = DateTime(2026, 9, 21, 9, 0);
      final id1 = await db.insert('kasa_hareketleri', {
        'hareket_tipi': 'Satış', 'tutar': 100, 'sube_id': 1,
        'tarih': t0.toIso8601String(), 'bakiye_sonrasi': 100,
      });
      final id2 = await db.insert('kasa_hareketleri', {
        'hareket_tipi': 'Satış', 'tutar': 50, 'sube_id': 2,
        'tarih': t0.add(const Duration(minutes: 1)).toIso8601String(),
        'bakiye_sonrasi': 50,
      });
      final id3 = await db.insert('kasa_hareketleri', {
        'hareket_tipi': 'Tahsilat', 'tutar': 30, 'sube_id': 1,
        'tarih': t0.add(const Duration(minutes: 2)).toIso8601String(),
        'bakiye_sonrasi': 130,
      });

      // Silme = soft-delete (deleted_at), ardından mutabakat.
      await db.update('kasa_hareketleri', {'deleted_at': DateTime.now().toIso8601String()},
          where: 'id = ?', whereArgs: [id2]);
      expect(await KasaDeposu().bakiyeUyumsuzlukSayisi(), 0,
          reason: 'Şube 1 zinciri zaten doğru; Şube 2 artık boş');
      expect(await _bakiyeMutabakatYap(), 0);

      // Şube 1 zinciri Şube 2'deki silme işleminden ETKİLENMEMELİ.
      expect(await _bakiyeSonrasi(db, id1), 100);
      expect(await _bakiyeSonrasi(db, id3), 130);
    });

    test(
        'sube_id NULL olan eski kayıtlar KENDİ ayrı grubunda hesaplanır, '
        'şube 1 ile karışmaz', () async {
      final t0 = DateTime(2026, 9, 21, 9, 0);
      final idNull = await db.insert('kasa_hareketleri', {
        'hareket_tipi': 'Satış', 'tutar': 20, 'sube_id': null,
        'tarih': t0.toIso8601String(),
      });
      final id1 = await db.insert('kasa_hareketleri', {
        'hareket_tipi': 'Satış', 'tutar': 100, 'sube_id': 1,
        'tarih': t0.add(const Duration(minutes: 1)).toIso8601String(),
      });

      await _bakiyeMutabakatYap();

      expect(await _bakiyeSonrasi(db, idNull), 20);
      expect(await _bakiyeSonrasi(db, id1), 100);
    });
  });
}
