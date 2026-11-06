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
// 2026-11-06 (test güvenilirliği, Kademe 1): bu test ÖNCEDEN sil()'in
// kopyası olan bir simülasyon fonksiyonunu çağırıyordu — üretim kodu
// bozulsa bile yeşil kalırdı. Artık GERÇEK SatisDeposu().sil() çağrılıyor
// (Veritabani.testVeritabani seam'i ile bellek-içi gerçek şema).
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:market_plus/depolar/satis_deposu.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

Future<void> _satisSil(int satisId) => SatisDeposu().sil(satisId);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (_) async => null);
    SharedPreferences.setMockInitialValues({});
    db = await TestVeritabani.olustur();
    Veritabani.testVeritabani = db;
  });
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    Veritabani.testVeritabani = null;
    await db.close();
  });

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

      await _satisSil(satisId);

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

    // CLAUDE.md §3.3 / §5.1: ikinci silme çağrısı hiçbir ters kayıt üretmez.
    test('aynı satış ikinci kez silinirse ikinci "Satış İptali" yazılmaz (idempotent)', () async {
      final cariId = await TestVeritabani.ornekCariEkle(db);
      final satisId = await db.insert('satislar', {
        'fis_no': 'CRI2026000000005',
        'tarih': DateTime.now().toIso8601String(),
        'cari_id': cariId,
        'genel_toplam': 50.0,
        'odenen_tutar': 50.0,
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
        'aciklama': 'Veresiye: CRI2026000000005',
        'borc': 50.0,
        'alacak': 0.0,
        'odeme_turu': 'Cari',
        'is_deleted': 0,
      });

      await _satisSil(satisId);
      await _satisSil(satisId);

      final iptaller = await db.query('cari_hareket',
          where: 'fis_id = ? AND fis_tipi = ?', whereArgs: [satisId, 'Satış İptali']);
      expect(iptaller, hasLength(1));
      final cari = (await db.query('cari', where: 'id = ?', whereArgs: [cariId])).first;
      expect((cari['bakiye'] as num).toDouble(), equals(0.0));
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

      await _satisSil(satisId);

      final cari = (await db.query('cari', where: 'id = ?', whereArgs: [cariId])).first;
      expect((cari['bakiye'] as num).toDouble(), equals(0.0));

      final kasaTers = await db.query('kasa_hareketleri',
          where: 'referans_id = ? AND referans_turu = ?', whereArgs: [satisId, 'satis_iptal']);
      expect(kasaTers, hasLength(1));
      expect((kasaTers.first['tutar'] as num).toDouble(), equals(60.0),
          reason: 'kasadan sadece GERÇEKTEN girmiş olan Nakit payı geri çıkmalı, Cari payı değil');
    });
  });

  // Regresyon (2026-11-06, §3.1/§4.2): sil() bakiyeyi Dart'ta YUVARLAMADAN
  // yazıyordu; artık tek kaynak CariDeposu.bakiyeTazeleTxn kuruşa yuvarlar.
  test('satış silinince cari bakiyesi kuruşa yuvarlanmış yazılır', () async {
    final cariId = await TestVeritabani.ornekCariEkle(db);
    for (final b in [0.1, 0.2]) {
      await db.insert('cari_hareket', {
        'global_id': const Uuid().v4(), 'cari_id': cariId,
        'tarih': DateTime.now().toIso8601String(), 'fis_tipi': 'Satış',
        'borc': b, 'alacak': 0.0, 'odeme_turu': 'Cari', 'is_deleted': 0,
      });
    }
    final satisId = await db.insert('satislar', {
      'fis_no': 'CRI2026000000009', 'tarih': DateTime.now().toIso8601String(),
      'cari_id': cariId, 'genel_toplam': 5.0, 'odenen_tutar': 5.0,
      'odeme_yontemi': 'Cari', 'fis_tipi': 'Satış', 'is_deleted': 0,
    });
    await db.insert('cari_hareket', {
      'global_id': const Uuid().v4(), 'cari_id': cariId,
      'tarih': DateTime.now().toIso8601String(), 'fis_tipi': 'Satış',
      'fis_id': satisId, 'borc': 5.0, 'alacak': 0.0, 'odeme_turu': 'Cari', 'is_deleted': 0,
    });

    await _satisSil(satisId);

    final cari = (await db.query('cari', where: 'id = ?', whereArgs: [cariId])).first;
    expect((cari['bakiye'] as num).toDouble(), 0.3, reason: '0.30000000000000004 değil');
  });
}
