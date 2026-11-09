// test/servisler/karma_odeme_fazla_test.dart
//
// Derin denetim (2026-11-09) #5, yüksek: çoklu ödemede Nakit dışı yönteme
// toplamdan fazla tutar girilebiliyor, fazlası cari borcuna / kart
// cirosuna yazılıyordu (100 TL'lik satışa 1000 TL Cari borç).
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/depolar/urun_deposu.dart';
import 'package:market_plus/modeller/sepet_model.dart';
import 'package:market_plus/servisler/satis_tamamlama_servisi.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

void main() {
  late Database db;
  late int urunId;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await TestVeritabani.olustur();
    Veritabani.testVeritabani = db;
    if ((await db.query('subeler', where: 'id = 1')).isEmpty) {
      await db.insert('subeler', {'id': 1, 'sube_kodu': 'MRK', 'sube_adi': 'Merkez'});
    }
    urunId = await TestVeritabani.ornekUrunEkle(db, satisFiyati: 100, stok: 10);
  });
  tearDown(() async {
    Veritabani.testVeritabani = null;
    await db.close();
  });

  Future<SepetKalem> kalem() async =>
      SepetKalem(urun: (await UrunDeposu().idileGetir(urunId))!, miktar: 1);

  test('Nakit dışı yöntem satış tutarını aşarsa satış reddedilir, hiçbir şey yazılmaz', () async {
    await expectLater(
      SatisTamamlamaServisi().tamamla(
        kalemler: [await kalem()], musteri: null, genelToplam: 100,
        odemeYontemi: 'Karma', odenenTutar: 1000,
        karmaKalemler: [{'yontem': 'Kredi Kartı', 'tutar': 1000}],
      ),
      throwsA(isA<Exception>().having((e) => e.toString(), 'mesaj', contains('aşamaz'))),
    );
    expect(await db.query('satislar'), isEmpty);
    expect(await db.query('kasa_hareketleri'), isEmpty);
  });

  test('Nakit fazlası para üstüdür: kasaya yalnız satış tutarı girer', () async {
    await SatisTamamlamaServisi().tamamla(
      kalemler: [await kalem()], musteri: null, genelToplam: 100,
      odemeYontemi: 'Karma', odenenTutar: 200,
      karmaKalemler: [{'yontem': 'Kredi Kartı', 'tutar': 40}, {'yontem': 'Nakit', 'tutar': 160}],
    );
    final kasa = await db.query('kasa_hareketleri');
    final toplam = kasa.fold<double>(0, (s, r) => s + (r['tutar'] as num).toDouble());
    expect(toplam, closeTo(100, 0.001));
  });
}
