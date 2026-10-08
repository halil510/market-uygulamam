// test/servisler/bayi_hizli_satis_uctan_uca_test.dart
//
// 2026-10-08: Hızlı Satış'ta bayi seçilince toptan kuralı (önce ürün toptan
// fiyatı, sonra grup iskontosu). Uçtan uca: gerçek sepet (veritabanından
// gruba özel fiyat/kademe önbelleği) + gerçek satış kaydı → satış toplamı,
// kalem indirimi (bayi fiyatı indirim DEĞİL), KDV ve cari borcu tutarlı.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:market_plus/depolar/cari_deposu.dart';
import 'package:market_plus/depolar/urun_deposu.dart';
import 'package:market_plus/saglayicilar/riverpod/sepet_provider.dart';
import 'package:market_plus/servisler/satis_tamamlama_servisi.dart';
import '../robot/robot_ortam.dart';

void main() {
  late Database db;
  late RobotVeri v;

  setUp(() async {
    await RobotOrtam.hazirla();
    db = await RobotOrtam.veritabaniAc();
    v = await RobotOrtam.tohumla(db);
  });
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await db.close();
  });

  test('bayiye Hızlı Satış: toptan fiyattan satılır, indirim/KDV/cari tutarlı', () async {
    final urunId = v.id['urun0']!;
    final urun2Id = v.id['urun1']!;
    // Grup %10 iskontolu; urun0'ın toptan fiyatı 107 (perakende 120),
    // urun1'in toptan fiyatı yok → grup iskontosu uygulanmalı.
    final grupId = await db.insert('fiyat_gruplari',
        {'ad': 'bayi gurubu', 'varsayilan_iskonto_orani': 10.0, 'aktif': 1});
    await db.update('urunler', {'satis_fiyati': 120.0, 'toptan_fiyat': 107.0},
        where: 'id = ?', whereArgs: [urunId]);
    await db.update('urunler', {'satis_fiyati': 50.0, 'toptan_fiyat': 0.0},
        where: 'id = ?', whereArgs: [urun2Id]);
    await db.update('cari', {'musteri_tipi': 'Bayi', 'fiyat_grubu_id': grupId},
        where: 'id = ?', whereArgs: [v.id['bayi']]);

    final bayi = (await CariDeposu().idileGetir(v.id['bayi']!))!;
    final u1 = (await UrunDeposu().idileGetir(urunId))!;
    final u2 = (await UrunDeposu().idileGetir(urun2Id))!;

    final c = ProviderContainer();
    addTearDown(c.dispose);
    final sepet = c.read(sepetProvider.notifier);
    // Önce perakende eklenir, sonra bayi seçilir (kullanıcının yaptığı sıra).
    await sepet.ekleAsync(u1, miktar: 2);
    await sepet.ekleAsync(u2, miktar: 1);
    expect(c.read(sepetProvider).genelToplam, 290); // 2×120 + 50
    sepet.musteriSec(bayi);
    await sepet.fiyatlarHazir();

    final d = c.read(sepetProvider);
    final k1 = d.kalemler.firstWhere((k) => k.urun.id == urunId);
    final k2 = d.kalemler.firstWhere((k) => k.urun.id == urun2Id);
    expect(k1.birimFiyat, 107); // toptan fiyatı grup iskontosundan önce
    expect(k2.birimFiyat, closeTo(45, 0.001)); // toptan yok → %10 grup
    expect(k1.toplamIndirim, 0);
    expect(k2.toplamIndirim, 0);
    expect(d.genelToplam, closeTo(259, 0.001)); // 214 + 45

    final cariOnce = (await db.query('cari', where: 'id = ?', whereArgs: [bayi.id]))
        .first['bakiye'] as num;
    final r = await SatisTamamlamaServisi().tamamla(
      kalemler: d.kalemler, musteri: bayi, genelToplam: d.genelToplam,
      odemeYontemi: 'Cari', odenenTutar: 0,
    );

    final satis = (await db.query('satislar', where: 'id = ?', whereArgs: [r.satisId])).first;
    expect((satis['genel_toplam'] as num).toDouble(), closeTo(259, 0.001));
    final kalemler = await db.query('satis_kalem', where: 'satis_id = ?', whereArgs: [r.satisId]);
    final toplamKalem = kalemler.fold<double>(0, (t, k) => t + (k['toplam_tutar'] as num).toDouble());
    expect(toplamKalem, closeTo(259, 0.001), reason: 'kalem toplamı = satış toplamı');
    for (final k in kalemler) {
      expect((k['iskonto_tutar'] as num).toDouble(), 0,
          reason: 'bayi fiyatı indirim olarak kaydedilmemeli (${k['urun_adi']})');
      final toplam = (k['toplam_tutar'] as num).toDouble();
      // KDV %20 dahil: KDV = toplam × 20/120
      expect((k['kdv_tutar'] as num).toDouble(), closeTo(toplam * 20 / 120, 0.01));
    }
    final cariSonra = (await db.query('cari', where: 'id = ?', whereArgs: [bayi.id]))
        .first['bakiye'] as num;
    expect(cariSonra - cariOnce, closeTo(259, 0.001), reason: 'cari borcu satış tutarı kadar');
  });

  test('gruba özel ürün fiyatı ve miktar kademesi Hızlı Satış\'ta da geçerli', () async {
    final urunId = v.id['urun0']!;
    final grupId = await db.insert('fiyat_gruplari',
        {'ad': 'altın', 'varsayilan_iskonto_orani': 10.0, 'aktif': 1});
    await db.update('urunler', {'satis_fiyati': 120.0, 'toptan_fiyat': 107.0},
        where: 'id = ?', whereArgs: [urunId]);
    await db.update('cari', {'musteri_tipi': 'Bayi', 'fiyat_grubu_id': grupId},
        where: 'id = ?', whereArgs: [v.id['bayi']]);
    await db.insert('urun_fiyat_gruplari', {'urun_id': urunId, 'fiyat_grubu_id': grupId, 'fiyat': 100.0});
    await db.insert('fiyat_kademeleri',
        {'urun_id': urunId, 'min_miktar': 10.0, 'birim': 'adet', 'fiyat': 95.0});

    final bayi = (await CariDeposu().idileGetir(v.id['bayi']!))!;
    final u1 = (await UrunDeposu().idileGetir(urunId))!;
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final sepet = c.read(sepetProvider.notifier);
    sepet.musteriSec(bayi);
    await sepet.ekleAsync(u1, miktar: 2);
    expect(c.read(sepetProvider).kalemler.first.birimFiyat, 100); // gruba özel
    sepet.miktarGuncelle(0, 12);
    expect(c.read(sepetProvider).kalemler.first.birimFiyat, 95); // kademe
    expect(c.read(sepetProvider).genelToplam, closeTo(1140, 0.001));
  });
}
