// lib/depolar/kategori_deposu.dart
//
// MASTER ERP DEEP AUDIT — Madde 2 (Mimari) sertleştirmesi:
// kategori_ekrani.dart için hiç repository sınıfı yoktu, ekranın
// kendisi doğrudan Veritabani().db üzerinden SQL çalıştırıyordu. Bu
// dosya o erişimi kapsar — davranış BİREBİR korunmuştur, sadece
// sorumluluk UI katmanından buraya taşınmıştır.
import 'package:sqflite/sqflite.dart';
import '../servisler/bulut/bulut_manager.dart';
import '../veri/database/veritabani.dart';

class KategoriDeposu {
  final Veritabani _db = Veritabani();
  Future<Database> get _d async => _db.db;

  Future<List<Map<String, dynamic>>> hepsiGetir() async {
    final db = await _d;
    final rows = await db.query('kategoriler', where: 'is_deleted = 0', orderBy: 'ad');
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  Future<Map<String, dynamic>> ekle(String ad) async {
    final db = await _d;
    final now = DateTime.now().toIso8601String();
    final id = await db.insert('kategoriler', {'ad': ad, 'last_updated': now});
    final satir = await db.query('kategoriler', where: 'id = ?', whereArgs: [id], limit: 1);
    final row = Map<String, dynamic>.from(satir.first);
    BulutManager().upsert('kategoriler', row);
    return row;
  }

  /// Soft-delete — ürünler kategoriye referans verebileceği için
  /// hard-delete YAPILMAZ (bkz. çağıran ekrandaki aynı gerekçe).
  Future<void> sil(int id) async {
    final db = await _d;
    final now = DateTime.now().toIso8601String();
    await db.update('kategoriler', {'is_deleted': 1, 'last_updated': now},
        where: 'id = ?', whereArgs: [id]);
    final satir = await db.query('kategoriler', where: 'id = ?', whereArgs: [id], limit: 1);
    if (satir.isNotEmpty) {
      BulutManager().upsert('kategoriler', Map<String, dynamic>.from(satir.first));
    }
  }
}
