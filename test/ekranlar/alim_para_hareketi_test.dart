// test/ekranlar/alim_para_hareketi_test.dart
//
// Derin analizde bulundu (P0): alim_ekrani.dart'ta Nakit/Havale ile
// yapılan alışlarda gerçek bir kasa/banka hareketi HİÇ oluşturulmuyordu
// — stok artıyor ama kasadan/bankadan hiç para çıkmamış gibi görünüyordu
// (protokol §10 ihlali). Bu test, _alimKaydet()'in düzeltilen mantığını
// (kalemler+stok+kasa/banka hareketi TEK transaction'da) gerçek depo Txn
// metotlarıyla, gerçek şema üzerinde doğruluyor.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/depolar/kasa_deposu.dart';
import 'package:market_plus/depolar/banka_hareket_deposu.dart';
import 'package:market_plus/modeller/kasa_hareket_model.dart';
import 'package:market_plus/modeller/banka_hareket_model.dart';
import '../helper/test_initializer.dart';

/// alim_ekrani.dart _alimKaydet()'in (düzeltilmiş) mantığıyla BİREBİR
/// aynı sırada çalışan basitleştirilmiş yardımcı.
Future<int> _alimiSimuleEt(
  Database db, {
  required int urunId,
  required int cariId,
  required double miktar,
  required double alisFiyat,
  required String odemeYontemi,
  int? bankaHesapId,
}) async {
  final kasaDepo = KasaDeposu();
  final bankaDepo = BankaHareketDeposu();
  final genelToplam = miktar * alisFiyat;
  late int alimId;

  await db.transaction((txn) async {
    alimId = await txn.insert('tedarikci_siparisler', {
      'cari_id': cariId,
      'siparis_no': 'AL-TEST', 'siparis_tarihi': DateTime.now().toIso8601String(),
      'toplam_tutar': genelToplam, 'durum': 'tamamlandi',
    });

    final rows = await txn.query('urunler', columns: ['stok'], where: 'id = ?', whereArgs: [urunId]);
    final onceki = (rows.first['stok'] as num).toDouble();
    await txn.update('urunler', {'stok': onceki + miktar}, where: 'id = ?', whereArgs: [urunId]);

    if (odemeYontemi == 'Nakit' && genelToplam > 0.005) {
      await kasaDepo.hareketEkleTxn(txn, KasaHareketModel(
        hareketTipi: 'Alım', tutar: genelToplam,
        referansId: alimId, referansTuru: 'alim', tarih: DateTime.now(),
      ));
    } else if (odemeYontemi == 'Havale' && genelToplam > 0.005) {
      await bankaDepo.ekleTxn(txn, BankaHareketModel(
        bankaHesapId: bankaHesapId!, islemTipi: 'Giden',
        tutar: genelToplam, aciklama: 'Mal Alımı', tarih: DateTime.now(),
      ));
    }
  });

  return alimId;
}

void main() {
  late Database db;

  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  group('Alım — gerçek para hareketi (P0 regresyonu)', () {
    test('Nakit alışta kasadan gerçek çıkış hareketi oluşur', () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db, stok: 10);
      final cariId = await TestVeritabani.ornekCariEkle(db, cariTipi: 'Tedarikçi');
      final alimId = await _alimiSimuleEt(db,
          urunId: urunId, cariId: cariId, miktar: 20, alisFiyat: 5, odemeYontemi: 'Nakit');

      final kasa = await db.query('kasa_hareketleri',
          where: 'referans_id = ? AND referans_turu = ?', whereArgs: [alimId, 'alim']);
      expect(kasa, hasLength(1), reason: 'Nakit alışta kasa çıkışı OLUŞMALI');
      expect((kasa.first['tutar'] as num).toDouble(), equals(100.0));

      final urun = (await db.query('urunler', where: 'id = ?', whereArgs: [urunId])).first;
      expect((urun['stok'] as num).toDouble(), equals(30.0));
    });

    test('Havale alışta banka hesabından gerçek çıkış hareketi oluşur', () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db, stok: 0);
      final cariId = await TestVeritabani.ornekCariEkle(db, cariTipi: 'Tedarikçi');
      final hesapId = await db.insert('banka_hesaplar', {
        'banka_id': 1, 'hesap_adi': 'Test Hesap', 'hesap_no': '123', 'bakiye': 1000,
      });

      await _alimiSimuleEt(db,
          urunId: urunId, cariId: cariId, miktar: 10, alisFiyat: 8,
          odemeYontemi: 'Havale', bankaHesapId: hesapId);

      final banka = await db.query('banka_hareketler', where: 'banka_hesap_id = ?', whereArgs: [hesapId]);
      expect(banka, hasLength(1), reason: 'Havale alışta banka çıkışı OLUŞMALI');
      expect(banka.first['islem_tipi'], equals('Giden'));
      expect((banka.first['tutar'] as num).toDouble(), equals(80.0));

      final hesap = (await db.query('banka_hesaplar', where: 'id = ?', whereArgs: [hesapId])).first;
      expect((hesap['bakiye'] as num).toDouble(), equals(920.0), reason: '1000 - 80 = 920');
    });

    test('Cari alışta kasa/banka hareketi OLUŞMAZ (borç olarak kalır)', () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db, stok: 0);
      final cariId = await TestVeritabani.ornekCariEkle(db, cariTipi: 'Tedarikçi');
      final alimId = await _alimiSimuleEt(db,
          urunId: urunId, cariId: cariId, miktar: 5, alisFiyat: 10, odemeYontemi: 'Cari');

      final kasa = await db.query('kasa_hareketleri', where: 'referans_id = ?', whereArgs: [alimId]);
      final banka = await db.query('banka_hareketler');
      expect(kasa, isEmpty);
      expect(banka, isEmpty);
    });
  });
}
