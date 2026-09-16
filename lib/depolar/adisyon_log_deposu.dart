// lib/depolar/adisyon_log_deposu.dart
//
// MASTER ERP DEEP AUDIT — Madde 2 (Mimari) sertleştirmesi:
// masa_detay_ekrani.dart doğrudan Veritabani().db üzerinden
// 'adisyon_log' tablosuna yazıyordu (repository katmanını atlıyordu).
// Bu dosya o erişimi kapsar.
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../servisler/audit_log_servisi.dart';
import '../servisler/bulut/bulut_manager.dart';
import '../servisler/bulut/sync_kuyruk_yazici.dart';
import '../veri/database/veritabani.dart';

class AdisyonLogDeposu {
  final Veritabani _db = Veritabani();
  Future<Database> get _d async => _db.db;

  /// Adisyon yazdırma olayını kaydeder — kuyruk kaydı business data ile
  /// AYNI transaction içinde yazılır (Madde 5 sertleştirmesi).
  Future<void> kaydet({
    required int siparisId,
    required String adisyonNo,
    int? yazdiranKullaniciId,
  }) async {
    final db = await _d;
    final gid = const Uuid().v4();
    final now = DateTime.now().toIso8601String();
    Map<String, dynamic>? satir;
    await db.transaction((txn) async {
      final id = await txn.insert('adisyon_log', {
        'global_id': gid,
        'siparis_id': siparisId,
        'adisyon_no': adisyonNo,
        'yazdiran_kullanici_id': yazdiranKullaniciId,
        'yazdirma_zamani': now,
        'last_updated': now,
      });
      final rows = await txn.query('adisyon_log',
          where: 'id = ?', whereArgs: [id], limit: 1);
      if (rows.isNotEmpty) {
        satir = Map<String, dynamic>.from(rows.first);
        await SyncKuyrukYazici.ekleTxn(txn, tablo: 'adisyon_log', veri: satir!);
      }
    });
    // Kuyruk kaydı zaten diskte kalıcı — sadece audit log + worker
    // tetikleme (bkz. IadeDeposu.notGuncelle'deki aynı gerekçe, çift
    // kuyruğa yazmamak için BulutManager().upsert() tekrar çağrılmıyor).
    if (satir != null) {
      await AuditLogServisi().kaydet('adisyon_log', satir!);
    }
    BulutManager().zorlaGonder();
  }
}
