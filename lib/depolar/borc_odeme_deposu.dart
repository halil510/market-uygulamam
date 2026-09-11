// lib/depolar/borc_odeme_deposu.dart
import 'package:sqflite/sqflite.dart';
import '../modeller/borc_odeme_model.dart';
import '../veri/database/veritabani.dart';
import '../servisler/log_servisi.dart';
import '../servisler/bulut/bulut_manager.dart';
import 'package:uuid/uuid.dart';

class BorcOdemeDeposu {
  final Veritabani _db = Veritabani();
  Future<Database> get _d async => _db.db;

  Future<int> ekle(BorcOdemeModel odeme) async {
    try {
      final db = await _d;
      final yeniId = await db.transaction((txn) => ekleTxn(txn, odeme));
      final guncelSatir = await db.query('borc_odemeler', where: 'id = ?', whereArgs: [yeniId], limit: 1);
      if (guncelSatir.isNotEmpty) {
        BulutManager().upsert('borc_odemeler', Map<String, dynamic>.from(guncelSatir.first));
      }
      return yeniId;
    } catch (e, st) {
      LogServisi().hata('BorcOdemeDeposu.ekle', hata: e, yigin: st);
      rethrow;
    }
  }

  /// [ekle] ile aynı mantık, VERİLEN transaction içinde çalışır.
  Future<int> ekleTxn(dynamic txn, BorcOdemeModel odeme) async {
    final m = odeme.toMap();
    m.remove('id');
    m['global_id'] ??= const Uuid().v4();
    m['last_updated'] ??= DateTime.now().toIso8601String();
    return await txn.insert('borc_odemeler', m);
  }

  Future<List<BorcOdemeModel>> odemeleriGetir({int? borcId, int limit = 20}) async {
    try {
      final db = await _d;
      final where = borcId != null ? 'borc_id = ?' : null;
      final args = borcId != null ? [borcId] : null;
      final rows = await db.query('borc_odemeler',
          where: where, whereArgs: args,
          orderBy: 'tarih DESC', limit: limit);
      return rows.map(BorcOdemeModel.fromMap).toList();
    } catch (e, st) {
      LogServisi().hata('BorcOdemeDeposu.odemeleriGetir', hata: e, yigin: st);
      return [];
    }
  }

  Future<double> toplamOdeme(int borcId) async {
    try {
      final db = await _d;
      final rows = await db.rawQuery(
        'SELECT COALESCE(SUM(tutar), 0) as toplam FROM borc_odemeler WHERE borc_id = ?',
        [borcId],
      );
      return (rows.first['toplam'] as num?)?.toDouble() ?? 0;
    } catch (e, st) {
      LogServisi().hata('BorcOdemeDeposu.toplamOdeme', hata: e, yigin: st);
      return 0;
    }
  }
}