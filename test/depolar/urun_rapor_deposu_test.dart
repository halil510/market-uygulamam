// Ürün Raporu (satış/alım) SQL toplulaştırması: filtreler, gruplama,
// iptal/sync-kopyası dışlama, alım durum filtresi.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/depolar/satis_deposu.dart';
import 'package:market_plus/depolar/urun_rapor_deposu.dart';
import 'package:market_plus/modeller/satis_kalem_model.dart';
import 'package:market_plus/modeller/satis_model.dart';
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

  Future<int> satis(String fisNo, double tutar, int urunId, {double adet = 1}) =>
      SatisDeposu().satisEkle(
          SatisModel(fisNo: fisNo, tarih: DateTime.now(), toplamTutar: tutar,
              genelToplam: tutar, odenenTutar: tutar, odemeYontemi: 'Nakit',
              fisTipi: 'Satış'),
          [SatisKalemModel(satisId: 0, urunId: urunId, urunAdi: 'Test',
              miktar: adet, birimFiyat: tutar / adet, toplamTutar: tutar)]);

  UrunRaporFiltre bugun({String? marka, String? anaGrup, UrunRaporGruplama g = UrunRaporGruplama.urun}) {
    final n = DateTime.now();
    final d = DateTime(n.year, n.month, n.day);
    return UrunRaporFiltre(bas: d, bit: d, marka: marka, anaGrup: anaGrup, gruplama: g);
  }

  test('satış raporu: iptal ve sync kopyası dışlanır, marka/grup filtresi çalışır', () async {
    final a = await TestVeritabani.ornekUrunEkle(db, stok: 50, barkod: 'B-A');
    final b = await TestVeritabani.ornekUrunEkle(db, stok: 50, barkod: 'B-B');
    await db.update('urunler', {'marka': 'MarkaX', 'ana_grup': 'Gıda'}, where: 'id = ?', whereArgs: [a]);
    await db.update('urunler', {'marka': 'MarkaY', 'ana_grup': 'Temizlik'}, where: 'id = ?', whereArgs: [b]);

    await satis('R-1', 100, a, adet: 2);
    await satis('R-2', 50, b);
    final iptal = await satis('R-3', 999, a);
    await db.update('satislar', {'iptal': 1}, where: 'id = ?', whereArgs: [iptal]);
    final kopya = await satis('R-4', 888, a);
    await db.update('satislar', {'sync_cakisma_kopyasi': 1}, where: 'id = ?', whereArgs: [kopya]);

    final depo = UrunRaporDeposu();
    final hepsi = await depo.satisRaporu(bugun());
    expect(hepsi.toplamTutar, 150);
    expect(hepsi.satirlar.length, 2);
    expect(hepsi.fisSayisi, 2);

    final x = await depo.satisRaporu(bugun(marka: 'MarkaX'));
    expect(x.toplamTutar, 100);
    expect(x.toplamMiktar, 2);

    final grup = await depo.satisRaporu(bugun(g: UrunRaporGruplama.anaGrup));
    expect(grup.satirlar.map((s) => s.ad).toSet(), {'Gıda', 'Temizlik'});

    final cari = await depo.satisRaporu(bugun(g: UrunRaporGruplama.cari));
    expect(cari.satirlar.single.ad, 'Perakende (Carisiz)');

    final yarin = DateTime.now().add(const Duration(days: 1));
    final bos = await depo.satisRaporu(UrunRaporFiltre(bas: yarin, bit: yarin));
    expect(bos.satirlar, isEmpty);
  });

  test('maliyet: tarihsel 0 ise ürünün güncel KDV dahil alışına düşer; doluysa o kullanılır', () async {
    final a = await TestVeritabani.ornekUrunEkle(db, stok: 50, barkod: 'B-M');
    await db.update('urunler', {'alis_fiyat_kdv_dahil': 12.0}, where: 'id = ?', whereArgs: [a]);
    final s1 = await satis('M-1', 100, a, adet: 2);
    await db.update('satis_kalem', {'alis_fiyat_kdv': 0}, where: 'satis_id = ?', whereArgs: [s1]);
    final s2 = await satis('M-2', 50, a, adet: 1);
    await db.update('satis_kalem', {'alis_fiyat_kdv': 20.0}, where: 'satis_id = ?', whereArgs: [s2]);

    final r = await UrunRaporDeposu().satisRaporu(bugun());
    expect(r.toplamMaliyet, 2 * 12.0 + 1 * 20.0);
  });

  test('alım tutarı teslim miktarından hesaplanır (kısmi teslim)', () async {
    final a = await TestVeritabani.ornekUrunEkle(db, stok: 0, barkod: 'B-KT');
    final id = await db.insert('tedarikci_siparisler', {
      'cari_id': await db.insert('cari', {'unvan': 'T', 'cari_tipi': 'Tedarikçi', 'bakiye': 0}),
      'siparis_no': 'KT-1', 'siparis_tarihi': DateTime.now().toIso8601String(),
      'toplam_tutar': 100, 'durum': 'teslim_alindi',
    });
    await db.insert('tedarikci_siparis_kalem', {
      'siparis_id': id, 'urun_id': a, 'siparis_mik': 20, 'teslim_mik': 4,
      'birim_fiyat': 5, 'toplam_tutar': 100,
    });
    final n = DateTime.now();
    final d = DateTime(n.year, n.month, n.day);
    final r = await UrunRaporDeposu().alimRaporu(UrunRaporFiltre(bas: d, bit: d));
    expect(r.toplamMiktar, 4);
    expect(r.toplamTutar, 20);
  });

  test('alım raporu: yalnız teslim alınanlar, cari ve marka filtresi', () async {
    final a = await TestVeritabani.ornekUrunEkle(db, stok: 0, barkod: 'B-AL');
    await db.update('urunler', {'marka': 'MarkaX'}, where: 'id = ?', whereArgs: [a]);
    final cariId = await db.insert('cari', {
      'unvan': 'Tedarik A.Ş.', 'cari_tipi': 'Tedarikçi', 'bakiye': 0,
    });
    final now = DateTime.now().toIso8601String();
    Future<void> alim(String no, String durum, double mik, double fiyat) async {
      final id = await db.insert('tedarikci_siparisler', {
        'cari_id': cariId, 'siparis_no': no, 'siparis_tarihi': now,
        'toplam_tutar': mik * fiyat, 'durum': durum,
      });
      await db.insert('tedarikci_siparis_kalem', {
        'siparis_id': id, 'urun_id': a, 'siparis_mik': mik, 'teslim_mik': mik,
        'birim_fiyat': fiyat, 'toplam_tutar': mik * fiyat,
      });
    }
    await alim('AL-1', 'teslim_alindi', 10, 5);
    await alim('AL-2', 'iptal', 100, 5);
    await alim('AL-3', 'beklemede', 100, 5);

    final depo = UrunRaporDeposu();
    final n = DateTime.now();
    final d = DateTime(n.year, n.month, n.day);
    final r = await depo.alimRaporu(UrunRaporFiltre(bas: d, bit: d, cariId: cariId, marka: 'MarkaX'));
    expect(r.toplamTutar, 50);
    expect(r.toplamMiktar, 10);
    expect(r.fisSayisi, 1);

    final c = await depo.alimRaporu(UrunRaporFiltre(bas: d, bit: d, gruplama: UrunRaporGruplama.cari));
    expect(c.satirlar.single.ad, 'Tedarik A.Ş.');
  });

  test('arama Türkçe karakter/büyük-küçük harf duyarsız (rapor + stok listesi)', () async {
    final a = await TestVeritabani.ornekUrunEkle(db, stok: 5, barkod: 'B-TR');
    await db.update('urunler', {'urun_adi': 'BİSKREM ÇİKOLATA'}, where: 'id = ?', whereArgs: [a]);
    await satis('TR-1', 30, a);
    final depo = UrunRaporDeposu();
    final n = DateTime.now();
    final d = DateTime(n.year, n.month, n.day);
    for (final q in ['biskrem', 'cikolata', 'BİSKREM']) {
      final r = await depo.satisRaporu(UrunRaporFiltre(bas: d, bit: d, arama: q));
      expect(r.satirlar.length, 1, reason: q);
      expect((await depo.stokListesi(arama: q)).length, 1, reason: q);
    }
  });
}
