// test/depolar/kasa_zincir_mutabakat_test.dart
//
// Çoklu cihaz analizi (2026-11-08): iki kasa internetsizken aynı şubeye
// hareket yazınca her biri kendi 'bakiye_sonrasi' zincirini sürdürüyordu;
// birleşince zincir (Vardiya anlık kasa bakiyesi ve sonraki hareketin
// başlangıcı) yanlış kalıyor, yalnız Veri Sağlığı'ndan elle düzeltilebiliyordu.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/depolar/kasa_deposu.dart';
import 'package:market_plus/servisler/senkron_sonrasi_mutabakat.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

const _damga = '2026-11-08T08:00:00.000';

Future<void> _hareket(Database db,
    {required String gid, required String tip, required double tutar,
     required double bakiyeSonrasi, required DateTime tarih}) =>
    db.insert('kasa_hareketleri', {
      'global_id': gid, 'sube_id': 1, 'hareket_tipi': tip, 'tutar': tutar,
      'bakiye_sonrasi': bakiyeSonrasi, 'tarih': tarih.toIso8601String(),
      'last_updated': _damga,
    });

Future<Map<String, Object?>> _satir(Database db, String gid) async =>
    (await db.query('kasa_hareketleri', where: 'global_id = ?', whereArgs: [gid])).first;

void main() {
  late Database db;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await TestVeritabani.olustur();
    Veritabani.testVeritabani = db;
    final sube = await db.query('subeler', where: 'id = 1');
    if (sube.isEmpty) {
      await db.insert('subeler', {'id': 1, 'sube_kodu': 'MRK', 'sube_adi': 'Merkez'});
    }
  });
  tearDown(() async {
    Veritabani.testVeritabani = null;
    await db.close();
  });

  test('iki kasanın internetsiz hareketleri birleşince zincir tarih sırasıyla yeniden kurulur', () async {
    final t = DateTime(2026, 11, 8, 10);
    // Bu kasa: 10:00 Satış 100 (kendi zinciri 0 → 100).
    await _hareket(db, gid: 'a1', tip: 'Satış', tutar: 100, bakiyeSonrasi: 100, tarih: t);
    // Diğer kasa (internetsiz): 09:30 Satış 50 → 50, 11:00 Gider 20 → 30.
    await _hareket(db, gid: 'b1', tip: 'Satış', tutar: 50, bakiyeSonrasi: 50,
        tarih: t.subtract(const Duration(minutes: 30)));
    await _hareket(db, gid: 'b2', tip: 'Gider', tutar: 20, bakiyeSonrasi: 30,
        tarih: t.add(const Duration(hours: 1)));

    await SenkronSonrasiMutabakat.calistir(degisenTablolar: {'kasa_hareketleri'});

    expect(((await _satir(db, 'b1'))['bakiye_sonrasi'] as num).toDouble(), 50);
    expect(((await _satir(db, 'a1'))['bakiye_sonrasi'] as num).toDouble(), 150);
    expect(((await _satir(db, 'b2'))['bakiye_sonrasi'] as num).toDouble(), 130);
    expect(await KasaDeposu().bakiyeUyumsuzlukSayisi(), 0);
  });

  test('senkron sonrası düzeltme damgayı ilerletmez ve buluta göndermez (cihazlar arası ping-pong yok)', () async {
    final t = DateTime(2026, 11, 8, 10);
    await _hareket(db, gid: 'a1', tip: 'Satış', tutar: 100, bakiyeSonrasi: 100, tarih: t);
    await _hareket(db, gid: 'b1', tip: 'Satış', tutar: 50, bakiyeSonrasi: 50,
        tarih: t.subtract(const Duration(minutes: 30)));

    expect(await KasaDeposu().zincirMutabakatYap(), 1);
    expect((await _satir(db, 'a1'))['last_updated'], _damga);
    final kuyruk = await db.query('sync_queue', where: "tablo_adi = 'kasa_hareketleri'");
    expect(kuyruk, isEmpty);
    // İkinci çalıştırma: değişecek bir şey yok.
    expect(await KasaDeposu().zincirMutabakatYap(), 0);
  });

  test('buluttan gelen hareket güncellemesi yerel (türetilmiş) bakiye_sonrasi değerini ezmez', () async {
    final t = DateTime(2026, 11, 8, 10);
    await _hareket(db, gid: 'a1', tip: 'Satış', tutar: 100, bakiyeSonrasi: 100, tarih: t);
    await Veritabani().supaKayitlariGuncelle('kasa_hareketleri', [
      {'global_id': 'a1', 'aciklama': 'buluttan', 'bakiye_sonrasi': 9999.0,
       'last_updated': DateTime(2026, 11, 8, 12).toIso8601String()},
    ]);
    final s = await _satir(db, 'a1');
    expect((s['bakiye_sonrasi'] as num).toDouble(), 100);
  });
}
