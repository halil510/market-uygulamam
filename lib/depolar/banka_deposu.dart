// lib/depolar/banka_deposu.dart
import 'package:sqflite/sqflite.dart';
import '../modeller/banka_model.dart';
import '../veri/database/veritabani.dart';
import '../servisler/log_servisi.dart';
import '../servisler/bulut/bulut_manager.dart';
import 'package:uuid/uuid.dart';

class BankaDeposu {
  final Veritabani _db = Veritabani();
  Future<Database> get _d async => _db.db;

  Future<int> ekle(BankaModel banka) async {
    try {
      final db = await _d;
      final m = banka.toMap();
      m.remove('id');
      m['global_id'] ??= const Uuid().v4();
      final id = await db.insert('bankalar', m);
      final satir = await db.query('bankalar', where: 'id = ?', whereArgs: [id], limit: 1);
      if (satir.isNotEmpty) {
        BulutManager().upsert('bankalar', Map<String, dynamic>.from(satir.first));
      }
      return id;
    } catch (e, st) {
      LogServisi().hata('BankaDeposu.ekle', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<void> guncelle(BankaModel banka) async {
    try {
      final db = await _d;
      final m = banka.toMap();
      m['last_updated'] = DateTime.now().toIso8601String();
      await db.update('bankalar', m, where: 'id = ?', whereArgs: [banka.id]);
      // 🔴 Bu tablo sonradan senkron sistemine eklendi — eski (senkron
      // öncesi oluşturulmuş) kayıtların global_id'si NULL olabilir ve
      // toMap() bunu SADECE doluysa gönderdiği için düzenleme bile
      // bunu düzeltmiyordu. Buluta göndermeden önce burada da garantiye
      // alınıyor (bkz. migrasyon v49->v50, kalıcı asıl düzeltme).
      final mevcut = await db.query('bankalar', columns: ['global_id'], where: 'id = ?', whereArgs: [banka.id], limit: 1);
      if (mevcut.isNotEmpty && (mevcut.first['global_id'] == null || (mevcut.first['global_id'] as String).isEmpty)) {
        await db.update('bankalar', {'global_id': const Uuid().v4()}, where: 'id = ?', whereArgs: [banka.id]);
      }
      final satir = await db.query('bankalar', where: 'id = ?', whereArgs: [banka.id], limit: 1);
      if (satir.isNotEmpty) {
        BulutManager().upsert('bankalar', Map<String, dynamic>.from(satir.first));
      }
    } catch (e, st) {
      LogServisi().hata('BankaDeposu.guncelle', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<void> sil(int id) async {
    try {
      final db = await _d;
      final now = DateTime.now().toIso8601String();
      await db.update('bankalar', {'aktif': 0, 'last_updated': now},
          where: 'id = ?', whereArgs: [id]);
      // 🔴 Derin analizde bulundu: silme işlemi buluta HİÇ bildirilmiyordu
      // (BulutManager çağrısı eksikti) — bankalar artık senkron sisteminde.
      final satir = await db.query('bankalar', where: 'id = ?', whereArgs: [id], limit: 1);
      if (satir.isNotEmpty) {
        BulutManager().upsert('bankalar', Map<String, dynamic>.from(satir.first));
      }
    } catch (e, st) {
      LogServisi().hata('BankaDeposu.sil', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<BankaModel?> idileGetir(int id) async {
    try {
      final db = await _d;
      final rows = await db.query('bankalar',
          where: 'id = ? AND aktif = 1', whereArgs: [id]);
      if (rows.isEmpty) return null;
      return BankaModel.fromMap(rows.first);
    } catch (e, st) {
      LogServisi().hata('BankaDeposu.idileGetir', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<List<BankaModel>> tumunuGetir() async {
    try {
      final db = await _d;
      final rows = await db.query('bankalar',
          where: 'aktif = 1', orderBy: 'ad ASC');
      return rows.map(BankaModel.fromMap).toList();
    } catch (e, st) {
      LogServisi().hata('BankaDeposu.tumunuGetir', hata: e, yigin: st);
      rethrow; // hata artık gizlenmiyor
    }
  }
}