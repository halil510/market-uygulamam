// lib/depolar/yazici_deposu.dart
import 'package:sqflite/sqflite.dart';
import '../servisler/log_servisi.dart';
import '../veri/database/veritabani.dart';
import '../modeller/yazici_model.dart';

class YaziciDeposu {
  final Veritabani _db = Veritabani();
  Future<Database> get _d async => _db.db;

  Future<int> ekle(YaziciModel y) async {
    try {
      final db = await _d;
      return await db.insert('yazicilar', y.toMap());
    } catch (e, st) {
      LogServisi().hata('Yazici.ekle', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<void> guncelle(YaziciModel y) async {
    try {
      final db = await _d;
      await db.update('yazicilar', y.toMap(), where: 'id = ?', whereArgs: [y.id]);
    } catch (e, st) {
      LogServisi().hata('Yazici.guncelle', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<void> sil(int id) async {
    try {
      final db = await _d;
      await db.delete('yazicilar', where: 'id = ?', whereArgs: [id]);
    } catch (e, st) {
      LogServisi().hata('Yazici.sil', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<List<YaziciModel>> tumunuGetir() async {
    try {
      final db = await _d;
      final rows = await db.query('yazicilar',
          where: 'aktif = 1', orderBy: 'varsayilan DESC, adi');
      return rows.map(YaziciModel.fromMap).toList();
    } catch (e, st) {
      LogServisi().hata('Yazici.metod', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<YaziciModel?> varsayilanGetir() async {
    try {
      final db = await _d;
      final rows = await db.query('yazicilar',
          where: 'varsayilan = 1 AND aktif = 1', limit: 1);
      if (rows.isEmpty) return null;
      return YaziciModel.fromMap(rows.first);
    } catch (e, st) {
      LogServisi().hata('Yazici.varsayilanGetir', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<void> varsayilanAyarla(int id) async {
    try {
      final db = await _d;
      await db.update('yazicilar', {'varsayilan': 0});
      await db.update('yazicilar', {'varsayilan': 1},
          where: 'id = ?', whereArgs: [id]);
    } catch (e, st) {
      LogServisi().hata('Yazici.varsayilanAyarla', hata: e, yigin: st);
      rethrow;
    }
  }
}
