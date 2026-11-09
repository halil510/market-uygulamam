// test/depolar/masa_qr_miktar_yuvarlama_test.dart
//
// Derin denetim (2026-11-09), yüksek:
//  #18 QR sipariş uçlarında miktar doğrulanmıyordu — negatif miktarla masa
//      hesabı düşürülebiliyor, ödemede stok artıyordu.
//  #19 Kuruş altı birim fiyatlı (indirimli) ürünlü masa hiç ödenemiyordu:
//      ödeme kontrolü toplamı ekrandan farklı yuvarlıyordu.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/depolar/masa_deposu.dart';
import 'package:market_plus/modeller/masa_model.dart';
import 'package:market_plus/servisler/masa_odeme_servisi.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late MasaDeposu depo;
  late int urunId;

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (_) async => null);
    SharedPreferences.setMockInitialValues({});
    db = await TestVeritabani.olustur();
    Veritabani.testVeritabani = db;
    depo = MasaDeposu();
    urunId = await TestVeritabani.ornekUrunEkle(db, satisFiyati: 50);
  });
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    Veritabani.testVeritabani = null;
    await db.close();
  });

  test('#18 negatif ya da sıfır miktarlı kalem reddedilir, masa hesabı değişmez', () async {
    final m = await depo.masaEkle(const MasaModel(ad: 'Masa 4'));
    final s = await depo.siparisAcVeyaGetir(m);
    await depo.kalemEkle(s.id!, urunId: urunId, urunAdi: 'Rakı', birimFiyat: 50, kdvOran: 20, miktar: 2);

    for (final kotu in [-2.0, 0.0, 100000.0, double.nan]) {
      await expectLater(
          depo.kalemEkle(s.id!, urunId: urunId, urunAdi: 'Rakı', birimFiyat: 50, kdvOran: 20, miktar: kotu),
          throwsArgumentError, reason: '$kotu');
    }
    final kalem = (await db.query('masa_siparis_kalem', where: 'siparis_id = ?', whereArgs: [s.id])).single;
    expect((kalem['miktar'] as num).toDouble(), 2);
  });

  test('#19 kuruş altı birim fiyatlı iki kalemli masa ödenebilir', () async {
    final m = await depo.masaEkle(const MasaModel(ad: 'Masa 5'));
    final s = await depo.siparisAcVeyaGetir(m);
    // %15 indirimli 12,50 TL → 10,625 (yuvarlanmadan saklanıyor).
    for (final ad in ['A', 'B']) {
      await db.insert('masa_siparis_kalem', {
        'siparis_id': s.id, 'urun_id': urunId, 'urun_adi': ad, 'miktar': 1,
        'birim_fiyat': 10.625, 'kdv_oran': 10,
      });
    }
    final kopya = (await depo.acikSiparisGetir(m))!;
    expect(kopya.hesaplananToplam, closeTo(21.26, 0.001));

    final sonuc = await MasaOdemeServisi().odemeYap(
      siparis: kopya, masaAdi: 'Masa 5',
      odemeKalemleri: [{'yontem': 'Nakit', 'tutar': 21.26}], paraUstu: 0,
    );
    expect(sonuc.genelToplam, closeTo(21.26, 0.001), reason: 'önceden "Sipariş değişti" atıyordu');
  });
}
