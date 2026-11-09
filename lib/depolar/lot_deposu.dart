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
  final _stokDepo = StokDeposu();

  /// Lot/Seri listesini (ürün adı/barkod JOIN'li) getirir — [urunId]
  /// verilirse sadece o ürünün lotları. Madde 2 mimari denetimi:
  /// lot_seri_ekrani.dart önceden bu sorguyu doğrudan kendisi
  /// çalıştırıyordu.
  Future<List<Map<String, dynamic>>> tumunuGetir({int? urunId}) async {
    final db = await Veritabani().db;
    return db.rawQuery('''
      SELECT ls.*, u.urun_adi, u.barkod as urun_barkod
      FROM lot_seri ls
      JOIN urunler u ON ls.urun_id = u.id
      ${urunId != null ? "WHERE ls.urun_id = ?" : ""}
      ORDER BY ls.son_kullanma_tarihi ASC, ls.lot_no ASC
    ''', urunId != null ? [urunId] : []);
  }

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
    // Yeni lotta [eskiMiktar] kullanılır; var olan lotta transaction içinde
    // DB değerinden yeniden hesaplanır (#52).
    var fark = miktar - eskiMiktar;
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
        // 🔴 DERİN DENETİM (2026-11-09, #52): eski miktar EKRAN listesinden
        // geliyordu — araya giren FEFO satışlarından sonra fark büyük çıkıp
        // ürün stoğu ve lot miktarı şişiyordu. Güncel değer DB'den okunur.
        final guncel = await txn.query('lot_seri',
            columns: ['miktar'], where: 'id = ?', whereArgs: [lotId], limit: 1);
        if (guncel.isNotEmpty) {
          fark = miktar - ((guncel.first['miktar'] as num?)?.toDouble() ?? 0);
        }
        data['last_updated'] = DateTime.now().toIso8601String();
        await txn.update('lot_seri', data, where: 'id=?', whereArgs: [lotId]);
      }

      if (fark == 0) return;
      final hareketGid = const Uuid().v4();
      final hareketAciklama = 'Lot Düzeltme: $lotNo';
      if (fark > 0) {
        await _stokDepo.stokGirTxn(txn, hareketGid,
            urunId: urunId,
            miktar: fark,
            kullaniciId: kullaniciId,
            aciklama: hareketAciklama,
            referansId: lotId,
            referansTuru: 'lot_seri',
            hareketTuru: 'Lot Düzeltme',
            lotId: lotId);
      } else {
        await _stokDepo.stokDusTxn(txn, hareketGid,
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
    await BulutManager().satiriBildir(db, 'lot_seri', lotId);
    if (fark != 0) {
      await BulutManager().satiriBildir(db, 'urunler', urunId);
      // 🔴 Derin analizde bulundu: çok şubeli stok payı (sube_urun) hiç
      // güncellenmiyordu. fark>0 iken ana stok ARTTIĞI (stokGirTxn) için,
      // subeStokPayiUygula'nın beklediği "ana stok yönü" (pozitif=düştü)
      // ile ters — bu yüzden -fark veriliyor.
      await _stokDepo.subeStokPayiUygula(urunId, -fark);
    }

    return (lotId, fark);
  }
}
