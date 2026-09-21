// test/servisler/alim_sil_test.dart
//
// Kullanıcı bulgusu (2026-09-22): "tedarikçi alım da aynı silme de
// listede gözüküyor sonra alacaklı konuma geçmiyor" — bir Alım
// silindiğinde (a) Alım Listesi'nin "Teslim Alınan" sekmesinde AYNEN
// görünmeye devam ediyordu, (b) stok hiç geri düşülmüyordu, (c) Nakit/
// Havale ile yapılmış bir alımda kasadan/bankadan çıkan para GERİ
// GELMİYORDU. Kök neden: AlimIslemServisi'nin hiç sil() metodu yoktu —
// silme, 'Alım' kavramından habersiz genel amaçlı CariDeposu.
// hareketIptalEt()'e düşüyordu (referans_turu='cari_hareket' arıyordu,
// ama alimKaydet() referans_turu='alim' yazıyordu — asla eşleşmiyordu).
//
// AlimIslemServisi Veritabani() singleton'ına bağımlı olduğundan
// (projenin yerleşik test deseni — bkz. satis_sil_cari_ters_kayit_test.
// dart), bu test yeni sil() metodundaki BİREBİR aynı akışı gerçek şema
// üzerinde doğrular.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../helper/test_initializer.dart';

/// AlimIslemServisi.sil()'in BİREBİR aynısı.
Future<void> _alimSilSimulasyonu(Database db, int alimId) async {
  await db.transaction((txn) async {
    final alim = (await txn.query('tedarikci_siparisler', where: 'id = ?', whereArgs: [alimId])).first;
    if (alim['durum'] != 'teslim_alindi') {
      throw Exception('Sadece teslim alınmış bir alım silinebilir.');
    }
    final cariId = alim['cari_id'] as int?;
    final alimNo = alim['siparis_no'] as String? ?? '#$alimId';
    final simdi = DateTime.now().toIso8601String();

    await txn.update('tedarikci_siparisler',
        {'durum': 'iptal', 'is_deleted': 1, 'last_updated': simdi},
        where: 'id = ?', whereArgs: [alimId]);

    final kalemler = await txn.query('tedarikci_siparis_kalem', where: 'siparis_id = ?', whereArgs: [alimId]);
    for (final k in kalemler) {
      final urunId = k['urun_id'] as int?;
      final miktar = (k['teslim_mik'] as num?)?.toDouble() ?? 0;
      if (urunId == null || miktar <= 0) continue;
      final onceki = (await txn.query('urunler', columns: ['stok'], where: 'id = ?', whereArgs: [urunId])).first['stok'] as num;
      final sonraki = onceki.toDouble() - miktar;
      await txn.update('urunler', {'stok': sonraki, 'last_updated': simdi}, where: 'id = ?', whereArgs: [urunId]);
      await txn.insert('stok_hareket', {
        'urun_id': urunId, 'hareket_turu': 'Alım İptali', 'miktar': miktar,
        'onceki_stok': onceki, 'sonraki_stok': sonraki,
        'referans_id': alimId, 'referans_turu': 'alim_iptal', 'tarih': simdi, 'last_updated': simdi,
      });
    }

    final kasaRows = await txn.query('kasa_hareketleri',
        where: 'referans_id = ? AND referans_turu = ? AND deleted_at IS NULL', whereArgs: [alimId, 'alim']);
    for (final k in kasaRows) {
      final tutar = (k['tutar'] as num?)?.toDouble() ?? 0;
      if (tutar <= 0) continue;
      final sonBakiye = (await txn.rawQuery('SELECT bakiye_sonrasi FROM kasa_hareketleri ORDER BY id DESC LIMIT 1')).first;
      final oncekiBakiye = (sonBakiye['bakiye_sonrasi'] as num?)?.toDouble() ?? 0;
      await txn.insert('kasa_hareketleri', {
        'global_id': const Uuid().v4(), 'hareket_tipi': 'Alım İptali', 'tutar': tutar,
        'referans_id': alimId, 'referans_turu': 'alim_iptal', 'tarih': simdi,
        'aciklama': 'Alım iptali: $alimNo', 'bakiye_sonrasi': oncekiBakiye + tutar,
      });
    }

    if (cariId != null) {
      final orijinal = await txn.query('cari_hareket',
          where: 'fis_id = ? AND cari_id = ? AND fis_tipi = ? AND is_deleted = 0',
          whereArgs: [alimId, cariId, 'Alım']);
      final toplamBorc = orijinal.fold(0.0, (s, r) => s + ((r['borc'] as num?)?.toDouble() ?? 0));
      final toplamAlacak = orijinal.fold(0.0, (s, r) => s + ((r['alacak'] as num?)?.toDouble() ?? 0));
      if (toplamBorc > 0.005 || toplamAlacak > 0.005) {
        await txn.insert('cari_hareket', {
          'global_id': const Uuid().v4(), 'cari_id': cariId, 'tarih': simdi, 'last_updated': simdi,
          'fis_tipi': 'Alım İptali', 'fis_id': alimId, 'fis_no': alimNo,
          'aciklama': 'Alım iptali: $alimNo', 'borc': toplamAlacak, 'alacak': toplamBorc, 'odeme_turu': 'Cari',
        });
      }
      await txn.rawUpdate(
          'UPDATE cari SET bakiye = (SELECT COALESCE(SUM(borc),0) - COALESCE(SUM(alacak),0) FROM cari_hareket WHERE cari_id = ? AND is_deleted = 0), last_updated = ? WHERE id = ?',
          [cariId, simdi, cariId]);
    }
  });
}

void main() {
  late Database db;
  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  group('AlimIslemServisi.sil() — Cari (veresiye) alım', () {
    test('bakiye TAM olarak eski haline döner (tedarikçiye olan borcumuz kalkar)', () async {
      final cariId = await TestVeritabani.ornekCariEkle(db, cariTipi: 'Tedarikçi');
      final urunId = await TestVeritabani.ornekUrunEkle(db, stok: 10);

      final alimId = await db.insert('tedarikci_siparisler', {
        'cari_id': cariId, 'siparis_no': 'AL2026000001', 'siparis_tarihi': DateTime.now().toIso8601String(),
        'toplam_tutar': 150.0, 'durum': 'teslim_alindi', 'is_deleted': 0,
      });
      await db.insert('tedarikci_siparis_kalem', {
        'siparis_id': alimId, 'urun_id': urunId, 'siparis_mik': 5, 'teslim_mik': 5,
        'birim_fiyat': 30.0, 'kdv_oran': 0, 'toplam_tutar': 150.0,
      });
      await db.update('urunler', {'stok': 15}, where: 'id = ?', whereArgs: [urunId]); // 10 + 5 alım
      await db.insert('cari_hareket', {
        'global_id': const Uuid().v4(), 'cari_id': cariId, 'tarih': DateTime.now().toIso8601String(),
        'fis_tipi': 'Alım', 'fis_id': alimId, 'fis_no': 'AL2026000001',
        'aciklama': 'Mal Alımı: AL2026000001', 'borc': 0, 'alacak': 150.0, 'odeme_turu': 'Cari', 'is_deleted': 0,
      });
      await db.update('cari', {'bakiye': -150.0}, where: 'id = ?', whereArgs: [cariId]);

      await _alimSilSimulasyonu(db, alimId);

      final cari = (await db.query('cari', where: 'id = ?', whereArgs: [cariId])).first;
      expect((cari['bakiye'] as num).toDouble(), equals(0.0),
          reason: 'Alım silinince tedarikçiye olan borcumuz tam sıfırlanmalı ("alacaklı" konumuna dönmeli)');

      final urun = (await db.query('urunler', where: 'id = ?', whereArgs: [urunId])).first;
      expect((urun['stok'] as num).toDouble(), equals(10.0), reason: 'alınan mal stoktan geri düşmeli');

      final siparis = (await db.query('tedarikci_siparisler', where: 'id = ?', whereArgs: [alimId])).first;
      expect(siparis['durum'], 'iptal', reason: 'Alım Listesi "Teslim Alınan" sekmesinden düşmeli');
      expect(siparis['is_deleted'], 1);
    });

    test('zaten "iptal" durumundaki bir alım TEKRAR silinemez', () async {
      final cariId = await TestVeritabani.ornekCariEkle(db, cariTipi: 'Tedarikçi');
      final alimId = await db.insert('tedarikci_siparisler', {
        'cari_id': cariId, 'siparis_no': 'AL2', 'siparis_tarihi': DateTime.now().toIso8601String(),
        'toplam_tutar': 50.0, 'durum': 'iptal', 'is_deleted': 1,
      });

      await expectLater(_alimSilSimulasyonu(db, alimId), throwsException);
    });
  });

  group('AlimIslemServisi.sil() — Nakit alım', () {
    test('kasadan çıkan para GERİ GELİR', () async {
      final cariId = await TestVeritabani.ornekCariEkle(db, cariTipi: 'Tedarikçi');
      final urunId = await TestVeritabani.ornekUrunEkle(db, stok: 0);
      final alimId = await db.insert('tedarikci_siparisler', {
        'cari_id': cariId, 'siparis_no': 'AL3', 'siparis_tarihi': DateTime.now().toIso8601String(),
        'toplam_tutar': 80.0, 'durum': 'teslim_alindi', 'is_deleted': 0,
      });
      await db.insert('tedarikci_siparis_kalem', {
        'siparis_id': alimId, 'urun_id': urunId, 'siparis_mik': 4, 'teslim_mik': 4,
        'birim_fiyat': 20.0, 'kdv_oran': 0, 'toplam_tutar': 80.0,
      });
      await db.update('urunler', {'stok': 4}, where: 'id = ?', whereArgs: [urunId]);
      await db.insert('kasa_hareketleri', {
        'global_id': const Uuid().v4(), 'hareket_tipi': 'Alım', 'tutar': 80.0,
        'referans_id': alimId, 'referans_turu': 'alim', 'tarih': DateTime.now().toIso8601String(),
        'bakiye_sonrasi': -80.0,
      });

      await _alimSilSimulasyonu(db, alimId);

      final kasaTers = await db.query('kasa_hareketleri',
          where: 'referans_id = ? AND referans_turu = ?', whereArgs: [alimId, 'alim_iptal']);
      expect(kasaTers, hasLength(1));
      expect((kasaTers.first['tutar'] as num).toDouble(), equals(80.0));

      final urun = (await db.query('urunler', where: 'id = ?', whereArgs: [urunId])).first;
      expect((urun['stok'] as num).toDouble(), equals(0.0));
    });
  });
}
