// test/servisler/bulut_bekleyen_ozet_test.dart
//
// BulutManager.bekleyenOzeti() — Bulut Senkronizasyon ekranındaki özet
// kartının veri kaynağı: yalnız 'beklemede' satırları sayar, kalıcı hatalar
// kapsam dışıdır; geçici hata alanlar ve en eski kayıt ayrıca raporlanır.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/servisler/bulut/bulut_manager.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

Future<int> _satir(
  Database db, {
  required String durum,
  int deneme = 0,
  String? hata,
  String? olusturma,
  String? sonDeneme,
}) =>
    db.insert('sync_queue', {
      'tablo_adi': 'satislar',
      'islem_tipi': 'UPSERT',
      'veri_json': '{}',
      'durum': durum,
      'deneme_sayisi': deneme,
      'hata_mesaji': hata,
      'created_at': ?olusturma,
      'son_deneme': ?sonDeneme,
    });

void main() {
  late Database db;
  setUp(() async {
    db = await TestVeritabani.olustur();
    Veritabani.testVeritabani = db;
  });
  tearDown(() async {
    Veritabani.testVeritabani = null;
    await db.close();
  });

  test('boş kuyruk: sıfır bekleyen, en eski ve son hata yok', () async {
    final o = await BulutManager().bekleyenOzeti();
    expect(o.bekleyen, 0);
    expect(o.yenidenDenenen, 0);
    expect(o.enEski, isNull);
    expect(o.sonHata, isNull);
  });

  test('yalnız beklemede satırları sayılır; kalıcı hata kapsam dışı', () async {
    await _satir(db, durum: 'beklemede');
    await _satir(db, durum: 'beklemede', deneme: 2, hata: 'SocketException');
    await _satir(db, durum: 'kalici_hata', deneme: 5, hata: 'HTTP 400');

    final o = await BulutManager().bekleyenOzeti();
    expect(o.bekleyen, 2);
    expect(o.yenidenDenenen, 1);
    expect(o.sonHata, 'SocketException');
  });

  test('en eski bekleyen kayıt (UTC damgası yerel saate çevrilerek) döner', () async {
    await _satir(db, durum: 'beklemede', olusturma: '2026-09-28 10:00:00');
    await _satir(db, durum: 'beklemede', olusturma: '2026-09-28 12:00:00');
    await _satir(db, durum: 'kalici_hata', olusturma: '2026-01-01 00:00:00');

    final o = await BulutManager().bekleyenOzeti();
    expect(o.enEski, DateTime.utc(2026, 9, 28, 10).toLocal());
  });

  test('son hata, en son denenen satırın hata metnidir', () async {
    await _satir(db,
        durum: 'beklemede', deneme: 1, hata: 'eski hata', sonDeneme: '2026-09-28T10:00:00Z');
    await _satir(db,
        durum: 'beklemede', deneme: 1, hata: 'yeni hata', sonDeneme: '2026-09-28T11:00:00Z');

    final o = await BulutManager().bekleyenOzeti();
    expect(o.sonHata, 'yeni hata');
  });
}
