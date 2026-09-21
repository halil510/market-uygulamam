// test/veri/gunluk_rapor_maliyet_test.dart
//
// Madde 24 (Raporlar) denetimi, 2026-09-20 — Gün Sonu raporu maliyet
// (COGS) sorgusu HER ZAMAN urunler.alis_fiyat'ın (GÜNCEL alış fiyatı)
// kullanıyordu — satış anındaki TARİHSEL maliyeti (satis_kalem.
// alis_fiyat'ta kalıcı olarak damgalanan) DEĞİL. Kâr/Zarar raporu
// (kar_zarar_provider.dart) bunu doğru yapıyordu — aynı tarih için iki
// rapor FARKLI "Net Kâr" gösterebiliyordu. gunluk_rapor_ekrani.dart'ın
// _yukle() metodu Veritabani() singleton'ına bağımlı olduğundan
// (projenin yerleşik test deseni), düzeltilmiş SQL BİREBİR aynı şekilde
// gerçek şema üzerinde doğrulanıyor.
//
// 🔴🔴 KRİTİK DÜZELTME (kullanıcı bulgusu, 2026-09-22): o "AYNI formül"
// KDV HARİÇ alış maliyetini (sk.alis_fiyat) KDV DAHİL ciro'dan (genel_
// toplam) çıkarıyordu — Net Kâr'ı maliyetin KDV payı kadar OLDUĞUNDAN
// FAZLA gösteriyordu. Artık ikisi de KDV DAHİL: satis_kalem.alis_fiyat_kdv
// (tarihsel), yoksa güncel urunler.alis_fiyat_kdv_dahil'e düşülür. Bu
// dosya bu YENİ formülü doğrular (SatisDeposu.maliyetToplami ile BİREBİR
// aynı SQL).
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import '../helper/test_initializer.dart';

/// SatisDeposu.maliyetToplami() / kar_zarar_provider.dart'taki formülle
/// BİREBİR AYNI.
Future<double> _maliyetHesapla(Database db, DateTime bas, DateTime bit) async {
  final rows = await db.rawQuery('''
    SELECT COALESCE(SUM(
      CASE WHEN sk.alis_fiyat_kdv > 0 THEN sk.miktar * sk.alis_fiyat_kdv
           ELSE sk.miktar * COALESCE(u.alis_fiyat_kdv_dahil, 0) END
    ), 0) as maliyet
    FROM satis_kalem sk
    JOIN satislar s ON sk.satis_id = s.id
    LEFT JOIN urunler u ON sk.urun_id = u.id
    WHERE s.tarih BETWEEN ? AND ?
      AND s.iptal = 0 AND s.is_deleted = 0
  ''', [bas.toIso8601String(), bit.toIso8601String()]);
  return (rows.first['maliyet'] as num?)?.toDouble() ?? 0;
}

void main() {
  late Database db;
  setUp(() async => db = await TestVeritabani.olustur());
  tearDown(() => db.close());

  final bas = DateTime(2026, 1, 1);
  final bit = DateTime(2026, 12, 31, 23, 59, 59);

  Future<int> satisEkle({double genelToplam = 100}) => db.insert('satislar', {
        'tarih': DateTime(2026, 6, 15).toIso8601String(),
        'genel_toplam': genelToplam, 'iptal': 0, 'is_deleted': 0,
      });

  test('satış anındaki TARİHSEL KDV DAHİL maliyet kullanılır, ürünün GÜNCEL '
      'alış fiyatı DEĞİL — ürün fiyatı satıştan SONRA değişse bile', () async {
    // Ürün satış anında KDV dahil 60 TL'ye alınmıştı (satis_kalem.
    // alis_fiyat_kdv=60), ama şu an tedarikçi fiyatı 70'e çıktı
    // (urunler.alis_fiyat_kdv_dahil=70).
    final urunId = await TestVeritabani.ornekUrunEkle(db);
    await db.update('urunler', {'alis_fiyat_kdv_dahil': 70},
        where: 'id = ?', whereArgs: [urunId]);
    final satisId = await satisEkle(genelToplam: 100);
    await db.insert('satis_kalem', {
      'satis_id': satisId, 'urun_id': urunId, 'urun_adi': 'Test',
      'miktar': 1, 'birim_fiyat': 100, 'alis_fiyat_kdv': 60, 'toplam_tutar': 100,
    });

    final maliyet = await _maliyetHesapla(db, bas, bit);

    expect(maliyet, 60.0,
        reason: 'satış anındaki maliyet (60) kullanılmalı, güncel fiyat (70) DEĞİL — '
            'önceden bu 70 dönerdi, iki rapor arasında Net Kâr uyuşmazlığına yol açardı');
  });

  test('satis_kalem.alis_fiyat_kdv 0/boşsa (eski/migrasyon-öncesi VEYA masa '
      'satışı satırı) güncel urunler.alis_fiyat_kdv_dahil\'e düşülür', () async {
    final urunId = await TestVeritabani.ornekUrunEkle(db);
    await db.update('urunler', {'alis_fiyat_kdv_dahil': 45},
        where: 'id = ?', whereArgs: [urunId]);
    final satisId = await satisEkle(genelToplam: 100);
    await db.insert('satis_kalem', {
      'satis_id': satisId, 'urun_id': urunId, 'urun_adi': 'Test',
      'miktar': 2, 'birim_fiyat': 100, 'alis_fiyat_kdv': 0, 'toplam_tutar': 200,
    });

    final maliyet = await _maliyetHesapla(db, bas, bit);

    expect(maliyet, 90.0, reason: '2 adet × güncel KDV dahil 45 TL = 90 (fallback)');
  });

  test('iptal edilmiş satış maliyete dahil edilmez', () async {
    final urunId = await TestVeritabani.ornekUrunEkle(db);
    final satisId = await db.insert('satislar', {
      'tarih': DateTime(2026, 6, 15).toIso8601String(),
      'genel_toplam': 100, 'iptal': 1, 'is_deleted': 0,
    });
    await db.insert('satis_kalem', {
      'satis_id': satisId, 'urun_id': urunId, 'urun_adi': 'Test',
      'miktar': 1, 'birim_fiyat': 100, 'alis_fiyat_kdv': 60, 'toplam_tutar': 100,
    });

    expect(await _maliyetHesapla(db, bas, bit), 0.0);
  });

  test('birden fazla kalem doğru toplanır', () async {
    final u1 = await TestVeritabani.ornekUrunEkle(db, barkod: '1');
    final u2 = await TestVeritabani.ornekUrunEkle(db, barkod: '2');
    final satisId = await satisEkle(genelToplam: 300);
    await db.insert('satis_kalem', {
      'satis_id': satisId, 'urun_id': u1, 'urun_adi': 'A',
      'miktar': 2, 'birim_fiyat': 100, 'alis_fiyat_kdv': 40, 'toplam_tutar': 200,
    });
    await db.insert('satis_kalem', {
      'satis_id': satisId, 'urun_id': u2, 'urun_adi': 'B',
      'miktar': 1, 'birim_fiyat': 100, 'alis_fiyat_kdv': 25, 'toplam_tutar': 100,
    });

    expect(await _maliyetHesapla(db, bas, bit), 105.0, reason: '2×40 + 1×25 = 105');
  });
}
