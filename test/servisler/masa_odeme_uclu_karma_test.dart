// test/servisler/masa_odeme_uclu_karma_test.dart
//
// Kademe 2 (2026-11-06): MasaOdemeServisi.odemeYap() ÜÇLÜ karma ödeme —
// ikili kombinasyonlar test edilmişti, üçlü hiç denenmemişti.
// 100 TL sipariş = 40 Nakit + 30 Kredi Kartı + 30 Cari.
//
// GERÇEK MasaDeposu (masa → sipariş → kalem) ve MasaOdemeServisi çağrılır.
//
// Bilinen tasarım (MasaOdemeServisi içindeki not): müşteri bağlıyken
// Nakit/Kart payı için de bakiyeyi ETKİLEMEYEN (borc=alacak) bir "bilgi"
// cari_hareket satırı yazılır — Hızlı Satış ile aynı. Bu yüzden satışa ait
// cari satırlardan yalnız biri gerçek borçtur (30/0); net etki 30'dur.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/cekirdek/utils/para_utils.dart';
import 'package:market_plus/depolar/masa_deposu.dart';
import 'package:market_plus/modeller/masa_model.dart';
import 'package:market_plus/servisler/aktif_sube_servisi.dart';
import 'package:market_plus/servisler/masa_odeme_servisi.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  final masaDepo = MasaDeposu();

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (_) async => null);
    SharedPreferences.setMockInitialValues({});
    db = await TestVeritabani.olustur();
    Veritabani.testVeritabani = db;
    // §3.5: satış/kasa sube_id'yi aktif şubeden alır — testte gerçek bir şube seçilir.
    final subeId = await db.insert('subeler',
        {'sube_adi': 'Merkez', 'sube_kodu': 'MRK', 'aktif': 1, 'is_deleted': 0});
    await AktifSubeServisi().subeDegistir(subeId, yeniSubeAdi: 'Merkez');
  });
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await AktifSubeServisi().subeDegistir(null);
    Veritabani.testVeritabani = null;
    await db.close();
  });

  const odeme = [
    {'yontem': 'Nakit', 'tutar': 40.0},
    {'yontem': 'Kredi Kartı', 'tutar': 30.0},
    {'yontem': 'Cari', 'tutar': 30.0},
  ];

  /// "Masa 1"e 100 TL'lik (2 × 50) bir açık sipariş kurar.
  Future<({int masaId, int cariId})> hazirla() async {
    final urunId = await TestVeritabani.ornekUrunEkle(db, satisFiyati: 50, stok: 10);
    final cariId = await TestVeritabani.ornekCariEkle(db);
    final masaId = await masaDepo.masaEkle(const MasaModel(ad: 'Masa 1'));
    final siparis = await masaDepo.siparisAcVeyaGetir(masaId);
    await masaDepo.kalemEkle(siparis.id!,
        urunId: urunId, urunAdi: 'Test Ürün', birimFiyat: 50, kdvOran: 20, miktar: 2);
    return (masaId: masaId, cariId: cariId);
  }

  Future<MasaOdemeSonuc> ode(int masaId, int cariId) async {
    final siparis = (await masaDepo.acikSiparisGetir(masaId))!;
    return MasaOdemeServisi().odemeYap(
      siparis: siparis,
      masaAdi: 'Masa 1',
      odemeKalemleri: [for (final o in odeme) Map<String, dynamic>.from(o)],
      paraUstu: 0,
      cariId: cariId,
      cariAdi: 'Test Cari',
    );
  }

  test('40 Nakit + 30 Kart + 30 Cari: satış, kasa, cari, masa ve sipariş doğru', () async {
    final h = await hazirla();
    expect(40.0 + 30.0 + 30.0, 100.0);

    final sonuc = await ode(h.masaId, h.cariId);

    // Satış
    final satis = (await db.query('satislar', where: 'id = ?', whereArgs: [sonuc.satisId])).first;
    expect((satis['genel_toplam'] as num).toDouble(), 100.0);
    expect(satis['odeme_yontemi'], 'Karma');
    expect(satis['sube_id'], isNot(isNull), reason: '§3.5 — satışta şube dolu');

    // Kasa: Nakit 40 + Kart 30 → 2 satır, referans_turu='satis'
    final kasa = await db.query('kasa_hareketleri',
        where: 'referans_id = ? AND referans_turu = ?',
        whereArgs: [sonuc.satisId, 'satis'], orderBy: 'id');
    expect(kasa, hasLength(2));
    final kasaYontem = {
      for (final k in kasa) k['odeme_yontemi'] as String: (k['tutar'] as num).toDouble()
    };
    expect(kasaYontem, {'Nakit': 40.0, 'Kredi Kartı': 30.0});
    expect(kasa.every((k) => (k['global_id'] as String?)?.isNotEmpty == true), isTrue,
        reason: '§3.6 — global_id dolu');

    // Cari: tek GERÇEK borç satırı 30/0, fis_tipi 'Satış'
    final cariSatirlari = await db.query('cari_hareket',
        where: 'fis_id = ? AND cari_id = ? AND is_deleted = 0',
        whereArgs: [sonuc.satisId, h.cariId]);
    final gercekBorc = cariSatirlari
        .where((r) => (r['borc'] as num).toDouble() != (r['alacak'] as num).toDouble())
        .toList();
    expect(gercekBorc, hasLength(1));
    expect((gercekBorc.single['borc'] as num).toDouble(), 30.0);
    expect((gercekBorc.single['alacak'] as num).toDouble(), 0.0);
    expect(gercekBorc.single['fis_tipi'], 'Satış');
    final cari = (await db.query('cari', where: 'id = ?', whereArgs: [h.cariId])).first;
    expect((cari['bakiye'] as num).toDouble(), 30.0);

    // Masa / sipariş
    final masa = (await db.query('masalar', where: 'id = ?', whereArgs: [h.masaId])).first;
    expect(masa['durum'], 'bos');
    final sip = (await db.query('masa_siparisleri',
            where: 'masa_id = ?', whereArgs: [h.masaId]))
        .first;
    expect(sip['durum'], 'odendi');
    expect(sip['satis_id'], sonuc.satisId);
  });

  test('mutabakat: kasa (Nakit+Kart) + cari net borç == satış toplamı', () async {
    final h = await hazirla();
    final sonuc = await ode(h.masaId, h.cariId);

    final kasaToplam = (await db.rawQuery(
            "SELECT COALESCE(SUM(tutar),0) AS t FROM kasa_hareketleri "
            "WHERE referans_id = ? AND referans_turu = 'satis'",
            [sonuc.satisId]))
        .first['t'] as num;
    final cariNet = (await db.rawQuery(
            'SELECT COALESCE(SUM(borc),0) - COALESCE(SUM(alacak),0) AS n '
            'FROM cari_hareket WHERE fis_id = ? AND cari_id = ? AND is_deleted = 0',
            [sonuc.satisId, h.cariId]))
        .first['n'] as num;
    final satis = (await db.query('satislar', where: 'id = ?', whereArgs: [sonuc.satisId])).first;

    expect(ParaUtils.yuvarla(kasaToplam.toDouble() + cariNet.toDouble()),
        (satis['genel_toplam'] as num).toDouble());
  });

  test('aynı sipariş ikinci kez ödenmek istenirse hata; mükerrer satış/kasa/cari oluşmaz', () async {
    final h = await hazirla();
    final eskiSiparis = (await masaDepo.acikSiparisGetir(h.masaId))!;
    await ode(h.masaId, h.cariId);

    // Ekranda kalmış (bayat) sipariş nesnesiyle ikinci ödeme denemesi.
    await expectLater(
      MasaOdemeServisi().odemeYap(
        siparis: eskiSiparis,
        masaAdi: 'Masa 1',
        odemeKalemleri: [for (final o in odeme) Map<String, dynamic>.from(o)],
        paraUstu: 0,
        cariId: h.cariId,
      ),
      throwsException,
    );

    expect(await db.query('satislar'), hasLength(1));
    expect(await db.query('kasa_hareketleri', where: "referans_turu = 'satis'"), hasLength(2));
    final cari = (await db.query('cari', where: 'id = ?', whereArgs: [h.cariId])).first;
    expect((cari['bakiye'] as num).toDouble(), 30.0);
  });
}
