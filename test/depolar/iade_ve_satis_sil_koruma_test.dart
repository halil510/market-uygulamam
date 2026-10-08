// test/depolar/iade_ve_satis_sil_koruma_test.dart
//
// 2026-09-28 bulut kontrolü regresyonları:
//  - Aynı satış iki kez silinince kasa/stok/cari İKİ KEZ ters çevriliyordu
//    (bulutta 14 TL'lik nakit satışın kasa girişi 3 kez ters çevrilmişti).
//  - "Hem Müşteri Hem Tedarikçi" cari iadede tedarikçi sayılıyor, müşteri
//    iadesinde bakiyesi düşeceği yerde ARTIYORDU.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/depolar/satis_deposu.dart';
import 'package:market_plus/modeller/cari_model.dart';
import 'package:market_plus/modeller/satis_kalem_model.dart';
import 'package:market_plus/modeller/satis_model.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

void main() {
  late Database db;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await TestVeritabani.olustur();
    Veritabani.testVeritabani = db;
  });
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    Veritabani.testVeritabani = null;
    await db.close();
  });

  test('satış iki kez silinince ters kayıtlar yalnızca bir kez oluşur', () async {
    final urunId = await TestVeritabani.ornekUrunEkle(db, stok: 10, barkod: 'B-sil');
    final satisId = await SatisDeposu().satisEkle(
        SatisModel(fisNo: 'T-SIL', tarih: DateTime.now(), toplamTutar: 14,
            genelToplam: 14, odenenTutar: 14, odemeYontemi: 'Nakit', fisTipi: 'Satış'),
        [SatisKalemModel(satisId: 0, urunId: urunId, urunAdi: 'Test',
            miktar: 1, birimFiyat: 14, toplamTutar: 14)]);
    await db.insert('kasa_hareketleri', {
      'hareket_tipi': 'Satış', 'tutar': 14.0, 'odeme_yontemi': 'Nakit',
      'referans_id': satisId, 'referans_turu': 'satis',
      'tarih': DateTime.now().toIso8601String(),
    });
    final stokOnce = (await db.query('urunler', where: 'id = ?', whereArgs: [urunId])).first['stok'] as num;

    await SatisDeposu().sil(satisId);
    await SatisDeposu().sil(satisId); // ikinci çağrı: çift tıklama / başka ekrandan

    final tersKasa = await db.query('kasa_hareketleri',
        where: 'referans_id = ? AND referans_turu = ?', whereArgs: [satisId, 'satis_iptal']);
    expect(tersKasa.length, 1);
    final stokSonra = (await db.query('urunler', where: 'id = ?', whereArgs: [urunId])).first['stok'] as num;
    expect(stokSonra - stokOnce, 1); // yalnızca bir kez geri yüklendi

    // 2026-10-08 bulut kontrolü: iptal stok hareketi kimliksiz yazılıyor,
    // senkron kuyruğuna girmiyordu → buluta hiç gitmiyordu.
    final iptalStok = await db.query('stok_hareket',
        where: 'referans_id = ? AND referans_turu = ?', whereArgs: [satisId, 'satis_iptal']);
    expect(iptalStok.length, 1);
    final gid = iptalStok.first['global_id'] as String?;
    expect(gid, isNotNull);
    final kuyruk = await db.query('sync_queue',
        where: "tablo_adi = 'stok_hareket' AND kayit_global_id = ?", whereArgs: [gid]);
    expect(kuyruk, isNotEmpty);
  });

  test('iade yönü: yalnızca saf tedarikçi alım iadesi sayılır', () {
    expect(cariSafTedarikciMi('Tedarikçi'), isTrue);
    expect(cariSafTedarikciMi('Tedarikci'), isTrue);
    expect(cariSafTedarikciMi('Müşteri'), isFalse);
    expect(cariSafTedarikciMi('Hem Müşteri Hem Tedarikçi'), isFalse);
    expect(cariSafTedarikciMi(null), isFalse);
  });
}
