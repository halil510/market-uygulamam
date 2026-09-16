// lib/depolar/marka_deposu.dart
//
// MASTER ERP DEEP AUDIT — Madde 2 (Mimari) sertleştirmesi:
// marka_ekrani.dart için hiç repository sınıfı yoktu, ekranın kendisi
// doğrudan Veritabani().db üzerinden SQL çalıştırıyordu. Bu dosya o
// erişimi kapsar — davranış BİREBİR korunmuştur, sadece sorumluluk UI
// katmanından buraya taşınmıştır.
import 'package:sqflite/sqflite.dart';
import '../servisler/bulut/bulut_manager.dart';
import '../veri/database/veritabani.dart';

class MarkaDeposu {
  final Veritabani _db = Veritabani();
  Future<Database> get _d async => _db.db;

  /// 'markalar' tablosundan (ürün sayısıyla birlikte) listeler; tablo
  /// henüz yoksa/hata olursa 'urunler.marka' sütunundan distinct alarak
  /// geriye dönük uyumlu bir liste üretir.
  Future<List<Map<String, dynamic>>> listele() async {
    final db = await _d;
    try {
      return await db.rawQuery(
        'SELECT m.id, m.ad, m.aktif, COUNT(u.id) as urun_sayisi '
        'FROM markalar m LEFT JOIN urunler u ON u.marka = m.ad AND u.is_deleted = 0 '
        'WHERE m.aktif = 1 '
        'GROUP BY m.id ORDER BY m.ad ASC',
      );
    } catch (_) {
      return await db.rawQuery(
        "SELECT marka as ad, COUNT(*) as urun_sayisi FROM urunler "
        "WHERE marka IS NOT NULL AND marka != '' AND is_deleted = 0 "
        "GROUP BY marka ORDER BY marka ASC",
      );
    }
  }

  Future<Map<String, dynamic>> ekle(String ad) async {
    final db = await _d;
    final now = DateTime.now().toIso8601String();
    final id = await db.insert('markalar', {'ad': ad, 'aktif': 1, 'last_updated': now});
    final satir = await db.query('markalar', where: 'id = ?', whereArgs: [id], limit: 1);
    final row = Map<String, dynamic>.from(satir.first);
    BulutManager().upsert('markalar', row);
    return row;
  }

  /// Marka adını değiştirir ve bu markayı kullanan tüm ürünlerin
  /// 'urunler.marka' sütununu da (eski ada göre) yeni adla günceller.
  Future<void> duzenle({
    required int id,
    required String eskiAd,
    required String yeniAd,
  }) async {
    final db = await _d;
    final now = DateTime.now().toIso8601String();
    await db.update('markalar', {'ad': yeniAd, 'last_updated': now},
        where: 'id = ?', whereArgs: [id]);
    await db.update('urunler', {'marka': yeniAd},
        where: 'marka = ? AND is_deleted = 0', whereArgs: [eskiAd]);
    final satir = await db.query('markalar', where: 'id = ?', whereArgs: [id], limit: 1);
    if (satir.isNotEmpty) {
      BulutManager().upsert('markalar', Map<String, dynamic>.from(satir.first));
    }
  }

  /// Soft-delete — 'aktif' bayrağı 0 yapılır (hard-delete, silmenin
  /// buluta bildirilememesine yol açardı, bkz. çağıran ekrandaki not).
  Future<void> sil(int id) async {
    final db = await _d;
    final now = DateTime.now().toIso8601String();
    await db.update('markalar', {'aktif': 0, 'last_updated': now},
        where: 'id = ?', whereArgs: [id]);
    final satir = await db.query('markalar', where: 'id = ?', whereArgs: [id], limit: 1);
    if (satir.isNotEmpty) {
      BulutManager().upsert('markalar', Map<String, dynamic>.from(satir.first));
    }
  }
}
