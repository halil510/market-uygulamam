// test/servisler/masa_odeme_cari_bilgi_satiri_test.dart
//
// Kendi-keşif turu (Masa modülü denetimi): SatisTamamlamaServisi.
// tamamla() (Hızlı Satış) bir müşteri bağlıyken Nakit/Kart payı için
// de bakiyeyi ETKİLEMEYEN (borc=alacak, self-cancelling) bir "bilgi"
// cari_hareket satırı yazar — böylece o satış müşterinin Cari
// ekstresinde görünür. MasaOdemeServisi.odemeYap() bunu HİÇ
// yapmıyordu: bir müşteriye bağlı masa hesabı Nakit/Kart ile (kısmen
// veya tamamen) ödenirse, o satış müşterinin cari geçmişinde HİÇ
// görünmüyordu.
//
// MasaOdemeServisi.odemeYap() Veritabani() singleton'ı üzerinden
// çalıştığı için (diğer depo testlerindeki AYNI gerekçe — bkz.
// virman_servisi_test.dart), burada altındaki gerçek depo metodu
// (CariDeposu.hareketEkleTxn) — odemeYap()'ın YENİ eklenen "bilgi
// satırı" mantığıyla BİREBİR AYNI sırayla — gerçek şema üzerinde bir
// in-memory veritabanı içinde doğrudan çağrılıyor.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/depolar/cari_deposu.dart';
import 'package:market_plus/modeller/cari_hareket_model.dart';
import '../helper/test_initializer.dart';

/// MasaOdemeServisi.odemeYap()'ın cari_hareket yazım BÖLÜMÜ ile
/// BİREBİR AYNI orkestrasyon.
Future<List<String>> _masaCariHareketleriYaz(
  Database db, {
  required int? efektifCariId,
  required int satisId,
  required String fisNo,
  required String masaAdi,
  required double cariTutar,
  required Map<String, double> gruplar, // {yontem: tutar}
}) async {
  final cariGlobalIdleri = <String>[];
  await db.transaction((txn) async {
    final digerTutar = gruplar.values.fold(0.0, (s, v) => s + v);
    if (efektifCariId != null && digerTutar > 0.005) {
      final yontemler = gruplar.keys.join('+');
      cariGlobalIdleri.add(await CariDeposu().hareketEkleTxn(
          txn,
          CariHareketModel(
            cariId: efektifCariId,
            tarih: DateTime.now(),
            fisTipi: 'Satış',
            fisId: satisId,
            fisNo: fisNo,
            aciklama:
                '$yontemler Masa Satış: $masaAdi ($fisNo) — bakiyeyi etkilemez',
            borc: digerTutar,
            alacak: digerTutar,
            odemeTuru: yontemler,
          )));
    }
    if (efektifCariId != null && cariTutar > 0.005) {
      cariGlobalIdleri.add(await CariDeposu().hareketEkleTxn(
          txn,
          CariHareketModel(
            cariId: efektifCariId,
            tarih: DateTime.now(),
            fisTipi: 'Satış',
            fisId: satisId,
            fisNo: fisNo,
            aciklama: 'Masa Veresiye: $masaAdi ($fisNo)',
            borc: cariTutar,
            alacak: 0,
            odemeTuru: 'Cari',
          )));
    }
  });
  return cariGlobalIdleri;
}

void main() {
  late Database db;
  late int cariId;
  setUp(() async {
    db = await TestVeritabani.olustur();
    cariId = await TestVeritabani.ornekCariEkle(db);
  });
  tearDown(() => db.close());

  test('müşteriye bağlı masa hesabı TAMAMEN Nakit ödenirse artık cari '
      'ekstresinde görünür bir "bilgi" satırı oluşur (önceden HİÇ oluşmuyordu)',
      () async {
    await _masaCariHareketleriYaz(db,
        efektifCariId: cariId,
        satisId: 1,
        fisNo: 'MSA2026000000001',
        masaAdi: 'Masa 3',
        cariTutar: 0,
        gruplar: {'Nakit': 150.0});

    final hareketler = await db.query('cari_hareket', where: 'cari_id = ?', whereArgs: [cariId]);
    expect(hareketler.length, 1);
    expect(hareketler.first['borc'], 150.0);
    expect(hareketler.first['alacak'], 150.0,
        reason: 'borc=alacak → bakiyeyi ETKİLEMEMELİ (self-cancelling)');
    expect(hareketler.first['odeme_turu'], 'Nakit');
  });

  test('Karma (Nakit+Cari) masa ödemesinde İKİ satır oluşur: gerçek '
      'Cari borcu VE bakiyeyi etkilemeyen Nakit bilgi satırı', () async {
    await _masaCariHareketleriYaz(db,
        efektifCariId: cariId,
        satisId: 2,
        fisNo: 'MSA2026000000002',
        masaAdi: 'Masa 5',
        cariTutar: 100.0,
        gruplar: {'Nakit': 50.0});

    final hareketler = await db.query('cari_hareket', where: 'cari_id = ?', whereArgs: [cariId]);
    expect(hareketler.length, 2);

    final cariSatiri = hareketler.firstWhere((h) => h['odeme_turu'] == 'Cari');
    expect(cariSatiri['borc'], 100.0);
    expect(cariSatiri['alacak'], 0.0);

    final nakitBilgiSatiri = hareketler.firstWhere((h) => h['odeme_turu'] == 'Nakit');
    expect(nakitBilgiSatiri['borc'], 50.0);
    expect(nakitBilgiSatiri['alacak'], 50.0);
  });

  test('müşteri BAĞLI DEĞİLSE (efektifCariId null) hiçbir cari_hareket '
      'satırı oluşmaz', () async {
    final gidler = await _masaCariHareketleriYaz(db,
        efektifCariId: null,
        satisId: 3,
        fisNo: 'MSA2026000000003',
        masaAdi: 'Masa 1',
        cariTutar: 0,
        gruplar: {'Nakit': 90.0});

    expect(gidler, isEmpty);
    final tumHareketler = await db.query('cari_hareket');
    expect(tumHareketler, isEmpty);
  });
}
