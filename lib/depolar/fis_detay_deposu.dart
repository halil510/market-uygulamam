// lib/depolar/fis_detay_deposu.dart
//
// Madde 2 mimari denetimi — katman ihlali temizliği: fis_detay_ekrani
// .dart önceden bu sorguları doğrudan kendisi çalıştırıyordu (ekran
// repository katmanını atlıyordu). Fiş tipine göre (Satış/İade/Alım/
// diğer cari hareketi) doğru tablolardan fiş başlığını ve kalemlerini
// okuyan mantık BİREBİR buraya taşındı — DAVRANIŞ DEĞİŞMEDİ.
//
// 🔴 DÜZELTME (2026-10-13, kullanıcı bulgusu: "fişi tıklayınca iade
// fişini hangi ürünleri gösteren ürünler görünmüyor"):
//  1. 'Tedarikçi İadesi' tipi HİÇBİR dalda ele alınmıyordu → else
//     dalına düşüp `kalemler: const []` dönüyordu. Ekranda "Bu hareket
//     için kalem detayı gösterilmiyor" mesajı çıkıyordu. Oysa gerçek
//     kalemler `tedarikci_iade_kalem` tablosunda mevcut. Artık ayrı bir
//     dal eklendi (başlık: tedarikci_iadeler, iade_no→fis_no alias).
//  2. İade dalında `barkod` her zaman `NULL` dönüyordu (JOIN vardı ama
//     kullanılmıyordu) → detay ekranında barkod gösterilemiyordu. Artık
//     `COALESCE(u.barkod, '') as barkod` ile urunler'den çekiliyor.
//  3. İade dalında iskonto her zaman 0.0 dönüyordu — oysa iade_kalem
//     tablosu iskonto_oran/iskonto_tutar sütunlarını tutuyor
//     (bkz. manuelKalemEkle, oturumIadeDuzenle). Artık gerçek değerler
//     gösteriliyor (indirimli iade detayı doğru yansıyor).
import 'package:sqflite/sqflite.dart';
import '../veri/database/veritabani.dart';

class FisDetaySonucu {
  final Map<String, dynamic>? fis;
  final List<Map<String, dynamic>> kalemler;
  const FisDetaySonucu({required this.fis, required this.kalemler});
}

class FisDetayDeposu {
  // Testlerde gerçek şemayla kurulan bellek-içi veritabanının enjekte
  // edilebilmesi için opsiyonel; verilmezse üretimde tekil Veritabani().db
  // kullanılır (davranış değişmedi).
  final Database? _db;
  FisDetayDeposu({this._db});

  Future<FisDetaySonucu> getir({
    required int fisId,
    required String fisTipi,
  }) async {
    final db = _db ?? await Veritabani().db;

    // "Toptan Satış" ve "Toptan Satış (Sipariş)"/"Masa Satış" fişleri de
    // tam olarak aynı satislar/satis_kalem tablolarını kullanır.
    if (fisTipi == 'Satış' ||
        fisTipi == 'Toptan Satış' ||
        fisTipi == 'Toptan Satış (Sipariş)' ||
        fisTipi == 'Masa Satış') {
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

    } else if (fisTipi == 'İade' ||
        fisTipi == 'Satış İade' ||
        fisTipi == 'Iade' ||
        fisTipi == 'Alım İadesi') {
      final rows = await db.rawQuery(
        'SELECT ia.*, c.unvan as cari_adi '
        'FROM iade ia LEFT JOIN cari c ON ia.cari_id = c.id '
        'WHERE ia.id = ? AND ia.deleted_at IS NULL',
        [fisId],
      );
      final fis = rows.isNotEmpty ? rows.first : null;

      // 🔴 DÜZELTME (2026-10-13): barkod NULL yerine urunler'den; iskonto
      // 0.0 yerine iade_kalem'deki gerçek değerler. KDV hâlâ 0.0 (iade
      // kalem tablosunda kdv_tutar sütunu yok, kdv_oran sadece ürün
      // kartında — burada göstermek yanıltıcı olurdu, eskisi gibi kalıyor).
      final kalemler = await db.rawQuery('''
        SELECT
          ik.id,
          ik.urun_adi,
          ik.miktar,
          ik.birim_fiyat,
          ik.toplam                           as toplam_tutar,
          COALESCE(u.birim_adi, 'Adet')       as birim_adi,
          COALESCE(ik.iskonto_oran, 0.0)      as iskonto_oran,
          COALESCE(ik.iskonto_tutar, 0.0)     as iskonto_tutar,
          0.0                                 as kdv_oran,
          0.0                                 as kdv_tutar,
          ik.birim_fiyat                      as net_fiyat,
          COALESCE(u.barkod, '')              as barkod
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

    } else if (fisTipi == 'Tedarikçi İadesi') {
      // 🔴 YENİ DAL (2026-10-13, kullanıcı bulgusu): tedarikçi iadeleri
      // `tedarikci_iadeler` + `tedarikci_iade_kalem` tablolarındadır
      // (bkz. iade_islem_servisi_tedarikci_bayi.dart). Aşağıdaki alias'lar
      // sayesinde detay ekranı (fis_detay_ekrani.dart) mevcut alan
      // adlarını (fis_no, tarih, toplam_tutar, kalemler'de urun_adi/
      // miktar/birim_fiyat/toplam_tutar) aynen bulur.
      //
      // Şema notu:
      //   tedarikci_iadeler.iade_no     → fis_no olarak alias'lanır
      //   tedarikci_iadeler.aciklama    → başlıkta iade_nedeni gösterilir
      //   tedarikci_iade_kalem.toplam_tutar → ekran toplam_tutar bekler
      final rows = await db.rawQuery('''
        SELECT ti.*, ti.iade_no AS fis_no, c.unvan AS cari_adi
        FROM tedarikci_iadeler ti
        LEFT JOIN cari c ON ti.cari_id = c.id
        WHERE ti.id = ? AND COALESCE(ti.is_deleted, 0) = 0
      ''', [fisId]);
      final fis = rows.isNotEmpty ? rows.first : null;

      final kalemler = await db.rawQuery('''
        SELECT
          tik.id,
          tik.urun_adi,
          tik.miktar,
          tik.birim_fiyat,
          tik.toplam_tutar,
          COALESCE(tik.kdv_oran, 0)      as kdv_oran,
          0.0                            as kdv_tutar,
          0.0                            as iskonto_oran,
          0.0                            as iskonto_tutar,
          tik.birim_fiyat                as net_fiyat,
          COALESCE(u.barkod, '')         as barkod,
          COALESCE(u.birim_adi, 'Adet')  as birim_adi
        FROM tedarikci_iade_kalem tik
        LEFT JOIN urunler u ON tik.urun_id = u.id
        WHERE tik.iade_id = ?
        ORDER BY tik.id
      ''', [fisId]);

      return FisDetaySonucu(
        fis: fis,
        kalemler: List<Map<String, dynamic>>.from(kalemler),
      );

    } else {
      // Tahsilat, ödeme, virman vb. — sadece cari_hareket satırı.
      // Kalem listesi yok (bu hareketlerin zaten kalem tablosu yok).
      final rows = await db.rawQuery(
        'SELECT * FROM cari_hareket WHERE id = ?',
        [fisId],
      );
      final fis = rows.isNotEmpty ? rows.first : null;
      return FisDetaySonucu(fis: fis, kalemler: const []);
    }
  }
}