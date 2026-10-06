// test/veri/sync_cakisma_gercek_akis_test.dart
//
// GERÇEK Veritabani.supaKayitlariGuncelle() akışı. Canlı olay: iade başka
// cihazda kalem kalem eklenirken başlık art arda güncellendi (970,03 →
// 2086,59). Bu cihazda kuyrukta bekleyen değişiklik YOKKEN ikinci güncelleme
// "çözülmemiş sync çakışması" olup uygulanmıyordu.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

void main() {
  late Database db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      // Bu cihazın son (otomatik) gönderimi, çekilen satırın damgasından ESKİ.
      'mp_sync_otogonder_iade': '2026-10-06T17:30:00.000Z',
      'mp_sync_gonder_iade': '2026-10-06T17:30:00.000Z',
    });
    db = await TestVeritabani.olustur();
    Veritabani.testVeritabani = db;
  });
  tearDown(() => db.close());

  Future<double> toplam() async =>
      ((await db.query('iade', where: "global_id = 'g-iade'")).first['toplam_tutar'] as num).toDouble();

  Future<void> yerelIade() => db.insert('iade', {
        'global_id': 'g-iade', 'fis_no': 'IAD-1', 'toplam_tutar': 970.03,
        'durum': 'tamamlandi', 'tarih': '2026-10-06T17:44:00Z',
        'last_updated': '2026-10-06T17:44:50.002466+00:00', // buluttan çekilmiş damga
      });

  Map<String, dynamic> gelen(double tutar) => {
        'global_id': 'g-iade', 'fis_no': 'IAD-1', 'toplam_tutar': tutar,
        'durum': 'tamamlandi', 'tarih': '2026-10-06T17:44:00Z',
        'last_updated': '2026-10-06T17:44:52.43754+00:00',
      };

  test('kuyruk boşken buluttan gelen daha yeni iade tutarı UYGULANIR, çakışma oluşmaz', () async {
    await yerelIade();
    await Veritabani().supaKayitlariGuncelle('iade', [gelen(2086.59)]);
    expect(await toplam(), 2086.59);
    expect(await db.query('sync_cakismalar'), isEmpty);
  });

  test('bu cihazda GÖNDERİLMEMİŞ değişiklik (kuyrukta) varsa çakışma kaydedilir, yerel korunur', () async {
    await yerelIade();
    await db.insert('sync_queue', {
      'tablo_adi': 'iade', 'kayit_global_id': 'g-iade', 'islem_tipi': 'UPSERT',
      'veri_json': '{}', 'durum': 'bekliyor', 'created_at': '2026-10-06T17:44:51Z',
    });
    await Veritabani().supaKayitlariGuncelle('iade', [gelen(2086.59)]);
    expect(await toplam(), 970.03, reason: 'gönderilmemiş yerel değişiklik ezilmemeli');
    final c = await db.query('sync_cakismalar');
    expect(c, hasLength(1));
    expect(c.first['cozuldu'], 0);
  });

  test('daha önce kalmış çözülmemiş sahte çakışma, değer uygulanınca otomatik kapanır', () async {
    await yerelIade();
    await db.insert('sync_cakismalar', {
      'tablo': 'iade', 'kayit_global_id': 'g-iade', 'alan_farklari': '{}',
      'tarih': '2026-10-06T20:45:19', 'cozuldu': 0,
    });
    await Veritabani().supaKayitlariGuncelle('iade', [gelen(2086.59)]);
    expect(await toplam(), 2086.59);
    final c = (await db.query('sync_cakismalar')).first;
    expect(c['cozuldu'], 1);
    expect(c['cozum_tipi'], 'otomatik');
  });
}
