// lib/depolar/sube_deposu.dart
//
// MASTER ERP DEEP AUDIT — Madde 2 (Mimari) sertleştirmesi:
// sube_ekrani.dart için hiç repository sınıfı yoktu, ekranın kendisi
// doğrudan Veritabani().db üzerinden SQL çalıştırıyordu. Bu dosya o
// erişimi kapsar — davranış BİREBİR korunmuştur, sadece sorumluluk UI
// katmanından buraya taşınmıştır.
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../servisler/bulut/bulut_manager.dart';
import '../veri/database/veritabani.dart';

class SubeDeposu {
  final Veritabani _db = Veritabani();
  Future<Database> get _d async => _db.db;

  Future<List<Map<String, dynamic>>> hepsiGetir() async {
    final db = await _d;
    final rows = await db.query('subeler', orderBy: 'sube_adi');
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  /// Madde 4 sertleştirmesi (depo_transfer_ekrani.dart): sadece
  /// silinmemiş VE aktif şubeleri döner — transfer kaynağı/hedefi
  /// seçiminde pasif/silinmiş bir şubeye işlem yapılmasın diye.
  Future<List<Map<String, dynamic>>> aktifOlanlariGetir() async {
    final db = await _d;
    final rows = await db.query('subeler',
        where: 'is_deleted = 0 AND aktif = 1', orderBy: 'sube_adi ASC');
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  /// [id] null ise yeni şube ekler, doluysa mevcut kaydı günceller.
  /// Şube kodu boş bırakılırsa zaman damgasından otomatik üretilir.
  Future<Map<String, dynamic>> ekleVeyaGuncelle({
    int? id,
    required String kod,
    required String ad,
    required String adres,
    required String telefon,
  }) async {
    final db = await _d;
    final now = DateTime.now().toIso8601String();
    final data = <String, dynamic>{
      'sube_kodu': kod.isEmpty ? 'S${DateTime.now().millisecondsSinceEpoch}' : kod,
      'sube_adi': ad,
      'adres': adres,
      'telefon': telefon,
      'aktif': 1,
      'updated_at': now,
      'last_updated': now,
    };
    int subeId;
    if (id == null) {
      data['global_id'] = const Uuid().v4();
      subeId = await db.insert('subeler', data);
    } else {
      subeId = id;
      await db.update('subeler', data, where: 'id=?', whereArgs: [subeId]);
    }
    final satir = await db.query('subeler', where: 'id = ?', whereArgs: [subeId], limit: 1);
    final row = Map<String, dynamic>.from(satir.first);
    BulutManager().upsert('subeler', row);
    return row;
  }
}
