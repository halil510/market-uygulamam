// test/depolar/masa_tasi_test.dart
//
// MasaDeposu.masaTasi — "Masa Taşı / Birleştir". Önceden 5 ayrı adımdı;
// arada hata/çökme olursa kalemler hedefe geçmiş ama kaynak sipariş açık
// kalabiliyordu. Artık tek transaction. GERÇEK depo fonksiyonu, gerçek
// şemalı bellek içi veritabanında çağrılır.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:market_plus/depolar/masa_deposu.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late MasaDeposu depo;
  late int masa1, masa2, cari;

  Future<int> kalem(int siparisId, String ad, double miktar, double fiyat, {int silindi = 0}) =>
      db.insert('masa_siparis_kalem', {
        'siparis_id': siparisId, 'urun_id': 1, 'urun_adi': ad, 'miktar': miktar,
        'birim_fiyat': fiyat, 'kdv_oran': 10, 'is_deleted': silindi,
      });

  Future<Map<String, Object?>> siparis(int id) async =>
      (await db.query('masa_siparisleri', where: 'id = ?', whereArgs: [id])).first;
  Future<String> masaDurum(int id) async =>
      (await db.query('masalar', where: 'id = ?', whereArgs: [id])).first['durum'] as String;
  Future<List<Map<String, Object?>>> kalemler(int siparisId) =>
      db.query('masa_siparis_kalem', where: 'siparis_id = ? AND is_deleted = 0', whereArgs: [siparisId]);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await TestVeritabani.olustur();
    Veritabani.testVeritabani = db;
    depo = MasaDeposu();
    await TestVeritabani.ornekUrunEkle(db);
    masa1 = await db.insert('masalar', {'ad': 'Masa 1', 'durum': 'bos'});
    masa2 = await db.insert('masalar', {'ad': 'Masa 2', 'durum': 'bos'});
    cari = await TestVeritabani.ornekCariEkle(db, unvan: 'Ahmet Bey');
  });

  tearDown(() async {
    Veritabani.testVeritabani = null;
    await db.close();
  });

  test('Boş masaya taşıma: kalemler, toplam, müşteri, açılış zamanı taşınır; kaynak kapanır', () async {
    final kaynak = await depo.siparisAcVeyaGetir(masa1);
    await depo.musteriBagla(kaynak.id!, cari, 'Ahmet Bey');
    await kalem(kaynak.id!, 'Çay', 2, 10);
    await kalem(kaynak.id!, 'Tost', 1, 50);
    final acilis = (await siparis(kaynak.id!))['acilis_zamani'];

    await depo.masaTasi(kaynak.id!, masa2);

    final hedef = await depo.acikSiparisGetir(masa2);
    expect(hedef, isNotNull);
    expect(hedef!.kalemler.length, 2);
    final h = await siparis(hedef.id!);
    expect((h['toplam_tutar'] as num).toDouble(), 70.0);
    expect(h['cari_id'], cari, reason: 'masaya bağlı müşteri yeni masaya taşınmalı');
    expect(h['acilis_zamani'], acilis, reason: 'hesap aynı — açılış zamanı korunmalı');
    expect((await siparis(kaynak.id!))['durum'], 'iptal');
    expect(await depo.acikSiparisGetir(masa1), isNull);
    expect(await masaDurum(masa1), 'bos');
    expect(await masaDurum(masa2), 'dolu');
  });

  test('Dolu masayla birleştirme: kalemler birleşir, toplam iki hesabın toplamı olur', () async {
    final kaynak = await depo.siparisAcVeyaGetir(masa1);
    await depo.musteriBagla(kaynak.id!, cari, 'Ahmet Bey');
    await kalem(kaynak.id!, 'Çay', 2, 10);
    final hedef = await depo.siparisAcVeyaGetir(masa2);
    await kalem(hedef.id!, 'Kahve', 1, 40);

    await depo.masaTasi(kaynak.id!, masa2);

    expect((await kalemler(hedef.id!)).length, 2);
    expect(((await siparis(hedef.id!))['toplam_tutar'] as num).toDouble(), 60.0);
    expect((await siparis(hedef.id!))['cari_id'], cari,
        reason: 'hedefin müşterisi yoksa kaynağınki geçer');
    expect((await siparis(kaynak.id!))['durum'], 'iptal');
  });

  test('Birleştirmede hedef masanın kendi müşterisi korunur', () async {
    final diger = await TestVeritabani.ornekCariEkle(db, unvan: 'Mehmet Bey');
    final kaynak = await depo.siparisAcVeyaGetir(masa1);
    await depo.musteriBagla(kaynak.id!, cari, 'Ahmet Bey');
    await kalem(kaynak.id!, 'Çay', 1, 10);
    final hedef = await depo.siparisAcVeyaGetir(masa2);
    await depo.musteriBagla(hedef.id!, diger, 'Mehmet Bey');

    await depo.masaTasi(kaynak.id!, masa2);

    expect((await siparis(hedef.id!))['cari_id'], diger);
  });

  test('Aynı masaya taşıma engellenir — sipariş kaybolmaz', () async {
    final kaynak = await depo.siparisAcVeyaGetir(masa1);
    await kalem(kaynak.id!, 'Çay', 2, 10);

    await expectLater(depo.masaTasi(kaynak.id!, masa1), throwsException);

    expect((await siparis(kaynak.id!))['durum'], 'acik');
    expect((await kalemler(kaynak.id!)).length, 1);
  });

  test('Silinmiş kalem taşınmaz ve toplama girmez', () async {
    final kaynak = await depo.siparisAcVeyaGetir(masa1);
    await kalem(kaynak.id!, 'Çay', 2, 10);
    await kalem(kaynak.id!, 'İptal edilen', 1, 99, silindi: 1);

    await depo.masaTasi(kaynak.id!, masa2);

    final hedef = await depo.acikSiparisGetir(masa2);
    final tumu = await db.query('masa_siparis_kalem', where: 'siparis_id = ?', whereArgs: [hedef!.id]);
    expect(tumu.length, 1);
    expect(((await siparis(hedef.id!))['toplam_tutar'] as num).toDouble(), 20.0);
  });

  test('Kapanmış (ödenmiş) sipariş taşınamaz', () async {
    final kaynak = await depo.siparisAcVeyaGetir(masa1);
    await kalem(kaynak.id!, 'Çay', 1, 10);
    await depo.siparisKapat(kaynak.id!, masa1);

    await expectLater(depo.masaTasi(kaynak.id!, masa2), throwsException);
    expect(await depo.acikSiparisGetir(masa2), isNull);
  });

  test('ATOMİKLİK: son adımda hata olursa HİÇBİR değişiklik kalmaz', () async {
    final kaynak = await depo.siparisAcVeyaGetir(masa1);
    await kalem(kaynak.id!, 'Çay', 2, 10);
    // İşlemin EN SON adımı (kaynak masayı boşa çevirme) sırasında hata.
    await db.execute('''
      CREATE TRIGGER test_hata BEFORE UPDATE OF durum ON masalar
      WHEN NEW.id = $masa1 AND NEW.durum = 'bos'
      BEGIN SELECT RAISE(ABORT, 'yapay hata'); END''');

    await expectLater(depo.masaTasi(kaynak.id!, masa2), throwsA(anything));

    expect((await siparis(kaynak.id!))['durum'], 'acik', reason: 'kaynak sipariş açık kalmalı');
    expect((await kalemler(kaynak.id!)).length, 1, reason: 'kalemler kaynakta kalmalı');
    expect(await depo.acikSiparisGetir(masa2), isNull, reason: 'hedefte yarım sipariş kalmamalı');
    expect(await masaDurum(masa2), 'bos', reason: 'hedef masa dolu görünmemeli');
  });
}
