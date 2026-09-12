// test/servisler/veri_sagligi_servisi_test.dart
//
// VeriSagligiServisi'nin (protokol §13) basit salt-okunur tespit
// sorgularını (mükerrer barkod, negatif stok, yetim kayıt, satış-stok)
// gerçek şemayla doğrular. Servis Veritabani() singleton'ı kullandığı
// için SQL'ler burada TestVeritabani db'si üzerinde birebir tekrar
// uygulanıyor (bu oturumdaki test deseniyle tutarlı).
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import '../helper/test_initializer.dart';

Future<int> _mukerrerBarkodSayisi(Database db) async {
  final rows = await db.rawQuery('''
    SELECT barkod, COUNT(*) as c FROM urunler
    WHERE barkod IS NOT NULL AND barkod != '' AND is_deleted = 0
    GROUP BY barkod HAVING c > 1
  ''');
  return rows.length;
}

Future<int> _negatifStokSayisi(Database db) async {
  final rows = await db.rawQuery("SELECT COUNT(*) as n FROM urunler WHERE stok < 0 AND is_deleted = 0");
  return (rows.first['n'] as int?) ?? 0;
}

Future<int> _yetimSatisKalemSayisi(Database db) async {
  final rows = await db.rawQuery(
      "SELECT COUNT(*) as n FROM satis_kalem sk WHERE NOT EXISTS (SELECT 1 FROM satislar s WHERE s.id = sk.satis_id)");
  return (rows.first['n'] as int?) ?? 0;
}

Future<int> _satisStokUyumsuzlukSayisi(Database db) async {
  final rows = await db.rawQuery('''
    SELECT COUNT(*) as n FROM satis_kalem sk
    JOIN satislar s ON s.id = sk.satis_id AND s.is_deleted = 0
    WHERE NOT EXISTS (
      SELECT 1 FROM stok_hareket sh
      WHERE sh.referans_id = sk.satis_id AND sh.referans_turu = 'satis' AND sh.urun_id = sk.urun_id
    )
  ''');
  return (rows.first['n'] as int?) ?? 0;
}

void main() {
  late Database db;

  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  // NOT: 'urunler.barkod' güncel şemada UNIQUE — bu yüzden gerçek bir
  // mükerrer kayıt TestVeritabani'nin (her zaman GÜNCEL şemayla kurulan)
  // taze veritabanında normal INSERT ile ÜRETİLEMEZ. Bu kontrol, eski
  // (UNIQUE kısıtı henüz yokken oluşmuş) kayıtları olan GERÇEK/yükseltilmiş
  // veritabanları için var — burada sadece "sağlıklı" (0) durumu ve
  // NULL barkodun yanlış pozitif üretmediğini doğruluyoruz.
  test('barkod hepsi farklıysa (veya NULL) mükerrer sayılmaz', () async {
    await TestVeritabani.ornekUrunEkle(db, urunAdi: 'A', barkod: '111');
    await TestVeritabani.ornekUrunEkle(db, urunAdi: 'B', barkod: '222');
    await db.insert('urunler', {
      'urun_adi': 'C (barkodsuz)', 'satis_fiyati': 10, 'stok': 5,
      'birim_adi': 'Adet', 'kdv_oran': '20', 'aktif': 1, 'is_deleted': 0,
    });
    await db.insert('urunler', {
      'urun_adi': 'D (barkodsuz)', 'satis_fiyati': 10, 'stok': 5,
      'birim_adi': 'Adet', 'kdv_oran': '20', 'aktif': 1, 'is_deleted': 0,
    });

    expect(await _mukerrerBarkodSayisi(db), equals(0));
  });

  test('negatif stok tespit edilir', () async {
    await TestVeritabani.ornekUrunEkle(db, barkod: 'NEG1', stok: -5);
    await TestVeritabani.ornekUrunEkle(db, barkod: 'NEG2', stok: 10);

    expect(await _negatifStokSayisi(db), equals(1));
  });

  test('yetim satış kalemi (silinmiş/olmayan satışa bağlı) tespit edilir', () async {
    final urunId = await TestVeritabani.ornekUrunEkle(db);
    await db.insert('satis_kalem', {
      'satis_id': 9999, 'urun_id': urunId, 'urun_adi': 'Test', 'miktar': 1,
      'birim_fiyat': 10, 'toplam_tutar': 10,
    });

    expect(await _yetimSatisKalemSayisi(db), equals(1));
  });

  test('satış-stok tutarlılığı: stok hareketi olmayan satış kalemi tespit edilir', () async {
    final urunId = await TestVeritabani.ornekUrunEkle(db);
    final satisId = await db.insert('satislar', {
      'fis_no': 'F1', 'tarih': DateTime.now().toIso8601String(), 'is_deleted': 0,
    });
    await db.insert('satis_kalem', {
      'satis_id': satisId, 'urun_id': urunId, 'urun_adi': 'Test', 'miktar': 2,
      'birim_fiyat': 10, 'toplam_tutar': 20,
    });
    // Kasıtlı olarak stok_hareket kaydı OLUŞTURULMADI.

    expect(await _satisStokUyumsuzlukSayisi(db), equals(1));

    // Stok hareketi eklenince tutarlılık sağlanmalı.
    await db.insert('stok_hareket', {
      'urun_id': urunId, 'hareket_turu': 'Çıkış', 'miktar': 2,
      'referans_id': satisId, 'referans_turu': 'satis', 'tarih': DateTime.now().toIso8601String(),
    });
    expect(await _satisStokUyumsuzlukSayisi(db), equals(0));
  });
}
