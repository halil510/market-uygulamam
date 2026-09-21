// test/servisler/cari_hareket_iptal_banka_kk_test.dart
//
// DEEP_AUDIT (kendi-keşif turu, 2026-09-21): CariDeposu.hareketIptalEt()
// ÖNCEDEN sadece kasa (nakit) tarafını bulup tersine çevirebiliyordu —
// Banka/Kredi Kartı ile yapılan bir tahsilat/ödeme iptal edildiğinde o
// taraf hiç dokunulmadan kalıyordu (banka_hareketler/kredi_karti_hareket
// tablolarında referans_id/referans_turu kolonu hiç yoktu). Migrasyon
// v72 bu kolonları ekledi, CariTahsilatOdemeServisi.kaydet() artık
// dolduruyor, hareketIptalEt() artık kasa ile AYNI desende bulup
// tersine çeviriyor.
//
// CariDeposu.hareketIptalEt() Veritabani() singleton'ı üzerinden
// çalıştığı için (diğer depo testlerinde olduğu gibi, bkz.
// virman_servisi_test.dart'taki AYNI gerekçe) burada altındaki gerçek
// depo metodları (BankaHareketDeposu.ekleTxn, KrediKartiDeposu.
// limitDegistirTxn) — hareketIptalEt() ile BİREBİR AYNI sırayla —
// gerçek şema üzerinde bir in-memory veritabanı içinde doğrudan
// çağrılıyor.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/depolar/banka_hareket_deposu.dart';
import 'package:market_plus/depolar/kredi_karti_deposu.dart';
import 'package:market_plus/modeller/banka_hareket_model.dart';
import '../helper/test_initializer.dart';

/// CariDeposu.hareketIptalEt()'in banka/kredi kartı bloklarıyla BİREBİR
/// AYNI orkestrasyon — tek fark, gerçek Veritabani() singleton'ı yerine
/// test db'sinin transaction'ı kullanılır.
Future<void> _hareketIptalEt(
  Database db, {
  required int cariHareketId,
}) async {
  await db.transaction((txn) async {
    final bankaRows = await txn.query('banka_hareketler',
        where:
            'referans_turu = ? AND referans_id = ? AND (is_deleted IS NULL OR is_deleted = 0)',
        whereArgs: ['cari_hareket', cariHareketId]);
    if (bankaRows.isNotEmpty) {
      final orijinal = bankaRows.first;
      final orijinalTip = orijinal['islem_tipi'] as String? ?? '';
      final orijinalTutar = (orijinal['tutar'] as num?)?.toDouble() ?? 0;
      final bankaHesapId = orijinal['banka_hesap_id'] as int?;
      final tersTip = orijinalTip == 'Giden'
          ? 'Gelen'
          : orijinalTip == 'Gelen'
              ? 'Giden'
              : null;
      if (tersTip != null && orijinalTutar > 0 && bankaHesapId != null) {
        await BankaHareketDeposu().ekleTxn(
            txn,
            BankaHareketModel(
              bankaHesapId: bankaHesapId,
              islemTipi: tersTip,
              tutar: orijinalTutar,
              referansId: cariHareketId,
              referansTuru: 'cari_hareket_iptal',
              tarih: DateTime.now(),
              aciklama: 'İptal testi',
            ));
      }
    }

    final kkRows = await txn.query('kredi_karti_hareket',
        where: 'referans_turu = ? AND referans_id = ? AND is_deleted = 0',
        whereArgs: ['cari_hareket', cariHareketId]);
    if (kkRows.isNotEmpty) {
      final orijinal = kkRows.first;
      final orijinalYon = orijinal['yon'] as String? ?? '';
      final orijinalTutar = (orijinal['tutar'] as num?)?.toDouble() ?? 0;
      final krediKartiId = orijinal['kredi_karti_id'] as int?;
      if (orijinalTutar > 0 && krediKartiId != null) {
        final tersDelta =
            orijinalYon == 'harcama' ? -orijinalTutar : orijinalTutar;
        await KrediKartiDeposu().limitDegistirTxn(
            txn, krediKartiId, tersDelta,
            aciklama: 'İptal testi',
            referansId: cariHareketId,
            referansTuru: 'cari_hareket_iptal');
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

  group('Banka tarafı — cari hareket iptali artık tersine çeviriyor', () {
    test(
        'müşteriden Banka ile 5.000₺ tahsilat iptal edilince banka '
        'bakiyesi de GERİ DÜŞER (önceden hiç düşmüyordu)', () async {
      final hesapId = await _bankaHesabiEkle(bakiye: 0);
      // 1. Orijinal tahsilat: müşteriden banka'ya 5000 giriyor (Gelen).
      final cariHareketId = 1; // sabit — sadece referans için, gerçek satır gerekmiyor.
      await db.transaction((txn) => BankaHareketDeposu().ekleTxn(
          txn,
          BankaHareketModel(
            bankaHesapId: hesapId, islemTipi: 'Gelen', tutar: 5000,
            tarih: DateTime.now(), referansId: cariHareketId,
            referansTuru: 'cari_hareket',
          )));

      var hesap = (await db.query('banka_hesaplar', where: 'id = ?', whereArgs: [hesapId])).first;
      expect(hesap['bakiye'], 5000.0);

      // 2. İptal: hareketIptalEt() mantığıyla bul + tersine çevir.
      await _hareketIptalEt(db, cariHareketId: cariHareketId);

      hesap = (await db.query('banka_hesaplar', where: 'id = ?', whereArgs: [hesapId])).first;
      expect(hesap['bakiye'], 0.0,
          reason: 'iptal sonrası banka bakiyesi orijinal tahsilattan ÖNCEKİ '
              'haline dönmeli — önceden bu asla olmuyordu');
    });

    test('tedarikçiye Banka ile yapılan 3.000₺ ödeme iptal edilince para GERİ GELİR',
        () async {
      final hesapId = await _bankaHesabiEkle(bakiye: 10000);
      const cariHareketId = 2;
      await db.transaction((txn) => BankaHareketDeposu().ekleTxn(
          txn,
          BankaHareketModel(
            bankaHesapId: hesapId, islemTipi: 'Giden', tutar: 3000,
            tarih: DateTime.now(), referansId: cariHareketId,
            referansTuru: 'cari_hareket',
          )));

      var hesap = (await db.query('banka_hesaplar', where: 'id = ?', whereArgs: [hesapId])).first;
      expect(hesap['bakiye'], 7000.0);

      await _hareketIptalEt(db, cariHareketId: cariHareketId);

      hesap = (await db.query('banka_hesaplar', where: 'id = ?', whereArgs: [hesapId])).first;
      expect(hesap['bakiye'], 10000.0);
    });
  });

  group('Kredi kartı tarafı — cari hareket iptali artık tersine çeviriyor', () {
    test(
        "müşteriden Kredi Kartı ile tahsilat (limit azaltan 'odeme' yönü) "
        'iptal edilince kullanılan limit GERİ ARTAR', () async {
      final kartId = await _krediKartiEkle(limit: 10000);
      const cariHareketId = 3;
      // Müşteriden tahsilat = kart kullanımını AZALTIR (negatif delta, 'odeme').
      await db.transaction((txn) => KrediKartiDeposu().limitDegistirTxn(
          txn, kartId, -1500,
          referansId: cariHareketId, referansTuru: 'cari_hareket'));

      var kart = (await db.query('kredi_kartlari', where: 'id = ?', whereArgs: [kartId])).first;
      expect(kart['kullanilan_limit'], -1500.0);

      await _hareketIptalEt(db, cariHareketId: cariHareketId);

      kart = (await db.query('kredi_kartlari', where: 'id = ?', whereArgs: [kartId])).first;
      expect(kart['kullanilan_limit'], 0.0,
          reason: 'iptal sonrası kullanılan limit orijinal işlemden ÖNCEKİ '
              'haline dönmeli');
    });
  });
}
