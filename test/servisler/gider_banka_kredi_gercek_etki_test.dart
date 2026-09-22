// test/servisler/gider_banka_kredi_gercek_etki_test.dart
//
// Paralel fork denetimi (2026-09-22, "tam ERP" turu) KRİTİK bir bulgu
// buldu: Banka/Kredi Kartı ödeme yöntemiyle girilen GİDERLER hiçbir
// gerçek banka_hareketler/kredi_karti_hareket satırı oluşturmuyordu —
// sadece 'giderler' tablosuna düşüyor, şirketin gerçek banka bakiyesi/
// kart limit kullanımı hiç etkilenmiyordu (Virman/İade'de daha önce
// bulunan AYNI hata sınıfı).
//
// GiderDeposu.ekle()/guncelle()/sil() artık CariTahsilatOdemeServisi'ndeki
// AYNI desenle gerçek hareket yazıyor/tersine çeviriyor — hesap/kart
// DEĞİŞTİRİLEBİLİR olduğundan (guncelle'de) uzlaştırma HESAP/KART
// BAZINDA yapılıyor.
//
// GiderDeposu Veritabani() singleton'ı üzerinden çalıştığı için (diğer
// depo testlerinde olduğu gibi, bkz. virman_servisi_test.dart'taki AYNI
// gerekçe) burada altındaki gerçek depo metodları (BankaHareketDeposu.
// ekleTxn, KrediKartiDeposu.limitDegistirTxn) — GiderDeposu ile BİREBİR
// AYNI sırayla ve AYNI net-hesaplama sorgularıyla — gerçek şema üzerinde
// bir in-memory veritabanı içinde doğrudan çağrılıyor.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/depolar/banka_hareket_deposu.dart';
import 'package:market_plus/depolar/kredi_karti_deposu.dart';
import 'package:market_plus/modeller/banka_hareket_model.dart';
import '../helper/test_initializer.dart';

Future<Map<int, double>> _bankaNetHesaplaTumHesaplar(dynamic db, int giderId) async {
  final rows = await db.query('banka_hareketler',
      where:
          "referans_id = ? AND referans_turu = 'gider' AND (is_deleted IS NULL OR is_deleted = 0)",
      whereArgs: [giderId]);
  final netler = <int, double>{};
  for (final r in rows) {
    final hesapId = r['banka_hesap_id'] as int?;
    if (hesapId == null) continue;
    final tip = r['islem_tipi'] as String? ?? '';
    final tutar = (r['tutar'] as num?)?.toDouble() ?? 0;
    netler[hesapId] = (netler[hesapId] ?? 0) + (tip == 'Giden' ? tutar : -tutar);
  }
  return netler;
}

Future<Map<int, double>> _krediNetHesaplaTumKartlar(dynamic db, int giderId) async {
  final rows = await db.query('kredi_karti_hareket',
      where: "referans_id = ? AND referans_turu = 'gider' AND is_deleted = 0",
      whereArgs: [giderId]);
  final netler = <int, double>{};
  for (final r in rows) {
    final kartId = r['kredi_karti_id'] as int?;
    if (kartId == null) continue;
    final yon = r['yon'] as String? ?? '';
    final tutar = (r['tutar'] as num?)?.toDouble() ?? 0;
    netler[kartId] = (netler[kartId] ?? 0) + (yon == 'harcama' ? tutar : -tutar);
  }
  return netler;
}

/// GiderDeposu.guncelle()'nin banka/kredi bloklarıyla BİREBİR AYNI
/// uzlaştırma mantığı.
Future<void> _bankaUzlastir(Database db,
    {required int giderId, required int? hedefHesapId, required double hedefTutar}) async {
  await db.transaction((txn) async {
    final netler = await _bankaNetHesaplaTumHesaplar(txn, giderId);
    final hedefler = <int, double>{if (hedefHesapId != null) hedefHesapId: hedefTutar};
    final etkilenen = {...netler.keys, ...hedefler.keys};
    for (final hesapId in etkilenen) {
      final mevcut = netler[hesapId] ?? 0;
      final hedef = hedefler[hesapId] ?? 0;
      final fark = hedef - mevcut;
      if (fark.abs() > 0.005) {
        await BankaHareketDeposu().ekleTxn(txn, BankaHareketModel(
          bankaHesapId: hesapId, islemTipi: fark > 0 ? 'Giden' : 'Gelen',
          tutar: fark.abs(), tarih: DateTime.now(),
          referansId: giderId, referansTuru: 'gider', aciklama: 'test',
        ));
      }
    }
  });
}

Future<void> _krediUzlastir(Database db,
    {required int giderId, required int? hedefKartId, required double hedefTutar}) async {
  await db.transaction((txn) async {
    final netler = await _krediNetHesaplaTumKartlar(txn, giderId);
    final hedefler = <int, double>{if (hedefKartId != null) hedefKartId: hedefTutar};
    final etkilenen = {...netler.keys, ...hedefler.keys};
    for (final kartId in etkilenen) {
      final mevcut = netler[kartId] ?? 0;
      final hedef = hedefler[kartId] ?? 0;
      final fark = hedef - mevcut;
      if (fark.abs() > 0.005) {
        await KrediKartiDeposu().limitDegistirTxn(txn, kartId, fark,
            aciklama: 'test', referansId: giderId, referansTuru: 'gider');
      }
    }
  });
}

void main() {
  late Database db;
  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  Future<int> _bankaIdAl() async => db.insert('bankalar', {'ad': 'Test Bankası'});
  Future<int> _bankaHesabiEkle({double bakiye = 0}) async {
    final bankaId = await _bankaIdAl();
    return db.insert('banka_hesaplar', {
      'banka_id': bankaId, 'hesap_adi': 'Test Hesap', 'hesap_no': '123',
      'bakiye': bakiye, 'kullanilabilir_bakiye': bakiye,
    });
  }

  Future<int> _krediKartiEkle({double limit = 10000}) async {
    final bankaId = await _bankaIdAl();
    return db.insert('kredi_kartlari', {
      'banka_id': bankaId, 'kart_adi': 'Test Kart', 'kart_no_maskeli': '**** 1234',
      'kartlimit': limit, 'kullanilan_limit': 0, 'kalan_limit': limit,
    });
  }

  group('Gider — Banka ödeme yöntemi artık GERÇEK banka hareketi yaratıyor', () {
    test('500₺ Banka gideri girilince hesap bakiyesi GERÇEKTEN 500₺ düşer', () async {
      final hesapId = await _bankaHesabiEkle(bakiye: 10000);
      const giderId = 1;

      await _bankaUzlastir(db, giderId: giderId, hedefHesapId: hesapId, hedefTutar: 500.0);

      final hesap = (await db.query('banka_hesaplar', where: 'id = ?', whereArgs: [hesapId])).first;
      expect((hesap['bakiye'] as num).toDouble(), equals(9500.0));
    });

    test('gider silinince (net→0 uzlaştırma) banka bakiyesi GERİ GELİR', () async {
      final hesapId = await _bankaHesabiEkle(bakiye: 10000);
      const giderId = 2;
      await _bankaUzlastir(db, giderId: giderId, hedefHesapId: hesapId, hedefTutar: 300.0);

      // Silme = hedef yok (null hesap → tüm hesaplar 0'a uzlaştırılır).
      await _bankaUzlastir(db, giderId: giderId, hedefHesapId: null, hedefTutar: 0);

      final hesap = (await db.query('banka_hesaplar', where: 'id = ?', whereArgs: [hesapId])).first;
      expect((hesap['bakiye'] as num).toDouble(), equals(10000.0),
          reason: 'Silinen gider kadar tutar bankaya geri dönmeli');
    });

    test('gider Nakit\'ten Banka\'ya güncellenip SONRA tutar artırılırsa hesap doğru düşer', () async {
      final hesapId = await _bankaHesabiEkle(bakiye: 5000);
      const giderId = 3;
      // İlk düzenleme: 200₺
      await _bankaUzlastir(db, giderId: giderId, hedefHesapId: hesapId, hedefTutar: 200.0);
      // İkinci düzenleme: 350₺'ye çıkarıldı (sadece FARK yazılmalı).
      await _bankaUzlastir(db, giderId: giderId, hedefHesapId: hesapId, hedefTutar: 350.0);

      final hesap = (await db.query('banka_hesaplar', where: 'id = ?', whereArgs: [hesapId])).first;
      expect((hesap['bakiye'] as num).toDouble(), equals(4650.0));

      final hareketler = await db.query('banka_hareketler', where: 'referans_id = ?', whereArgs: [giderId]);
      expect(hareketler, hasLength(2), reason: 'İlk yazım + fark düzeltmesi, orijinal satır DEĞİŞTİRİLMEMELİ');
    });

    test('gider Banka A\'dan Banka B\'ye taşınınca A geri gelir, B düşer', () async {
      final hesapA = await _bankaHesabiEkle(bakiye: 5000);
      final hesapB = await _bankaHesabiEkle(bakiye: 5000);
      const giderId = 4;
      await _bankaUzlastir(db, giderId: giderId, hedefHesapId: hesapA, hedefTutar: 1000.0);

      // Hesap değiştirildi: artık B hedef, A hiç hedef değil (→ 0'a uzlaşır).
      await _bankaUzlastir(db, giderId: giderId, hedefHesapId: hesapB, hedefTutar: 1000.0);

      final a = (await db.query('banka_hesaplar', where: 'id = ?', whereArgs: [hesapA])).first;
      final b = (await db.query('banka_hesaplar', where: 'id = ?', whereArgs: [hesapB])).first;
      expect((a['bakiye'] as num).toDouble(), equals(5000.0), reason: 'A hesabı tam geri gelmeli');
      expect((b['bakiye'] as num).toDouble(), equals(4000.0), reason: 'B hesabı 1000 düşmeli');
    });
  });

  group('Gider — Kredi Kartı ödeme yöntemi artık GERÇEK kart hareketi yaratıyor', () {
    test('400₺ Kredi Kartı gideri girilince kullanılan limit GERÇEKTEN artar', () async {
      final kartId = await _krediKartiEkle(limit: 5000);
      const giderId = 5;

      await _krediUzlastir(db, giderId: giderId, hedefKartId: kartId, hedefTutar: 400.0);

      final kart = (await db.query('kredi_kartlari', where: 'id = ?', whereArgs: [kartId])).first;
      expect((kart['kullanilan_limit'] as num).toDouble(), equals(400.0));
      expect((kart['kalan_limit'] as num).toDouble(), equals(4600.0));
    });

    test('gider silinince kullanılan limit GERİ AZALIR', () async {
      final kartId = await _krediKartiEkle(limit: 5000);
      const giderId = 6;
      await _krediUzlastir(db, giderId: giderId, hedefKartId: kartId, hedefTutar: 250.0);

      await _krediUzlastir(db, giderId: giderId, hedefKartId: null, hedefTutar: 0);

      final kart = (await db.query('kredi_kartlari', where: 'id = ?', whereArgs: [kartId])).first;
      expect((kart['kullanilan_limit'] as num).toDouble(), equals(0.0));
    });
  });
}
