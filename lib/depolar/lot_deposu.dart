// lib/depolar/lot_deposu.dart
//
// Lot/Seri ekranının db.transaction() mantığını SCREEN→SERVICE→
// REPOSITORY mimarisine taşıyan depo. Davranış, önceden ekranın kendi
// _lotDialog()'unda yürüttüğü mantıkla birebir aynıdır: lot_seri kaydı
// (ekle/güncelle) + miktar farkı varsa StokDeposu üzerinden "Lot
// Düzeltme" stok_hareket'i AYNI transaction içinde, commit sonrası
// bulut senkronu.
import 'package:uuid/uuid.dart';
import 'stok_deposu.dart';
import '../servisler/bulut/bulut_manager.dart';
import '../veri/database/veritabani.dart';

class LotDeposu {
  /// [existingLotId] null ise yeni lot eklenir, doluysa günceller.
  /// [eskiMiktar] güncelleme durumunda önceki miktar (fark hesaplamak
  /// için) — yeni eklemede 0 kabul edilir.
  ///
  /// Döner: (lotId, fark) — [fark] sıfır değilse çağıran taraf Onay
  /// Merkezi kaydı için kullanabilir.
  Future<(int, double)> kaydet({
    int? existingLotId,
    required int urunId,
    required double eskiMiktar,
    required String lotNo,
    String? sktIso,
    required double miktar,
    String? aciklama,
    required int? kullaniciId,
  }) async {
    final db = await Veritabani().db;
    final fark = miktar - eskiMiktar;
    late int lotId;

    final data = {
      'lot_no': lotNo,
      'son_kullanma_tarihi': sktIso,
      'miktar': miktar,
      'aciklama': aciklama,
    };

    await db.transaction((txn) async {
      if (existingLotId == null) {
        final gid = const Uuid().v4();
        lotId = await txn.insert('lot_seri', {
          ...data,
          'global_id': gid,
          'urun_id': urunId,
          'kayit_tarihi': DateTime.now().toIso8601String(),
          'last_updated': DateTime.now().toIso8601String(),
        });
      } else {
        lotId = existingLotId;
        data['last_updated'] = DateTime.now().toIso8601String();
        await txn.update('lot_seri', data, where: 'id=?', whereArgs: [lotId]);
      }

      if (fark == 0) return;
      final hareketGid = const Uuid().v4();
      final hareketAciklama = 'Lot Düzeltme: $lotNo';
      if (fark > 0) {
        await StokDeposu().stokGirTxn(txn, hareketGid,
            urunId: urunId,
            miktar: fark,
            kullaniciId: kullaniciId,
            aciklama: hareketAciklama,
            referansId: lotId,
            referansTuru: 'lot_seri',
            hareketTuru: 'Lot Düzeltme',
            lotId: lotId);
      } else {
        await StokDeposu().stokDusTxn(txn, hareketGid,
            urunId: urunId,
            miktar: fark.abs(),
            kullaniciId: kullaniciId,
            aciklama: hareketAciklama,
            referansId: lotId,
            referansTuru: 'lot_seri',
            hareketTuru: 'Lot Düzeltme',
            lotId: lotId);
      }
    });

    // Transaction kalıcı olduktan sonra buluta bildir.
    final satir =
        await db.query('lot_seri', where: 'id = ?', whereArgs: [lotId], limit: 1);
    if (satir.isNotEmpty) {
      BulutManager().upsert('lot_seri', Map<String, dynamic>.from(satir.first));
    }
    if (fark != 0) {
      final urunSatir =
          await db.query('urunler', where: 'id = ?', whereArgs: [urunId], limit: 1);
      if (urunSatir.isNotEmpty) {
        BulutManager().upsert('urunler', Map<String, dynamic>.from(urunSatir.first));
      }
    }

    return (lotId, fark);
  }
}
