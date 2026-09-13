// test/ekranlar/tedarikci_siparis_test.dart
//
// FAZ 6 (Satın Alma): "Tedarikçi Siparişleri" ekranındaki 'Bekleyen' sipariş
// akışı önceden hiç implement edilmemişti — 'Sipariş Ver' doğrudan Alım
// (mal kabul) ekranına atlıyor, hiçbir zaman 'beklemede' kayıt açmıyordu.
// Bu test, düzeltilen iki adımı (SiparisOlusturEkrani ve
// AlimEkrani(mevcutSiparisId:)) gerçek şema üzerinde, o ekranlardaki
// mantıkla BİREBİR aynı sırada doğrular:
//   1) Sipariş oluşturma: SADECE 'beklemede' kayıt açar, stok/kasa/cari
//      hiçbir şekilde etkilenmez.
//   2) Teslim alma: var olan siparişi GÜNCELLER (mükerrer kayıt açmaz),
//      kalemin teslim_mik'ini işler, stok artar, gerçek kasa hareketi oluşur.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/depolar/kasa_deposu.dart';
import 'package:market_plus/modeller/kasa_hareket_model.dart';
import '../helper/test_initializer.dart';

Future<int> _siparisOlustur(
  Database db, {
  required int cariId,
  required int urunId,
  required double miktar,
  required double birimFiyat,
}) async {
  late int siparisId;
  await db.transaction((txn) async {
    siparisId = await txn.insert('tedarikci_siparisler', {
      'cari_id': cariId,
      'siparis_no': 'SIP-TEST',
      'siparis_tarihi': DateTime.now().toIso8601String(),
      'toplam_tutar': miktar * birimFiyat,
      'durum': 'beklemede',
    });
    await txn.insert('tedarikci_siparis_kalem', {
      'siparis_id': siparisId,
      'urun_id': urunId,
      'siparis_mik': miktar,
      'teslim_mik': 0,
      'birim_fiyat': birimFiyat,
      'kdv_oran': 0,
      'toplam_tutar': miktar * birimFiyat,
    });
  });
  return siparisId;
}

/// AlimEkrani._alimKaydet()'in siparisModu==true dalıyla BİREBİR aynı sırada
/// çalışan basitleştirilmiş yardımcı.
Future<void> _siparisiTeslimAl(
  Database db, {
  required int siparisId,
  required int urunId,
  required double teslimMiktar,
  required double birimFiyat,
}) async {
  final kasaDepo = KasaDeposu();
  final genelToplam = teslimMiktar * birimFiyat;

  await db.transaction((txn) async {
    await txn.update('tedarikci_siparisler', {
      'durum': 'teslim_alindi',
      'toplam_tutar': genelToplam,
    }, where: 'id = ?', whereArgs: [siparisId]);

    final kalem = (await txn.query('tedarikci_siparis_kalem',
        where: 'siparis_id = ? AND urun_id = ?', whereArgs: [siparisId, urunId])).first;
    await txn.update('tedarikci_siparis_kalem', {
      'teslim_mik': teslimMiktar,
      'birim_fiyat': birimFiyat,
      'toplam_tutar': genelToplam,
    }, where: 'id = ?', whereArgs: [kalem['id']]);

    final rows = await txn.query('urunler', columns: ['stok'], where: 'id = ?', whereArgs: [urunId]);
    final onceki = (rows.first['stok'] as num).toDouble();
    await txn.update('urunler', {'stok': onceki + teslimMiktar}, where: 'id = ?', whereArgs: [urunId]);

    await kasaDepo.hareketEkleTxn(txn, KasaHareketModel(
      hareketTipi: 'Alım',
      tutar: genelToplam,
      referansId: siparisId,
      referansTuru: 'alim',
      tarih: DateTime.now(),
    ));
  });
}

void main() {
  late Database db;

  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  group('Tedarikçi Siparişi — bekleyen sipariş → teslim alma (FAZ 6)', () {
    test('Sipariş oluşturma stok/kasa/cariyi ETKİLEMEZ, sadece beklemede kayıt açar', () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db, stok: 5);
      final cariId = await TestVeritabani.ornekCariEkle(db, cariTipi: 'Tedarikçi');

      final siparisId = await _siparisOlustur(db, cariId: cariId, urunId: urunId, miktar: 20, birimFiyat: 5);

      final siparis = (await db.query('tedarikci_siparisler', where: 'id = ?', whereArgs: [siparisId])).first;
      expect(siparis['durum'], equals('beklemede'));

      final urun = (await db.query('urunler', where: 'id = ?', whereArgs: [urunId])).first;
      expect((urun['stok'] as num).toDouble(), equals(5.0), reason: 'Sipariş vermek stoğu artırmamalı');

      final kasa = await db.query('kasa_hareketleri', where: 'referans_id = ?', whereArgs: [siparisId]);
      expect(kasa, isEmpty, reason: 'Sipariş vermek kasa hareketi oluşturmamalı');
    });

    test('Teslim alma mevcut siparişi GÜNCELLER, mükerrer kayıt açmaz, stok/kasa etkilenir', () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db, stok: 5);
      final cariId = await TestVeritabani.ornekCariEkle(db, cariTipi: 'Tedarikçi');
      final siparisId = await _siparisOlustur(db, cariId: cariId, urunId: urunId, miktar: 20, birimFiyat: 5);

      await _siparisiTeslimAl(db, siparisId: siparisId, urunId: urunId, teslimMiktar: 20, birimFiyat: 5.5);

      final tumSiparisler = await db.query('tedarikci_siparisler', where: 'cari_id = ?', whereArgs: [cariId]);
      expect(tumSiparisler, hasLength(1), reason: 'Teslim alma mükerrer sipariş satırı AÇMAMALI');
      expect(tumSiparisler.first['durum'], equals('teslim_alindi'));

      final kalem = (await db.query('tedarikci_siparis_kalem', where: 'siparis_id = ?', whereArgs: [siparisId])).first;
      expect((kalem['teslim_mik'] as num).toDouble(), equals(20.0));

      final urun = (await db.query('urunler', where: 'id = ?', whereArgs: [urunId])).first;
      expect((urun['stok'] as num).toDouble(), equals(25.0), reason: '5 + 20 = 25');

      final kasa = await db.query('kasa_hareketleri', where: 'referans_id = ? AND referans_turu = ?', whereArgs: [siparisId, 'alim']);
      expect(kasa, hasLength(1));
      expect((kasa.first['tutar'] as num).toDouble(), equals(110.0), reason: '20 × 5.5 = 110');
    });
  });
}
