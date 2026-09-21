// test/servisler/donem_arsiv_silme_test.dart
//
// Yıl Sonu Devir — GERÇEK TEMİZLEME (2026-09-21, kullanıcı onayı:
// "veritabanı temizleme işlemini de yap" + "cariler de sade bakiye
// kalan devir gözükecek"). DonemArsivServisi.aktifTablolardanSilVeAcilis
// Yaz()'ın en kritik özelliğini doğrular: silme, stok/cari mutabakat
// SUM'unu ve kasa'nın "son satır" bakiyesini BOZMAMALI — aksi halde
// devirden SONRA "Mutabakat Düzelt" çalıştıran biri yanlış (eksik)
// bir bakiyeye "düzeltirdi".
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/servisler/donem_arsiv_servisi.dart';
import '../helper/test_initializer.dart';

/// StokDeposu.stokMutabakatYap() ile AYNI formül.
Future<double> _stokNetToplam(Database db, int urunId) async {
  final rows = await db.rawQuery(
      'SELECT SUM(sonraki_stok - onceki_stok) AS net FROM stok_hareket WHERE urun_id = ?',
      [urunId]);
  return (rows.first['net'] as num?)?.toDouble() ?? 0;
}

/// CariDeposu.bakiyeMutabakatYap() ile AYNI formül.
Future<double> _cariHesaplananBakiye(Database db, int cariId) async {
  final rows = await db.rawQuery('''
    SELECT COALESCE(SUM(borc),0) - COALESCE(SUM(alacak),0) AS b
    FROM cari_hareket WHERE cari_id = ? AND is_deleted = 0
  ''', [cariId]);
  return (rows.first['b'] as num?)?.toDouble() ?? 0;
}

/// KasaDeposu._sonBakiyeTxn() ile AYNI formül (tek şube).
Future<double> _kasaSonBakiye(Database db, int subeId) async {
  final rows = await db.rawQuery(
      'SELECT bakiye_sonrasi FROM kasa_hareketleri WHERE deleted_at IS NULL AND sube_id = ? '
      'ORDER BY tarih DESC, id DESC LIMIT 1',
      [subeId]);
  if (rows.isEmpty) return 0;
  return (rows.first['bakiye_sonrasi'] as num?)?.toDouble() ?? 0;
}

void main() {
  late Database db;
  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  final baslangic = DateTime(2026, 1, 1);
  final bitis = DateTime(2026, 12, 31, 23, 59, 59);
  const donemId = 1;
  const donemYili = 2026;
  const subeId = 1;

  group('aktifTablolardanSilVeAcilisYaz — STOK', () {
    test(
        'dönem içi stok_hareket satırları silinir, TEK açılış satırıyla '
        'net SUM (stokMutabakatYap formülü) DEĞİŞMEZ', () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db, stok: 30);
      // Net etki: +10 (giriş) -5 (satış) +25 (giriş) = +30 net.
      await db.insert('stok_hareket', {
        'urun_id': urunId, 'hareket_turu': 'Giriş', 'miktar': 10,
        'onceki_stok': 0, 'sonraki_stok': 10, 'sube_id': subeId,
        'tarih': DateTime(2026, 3, 1).toIso8601String(),
      });
      await db.insert('stok_hareket', {
        'urun_id': urunId, 'hareket_turu': 'Satış', 'miktar': 5,
        'onceki_stok': 10, 'sonraki_stok': 5, 'sube_id': subeId,
        'tarih': DateTime(2026, 6, 1).toIso8601String(),
      });
      await db.insert('stok_hareket', {
        'urun_id': urunId, 'hareket_turu': 'Giriş', 'miktar': 25,
        'onceki_stok': 5, 'sonraki_stok': 30, 'sube_id': subeId,
        'tarih': DateTime(2026, 9, 1).toIso8601String(),
      });
      // 2025'e düşen bir satır (silinmemeli, dönem dışı).
      await db.insert('stok_hareket', {
        'urun_id': urunId, 'hareket_turu': 'Giriş', 'miktar': 1,
        'onceki_stok': -1, 'sonraki_stok': 0, 'sube_id': subeId,
        'tarih': DateTime(2025, 12, 1).toIso8601String(),
      });

      final oncekiNet = await _stokNetToplam(db, urunId);
      expect(oncekiNet, 31); // 30 (2026) + 1 (2025)

      await DonemArsivServisi().aktifTablolardanSilVeAcilisYaz(
        donemId: donemId, donemYili: donemYili, subeId: subeId,
        baslangic: baslangic, bitis: bitis, aktifDbTest: db,
      );

      final kalanlar = await db.query('stok_hareket',
          where: "tarih >= ? AND tarih <= ? AND hareket_turu != 'Devir Açılış'",
          whereArgs: [baslangic.toIso8601String(), bitis.toIso8601String()]);
      expect(kalanlar, isEmpty); // dönem içi 3 satır silindi

      final acilisSatirlari = await db.query('stok_hareket',
          where: "hareket_turu = 'Devir Açılış' AND urun_id = ?", whereArgs: [urunId]);
      expect(acilisSatirlari, hasLength(1)); // TEK satır

      final sonrakiNet = await _stokNetToplam(db, urunId);
      // SUM DEĞİŞMEDİ — mutabakat hâlâ doğru sonucu üretir.
      expect(sonrakiNet, closeTo(oncekiNet, 0.001));
    });

    test('idempotent — ikinci çağrıda mükerrer açılış satırı yazılmaz',
        () async {
      final urunId = await TestVeritabani.ornekUrunEkle(db);
      await db.insert('stok_hareket', {
        'urun_id': urunId, 'hareket_turu': 'Giriş', 'miktar': 10,
        'onceki_stok': 0, 'sonraki_stok': 10, 'sube_id': subeId,
        'tarih': DateTime(2026, 3, 1).toIso8601String(),
      });

      final servis = DonemArsivServisi();
      await servis.aktifTablolardanSilVeAcilisYaz(
        donemId: donemId, donemYili: donemYili, subeId: subeId,
        baslangic: baslangic, bitis: bitis, aktifDbTest: db,
      );
      await servis.aktifTablolardanSilVeAcilisYaz(
        donemId: donemId, donemYili: donemYili, subeId: subeId,
        baslangic: baslangic, bitis: bitis, aktifDbTest: db,
      );

      final acilisSatirlari = await db.query('stok_hareket',
          where: "hareket_turu = 'Devir Açılış' AND urun_id = ?", whereArgs: [urunId]);
      expect(acilisSatirlari, hasLength(1)); // ikinci çağrı ikinci satır EKLEMEDİ
    });
  });

  group('aktifTablolardanSilVeAcilisYaz — CARİ (kullanıcının "sade kalan bakiye" isteği)', () {
    test(
        'dönem içi cari_hareket satırları silinir, snapshot\'taki "kalan '
        'bakiye" TEK Devir satırıyla yazılır — hesaplanan bakiye DEĞİŞMEZ',
        () async {
      final cariId = await TestVeritabani.ornekCariEkle(db);
      await db.insert('cari_hareket', {
        'cari_id': cariId, 'fis_tipi': 'Satış', 'borc': 500, 'alacak': 0,
        'tarih': DateTime(2026, 3, 1).toIso8601String(), 'is_deleted': 0,
      });
      await db.insert('cari_hareket', {
        'cari_id': cariId, 'fis_tipi': 'Tahsilat', 'borc': 0, 'alacak': 200,
        'tarih': DateTime(2026, 6, 1).toIso8601String(), 'is_deleted': 0,
      });
      // Kapanış snapshot'ı (gerçek akışta FAZ 5 bunu ÖNCEDEN yazar) —
      // authoritative "kalan bakiye" = 300 (500 borç - 200 alacak).
      await db.insert('cari_kapanis_snapshot', {
        'devir_id': 'test-devir', 'donem_id': donemId, 'cari_id': cariId,
        'bakiye': 300.0,
      });

      final oncekiHesaplanan = await _cariHesaplananBakiye(db, cariId);
      expect(oncekiHesaplanan, 300);

      await DonemArsivServisi().aktifTablolardanSilVeAcilisYaz(
        donemId: donemId, donemYili: donemYili, subeId: subeId,
        baslangic: baslangic, bitis: bitis, aktifDbTest: db,
      );

      final eskiSatirlar = await db.query('cari_hareket',
          where: "cari_id = ? AND fis_tipi != 'Devir'", whereArgs: [cariId]);
      expect(eskiSatirlar, isEmpty);

      final devirSatirlari = await db.query('cari_hareket',
          where: "cari_id = ? AND fis_tipi = 'Devir'", whereArgs: [cariId]);
      expect(devirSatirlari, hasLength(1)); // TEK, sade satır
      expect(devirSatirlari.first['borc'], 300.0);
      expect(devirSatirlari.first['alacak'], 0.0);

      final sonrakiHesaplanan = await _cariHesaplananBakiye(db, cariId);
      expect(sonrakiHesaplanan, closeTo(oncekiHesaplanan, 0.005));
    });

    test('negatif bakiye (alacaklı cari) alacak sütununa yazılır', () async {
      final cariId = await TestVeritabani.ornekCariEkle(db);
      await db.insert('cari_hareket', {
        'cari_id': cariId, 'fis_tipi': 'Tahsilat', 'borc': 0, 'alacak': 150,
        'tarih': DateTime(2026, 3, 1).toIso8601String(), 'is_deleted': 0,
      });
      await db.insert('cari_kapanis_snapshot', {
        'devir_id': 'test-devir', 'donem_id': donemId, 'cari_id': cariId,
        'bakiye': -150.0,
      });

      await DonemArsivServisi().aktifTablolardanSilVeAcilisYaz(
        donemId: donemId, donemYili: donemYili, subeId: subeId,
        baslangic: baslangic, bitis: bitis, aktifDbTest: db,
      );

      final devirSatiri = (await db.query('cari_hareket',
              where: "cari_id = ? AND fis_tipi = 'Devir'", whereArgs: [cariId]))
          .first;
      expect(devirSatiri['borc'], 0.0);
      expect(devirSatiri['alacak'], 150.0);
    });
  });

  group('aktifTablolardanSilVeAcilisYaz — KASA', () {
    test(
        'dönem içi kasa_hareketleri silinir, snapshot bakiyesi TEK '
        'AçılışKasa satırıyla yazılır — sonraki "son bakiye" sorgusu '
        'sıfıra DÜŞMEZ', () async {
      await db.insert('kasa_hareketleri', {
        'hareket_tipi': 'Satış', 'tutar': 400, 'sube_id': subeId,
        'bakiye_sonrasi': 400,
        'tarih': DateTime(2026, 3, 1).toIso8601String(),
      });

      await db.insert('kasa_kapanis_snapshot', {
        'devir_id': 'test-devir', 'donem_id': donemId, 'sube_id': subeId,
        'bakiye': 400.0,
      });

      await DonemArsivServisi().aktifTablolardanSilVeAcilisYaz(
        donemId: donemId, donemYili: donemYili, subeId: subeId,
        baslangic: baslangic, bitis: bitis, aktifDbTest: db,
      );

      final kalanEski = await db.query('kasa_hareketleri',
          where: "hareket_tipi != 'AçılışKasa'");
      expect(kalanEski, isEmpty);

      // 🔴 EN KRİTİK ASSERTION: silme sonrası bu sorgu sıfır DEĞİL,
      // devam eden doğru bakiyeyi dönmeli (aksi halde bir sonraki kasa
      // hareketi yanlış bir tabana eklenirdi).
      final sonBakiye = await _kasaSonBakiye(db, subeId);
      expect(sonBakiye, 400.0);
    });
  });

  group('aktifTablolardanSilVeAcilisYaz — BANKA (açılış satırı GEREKMEZ)', () {
    test('dönem içi banka_hareketler silinir, hiçbir açılış satırı eklenmez',
        () async {
      await db.insert('banka_hareketler', {
        'banka_hesap_id': 1, 'islem_tipi': 'Havale', 'tutar': 250,
        'tarih': DateTime(2026, 3, 1).toIso8601String(),
      });

      await DonemArsivServisi().aktifTablolardanSilVeAcilisYaz(
        donemId: donemId, donemYili: donemYili, subeId: subeId,
        baslangic: baslangic, bitis: bitis, aktifDbTest: db,
      );

      final kalan = await db.query('banka_hareketler');
      expect(kalan, isEmpty); // sil VAR, açılış satırı YOK (gerekmiyor)
    });
  });

  group('aktifTablolardanSilVeAcilisYaz — SATIŞ (FK güvenliği)', () {
    test(
        'iade tarafından referans edilen satış SİLİNMEZ (FOREIGN KEY '
        'ihlali önlenir), referanssız satışlar normal silinir', () async {
      // Üretim bağlantısında PRAGMA foreign_keys=ON (veritabani.dart) —
      // burada da AÇIKÇA açılıyor ki bu test gerçekten "silseydik hata
      // verirdi" senaryosunu kanıtlasın, sadece SQL filtresini değil.
      await db.insert('subeler', {'sube_kodu': 'S1', 'sube_adi': 'Test Şube'});
      await db.execute('PRAGMA foreign_keys = ON');
      final serbstSatisId = await db.insert('satislar', {
        'tarih': DateTime(2026, 3, 1).toIso8601String(), 'sube_id': subeId,
        'genel_toplam': 100.0,
      });
      final iadeliSatisId = await db.insert('satislar', {
        'tarih': DateTime(2026, 4, 1).toIso8601String(), 'sube_id': subeId,
        'genel_toplam': 200.0,
      });
      // iade bu satışa satis_id ile işaret ediyor — gerçek bir FOREIGN
      // KEY (CASCADE'siz), silinirse PRAGMA foreign_keys=ON altında hata.
      await db.insert('iade', {
        'satis_id': iadeliSatisId, 'fis_no': 'IADE-1',
        'tarih': DateTime(2026, 5, 1).toIso8601String(), 'toplam_tutar': 50,
      });

      await DonemArsivServisi().aktifTablolardanSilVeAcilisYaz(
        donemId: donemId, donemYili: donemYili, subeId: subeId,
        baslangic: baslangic, bitis: bitis, aktifDbTest: db,
      );

      final serbst = await db.query('satislar', where: 'id = ?', whereArgs: [serbstSatisId]);
      expect(serbst, isEmpty); // referanssız — silindi

      final iadeli = await db.query('satislar', where: 'id = ?', whereArgs: [iadeliSatisId]);
      expect(iadeli, isNotEmpty); // iade referans veriyor — KORUNDU, hata YOK
    });
  });
}
