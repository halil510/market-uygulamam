// lib/depolar/fis_detay_deposu.dart
//
// Madde 2 mimari denetimi — katman ihlali temizliği: fis_detay_ekrani
// .dart önceden bu sorguları doğrudan kendisi çalıştırıyordu (ekran
// repository katmanını atlıyordu). Fiş tipine göre (Satış/İade/Alım/
// diğer cari hareketi) doğru tablolardan fiş başlığını ve kalemlerini
// okuyan mantık BİREBİR buraya taşındı — DAVRANIŞ DEĞİŞMEDİ.
import '../veri/database/veritabani.dart';

class FisDetaySonucu {
  final Map<String, dynamic>? fis;
  final List<Map<String, dynamic>> kalemler;
  const FisDetaySonucu({required this.fis, required this.kalemler});
}

class FisDetayDeposu {
  Future<FisDetaySonucu> getir({
    required int fisId,
    required String fisTipi,
  }) async {
    final db = await Veritabani().db;

    // "Toptan Satış" ve "Toptan Satış (Sipariş)"/"Masa Satış" fişleri de
    // tam olarak aynı satislar/satis_kalem tablolarını kullanır.
    if (fisTipi == 'Satış' || fisTipi == 'Toptan Satış' ||
        fisTipi == 'Toptan Satış (Sipariş)' || fisTipi == 'Masa Satış') {
      final rows = await db.rawQuery(
        'SELECT s.*, c.unvan as cari_adi '
        'FROM satislar s LEFT JOIN cari c ON s.cari_id = c.id '
        'WHERE s.id = ? AND s.is_deleted = 0',
        [fisId],
      );
      final fis = rows.isNotEmpty ? rows.first : null;

      final kalemler = await db.rawQuery('''
        SELECT
          sk.id,
          sk.urun_adi,
          sk.barkod,
          sk.miktar,
          sk.birim_fiyat,
          sk.iskonto_oran,
          sk.iskonto_tutar,
          sk.kdv_oran,
          sk.kdv_tutar,
          sk.net_fiyat,
          sk.toplam_tutar,
          COALESCE(u.birim_adi, 'Adet') as birim_adi
        FROM satis_kalem sk
        LEFT JOIN urunler u ON sk.urun_id = u.id
        WHERE sk.satis_id = ?
        ORDER BY sk.id
      ''', [fisId]);

      return FisDetaySonucu(fis: fis, kalemler: List<Map<String, dynamic>>.from(kalemler));

    } else if (fisTipi == 'İade' || fisTipi == 'Satış İade' || fisTipi == 'Iade' || fisTipi == 'Alım İadesi') {
      final rows = await db.rawQuery(
        'SELECT ia.*, c.unvan as cari_adi '
        'FROM iade ia LEFT JOIN cari c ON ia.cari_id = c.id '
        'WHERE ia.id = ? AND ia.deleted_at IS NULL',
        [fisId],
      );
      final fis = rows.isNotEmpty ? rows.first : null;

      final kalemler = await db.rawQuery('''
        SELECT
          ik.id,
          ik.urun_adi,
          ik.miktar,
          ik.birim_fiyat,
          ik.toplam           as toplam_tutar,
          COALESCE(u.birim_adi, 'Adet') as birim_adi,
          0.0                 as iskonto_oran,
          0.0                 as iskonto_tutar,
          0.0                 as kdv_oran,
          0.0                 as kdv_tutar,
          0.0                 as net_fiyat,
          NULL                as barkod
        FROM iade_kalem ik
        LEFT JOIN urunler u ON ik.urun_id = u.id
        WHERE ik.iade_id = ?
        ORDER BY ik.id
      ''', [fisId]);

      return FisDetaySonucu(fis: fis, kalemler: List<Map<String, dynamic>>.from(kalemler));

    } else if (fisTipi == 'Alım' || fisTipi == 'Tedarik' || fisTipi == 'Sipariş') {
      final rows = await db.rawQuery(
        'SELECT ts.*, ts.siparis_no as fis_no, ts.siparis_tarihi as tarih, '
        'ts.toplam_tutar as genel_toplam, c.unvan as cari_adi '
        'FROM tedarikci_siparisler ts '
        'LEFT JOIN cari c ON ts.cari_id = c.id '
        'WHERE ts.id = ? AND (ts.is_deleted IS NULL OR ts.is_deleted = 0)',
        [fisId],
      );
      final fis = rows.isNotEmpty ? rows.first : null;

      final kalemler = await db.rawQuery('''
        SELECT
          tsk.id,
          COALESCE(u.urun_adi, 'Bilinmiyor') as urun_adi,
          u.barkod,
          tsk.siparis_mik       as miktar,
          tsk.birim_fiyat,
          0.0                   as iskonto_oran,
          0.0                   as iskonto_tutar,
          COALESCE(tsk.kdv_oran, 0) as kdv_oran,
          (tsk.siparis_mik * tsk.birim_fiyat * COALESCE(tsk.kdv_oran, 0) / 100.0) as kdv_tutar,
          tsk.birim_fiyat       as net_fiyat,
          tsk.toplam_tutar,
          COALESCE(u.birim_adi, 'Adet') as birim_adi
        FROM tedarikci_siparis_kalem tsk
        LEFT JOIN urunler u ON tsk.urun_id = u.id
        WHERE tsk.siparis_id = ?
        ORDER BY tsk.id
      ''', [fisId]);

      return FisDetaySonucu(fis: fis, kalemler: List<Map<String, dynamic>>.from(kalemler));

    } else {
      // Tahsilat, ödeme, virman vb. — sadece cari_hareket satırı
      final rows = await db.rawQuery(
        'SELECT * FROM cari_hareket WHERE id = ?',
        [fisId],
      );
      final fis = rows.isNotEmpty ? rows.first : null;
      return FisDetaySonucu(fis: fis, kalemler: const []);
    }
  }
}
