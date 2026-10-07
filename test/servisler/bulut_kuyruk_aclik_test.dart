// test/servisler/bulut_kuyruk_aclik_test.dart
//
// Bulut Veri Güvenliği Raporu (2026-10-07), Bulgu 5 — kuyruk açlığı:
// ebeveyni buluta ulaşmayan yüzlerce satır (backoff penceresinde) kuyruğun
// başını işgal edince, arkadaki YENİ satışlar hiç gönderilmiyordu.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/servisler/bulut/bulut_manager.dart';
import 'package:market_plus/servisler/bulut/bulut_saglayici.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

class _SahteSaglayici implements IBulutSaglayici {
  final gidenGidler = <String>[];

  @override String get ad => 'Sahte';
  @override String get ikon => '🧪';
  @override Future<BaglantiSonuc> baglantiTest() async =>
      const BaglantiSonuc(basarili: true, mesaj: 'ok');
  @override
  Future<void> upsert({required String tablo, required Map<String, dynamic> veri,
      required String uniqueAlan}) async {}
  @override
  Future<BulutSonuc> topluUpsert({required String tablo,
      required List<Map<String, dynamic>> veriler, required String uniqueAlan}) async {
    gidenGidler.addAll(veriler.map((v) => v['global_id'].toString()));
    return BulutSonuc(basarili: veriler.length);
  }
  @override
  Future<List<Map<String, dynamic>>> cek({required String tablo,
      DateTime? sonGuncelleme, int limit = 1000}) async => [];
  @override
  Future<void> sil({required String tablo, required String uniqueAlan,
      required String deger}) async {}
  @override
  Future<void> kaliciSil({required String tablo, required String uniqueAlan,
      required String deger}) async {}
  @override Future<void> ayarlariKaydet(Map<String, String> ayarlar) async {}
  @override Future<Map<String, String>> ayarlariYukle() async => {};
}

void main() {
  late Database db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await TestVeritabani.olustur();
    Veritabani.testVeritabani = db;
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    BulutManager().testIcinSifirla();
    Veritabani.testVeritabani = null;
    await db.close();
  });

  test('backoff penceresindeki 600 satır yeni satışın gönderimini engellemez', () async {
    final simdi = DateTime.now().toIso8601String();
    final batch = db.batch();
    for (var i = 0; i < 600; i++) {
      batch.insert('sync_queue', {
        'tablo_adi': 'stok_hareket',
        'kayit_global_id': 'BEKLEYEN-$i',
        'islem_tipi': 'UPSERT',
        'veri_json': jsonEncode({'global_id': 'BEKLEYEN-$i'}),
        'deneme_sayisi': 6, // ~10 dk backoff — bu turda denenmez
        'son_deneme': simdi,
        'hata_mesaji': 'ebeveyn kayıt henüz bulutta yok — bekletildi',
        'durum': 'beklemede',
      });
    }
    await batch.commit(noResult: true);
    await db.insert('sync_queue', {
      'tablo_adi': 'satislar',
      'kayit_global_id': 'YENI-SATIS',
      'islem_tipi': 'UPSERT',
      'veri_json': jsonEncode({'global_id': 'YENI-SATIS', 'fis_no': 'MKP1'}),
      'deneme_sayisi': 0,
      'durum': 'beklemede',
    });

    final sahte = _SahteSaglayici();
    await BulutManager().saglayiciAyarla(sahte);
    // saglayiciAyarla arka planda bir tur başlatır; o tur sürerken
    // zorlaGonder erken döner — satış gidene (ya da süre dolana) kadar dene.
    for (var i = 0; i < 40 && !sahte.gidenGidler.contains('YENI-SATIS'); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await BulutManager().zorlaGonder();
    }

    expect(sahte.gidenGidler, contains('YENI-SATIS'));
    expect(sahte.gidenGidler.where((g) => g.startsWith('BEKLEYEN')), isEmpty,
        reason: 'backoff penceresindekiler bu turda denenmez');
    final kalan = await db.query('sync_queue', where: "kayit_global_id = 'YENI-SATIS'");
    expect(kalan, isEmpty, reason: 'gönderilen satış kuyruktan düşer');
  });
}
