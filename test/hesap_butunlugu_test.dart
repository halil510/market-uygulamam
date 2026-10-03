// test/hesap_butunlugu_test.dart
//
// Uygulamanın para/tarih hesaplarının TUTARLILIĞI (2026-10-03):
//  1. Tarih ayrıştırma — SQLite dilimsiz UTC damgası yerel saat sanılmamalı.
//  2. Rapor sorguları farklı tarih biçimlerinde (T'li / boşluklu / kesirli)
//     AYNI satırları görmeli (ciro ↔ maliyet ↔ detay tutarlı).
//  3. Bir günlük tam senaryo: nakit/kart/cari/iptal/silinmiş/sync-kopyası/iade
//     → Gün Sonu, satış listesi, cari bakiye birbiriyle uyumlu.
//  4. Gerçek Veritabani().supaKayitlariGuncelle akışında tarih çakışmaları.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/depolar/cari_deposu.dart';
import 'package:market_plus/depolar/satis_deposu.dart';
import 'package:market_plus/servisler/bulut/sync_lww_koruma.dart';
import 'package:market_plus/servisler/kolon_haritalama.dart';
import 'package:market_plus/veri/database/sync_cakisma_tespit.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import 'helper/test_initializer.dart';

/// SQLite CURRENT_TIMESTAMP biçimi: UTC, dilimsiz, boşluklu.
String _sqliteUtc(DateTime t) =>
    t.toUtc().toIso8601String().replaceFirst('T', ' ').substring(0, 19);

String _gun(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

void main() {
  group('KolonHaritalama.utcZaman', () {
    test('SQLite boşluklu damga UTC sayılır (yerel sanılıp kaydırılmaz)', () {
      expect(KolonHaritalama.utcZaman('2026-10-03 10:00:00'),
          DateTime.utc(2026, 10, 3, 10));
    });
    test('Z / +00:00 / +03:00 aynı anı gösterir', () {
      final a = KolonHaritalama.utcZaman('2026-10-03T10:00:00Z')!;
      final b = KolonHaritalama.utcZaman('2026-10-03T10:00:00+00:00')!;
      final c = KolonHaritalama.utcZaman('2026-10-03T13:00:00+03:00')!;
      expect(a, b);
      expect(a, c);
    });
    test("Dart'ın dilimsiz yerel damgası yerel saat olarak çevrilir", () {
      final yerel = DateTime(2026, 10, 3, 13, 0, 0);
      expect(KolonHaritalama.utcZaman(yerel.toIso8601String()), yerel.toUtc());
    });
    test('null / boş / bozuk → null', () {
      expect(KolonHaritalama.utcZaman(null), isNull);
      expect(KolonHaritalama.utcZaman(''), isNull);
      expect(KolonHaritalama.utcZaman('bozuk'), isNull);
    });
  });

  group('SyncLwwKoruma — SQLite biçimli yerel damga', () {
    test('yerel (UTC 10:00) bulut (09:30Z)ten YENİ → gönderilir, atlanmaz', () {
      final k = {'global_id': 'a', 'last_updated': '2026-10-03 10:00:00'};
      final atlanan = SyncLwwKoruma.bulutuKesinDahaYeniOlanlar(
        kayitlar: [k],
        uniqueAlan: 'global_id',
        bulutZamanlari: {'a': DateTime.utc(2026, 10, 3, 9, 30)},
      );
      expect(atlanan, isEmpty,
          reason: 'ham tryParse yerel sanıp 3 saat geriye kaydırıyor, yeni '
              'yerel değişiklik buluta HİÇ gitmiyordu');
    });
    test('yerel (UTC 10:00) bulut (10:30Z)ten ESKİ → atlanır', () {
      final k = {'global_id': 'a', 'last_updated': '2026-10-03 10:00:00'};
      final atlanan = SyncLwwKoruma.bulutuKesinDahaYeniOlanlar(
        kayitlar: [k],
        uniqueAlan: 'global_id',
        bulutZamanlari: {'a': DateTime.utc(2026, 10, 3, 10, 30)},
      );
      expect(atlanan, hasLength(1));
    });
    test('zamanHaritasi bulutun boşluklu/Z/+00 biçimlerini aynı okur', () {
      final h = SyncLwwKoruma.zamanHaritasi([
        {'global_id': 'a', 'last_updated': '2026-10-03T10:00:00+00:00'},
        {'global_id': 'b', 'last_updated': '2026-10-03 10:00:00'},
        {'global_id': 'c', 'last_updated': '2026-10-03T10:00:00.000Z'},
      ], 'global_id');
      expect(h['a'], h['b']);
      expect(h['b'], h['c']);
    });
  });

  group('SyncCakismaTespit — tarih biçimi farkı sahte çakışma üretmez', () {
    test('boşluklu ↔ T\'li ↔ Z ↔ +00:00 ↔ kesirli aynı an eşit sayılır', () {
      for (final gelen in [
        '2026-10-03T10:00:00Z',
        '2026-10-03T10:00:00+00:00',
        '2026-10-03T10:00:00.000Z',
        '2026-10-03T10:00:00',
        '2026-10-03 10:00:00',
      ]) {
        expect(
            SyncCakismaTespit.farklariBul(
                {'tarih': '2026-10-03 10:00:00'}, {'tarih': gelen}),
            isEmpty,
            reason: gelen);
      }
    });
    test('1 saniye farklı tarih GERÇEK fark sayılır', () {
      expect(
          SyncCakismaTespit.farklariBul(
              {'tarih': '2026-10-03 10:00:00'}, {'tarih': '2026-10-03T10:00:01Z'}),
          contains('tarih'));
    });
    test('tutar: 100 ↔ 100.0 ↔ 100.0000000001 eşit; 100.01 farklı', () {
      expect(SyncCakismaTespit.farklariBul({'t': 100}, {'t': 100.0}), isEmpty);
      expect(SyncCakismaTespit.farklariBul({'t': 100}, {'t': 100.0000000001}), isEmpty);
      expect(SyncCakismaTespit.farklariBul({'t': 100}, {'t': 100.01}), contains('t'));
    });
  });

  group('Rapor sorguları — tarih biçimi tutarlılığı', () {
    late Database db;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = await TestVeritabani.olustur();
      Veritabani.testVeritabani = db;
    });
    tearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      Veritabani.testVeritabani = null;
      await db.close();
    });

    Future<void> satis(String fis, String tarih, {double tutar = 100}) async {
      final urunId = await TestVeritabani.ornekUrunEkle(db, barkod: 'UX-$fis');
      final id = await db.insert('satislar', {
        'fis_no': fis, 'tarih': tarih, 'toplam_tutar': tutar,
        'genel_toplam': tutar, 'odenen_tutar': tutar,
        'odeme_yontemi': 'Nakit', 'fis_tipi': 'Satış',
        'iptal': 0, 'is_deleted': 0,
      });
      await db.insert('satis_kalem', {
        'satis_id': id, 'urun_id': urunId, 'urun_adi': 'x', 'miktar': 1, 'birim_fiyat': tutar,
        'toplam_tutar': tutar, 'alis_fiyat_kdv': 10,
      });
    }

    test('Gün içindeki 4 farklı biçim + gün dışı 2 satır: tüm raporlar AYNI 4 satırı görür', () async {
      final bugun = DateTime(2026, 10, 3);
      final g = _gun(bugun), dun = _gun(bugun.subtract(const Duration(days: 1))),
          yarin = _gun(bugun.add(const Duration(days: 1)));
      await satis('D1', '${g}T10:00:00.000');         // Dart yerel
      await satis('D2', '$g 11:00:00');               // SQLite biçimi
      await satis('D3', '${g}T23:59:59.500');         // gün sonu, kesirli
      await satis('D4', '${g}T12:00:00+00:00');       // buluttan gelen
      await satis('DIS1', '$dun 23:59:59');           // dün
      await satis('DIS2', '${yarin}T00:00:00');       // yarın

      final bas = DateTime(2026, 10, 3), bit = DateTime(2026, 10, 3, 23, 59, 59);
      final depo = SatisDeposu();
      final liste = await depo.tariheGoreGetir(bas, bit);
      final detay = await depo.gunSonuDetayGetir(bas, bit);
      final maliyet = await depo.maliyetToplami(bas, bit);

      expect(liste.map((s) => s.fisNo).toSet(), {'D1', 'D2', 'D3', 'D4'});
      expect(detay.length, 4, reason: 'detay listesi satış listesiyle aynı satırları görmeli');
      expect(maliyet, 40, reason: '4 satır × 10 maliyet — ciro ile aynı kümeyi saymalı');
    });

    test('iade: boşluklu tarihli iade de gün aralığına girer, iptal edilen girmez', () async {
      final g = _gun(DateTime(2026, 10, 3));
      final urunId = await TestVeritabani.ornekUrunEkle(db);
      await db.update('urunler', {'alis_fiyat_kdv_dahil': 50.0},
          where: 'id = ?', whereArgs: [urunId]);
      Future<void> iade(String tarih, double tutar, String durum) async {
        final id = await db.insert(
            'iade', {'tarih': tarih, 'toplam_tutar': tutar, 'durum': durum});
        await db.insert('iade_kalem', {
          'iade_id': id, 'urun_id': urunId, 'urun_adi': 'x',
          'miktar': 1, 'birim_fiyat': tutar, 'toplam': tutar,
        });
      }
      await iade('${g}T09:00:00', 100, 'tamamlandi');
      await iade('$g 10:00:00', 200, 'tamamlandi');
      await iade('$g 11:00:00', 400, 'iptal');
      final r = await SatisDeposu().iadeTutarVeMaliyet(
          DateTime(2026, 10, 3), DateTime(2026, 10, 3, 23, 59, 59));
      expect(r.tutar, 300);
      expect(r.maliyet, 100);
    });
  });

  group('Bir günlük tam senaryo — Gün Sonu ↔ liste ↔ cari', () {
    late Database db;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = await TestVeritabani.olustur();
      Veritabani.testVeritabani = db;
    });
    tearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      Veritabani.testVeritabani = null;
      await db.close();
    });

    test('ciro = nakit + kart + cari; iptal/silinmiş/sync-kopyası sayılmaz', () async {
      final simdi = DateTime.now().toIso8601String();
      Future<int> satis(String fis, double tutar, String yontem,
          {double? odenen, int iptal = 0, int silindi = 0, int kopya = 0}) async {
        final urunId = await TestVeritabani.ornekUrunEkle(db, barkod: 'UX-$fis');
        final id = await db.insert('satislar', {
          'fis_no': fis, 'tarih': simdi, 'toplam_tutar': tutar,
          'genel_toplam': tutar, 'odenen_tutar': odenen ?? tutar,
          'odeme_yontemi': yontem, 'fis_tipi': 'Satış',
          'iptal': iptal, 'is_deleted': silindi, 'sync_cakisma_kopyasi': kopya,
        });
        await db.insert('satis_kalem', {
          'satis_id': id, 'urun_id': urunId, 'urun_adi': 'x', 'miktar': 1, 'birim_fiyat': tutar,
          'toplam_tutar': tutar, 'alis_fiyat_kdv': tutar * 0.6,
        });
        return id;
      }

      await satis('N1', 100, 'Nakit', odenen: 150); // para üstü 50
      await satis('K1', 50, 'Kredi Kartı');
      await satis('C1', 200, 'Cari', odenen: 0);
      await satis('IPT', 70, 'Nakit', iptal: 1);
      await satis('SIL', 33, 'Nakit', silindi: 1);
      await satis('KOP', 999, 'Nakit', kopya: 1);

      final depo = SatisDeposu();
      final i = await depo.gunlukIstatistik();
      expect(i['satis_sayisi'], 3);
      expect(i['ciro'], 350);
      expect(i['nakit'], 100, reason: 'para üstü (50) nakite sayılmamalı');
      expect(i['kart'], 50);
      expect(i['cari'], 200);
      expect(i['nakit']! + i['kart']! + i['cari']!, i['ciro']);

      final bas = DateTime.now().subtract(const Duration(hours: 1));
      final bit = DateTime.now().add(const Duration(hours: 1));
      final liste = await depo.tariheGoreGetir(bas, bit);
      expect(liste.fold<double>(0, (t, s) => t + s.genelToplam), 350,
          reason: 'Satış Listesi toplamı Gün Sonu cirosuyla aynı olmalı');
      expect(await depo.iptalSayisiGetir(bas, bit), 1);

      // Maliyet: 350 × 0.6 = 210; günlük ve aralıklı hesap aynı.
      expect(await depo.maliyetToplami(bas, bit), closeTo(210, 1e-9));
      expect(await depo.gunlukMaliyet(), closeTo(210, 1e-9));
    });

    test('cari bakiye = Σ(borç − alacak); iptal/silinen hareket bakiyeyi geri alır', () async {
      final cariId = await TestVeritabani.ornekCariEkle(db);
      Future<void> h(String gid, {double borc = 0, double alacak = 0}) =>
          db.insert('cari_hareket', {
            'global_id': gid, 'cari_id': cariId,
            'tarih': DateTime.now().toIso8601String(),
            'fis_tipi': borc > 0 ? 'Satış' : 'Tahsilat',
            'aciklama': 't', 'borc': borc, 'alacak': alacak, 'is_deleted': 0,
          }).then((_) {});

      Future<double> bakiye() async => ((await db.query('cari',
              columns: ['bakiye'], where: 'id = ?', whereArgs: [cariId]))
          .first['bakiye'] as num).toDouble();

      await h('s1', borc: 200);
      await h('s2', borc: 150.5);
      await h('t1', alacak: 80.25);
      expect(await bakiye(), closeTo(270.25, 1e-9));

      await db.update('cari_hareket', {'is_deleted': 1},
          where: 'global_id = ?', whereArgs: ['s2']);
      await CariDeposu().bakiyeYenidenHesapla(cariId);
      expect(await bakiye(), closeTo(119.75, 1e-9));
      expect(await CariDeposu().bakiyeUyumsuzlukSayisi(), 0);
    });
  });

  group('supaKayitlariGuncelle — tarih/last_updated çakışmaları (gerçek akış)', () {
    late Database db;
    Future<void> kur({Map<String, Object> prefs = const {}}) async {
      SharedPreferences.setMockInitialValues(prefs);
      db = await TestVeritabani.olustur();
      Veritabani.testVeritabani = db;
    }

    tearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      Veritabani.testVeritabani = null;
      await db.close();
    });

    Future<void> urun(String gid, String ad, String lastUpdated) async {
      final id = await TestVeritabani.ornekUrunEkle(db, urunAdi: ad, barkod: 'B-$gid');
      await db.update('urunler', {'global_id': gid, 'last_updated': lastUpdated},
          where: 'id = ?', whereArgs: [id]);
    }

    Future<String> ad(String gid) async => (await db
        .query('urunler', where: 'global_id = ?', whereArgs: [gid]))
        .first['urun_adi'] as String;

    Future<int> cakismaSayisi() async =>
        (await db.query('sync_cakismalar')).length;

    test('yerel (Dart yerel T) bulut (Z)ten yeni → yerel korunur', () async {
      await kur();
      final simdi = DateTime.now();
      await urun('u1', 'Yerel', simdi.toIso8601String());
      await Veritabani().supaKayitlariGuncelle('urunler', [
        {'global_id': 'u1', 'urun_adi': 'Bulut',
         'last_updated': simdi.subtract(const Duration(hours: 1)).toUtc().toIso8601String()},
      ]);
      expect(await ad('u1'), 'Yerel');
    });

    test('yerel (SQLite UTC boşluklu) bulut (Z)ten yeni → yerel korunur', () async {
      await kur();
      final simdi = DateTime.now();
      await urun('u1', 'Yerel', _sqliteUtc(simdi));
      await Veritabani().supaKayitlariGuncelle('urunler', [
        {'global_id': 'u1', 'urun_adi': 'Bulut',
         'last_updated': simdi.subtract(const Duration(minutes: 30)).toUtc().toIso8601String()},
      ]);
      expect(await ad('u1'), 'Yerel');
    });

    test('bulut daha yeni → uygulanır (kuyrukta bekleyen yoksa çakışma da yok)', () async {
      await kur();
      final simdi = DateTime.now();
      await urun('u1', 'Yerel', _sqliteUtc(simdi.subtract(const Duration(hours: 2))));
      await Veritabani().supaKayitlariGuncelle('urunler', [
        {'global_id': 'u1', 'urun_adi': 'Bulut',
         'last_updated': simdi.toUtc().toIso8601String()},
      ]);
      expect(await ad('u1'), 'Bulut');
    });

    test('3 saat dilim kayması: SQLite UTC damgalı gönderilmiş kayıt SAHTE çakışma üretmez', () async {
      // Yerel kayıt 1 saat önce yazılmış (UTC boşluklu), filigran 30 dk önce:
      // yerel değişiklik zaten gönderilmiş → çakışma YOK.
      final simdi = DateTime.now();
      await kur(prefs: {
        'mp_sync_otogonder_urunler':
            simdi.subtract(const Duration(minutes: 30)).toUtc().toIso8601String(),
      });
      await urun('u1', 'Yerel', _sqliteUtc(simdi.subtract(const Duration(hours: 1))));
      await Veritabani().supaKayitlariGuncelle('urunler', [
        {'global_id': 'u1', 'urun_adi': 'Bulut',
         'last_updated': simdi.toUtc().toIso8601String()},
      ]);
      expect(await ad('u1'), 'Bulut');
      expect(await cakismaSayisi(), 0);
    });

    test('GERÇEK çakışma gizlenmez: SQLite UTC damgalı yerel değişiklik filigrandan SONRA', () async {
      // Filigran 1 saat önce, yerel değişiklik şimdi (UTC boşluklu). Ham
      // tryParse yerel sanıp 3 saat geri kaydırıyor → "zaten gönderilmişti"
      // sanılıp çakışma SESSİZCE yutuluyordu.
      final simdi = DateTime.now();
      await kur(prefs: {
        'mp_sync_otogonder_urunler':
            simdi.subtract(const Duration(hours: 1)).toUtc().toIso8601String(),
      });
      await urun('u1', 'Yerel', _sqliteUtc(simdi));
      await Veritabani().supaKayitlariGuncelle('urunler', [
        {'global_id': 'u1', 'urun_adi': 'Bulut',
         'last_updated': simdi.add(const Duration(minutes: 1)).toUtc().toIso8601String()},
      ]);
      expect(await cakismaSayisi(), 1,
          reason: 'gönderilmemiş yerel değişiklik ezilirken çakışma kaydı düşmeli');
    });

    test('kuyrukta bekleyen yerel değişiklik + daha yeni bulut → çakışma kaydı düşer', () async {
      await kur();
      final simdi = DateTime.now();
      await urun('u1', 'Yerel', _sqliteUtc(simdi.subtract(const Duration(minutes: 5))));
      await db.insert('sync_queue', {
        'tablo_adi': 'urunler', 'kayit_global_id': 'u1',
        'islem_tipi': 'UPDATE', 'veri_json': '{}',
      });
      await Veritabani().supaKayitlariGuncelle('urunler', [
        {'global_id': 'u1', 'urun_adi': 'Bulut',
         'last_updated': simdi.toUtc().toIso8601String()},
      ]);
      expect(await cakismaSayisi(), 1);
      final c = (await db.query('sync_cakismalar')).first;
      expect(c['tablo'], 'urunler');
      expect(c['cozuldu'], 0);
    });

    test('işlem verisi (satislar): gerçek çakışmada yerel tutar KORUNUR, çakışma kaydı düşer', () async {
      await kur();
      final simdi = DateTime.now();
      await db.insert('satislar', {
        'global_id': 's-1', 'fis_no': 'F1', 'tarih': simdi.toIso8601String(),
        'toplam_tutar': 100, 'genel_toplam': 100, 'odeme_yontemi': 'Nakit',
        'fis_tipi': 'Satış', 'iptal': 0, 'is_deleted': 0,
        'last_updated': _sqliteUtc(simdi.subtract(const Duration(minutes: 5))),
      });
      await db.insert('sync_queue', {
        'tablo_adi': 'satislar', 'kayit_global_id': 's-1',
        'islem_tipi': 'UPDATE', 'veri_json': '{}',
      });
      await Veritabani().supaKayitlariGuncelle('satislar', [
        {'global_id': 's-1', 'genel_toplam': 90.0,
         'last_updated': simdi.toUtc().toIso8601String()},
      ]);
      final satir = (await db.query('satislar', where: 'global_id = ?', whereArgs: ['s-1'])).first;
      expect((satir['genel_toplam'] as num).toDouble(), 100,
          reason: 'işlem verisi otomatik LWW ile ezilmemeli');
      expect(await cakismaSayisi(), 1);
    });

    test('aynı kayıt için tekrarlanan çakışma tek satırda güncellenir (birikmez)', () async {
      await kur();
      final simdi = DateTime.now();
      await urun('u1', 'Yerel', _sqliteUtc(simdi.subtract(const Duration(minutes: 5))));
      await db.insert('sync_queue', {
        'tablo_adi': 'urunler', 'kayit_global_id': 'u1',
        'islem_tipi': 'UPDATE', 'veri_json': '{}',
      });
      for (var n = 1; n <= 3; n++) {
        await Veritabani().supaKayitlariGuncelle('urunler', [
          {'global_id': 'u1', 'urun_adi': 'Bulut-$n',
           'last_updated': simdi.add(Duration(minutes: n)).toUtc().toIso8601String()},
        ]);
        await db.update('urunler', {'urun_adi': 'Yerel', 'last_updated': _sqliteUtc(simdi.subtract(const Duration(minutes: 5)))},
            where: 'global_id = ?', whereArgs: ['u1']);
      }
      expect(await cakismaSayisi(), 1);
    });
  });
}
