// lib/depolar/iade_deposu.dart
//
// MASTER ERP DEEP AUDIT — Madde 2 (Mimari) sertleştirmesi: iade_ekrani_
// gecmis.dart doğrudan Veritabani().db üzerinden SQL çalıştırıyordu
// (repository katmanını atlıyordu). Bu dosya o erişimi kapsar. Çok
// tablolu iade akışları (toplu iade, fiş iadesi, düzenleme/silme) için
// bkz. IadeIslemServisi — bu sınıf sadece "iade" başlığının tekil not/
// açıklama güncellemesi gibi basit, tek-tablo işlemleri için.
import 'package:sqflite/sqflite.dart';
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

  /// "İade Geçmişi" listesi — tarih/cari filtreli, cari adı JOIN'li, en
  /// fazla [limit] kayıt (iptal edilenler hariç).
  Future<List<Map<String, dynamic>>> gecmisListesiGetir({
    DateTime? baslangic,
    DateTime? bitis,
    int? cariId,
    int limit = 100,
  }) async {
    final db = await _d;
    var where = '1=1';
    final args = <dynamic>[];
    if (baslangic != null) {
      where += ' AND ia.tarih >= ?';
      args.add(baslangic.toIso8601String());
    }
    if (bitis != null) {
      where += ' AND ia.tarih <= ?';
      args.add(bitis.add(const Duration(days: 1)).toIso8601String());
    }
    if (cariId != null) {
      where += ' AND ia.cari_id = ?';
      args.add(cariId);
    }
    return db.rawQuery('''
      SELECT ia.*,
        c.unvan as cari_adi,
        (SELECT COUNT(*) FROM iade_kalem WHERE iade_id = ia.id) as kalem_sayisi
      FROM iade ia
      LEFT JOIN cari c ON ia.cari_id = c.id
      WHERE ia.durum != 'iptal' AND $where
      ORDER BY ia.tarih DESC
      LIMIT $limit
    ''', args);
  }

  /// Bu satıştan daha önce iade edilmiş miktarları ürün bazında toplar
  /// ("Fiş No ile İade" sekmesindeki çift-iade koruması için).
  Future<Map<int, double>> fisIadeliMiktarlariGetir(int satisId) async {
    final db = await _d;
    final rows = await db.rawQuery('''
      SELECT ik.urun_id AS urun_id, SUM(ik.miktar) AS toplam
      FROM iade_kalem ik
      JOIN iade i ON ik.iade_id = i.id
      WHERE i.satis_id = ?
      GROUP BY ik.urun_id
    ''', [satisId]);
    return {
      for (final r in rows)
        (r['urun_id'] as num).toInt(): (r['toplam'] as num?)?.toDouble() ?? 0,
    };
  }
}
