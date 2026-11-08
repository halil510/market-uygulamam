// test/servisler/mutabakat_toplu_sorgu_test.dart
//
// Faz D (performans, 2026-11-08): satır başına sorgu atan (N+1) mutabakat/
// toplu bakım fonksiyonları tek sorguya indirildi. Bu testler sonucu
// (düzeltilen değerler + dönen adet) sabitler — davranış değişmedi.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/depolar/borc_deposu.dart';
import 'package:market_plus/depolar/toptan_fiyat_deposu.dart';
import 'package:market_plus/depolar/urun_deposu.dart';
import 'package:market_plus/servisler/puan_servisi.dart';
import 'package:market_plus/veri/database/veritabani.dart';
import '../helper/test_initializer.dart';

void main() {
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

  test('BorcDeposu.odemeMutabakatYap: yalnız sapan borçlar ödemelerin toplamına çekilir', () async {
    final now = DateTime.now().toIso8601String();
    Future<int> borc(String baslik, double tutar, double odenen) => db.insert('borclar', {
          'baslik': baslik, 'tur': 'Diğer', 'tutar': tutar, 'odenen_tutar': odenen,
          'kesim_tarihi': now, 'son_odeme_tarihi': now, 'is_deleted': 0,
        });
    final dogru = await borc('Doğru', 100, 30);
    final eksik = await borc('Eksik', 100, 0); // ödemeleri 100 → kapanmalı
    final fazla = await borc('Fazla', 200, 150); // ödemesi 50
    final odemesiz = await borc('Ödemesiz', 80, 20); // hiç ödeme yok → 0
    final silinmis = await db.insert('borclar', {
      'baslik': 'Silinmiş', 'tur': 'Diğer', 'tutar': 10, 'odenen_tutar': 99,
      'kesim_tarihi': now, 'son_odeme_tarihi': now, 'is_deleted': 1,
    });
    for (final (id, t) in [(dogru, 10.0), (dogru, 20.0), (eksik, 60.0), (eksik, 40.0), (fazla, 50.0)]) {
      await db.insert('borc_odemeler', {'borc_id': id, 'tutar': t, 'tarih': now});
    }

    expect(await BorcDeposu().odemeMutabakatYap(), 3);

    Future<Map<String, Object?>> oku(int id) async =>
        (await db.query('borclar', where: 'id = ?', whereArgs: [id])).single;
    expect((await oku(dogru))['odenen_tutar'], 30);
    expect((await oku(eksik))['odenen_tutar'], 100);
    expect((await oku(eksik))['odendi'], 1);
    expect((await oku(fazla))['odenen_tutar'], 50);
    expect((await oku(fazla))['odendi'], 0);
    expect((await oku(odemesiz))['odenen_tutar'], 0);
    expect((await oku(silinmis))['odenen_tutar'], 99, reason: 'silinmiş borca dokunulmaz');

    expect(await BorcDeposu().odemeMutabakatYap(), 0, reason: 'ikinci çağrı değiştirmez');
  });

  test('PuanServisi.puanMutabakatYap: her müşteri kendi hareketlerinden hesaplanır', () async {
    final a = await TestVeritabani.ornekCariEkle(db, unvan: 'A');
    final b = await TestVeritabani.ornekCariEkle(db, unvan: 'B');
    final c = await TestVeritabani.ornekCariEkle(db, unvan: 'C');
    final now = DateTime.now().toIso8601String();
    for (final (cari, tip, puan) in [
      (a, 'Kazanıldı', 100.0), (a, 'Harcandı', -30.0),
      (b, 'Kazanıldı', 50.0), (b, 'İptal', -50.0),
      (c, 'Kazanıldı', 10.0),
    ]) {
      await db.insert('puan_hareket',
          {'cari_id': cari, 'islem_tipi': tip, 'puan': puan, 'tarih': now});
    }
    for (final (cari, toplam, kullanilan) in [(a, 999.0, 0.0), (b, 50.0, 5.0), (c, 10.0, 0.0)]) {
      await db.insert('musteri_puan', {'cari_id': cari, 'toplam_puan': toplam, 'kullanilan': kullanilan});
    }

    expect(await PuanServisi().puanMutabakatYap(), 2);

    Future<Map<String, Object?>> oku(int cari) async =>
        (await db.query('musteri_puan', where: 'cari_id = ?', whereArgs: [cari])).single;
    expect((await oku(a))['toplam_puan'], 100);
    expect((await oku(a))['kullanilan'], 30);
    expect((await oku(b))['toplam_puan'], 0);
    expect((await oku(b))['kullanilan'], 0);
    expect((await oku(c))['toplam_puan'], 10);
    expect(await PuanServisi().puanMutabakatYap(), 0);
  });

  test('ToptanFiyatDeposu.urunlerinGrupFiyatlariGetir: tek tek sorguyla aynı sonuç', () async {
    final depo = ToptanFiyatDeposu();
    final g1 = await db.insert('fiyat_gruplari', {'ad': 'Bayi'});
    final g2 = await db.insert('fiyat_gruplari', {'ad': 'Toptan'});
    final urunler = <int>[];
    for (var i = 0; i < 4; i++) {
      urunler.add(await TestVeritabani.ornekUrunEkle(db, urunAdi: 'F$i', barkod: 'F$i'));
    }
    await db.insert('urun_fiyat_gruplari', {'urun_id': urunler[0], 'fiyat_grubu_id': g1, 'fiyat': 12.5});
    await db.insert('urun_fiyat_gruplari', {'urun_id': urunler[2], 'fiyat_grubu_id': g1, 'fiyat': 7});
    await db.insert('urun_fiyat_gruplari', {'urun_id': urunler[1], 'fiyat_grubu_id': g2, 'fiyat': 99});

    final toplu = await depo.urunlerinGrupFiyatlariGetir(urunler, g1);
    final tekTek = <int, double>{};
    for (final u in urunler) {
      final f = await depo.urunGrupFiyatiGetir(u, g1);
      if (f != null) tekTek[u] = f;
    }
    expect(toplu, tekTek);
    expect(toplu, {urunler[0]: 12.5, urunler[2]: 7.0});
    expect(await depo.urunlerinGrupFiyatlariGetir([], g1), isEmpty);
  });

  test('UrunDeposu.tumPasifleriAktifYap: silinmemiş tüm pasifler aktif olur, adet döner', () async {
    final ids = <int>[];
    for (var i = 0; i < 5; i++) {
      ids.add(await TestVeritabani.ornekUrunEkle(db, urunAdi: 'Ü$i', barkod: 'B$i'));
    }
    await db.update('urunler', {'aktif': 0}, where: 'id IN (?, ?, ?)', whereArgs: [ids[0], ids[1], ids[2]]);
    await db.update('urunler', {'aktif': 0, 'is_deleted': 1}, where: 'id = ?', whereArgs: [ids[3]]);

    expect(await UrunDeposu().tumPasifleriAktifYap(), 3);

    final rows = await db.query('urunler', columns: ['id', 'aktif'], orderBy: 'id');
    expect([for (final r in rows) r['aktif']], [1, 1, 1, 0, 1]);
  });
}
