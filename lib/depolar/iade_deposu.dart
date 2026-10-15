// lib/depolar/iade_deposu.dart
//
// MASTER ERP DEEP AUDIT — Madde 2 (Mimari) sertleştirmesi: iade_ekrani_
// gecmis.dart doğrudan Veritabani().db üzerinden SQL çalıştırıyordu
// (repository katmanını atlıyordu). Bu dosya o erişimi kapsar. Çok
// tablolu iade akışları (toplu iade, fiş iadesi, düzenleme/silme) için
// bkz. IadeIslemServisi — bu sınıf sadece "iade" başlığının tekil not/
// açıklama güncellemesi gibi basit, tek-tablo işlemleri için.
//
// 🔴 DÜZELTME (kullanıcı bulgusu — "iade geçmişinde tedarikçi iadeleri
// görünmüyor"): tedarikçi iadeleri `tedarikci_iadeler` tablosundadır ve
// tarihsel olarak geçmiş sorgusuna dahil edilmiyordu. gecmisListesiGetir
// artık iki tabloyu UNION ALL ile birleştirir, kaynak sütunuyla ayırt
// eder (iade → müşteri/bayi/hızlı/excel/fiş, tedarikci → tedarikçi).
//
// 🔴 DÜZENLEME MODU (2026-10-13): iadeOdemeYontemiGetir ve cariBayiMi
// yardımcıları eklendi. _gecmisIadeyiDevamEt (edit moduna giriş) bu
// iki metotla orijinal ödeme yöntemini ve cari tipini tespit edip
// State'e set ediyor.
import 'package:sqflite/sqflite.dart';
import '../cekirdek/sabitler/db_sabitleri.dart';
import '../servisler/audit_log_servisi.dart';
import '../servisler/bulut/bulut_manager.dart';
import '../servisler/bulut/sync_kuyruk_yazici.dart';
import '../veri/database/veritabani.dart';

class IadeDeposu {
  final Veritabani _db = Veritabani();
  Future<Database> get _d async => _db.db;

  /// İade nedeni/notunu günceller — kuyruk kaydı business data ile AYNI
  /// transaction içinde yazılır (Madde 5 sertleştirmesi): rollback
  /// olursa ikisi de geri alınır, commit olursa ikisi de kalıcı olur.
  /// Gerçek ağ gönderimi zaten transaction dışında (BulutManager
  /// worker'ı) gerçekleşir — burada tekrar upsert() çağırmıyoruz, aksi
  /// halde aynı satır kuyruğa iki kez (biri gereksiz) yazılırdı.
  Future<void> notGuncelle({
    required int iadeId,
    required String iadeNedeni,
  }) async {
    final db = await _d;
    final now = DateTime.now().toIso8601String();
    Map<String, dynamic>? guncelSatir;
    await db.transaction((txn) async {
      await txn.update(
        'iade',
        {'iade_nedeni': iadeNedeni, 'last_updated': now},
        where: 'id = ?',
        whereArgs: [iadeId],
      );
      final satir = await txn.query('iade',
          where: 'id = ?', whereArgs: [iadeId], limit: 1);
      if (satir.isNotEmpty) {
        guncelSatir = Map<String, dynamic>.from(satir.first);
        await SyncKuyrukYazici.ekleTxn(txn, tablo: 'iade', veri: guncelSatir!);
      }
    });
    // Kuyruk kaydı zaten diskte kalıcı — BulutManager().upsert() yerine
    // sadece audit log'u tetikliyoruz (bkz. BulutManager.upsert()'in
    // AuditLogServisi kancası ile aynı sözleşme) ve worker'ı uyandırıyoruz.
    if (guncelSatir != null) {
      await AuditLogServisi().kaydet('iade', guncelSatir!);
    }
    BulutManager().zorlaGonder();
  }

  // 🔴 MASTER ERP DEEP AUDIT — Madde 2 (Mimari) sertleştirmesi, devam
  // (2026-09-22): iade_ekrani_gecmis.dart/iade_ekrani_fis.dart/
  // cari_hareket_ekrani.dart doğrudan Veritabani().db üzerinden bu
  // salt-okunur sorguları çalıştırıyordu. Aşağıdaki metodlar aynı SQL'i
  // (davranış birebir korunarak) repository katmanına taşır.

  /// Tek bir iade başlığını (id) döner — bulunamazsa null.
  Future<Map<String, dynamic>?> idileGetir(int iadeId) async {
    final db = await _d;
    final rows = await db.query('iade', where: 'id = ?', whereArgs: [iadeId]);
    return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
  }

  /// Bir iadenin ham kalem satırları (iade_kalem) — ürün bilgisi JOIN'siz.
  Future<List<Map<String, dynamic>>> kalemleriGetir(int iadeId) async {
    final db = await _d;
    final rows = await db.query('iade_kalem', where: 'iade_id = ?', whereArgs: [iadeId]);
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  /// Bir iadenin kalemleri — ürün adı/KDV oranı JOIN'li (detay diyaloğu için).
  Future<List<Map<String, dynamic>>> kalemleriUrunBilgisiyleGetir(int iadeId) async {
    final db = await _d;
    final rows = await db.rawQuery('''
      SELECT ik.*, u.urun_adi as urun_adi_db, u.kdv_oran as urun_kdv_oran
      FROM iade_kalem ik
      LEFT JOIN urunler u ON ik.urun_id = u.id
      WHERE ik.iade_id = ?
    ''', [iadeId]);
    return rows;
  }

  /// Bir TEDARİKÇİ iadesinin kalemleri — ürün adı/KDV oranı JOIN'li.
  /// Şema farkı: bu tabloda satır tutarı `toplam_tutar` sütununda
  /// (iade_kalem'de `toplam`). Çağıran taraf (iade_ekrani_gecmis.dart
  /// detay diyaloğu) `toplam` beklediği için normalize edilir.
  Future<List<Map<String, dynamic>>> tedarikciKalemleriGetir(int iadeId) async {
    final db = await _d;
    final rows = await db.rawQuery('''
      SELECT tik.*, u.urun_adi as urun_adi_db, u.kdv_oran as urun_kdv_oran
      FROM ${DbSabitler.tedarikciIadeKalem} tik
      LEFT JOIN urunler u ON tik.urun_id = u.id
      WHERE tik.iade_id = ?
    ''', [iadeId]);
    return rows.map((r) {
      final m = Map<String, dynamic>.from(r);
      // Şema normalizasyonu: tek satır tutarı her iki tabloda AYNI anahtar
      // altında gösterilir.
      if (!m.containsKey('toplam') && m.containsKey('toplam_tutar')) {
        m['toplam'] = m['toplam_tutar'];
      }
      return m;
    }).toList();
  }

  /// 🔴 DÜZENLEME MODU (2026-10-13): Bir iade için orijinal ödeme yöntemini
  /// (cari_hareket.odeme_turu) döner. Düzenleme modunda yeni kalem
  /// eklendiğinde cari_hareket'in doğru semantikle yazılması için gerekli.
  /// Kayıt yoksa 'Nakit' döner (güvenli varsayılan).
  Future<String> iadeOdemeYontemiGetir(int iadeId, int cariId) async {
    final db = await _d;
    final rows = await db.rawQuery('''
      SELECT odeme_turu FROM cari_hareket
      WHERE fis_id = ? AND cari_id = ?
        AND fis_tipi IN ('İade','Alım İadesi')
        AND is_deleted = 0
      ORDER BY id DESC LIMIT 1
    ''', [iadeId, cariId]);
    if (rows.isEmpty) return 'Nakit';
    final v = (rows.first['odeme_turu'] as String?)?.trim();
    return (v != null && v.isNotEmpty) ? v : 'Nakit';
  }

  /// 🔴 DÜZENLEME MODU (2026-10-13): Verilen cari_id'nin bayi/toptan mı
  /// olduğunu döner. Bayi iadeleri "Düzenle" ile düzenleme moduna
  /// girmemeli (fiyat kuralı bayi fiyatından gelir → serbest bırakılamaz).
  ///
  /// NOT: cari_tipi enum'ı projede 'Bayi', 'Toptan', 'bayi_toptan' gibi
  /// farklı biçimlerde olabilir — küçük harf + contains ile esnektir.
  Future<bool> cariBayiMi(int cariId) async {
    final db = await _d;
    final rows = await db.query('cari',
        columns: ['cari_tipi'], where: 'id = ?', whereArgs: [cariId], limit: 1);
    if (rows.isEmpty) return false;
    final tip = ((rows.first['cari_tipi'] as String?) ?? '').toLowerCase();
    return tip.contains('bayi') || tip.contains('toptan');
  }

  /// "İade Geçmişi" listesi — tarih/cari filtreli, cari adı JOIN'li, en
  /// fazla [limit] kayıt (iptal edilenler hariç).
  ///
  /// 🔴 DÜZELTME (kullanıcı bulgusu: "iade geçmişinde tedarikçi iadeleri
  /// görünmüyor"): sorgu artık `iade` (müşteri/bayi/hızlı/excel/fiş
  /// iadeleri) ve `tedarikci_iadeler` (tedarikçiye iade) tablolarını
  /// UNION ALL ile birleştirir. Her satır `kaynak` alanı taşır
  /// ('iade' | 'tedarikci') — sil/detay/faturalandır eylemleri bu alana
  /// göre doğru servise yönlendirilir (bkz. iade_ekrani_gecmis.dart).
  ///
  /// Alan eşlemesi (tedarikçi → iade):
  ///   tedarikci_iadeler.iade_no        → fis_no
  ///   tedarikci_iadeler.aciklama       → iade_nedeni
  ///   tedarikci_iadeler.olusturan_id   → kasiyer_id
  ///   tedarikci_iadeler.is_deleted=1   → durum='iptal'
  ///   tedarikci_iadeler.is_deleted=0   → durum='tamamlandi'
  Future<List<Map<String, dynamic>>> gecmisListesiGetir({
    DateTime? baslangic,
    DateTime? bitis,
    int? cariId,
    int limit = 100,
  }) async {
    final db = await _d;

    // iade tablosu için koşullar (alias: ia)
    final iadeKosullar = <String>["ia.durum != 'iptal'"];
    final iadeArgs = <dynamic>[];
    // tedarikci_iadeler için koşullar (alias: ti)
    final tiKosullar = <String>[r'COALESCE(ti.is_deleted, 0) = 0'];
    final tiArgs = <dynamic>[];

    if (baslangic != null) {
      final v = baslangic.toIso8601String();
      iadeKosullar.add('datetime(ia.tarih) >= datetime(?)');
      iadeArgs.add(v);
      tiKosullar.add('datetime(ti.tarih) >= datetime(?)');
      tiArgs.add(v);
    }
    if (bitis != null) {
      final v = bitis.add(const Duration(days: 1)).toIso8601String();
      iadeKosullar.add('datetime(ia.tarih) <= datetime(?)');
      iadeArgs.add(v);
      tiKosullar.add('datetime(ti.tarih) <= datetime(?)');
      tiArgs.add(v);
    }
    if (cariId != null) {
      iadeKosullar.add('ia.cari_id = ?');
      iadeArgs.add(cariId);
      tiKosullar.add('ti.cari_id = ?');
      tiArgs.add(cariId);
    }

    final iadeWhere = iadeKosullar.join(' AND ');
    final tiWhere = tiKosullar.join(' AND ');

    return db.rawQuery('''
      SELECT * FROM (
        SELECT
          ia.id,
          ia.global_id,
          ia.cari_id,
          ia.satis_id,
          ia.fis_no,
          ia.tarih,
          ia.toplam_tutar,
          ia.iade_nedeni,
          ia.durum,
          ia.kasiyer_id,
          ia.last_updated,
          c.unvan AS cari_adi,
          (SELECT COUNT(*) FROM iade_kalem WHERE iade_id = ia.id) AS kalem_sayisi,
          'iade' AS kaynak
        FROM iade ia
        LEFT JOIN cari c ON ia.cari_id = c.id
        WHERE $iadeWhere

        UNION ALL

        SELECT
          ti.id,
          ti.global_id,
          ti.cari_id,
          NULL AS satis_id,
          ti.iade_no AS fis_no,
          ti.tarih,
          ti.toplam_tutar,
          ti.aciklama AS iade_nedeni,
          CASE WHEN COALESCE(ti.is_deleted, 0) = 1
               THEN 'iptal' ELSE 'tamamlandi' END AS durum,
          ti.olusturan_id AS kasiyer_id,
          ti.last_updated,
          c.unvan AS cari_adi,
          (SELECT COUNT(*) FROM ${DbSabitler.tedarikciIadeKalem}
            WHERE iade_id = ti.id) AS kalem_sayisi,
          'tedarikci' AS kaynak
        FROM ${DbSabitler.tedarikciIadeler} ti
        LEFT JOIN cari c ON ti.cari_id = c.id
        WHERE $tiWhere
      )
      ORDER BY tarih DESC
      LIMIT $limit
    ''', [...iadeArgs, ...tiArgs]);
  }

  /// Bu satıştan daha önce iade edilmiş miktarları ürün bazında toplar
  /// ("Fiş No ile İade" sekmesindeki çift-iade koruması için).
  Future<Map<int, double>> fisIadeliMiktarlariGetir(int satisId) async {
    final db = await _d;
    final rows = await db.rawQuery('''
      SELECT ik.urun_id AS urun_id, SUM(ik.miktar) AS toplam
      FROM iade_kalem ik
      JOIN iade i ON ik.iade_id = i.id
      WHERE i.satis_id = ? AND COALESCE(i.durum, '') != 'iptal'
        AND i.deleted_at IS NULL -- silinmiş iade "iade edilmiş" sayılmaz
      GROUP BY ik.urun_id
    ''', [satisId]);
    return {
      for (final r in rows)
        (r['urun_id'] as num).toInt(): (r['toplam'] as num?)?.toDouble() ?? 0,
    };
  }
}