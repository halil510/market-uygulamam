// lib/servisler/toptan_satis_islem_servisi.dart
//
// Toptan Satış ekranının db.transaction() mantığını SCREEN→SERVICE→
// REPOSITORY mimarisine taşıyan servis. Davranış, önceden ekranın kendi
// _satisiTamamla()'sında yürüttüğü mantıkla birebir aynıdır: satış +
// stok (FEFO) + cari hareketi TEK transaction içinde, commit sonrası
// bulut senkronu.
import 'package:flutter/foundation.dart';
import '../depolar/cari_deposu.dart';
import '../depolar/satis_deposu.dart';
import '../depolar/stok_deposu.dart';
import '../modeller/satis_model.dart';
import '../modeller/satis_kalem_model.dart';
import '../modeller/cari_hareket_model.dart';
import '../servisler/bulut/bulut_manager.dart';
import '../veri/database/veritabani.dart';

/// Stok düşümü için gereken minimal kalem bilgisi.
class ToptanStokKalemi {
  final int urunId;
  final double stokMiktari;
  const ToptanStokKalemi({required this.urunId, required this.stokMiktari});
}

class ToptanSatisIslemServisi {
  final _satisDepo = SatisDeposu();
  final _stokDepo = StokDeposu();
  final _cariDepo = CariDeposu();

  /// Döner: yeni satışın id'si.
  Future<int> satisKaydet({
    required SatisModel satis,
    required List<SatisKalemModel> kalemler,
    required List<ToptanStokKalemi> stokKalemleri,
    required int cariId,
    required String fisNo,
    required double genelToplam,
    required int? kullaniciId,
    required String? kullaniciAdi,
  }) async {
    final db = await Veritabani().db;
    late final int satisId;
    // FAZ 5 (Lot/SKT): lot_takibi açık üründe birden fazla lottan
    // tüketilebildiği için ürün başına birden fazla global_id olabiliyor.
    final stokHareketGidleri = <int, List<String>>{};
    late final String cariGlobalId;

    await db.transaction((txn) async {
      satisId = await _satisDepo.satisEkleTxn(txn, satis, kalemler);

      for (final k in stokKalemleri) {
        stokHareketGidleri[k.urunId] = await _stokDepo.stokDusFefoTxn(
          txn,
          urunId: k.urunId,
          miktar: k.stokMiktari,
          kullaniciId: kullaniciId,
          referansId: satisId,
          referansTuru: 'toptan_satis',
        );
      }

      cariGlobalId = await _cariDepo.hareketEkleTxn(
          txn,
          CariHareketModel(
            cariId: cariId,
            tarih: satis.tarih,
            fisTipi: 'Toptan Satış',
            fisId: satisId,
            fisNo: fisNo,
            aciklama: 'Toptan satış: $fisNo',
            borc: genelToplam,
            alacak: 0,
            odemeTuru: 'Cari',
            kullanici: kullaniciAdi,
          ));
    });

    // Transaction kalıcı olduktan sonra buluta bildir.
    try {
      BulutManager().upsert('satislar',
          {...satis.toMap(), 'id': satisId, 'global_id': satis.globalId});
      for (final k in kalemler) {
        BulutManager().upsert('satis_kalem', k.toMap());
      }
      for (final k in stokKalemleri) {
        final gidler = stokHareketGidleri[k.urunId];
        if (gidler == null || gidler.isEmpty) continue;
        final urunSatir = await db.query('urunler',
            where: 'id = ?', whereArgs: [k.urunId], limit: 1);
        if (urunSatir.isNotEmpty) {
          BulutManager()
              .upsert('urunler', Map<String, dynamic>.from(urunSatir.first));
        }
        for (final gid in gidler) {
          final stokSatir = await db.query('stok_hareket',
              where: 'global_id = ?', whereArgs: [gid], limit: 1);
          if (stokSatir.isNotEmpty) {
            BulutManager().upsert(
                'stok_hareket', Map<String, dynamic>.from(stokSatir.first));
          }
        }
      }
      final cariHareketSatir = await db.query('cari_hareket',
          where: 'global_id = ?', whereArgs: [cariGlobalId], limit: 1);
      if (cariHareketSatir.isNotEmpty) {
        BulutManager().upsert(
            'cari_hareket', Map<String, dynamic>.from(cariHareketSatir.first));
      }
      final cariSatir =
          await db.query('cari', where: 'id = ?', whereArgs: [cariId], limit: 1);
      if (cariSatir.isNotEmpty) {
        BulutManager().upsert('cari', Map<String, dynamic>.from(cariSatir.first));
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Toptan satış bulut bildirimi hatası: $e');
    }

    return satisId;
  }
}
