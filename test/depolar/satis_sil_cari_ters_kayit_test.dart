// test/depolar/satis_sil_cari_ters_kayit_test.dart
//
// Kullanıcı bulgusu (2026-09-21): Satış Listesi'nden veresiye (Cari) bir
// satış silindiğinde, Cari Hareketler ekranında açıklanamaz bir
// "Tahsilat İptali" satırı beliriyor ve müşteri borcu SIFIRLANMIYORDU —
// sanki satış hiç silinmemiş gibi aynı tutar borç olarak kalıyordu.
//
// Kök neden: SatisDeposu.sil() içindeki cari ters-kayıt mantığı
// satislar.odenen_tutar alanına bakıyordu. Ama saf Veresiye (Cari)
// satışlarda bu alan (hizli_satis_ekrani_odeme.dart'taki "diğer" dal —
// _satisiTamamla(yontem, sepet.genelToplam, 0.0)) GERÇEK bir tahsilatı
// DEĞİL, satış toplamının kendisini taşıyordu. Sonuç: "Satış İptali"
// borcu doğru sıfırlıyordu AMA hemen ardından odenenTutar > 0 olduğu
// için FAZLADAN bir "Tahsilat İptali" borcu daha ekleniyordu — net etki
// SIFIR değil, ORİJİNAL BORCUN AYNISI oluyordu.
//
// Düzeltme: artık odenen_tutar'a güvenilmiyor — bu satışın GERÇEKTEN
// yazdığı cari_hareket satırları (fis_id + fis_tipi='Satış') sorgulanıp
// toplam borç/alacağın TAM TERSİ TEK bir "Satış İptali" kaydıyla
// sıfırlanıyor. Aynı mantık kasa_hareketleri için de uygulandı (Karma
// satışlarda kasadan olduğundan fazla düşülmesini önler).
//
// SatisDeposu.sil() Veritabani() singleton'ına bağımlı olduğundan
// (projenin yerleşik test deseni — bkz. satis_odeme_dagilimi_test.dart),
// bu test o metottaki BİREBİR aynı sorgu/insert akışını gerçek şema
// üzerinde doğrular.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../helper/test_initializer.dart';

/// SatisDeposu.sil()'deki 5. ve 6. adımların (kasa/cari ters kaydı)
/// BİREBİR aynısı.
Future<void> _satisSilSimulasyonu(Database db, int satisId) async {
  await db.transaction((txn) async {
    final satis = (await txn.query('satislar', where: 'id = ?', whereArgs: [satisId])).first;
    final odemeYontemi = satis['odeme_yontemi'] as String? ?? '';
    final cariId = satis['cari_id'] as int?;
    final fisNo = satis['fis_no'] as String? ?? '#$satisId';
    final simdi = DateTime.now().toIso8601String();

    await txn.update('satislar', {'is_deleted': 1, 'iptal': 1, 'last_updated': simdi},
        where: 'id = ?', whereArgs: [satisId]);

    final orijinalKasaSatirlari = await txn.query('kasa_hareketleri',
        where: 'referans_id = ? AND referans_turu = ? AND deleted_at IS NULL',
        whereArgs: [satisId, 'satis']);
    for (final k in orijinalKasaSatirlari) {
      final tutar = (k['tutar'] as num?)?.toDouble() ?? 0;
      if (tutar <= 0) continue;
      final sonBakiye = (await txn.rawQuery(
              'SELECT bakiye_sonrasi FROM kasa_hareketleri ORDER BY id DESC LIMIT 1'))
          .firstOrNull;
      final oncekiBakiye = (sonBakiye?['bakiye_sonrasi'] as num?)?.toDouble() ?? 0;
      await txn.insert('kasa_hareketleri', {
        'global_id': const Uuid().v4(),
        'hareket_tipi': 'Satış İptali',
        'tutar': tutar,
        'referans_id': satisId,
        'referans_turu': 'satis_iptal',
        'tarih': simdi,
        'aciklama': 'Satış iptali: $fisNo',
        'odeme_yontemi': k['odeme_yontemi'],
        'bakiye_sonrasi': oncekiBakiye - tutar,
      });
    }

    if (cariId != null) {
      final orijinalCariSatirlari = await txn.query('cari_hareket',
          where: 'fis_id = ? AND cari_id = ? AND fis_tipi IN (?, ?) AND is_deleted = 0',
          whereArgs: [satisId, cariId, 'Satış', 'Toptan Satış']);
      final toplamBorc = orijinalCariSatirlari.fold(
          0.0, (s, r) => s + ((r['borc'] as num?)?.toDouble() ?? 0));
      final toplamAlacak = orijinalCariSatirlari.fold(
          0.0, (s, r) => s + ((r['alacak'] as num?)?.toDouble() ?? 0));
      if (toplamBorc > 0.005 || toplamAlacak > 0.005) {
        await txn.insert('cari_hareket', {
          'global_id': const Uuid().v4(),
          'cari_id': cariId,
          'tarih': simdi,
          'last_updated': simdi,
          'fis_tipi': 'Satış İptali',
          'fis_id': satisId,
          'fis_no': fisNo,
          'aciklama': 'Satış iptali: $fisNo',
          'borc': toplamAlacak,
          'alacak': toplamBorc,
          'odeme_turu': odemeYontemi,
        });
      }
      final bRes = await txn.rawQuery(
          'SELECT SUM(borc) - SUM(alacak) AS b FROM cari_hareket WHERE cari_id = ? AND is_deleted = 0',
          [cariId]);
      final yeniBakiye = (bRes.first['b'] as num?)?.toDouble() ?? 0;
      await txn.update('cari', {'bakiye': yeniBakiye, 'last_updated': simdi},
          where: 'id = ?', whereArgs: [cariId]);
    }
  });
}

void main() {
  late Database db;

  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  group('SatisDeposu.sil() — saf Veresiye (Cari) satış', () {
    test('silinince bakiye TAM SIFIRA döner, hayalet Tahsilat İptali OLUŞMAZ', () async {
      final cariId = await TestVeritabani.ornekCariEkle(db);

      // Üretimdeki gerçek hatalı senaryo: hizli_satis_ekrani_odeme.dart
      // pure-Cari satışta odenen_tutar'ı genel_toplam ile AYNI yazıyor
      // (bookkeeping alanı — gerçek tahsilat DEĞİL).
      final satisId = await db.insert('satislar', {
        'fis_no': 'CRI2026000000003',
        'tarih': DateTime.now().toIso8601String(),
        'cari_id': cariId,
        'genel_toplam': 90.0,
        'odenen_tutar': 90.0,
        'odeme_yontemi': 'Cari',
        'fis_tipi': 'Satış',
        'is_deleted': 0,
      });
      await db.insert('cari_hareket', {
        'global_id': const Uuid().v4(),
        'cari_id': cariId,
        'tarih': DateTime.now().toIso8601String(),
        'fis_tipi': 'Satış',
        'fis_id': satisId,
        'fis_no': 'CRI2026000000003',
        'aciklama': 'Veresiye: CRI2026000000003',
        'borc': 90.0,
        'alacak': 0.0,
        'odeme_turu': 'Cari',
        'is_deleted': 0,
      });
      await db.update('cari', {'bakiye': 90.0}, where: 'id = ?', whereArgs: [cariId]);

      await _satisSilSimulasyonu(db, satisId);

      final cari = (await db.query('cari', where: 'id = ?', whereArgs: [cariId])).first;
      expect((cari['bakiye'] as num).toDouble(), equals(0.0),
          reason: 'Satış silinince veresiye borcu tamamen kalkmalı');

      final tahsilatIptali = await db.query('cari_hareket',
          where: 'fis_id = ? AND fis_tipi = ?', whereArgs: [satisId, 'Tahsilat İptali']);
      expect(tahsilatIptali, isEmpty,
          reason: 'Hiç gerçekleşmemiş bir tahsilatın iptali yazılmamalı');

      final kasaTers = await db.query('kasa_hareketleri',
          where: 'referans_id = ? AND referans_turu = ?', whereArgs: [satisId, 'satis_iptal']);
      expect(kasaTers, isEmpty, reason: 'Veresiye satışta hiç kasa hareketi olmadığından ters kayıt da olmamalı');
    });
  });

  group('SatisDeposu.sil() — Karma (Nakit + Cari) satış', () {
    test('kasadan sadece Nakit payı düşer, cari borcu sadece Cari payı kadar sıfırlanır', () async {
      final cariId = await TestVeritabani.ornekCariEkle(db);

      final satisId = await db.insert('satislar', {
        'fis_no': 'CRI2026000000004',
        'tarih': DateTime.now().toIso8601String(),
        'cari_id': cariId,
        'genel_toplam': 100.0,
        'odenen_tutar': 100.0, // Karma toplamı: 60 Nakit + 40 Cari
        'odeme_yontemi': 'Karma',
        'fis_tipi': 'Satış',
        'is_deleted': 0,
      });
      await db.insert('kasa_hareketleri', {
        'global_id': const Uuid().v4(),
        'hareket_tipi': 'Satış',
        'tutar': 60.0,
        'referans_id': satisId,
        'referans_turu': 'satis',
        'tarih': DateTime.now().toIso8601String(),
        'odeme_yontemi': 'Nakit',
        'bakiye_sonrasi': 60.0,
      });
      await db.insert('cari_hareket', {
        'global_id': const Uuid().v4(),
        'cari_id': cariId,
        'tarih': DateTime.now().toIso8601String(),
        'fis_tipi': 'Satış',
        'fis_id': satisId,
        'aciklama': 'Veresiye (Karma): CRI2026000000004',
        'borc': 40.0,
        'alacak': 0.0,
        'odeme_turu': 'Cari',
        'is_deleted': 0,
      });
      await db.update('cari', {'bakiye': 40.0}, where: 'id = ?', whereArgs: [cariId]);

      await _satisSilSimulasyonu(db, satisId);

      final cari = (await db.query('cari', where: 'id = ?', whereArgs: [cariId])).first;
      expect((cari['bakiye'] as num).toDouble(), equals(0.0));

      final kasaTers = await db.query('kasa_hareketleri',
          where: 'referans_id = ? AND referans_turu = ?', whereArgs: [satisId, 'satis_iptal']);
      expect(kasaTers, hasLength(1));
      expect((kasaTers.first['tutar'] as num).toDouble(), equals(60.0),
          reason: 'kasadan sadece GERÇEKTEN girmiş olan Nakit payı geri çıkmalı, Cari payı değil');
    });
  });
}
