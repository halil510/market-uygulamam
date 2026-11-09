// test/depolar/satis_sil_guncelleme_iade_test.dart
//
// Derin denetim (2026-11-09), yüksek:
//  #3 Güncellenmiş fiş silinince 'fis_guncelleme' kasa satırları ters
//     çevrilmiyor, kasa kalıcı yanlış kalıyordu.
//  #4 İade alınmış satış silinince stok/kasa/cari ikinci kez iade ediliyordu.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/depolar/satis_deposu.dart';
import 'package:market_plus/modeller/kasa_hareket_model.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

final _t = DateTime(2026, 11, 9, 10).toIso8601String();

Future<int> _satis(Database db, {String yontem = 'Nakit', double toplam = 100}) =>
    db.insert('satislar', {
      'global_id': 's-${DateTime.now().microsecondsSinceEpoch}', 'fis_no': 'F-${DateTime.now().microsecondsSinceEpoch}',
      'tarih': _t, 'genel_toplam': toplam, 'odeme_yontemi': yontem,
      'sube_id': 1, 'is_deleted': 0, 'iptal': 0,
    });

Future<void> _kasa(Database db, int satisId, String tip, double tutar, String yontem, String tur) =>
    db.insert('kasa_hareketleri', {
      'hareket_tipi': tip, 'tutar': tutar, 'odeme_yontemi': yontem,
      'referans_id': satisId, 'referans_turu': tur, 'sube_id': 1, 'tarih': _t,
    });

/// Ödeme yöntemine göre kasa net etkisi (giriş +, çıkış −).
Future<Map<String, double>> _yontemNet(Database db) async {
  final m = <String, double>{};
  for (final r in await db.query('kasa_hareketleri', where: 'deleted_at IS NULL')) {
    final t = (r['tutar'] as num).toDouble();
    final y = r['odeme_yontemi'] as String? ?? '';
    m[y] = (m[y] ?? 0) + (KasaHareketModel.girisMi(r['hareket_tipi'] as String) ? t : -t);
  }
  return m;
}

void main() {
  late Database db;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await TestVeritabani.olustur();
    Veritabani.testVeritabani = db;
    if ((await db.query('subeler', where: 'id = 1')).isEmpty) {
      await db.insert('subeler', {'id': 1, 'sube_kodu': 'MRK', 'sube_adi': 'Merkez'});
    }
  });
  tearDown(() async {
    Veritabani.testVeritabani = null;
    await db.close();
  });

  test('#3 tutarı artırılmış (fiş güncelleme) nakit fiş silinince kasa sıfırlanır', () async {
    final id = await _satis(db, toplam: 150);
    await _kasa(db, id, 'Satış', 100, 'Nakit', 'satis');
    await _kasa(db, id, 'Satış', 50, 'Nakit', 'fis_guncelleme'); // güncellemede +50
    await SatisDeposu().sil(id);
    final net = await _yontemNet(db);
    expect(net['Nakit'], closeTo(0, 0.001), reason: 'önceden +50 kalıyordu');
  });

  test('#3 güncellemede Nakit → Kart çevrilen fiş silinince iki kasa da sıfırlanır', () async {
    final id = await _satis(db, yontem: 'Kredi Kartı');
    await _kasa(db, id, 'Satış', 100, 'Nakit', 'satis');
    await _kasa(db, id, 'İade', 100, 'Nakit', 'fis_guncelleme'); // eski nakit geri verildi
    await _kasa(db, id, 'Satış', 100, 'Kredi Kartı', 'satis'); // yeni kart ödemesi
    await SatisDeposu().sil(id);
    final net = await _yontemNet(db);
    expect(net['Nakit'], closeTo(0, 0.001), reason: 'önceden −100 açık veriyordu');
    expect(net['Kredi Kartı'], closeTo(0, 0.001));
  });

  test('#4 iade alınmış satış silinemez; hiçbir ters kayıt yazılmaz', () async {
    final urunId = await TestVeritabani.ornekUrunEkle(db, stok: 10);
    final id = await _satis(db);
    await db.insert('satis_kalem', {
      'satis_id': id, 'urun_id': urunId, 'urun_adi': 'X', 'miktar': 2, 'birim_fiyat': 50,
    });
    await _kasa(db, id, 'Satış', 100, 'Nakit', 'satis');
    await db.insert('iade', {'satis_id': id, 'fis_no': 'IAD-1', 'tarih': _t, 'toplam_tutar': 50});

    await expectLater(SatisDeposu().sil(id), throwsA(isA<Exception>()
        .having((e) => e.toString(), 'mesaj', contains('önce iadeyi silin'))));
    final satis = (await db.query('satislar', where: 'id = ?', whereArgs: [id])).first;
    expect(satis['iptal'], 0);
    expect(await db.query('kasa_hareketleri', where: "referans_turu = 'satis_iptal'"), isEmpty);
    expect(((await db.query('urunler', where: 'id = ?', whereArgs: [urunId])).first['stok'] as num)
        .toDouble(), 10);
  });

  test('#4 iadesi silinmiş (iptal) satış normal silinebilir', () async {
    final id = await _satis(db);
    await _kasa(db, id, 'Satış', 100, 'Nakit', 'satis');
    await db.insert('iade', {
      'satis_id': id, 'fis_no': 'IAD-2', 'tarih': _t, 'toplam_tutar': 50, 'durum': 'iptal',
    });
    await SatisDeposu().sil(id);
    expect((await db.query('satislar', where: 'id = ?', whereArgs: [id])).first['iptal'], 1);
    expect((await _yontemNet(db))['Nakit'], closeTo(0, 0.001));
  });
}
