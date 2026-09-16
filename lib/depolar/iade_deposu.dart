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
}
