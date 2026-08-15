// lib/depolar/banka_hesap_deposu.dart
import 'package:sqflite/sqflite.dart';
import '../modeller/banka_hesap_model.dart';
import '../veri/database/veritabani.dart';
import '../servisler/log_servisi.dart';
import '../servisler/bulut/bulut_manager.dart';
import 'package:uuid/uuid.dart';

class BankaHesapDeposu {
  final Veritabani _db = Veritabani();
  Future<Database> get _d async => _db.db;

  Future<int> ekle(BankaHesapModel hesap) async {
    try {
      final db = await _d;
      final m = hesap.toMap();
      m.remove('id');
      m['global_id'] ??= const Uuid().v4();
      m['last_updated'] = DateTime.now().toIso8601String();
      final id = await db.insert('banka_hesaplar', m);
      final satir = await db.query('banka_hesaplar', where: 'id = ?', whereArgs: [id], limit: 1);
      if (satir.isNotEmpty) {
        BulutManager().upsert('banka_hesaplar', Map<String, dynamic>.from(satir.first));
      }
      return id;
    } catch (e, st) {
      LogServisi().hata('BankaHesapDeposu.ekle', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<void> guncelle(BankaHesapModel hesap) async {
    try {
      final db = await _d;
      final m = hesap.toMap();
      m['last_updated'] = DateTime.now().toIso8601String();
      await db.update('banka_hesaplar', m, where: 'id = ?', whereArgs: [hesap.id]);
      // 🔴 Bkz. BankaDeposu.guncelle() içindeki aynı not — bu tablo da
      // sonradan senkron sistemine eklendi, eski kayıtlarda global_id
      // NULL olabilir.
      final mevcut = await db.query('banka_hesaplar', columns: ['global_id'], where: 'id = ?', whereArgs: [hesap.id], limit: 1);
      if (mevcut.isNotEmpty && (mevcut.first['global_id'] == null || (mevcut.first['global_id'] as String).isEmpty)) {
        await db.update('banka_hesaplar', {'global_id': const Uuid().v4()}, where: 'id = ?', whereArgs: [hesap.id]);
      }
      final satir = await db.query('banka_hesaplar', where: 'id = ?', whereArgs: [hesap.id], limit: 1);
      if (satir.isNotEmpty) {
        BulutManager().upsert('banka_hesaplar', Map<String, dynamic>.from(satir.first));
      }
    } catch (e, st) {
      LogServisi().hata('BankaHesapDeposu.guncelle', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<List<BankaHesapModel>> tumunuGetir({int? bankaId}) async {
    try {
      final db = await _d;
      final where = bankaId != null ? 'banka_id = ? AND aktif = 1' : 'aktif = 1';
      final args = bankaId != null ? [bankaId] : null;
      final rows = await db.query('banka_hesaplar',
          where: where, whereArgs: args, orderBy: 'hesap_adi ASC');
      return rows.map(BankaHesapModel.fromMap).toList();
    } catch (e, st) {
      LogServisi().hata('BankaHesapDeposu.tumunuGetir', hata: e, yigin: st);
      rethrow; // hata artık gizlenmiyor
    }
  }

  Future<BankaHesapModel?> idileGetir(int id) async {
    try {
      final db = await _d;
      final rows = await db.query('banka_hesaplar',
          where: 'id = ? AND aktif = 1', whereArgs: [id]);
      if (rows.isEmpty) return null;
      return BankaHesapModel.fromMap(rows.first);
    } catch (e, st) {
      LogServisi().hata('BankaHesapDeposu.idileGetir', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<void> bakiyeGuncelle(int id, double yeniBakiye) async {
    try {
      final db = await _d;
      await db.update('banka_hesaplar',
          {'bakiye': yeniBakiye, 'last_updated': DateTime.now().toIso8601String()},
          where: 'id = ?', whereArgs: [id]);
      final satir = await db.query('banka_hesaplar', where: 'id = ?', whereArgs: [id], limit: 1);
      if (satir.isNotEmpty) {
        BulutManager().upsert('banka_hesaplar', Map<String, dynamic>.from(satir.first));
      }
    } catch (e, st) {
      LogServisi().hata('BankaHesapDeposu.bakiyeGuncelle', hata: e, yigin: st);
      rethrow;
    }
  }
}