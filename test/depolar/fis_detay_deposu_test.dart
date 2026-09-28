// test/depolar/fis_detay_deposu_test.dart
//
// FisDetayDeposu (Madde 2 mimari denetimi, 2026-09-20: fis_detay_ekrani
// .dart'tan taşındı) — fiş tipine göre DOĞRU tablolardan (satislar/
// satis_kalem, iade/iade_kalem, tedarikci_siparisler/tedarikci_siparis_
// kalem, ya da diğer cari hareketleri için cari_hareket) okuduğunu
// doğrular. Bu, kullanıcıya YANLIŞ bir tablodan veri gösterme (ör.
// "İade" fişinin "Satış" olarak okunması) riskini kapatır.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/depolar/fis_detay_deposu.dart';
import '../helper/test_initializer.dart';

void main() {
  late Database db;
  late FisDetayDeposu depo;
  setUp(() async {
    db = await TestVeritabani.olustur();
    depo = FisDetayDeposu(db: db);
  });
  tearDown(() => db.close());

  test('Satış fişi: satislar + satis_kalem doğru okunur', () async {
    final urunId = await TestVeritabani.ornekUrunEkle(db, urunAdi: 'Ekmek');
    final satisId = await db.insert('satislar', {
      'fis_no': 'S-001', 'genel_toplam': 150, 'is_deleted': 0, 'iptal': 0,
    });
    await db.insert('satis_kalem', {
      'satis_id': satisId, 'urun_id': urunId, 'urun_adi': 'Ekmek',
      'miktar': 2, 'birim_fiyat': 75, 'toplam_tutar': 150,
    });

    final sonuc = await depo.getir(fisId: satisId, fisTipi: 'Satış');

    expect(sonuc.fis, isNotNull);
    expect(sonuc.fis!['fis_no'], 'S-001');
    expect(sonuc.kalemler, hasLength(1));
    expect(sonuc.kalemler.first['urun_adi'], 'Ekmek');
  });

  test('"Toptan Satış (Sipariş)" ve "Masa Satış" de satislar/satis_kalem üzerinden okunur', () async {
    final urunId = await TestVeritabani.ornekUrunEkle(db);
    final satisId = await db.insert('satislar', {
      'fis_no': 'S-002', 'genel_toplam': 300, 'is_deleted': 0, 'iptal': 0,
    });
    await db.insert('satis_kalem', {
      'satis_id': satisId, 'urun_id': urunId, 'urun_adi': 'Ürün',
      'miktar': 1, 'birim_fiyat': 300, 'toplam_tutar': 300,
    });

    for (final tip in ['Toptan Satış (Sipariş)', 'Masa Satış', 'Toptan Satış']) {
      final sonuc = await depo.getir(fisId: satisId, fisTipi: tip);
      expect(sonuc.fis, isNotNull, reason: '$tip için fiş bulunmalı');
      expect(sonuc.kalemler, hasLength(1), reason: '$tip için kalem bulunmalı');
    }
  });

  test('Silinmiş (is_deleted=1) satış fişi döndürülmez', () async {
    final satisId = await db.insert('satislar', {
      'fis_no': 'S-003', 'genel_toplam': 100, 'is_deleted': 1, 'iptal': 0,
    });

    final sonuc = await depo.getir(fisId: satisId, fisTipi: 'Satış');
    expect(sonuc.fis, isNull);
  });

  test('İade fişi: iade + iade_kalem doğru okunur', () async {
    final urunId = await TestVeritabani.ornekUrunEkle(db, urunAdi: 'Süt');
    final iadeId = await db.insert('iade', {'fis_no': 'I-001', 'toplam_tutar': 50});
    await db.insert('iade_kalem', {
      'iade_id': iadeId, 'urun_id': urunId, 'urun_adi': 'Süt',
      'miktar': 1, 'birim_fiyat': 50, 'toplam': 50,
    });

    final sonuc = await depo.getir(fisId: iadeId, fisTipi: 'İade');

    expect(sonuc.fis, isNotNull);
    expect(sonuc.kalemler, hasLength(1));
    expect(sonuc.kalemler.first['toplam_tutar'], 50); // 'toplam' -> 'toplam_tutar' alias
  });

  test('Silinmiş (deleted_at dolu) iade fişi döndürülmez', () async {
    final iadeId = await db.insert('iade', {
      'fis_no': 'I-002', 'toplam_tutar': 20,
      'deleted_at': DateTime.now().toIso8601String(),
    });

    final sonuc = await depo.getir(fisId: iadeId, fisTipi: 'İade');
    expect(sonuc.fis, isNull);
  });

  test('Alım fişi: tedarikci_siparisler + tedarikci_siparis_kalem doğru okunur', () async {
    final urunId = await TestVeritabani.ornekUrunEkle(db, urunAdi: 'Yağ');
    final cariId = await TestVeritabani.ornekCariEkle(db, cariTipi: 'Tedarikçi');
    final siparisId = await db.insert('tedarikci_siparisler', {
      'cari_id': cariId, 'siparis_no': 'A-001', 'toplam_tutar': 500, 'is_deleted': 0,
    });
    await db.insert('tedarikci_siparis_kalem', {
      'siparis_id': siparisId, 'urun_id': urunId,
      'siparis_mik': 10, 'birim_fiyat': 50, 'toplam_tutar': 500,
    });

    final sonuc = await depo.getir(fisId: siparisId, fisTipi: 'Alım');

    expect(sonuc.fis, isNotNull);
    expect(sonuc.fis!['fis_no'], 'A-001'); // siparis_no -> fis_no alias
    expect(sonuc.kalemler, hasLength(1));
    expect(sonuc.kalemler.first['urun_adi'], 'Yağ'); // urunler JOIN
  });

  test('Diğer fiş tipleri (Tahsilat/Ödeme/Virman vb.): sadece cari_hareket satırı, kalem YOK', () async {
    final cariId = await TestVeritabani.ornekCariEkle(db);
    final hareketId = await db.insert('cari_hareket', {
      'cari_id': cariId, 'fis_tipi': 'Tahsilat', 'borc': 0, 'alacak': 200,
    });

    final sonuc = await depo.getir(fisId: hareketId, fisTipi: 'Tahsilat');

    expect(sonuc.fis, isNotNull);
    expect(sonuc.fis!['alacak'], 200);
    expect(sonuc.kalemler, isEmpty);
  });

  test('Bulunamayan fiş id\'si için fis null, kalemler boş döner (çökmez)', () async {
    final sonuc = await depo.getir(fisId: 999999, fisTipi: 'Satış');
    expect(sonuc.fis, isNull);
    expect(sonuc.kalemler, isEmpty);
  });
}
