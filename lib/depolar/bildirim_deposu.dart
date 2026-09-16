// lib/depolar/bildirim_deposu.dart
//
// MASTER ERP DEEP AUDIT — Madde 2 (Mimari) sertleştirmesi:
// bildirim_merkezi_ekrani.dart için hiç repository sınıfı yoktu, hem
// provider hem okundu-işaretleme akışları doğrudan Veritabani().db
// üzerinden SQL çalıştırıyordu. Bu dosya o erişimi kapsar. NOT: 'bildirimler'
// tablosu bilinçli olarak senkron sistemine dahil DEĞİL (cihaza özel) —
// bu davranış korunmuştur, BulutManager çağrısı eklenmedi.
import 'package:sqflite/sqflite.dart';
import '../cekirdek/sabitler/db_sabitleri.dart';
import '../veri/database/veritabani.dart';

class BildirimDeposu {
  final Veritabani _db = Veritabani();
  Future<Database> get _d async => _db.db;

  Future<List<Map<String, dynamic>>> sonBildirimler({int limit = 100}) async {
    final db = await _d;
    try {
      final rows = await db.query(DbSabitler.bildirimler,
          orderBy: 'tarih DESC', limit: limit);
      return rows.map((r) => Map<String, dynamic>.from(r)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> okunduIsaretle(int id) async {
    final db = await _d;
    await db.update(DbSabitler.bildirimler, {'okundu': 1}, where: 'id=?', whereArgs: [id]);
  }

  Future<void> tumunuOkunduIsaretle() async {
    final db = await _d;
    await db.update(DbSabitler.bildirimler, {'okundu': 1});
  }
}
