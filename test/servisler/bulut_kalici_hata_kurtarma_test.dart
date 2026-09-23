// test/servisler/bulut_kalici_hata_kurtarma_test.dart
//
// BulutManager — 'kalici_hata' sync_queue satırlarının genel kurtarması.
// Önceden bu satırlar bir daha hiç denenmiyordu (kod/anahtar düzeltilse
// bile). Sağlayıcı ayarlanmadığı için _isle() erken döner — burada yalnızca
// kuyruk durumu geçişleri test edilir.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/servisler/bulut/bulut_manager.dart';
import 'package:market_plus/servisler/bulut/sync_backoff.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

Future<int> _satir(Database db, {required String durum, int deneme = 0, String tablo = 'satislar'}) =>
    db.insert('sync_queue', {
      'tablo_adi': tablo,
      'islem_tipi': 'UPSERT',
      'veri_json': '{}',
      'durum': durum,
      'deneme_sayisi': deneme,
      'hata_mesaji': 'HTTP 400 örnek',
    });

Future<Map<String, Object?>> _oku(Database db, int id) async =>
    (await db.query('sync_queue', where: 'id = ?', whereArgs: [id])).first;

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

  test('otomatik: sınırın altındaki kalıcı hata beklemeye döner, deneme sayısı korunur', () async {
    final id = await _satir(db, durum: 'kalici_hata', deneme: 3);
    final adet = await BulutManager().kaliciHatalariOtomatikGeriAl();
    expect(adet, 1);
    final r = await _oku(db, id);
    expect(r['durum'], 'beklemede');
    expect(r['deneme_sayisi'], 3); // backoff geçerli kalsın
  });

  test('otomatik: sınıra ulaşmış satıra dokunulmaz (sonsuz yeniden deneme yok)', () async {
    final id = await _satir(db, durum: 'kalici_hata', deneme: kaliciHataOtomatikDenemeSiniri);
    expect(await BulutManager().kaliciHatalariOtomatikGeriAl(), 0);
    expect((await _oku(db, id))['durum'], 'kalici_hata');
  });

  test('elle: tüm kalıcı hatalar sıfırlanır, diğer satırlara dokunulmaz', () async {
    final a = await _satir(db, durum: 'kalici_hata', deneme: 50);
    final b = await _satir(db, durum: 'kalici_hata', deneme: 2, tablo: 'cari');
    final c = await _satir(db, durum: 'beklemede', deneme: 4);
    expect(await BulutManager().kaliciHatalariYenidenDene(), 2);
    expect((await _oku(db, a))['deneme_sayisi'], 0);
    expect((await _oku(db, b))['durum'], 'beklemede');
    expect((await _oku(db, c))['deneme_sayisi'], 4);
  });

  test('özet tablo bazında gruplar', () async {
    await _satir(db, durum: 'kalici_hata');
    await _satir(db, durum: 'kalici_hata');
    await _satir(db, durum: 'kalici_hata', tablo: 'cari');
    await _satir(db, durum: 'beklemede');
    final ozet = await BulutManager().kaliciHataOzeti();
    expect(ozet.map((o) => (o.tablo, o.adet)).toList(), [('satislar', 2), ('cari', 1)]);
    expect(ozet.first.ornekHata, 'HTTP 400 örnek');
  });
}
