// lib/depolar/borc_deposu.dart
import 'package:sqflite/sqflite.dart';
import '../modeller/borc_model.dart';
import '../modeller/borc_odeme_model.dart';
import 'borc_odeme_deposu.dart';
import '../veri/database/veritabani.dart';
import '../servisler/log_servisi.dart';
import '../servisler/bulut/bulut_manager.dart';
import 'package:uuid/uuid.dart';

class BorcDeposu {
  final Veritabani _db = Veritabani();
  Future<Database> get _d async => _db.db;
  final _odemeDeposu = BorcOdemeDeposu();

  Future<int> ekle(BorcModel borc) async {
    try {
      final db = await _d;
      final m = borc.toMap();
      m.remove('id');
      m['global_id'] ??= const Uuid().v4();
      m['last_updated'] ??= DateTime.now().toIso8601String();
      final yeniId = await db.insert('borclar', m);
      final guncelSatir = await db.query('borclar', where: 'id = ?', whereArgs: [yeniId], limit: 1);
      if (guncelSatir.isNotEmpty) {
        BulutManager().upsert('borclar', Map<String, dynamic>.from(guncelSatir.first));
      }
      return yeniId;
    } catch (e, st) {
      LogServisi().hata('BorcDeposu.ekle', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<void> guncelle(BorcModel borc) async {
    try {
      final db = await _d;
      final m = borc.toMap()..['last_updated'] = DateTime.now().toIso8601String();
      await db.update('borclar', m, where: 'id = ?', whereArgs: [borc.id]);
      final guncelSatir = await db.query('borclar', where: 'id = ?', whereArgs: [borc.id], limit: 1);
      if (guncelSatir.isNotEmpty) {
        BulutManager().upsert('borclar', Map<String, dynamic>.from(guncelSatir.first));
      }
    } catch (e, st) {
      LogServisi().hata('BorcDeposu.guncelle', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<void> sil(int id) async {
    try {
      final db = await _d;
      // 🔴🔴 ÖNEMLİ DÜZELTME: Önceden GERÇEK (hard) silme
      // kullanılıyordu. Bu tabloda zaten 'is_deleted' sütunu var —
      // artık diğer tablolarla tutarlı şekilde soft-delete kullanılıyor.
      final now = DateTime.now().toIso8601String();
      await db.update('borclar', {'is_deleted': 1, 'last_updated': now},
          where: 'id = ?', whereArgs: [id]);
      final guncelSatir = await db.query('borclar', where: 'id = ?', whereArgs: [id], limit: 1);
      if (guncelSatir.isNotEmpty) {
        BulutManager().upsert('borclar', Map<String, dynamic>.from(guncelSatir.first));
      }
    } catch (e, st) {
      LogServisi().hata('BorcDeposu.sil', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<List<BorcModel>> tumunuGetir({bool sadeceAktif = true}) async {
    try {
      final db = await _d;
      final where = sadeceAktif ? 'odendi = 0 AND is_deleted = 0' : 'is_deleted = 0';
      final rows = await db.query('borclar', where: where, orderBy: 'son_odeme_tarihi ASC');
      return rows.map(BorcModel.fromMap).toList();
    } catch (e, st) {
      LogServisi().hata('BorcDeposu.tumunuGetir', hata: e, yigin: st);
      return [];
    }
  }

  // ✅ YENİ METOD: ID ile tek bir borç getirir
  Future<BorcModel?> idileGetir(int id) async {
    try {
      final db = await _d;
      final rows = await db.query('borclar', where: 'id = ? AND is_deleted = 0', whereArgs: [id]);
      if (rows.isEmpty) return null;
      return BorcModel.fromMap(rows.first);
    } catch (e, st) {
      LogServisi().hata('BorcDeposu.idileGetir', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<List<BorcModel>> vadesiGecenleriGetir() async {
    try {
      final db = await _d;
      final now = DateTime.now().toIso8601String();
      final rows = await db.rawQuery(
        'SELECT * FROM borclar WHERE odendi = 0 AND is_deleted = 0 AND son_odeme_tarihi < ? ORDER BY son_odeme_tarihi ASC',
        [now],
      );
      return rows.map(BorcModel.fromMap).toList();
    } catch (e, st) {
      LogServisi().hata('BorcDeposu.vadesiGecenleriGetir', hata: e, yigin: st);
      return [];
    }
  }

  Future<List<BorcModel>> yaklasanlariGetir({int gun = 7}) async {
    try {
      final db = await _d;
      final now = DateTime.now().toIso8601String();
      final hedef = DateTime.now().add(Duration(days: gun)).toIso8601String();
      final rows = await db.rawQuery(
        'SELECT * FROM borclar WHERE odendi = 0 AND is_deleted = 0 AND son_odeme_tarihi BETWEEN ? AND ? ORDER BY son_odeme_tarihi ASC',
        [now, hedef],
      );
      return rows.map(BorcModel.fromMap).toList();
    } catch (e, st) {
      LogServisi().hata('BorcDeposu.yaklasanlariGetir', hata: e, yigin: st);
      return [];
    }
  }

  Future<void> odemeYap(int borcId, double tutar) async {
    try {
      final db = await _d;
      final rows = await db.query('borclar', where: 'id = ?', whereArgs: [borcId]);
      if (rows.isEmpty) return;
      final tutarToplam = (rows.first['tutar'] as num).toDouble();
      final eskiOdenen  = (rows.first['odenen_tutar'] as num?)?.toDouble() ?? 0;
      final yeniOdenen  = eskiOdenen + tutar;
      final odendiMi    = yeniOdenen >= tutarToplam;

      await _odemeDeposu.ekle(BorcOdemeModel(
        borcId: borcId,
        tutar: tutar,
        tarih: DateTime.now(),
        odemeYontemi: 'Nakit',
      ));

      await db.update(
        'borclar',
        {
          'odenen_tutar': yeniOdenen,
          'odendi': odendiMi ? 1 : 0,
          'last_updated': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [borcId],
      );
      final guncelSatir = await db.query('borclar', where: 'id = ?', whereArgs: [borcId], limit: 1);
      if (guncelSatir.isNotEmpty) {
        BulutManager().upsert('borclar', Map<String, dynamic>.from(guncelSatir.first));
      }
    } catch (e, st) {
      LogServisi().hata('BorcDeposu.odemeYap', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<int> odemeMutabakatYap() async {
    try {
      final db = await _d;
      final borclar = await db.query('borclar', where: 'is_deleted = 0');
      int duzeltilen = 0;
      for (final b in borclar) {
        final borcId = b['id'] as int;
        final eskiOdenen = (b['odenen_tutar'] as num?)?.toDouble() ?? 0;
        final odemeler = await db.query('borc_odemeler', where: 'borc_id = ?', whereArgs: [borcId]);
        final dogruOdenen = odemeler.fold<double>(
            0, (s, o) => s + ((o['tutar'] as num?)?.toDouble() ?? 0));
        if ((eskiOdenen - dogruOdenen).abs() > 0.01) {
          final tutar = (b['tutar'] as num).toDouble();
          await db.update('borclar', {
            'odenen_tutar': dogruOdenen,
            'odendi': dogruOdenen >= tutar ? 1 : 0,
            'last_updated': DateTime.now().toIso8601String(),
          }, where: 'id = ?', whereArgs: [borcId]);
          final guncelSatir = await db.query('borclar', where: 'id = ?', whereArgs: [borcId], limit: 1);
          if (guncelSatir.isNotEmpty) {
            BulutManager().upsert('borclar', Map<String, dynamic>.from(guncelSatir.first));
          }
          duzeltilen++;
        }
      }
      return duzeltilen;
    } catch (e, st) {
      LogServisi().hata('BorcDeposu.odemeMutabakatYap', hata: e, yigin: st);
      return 0;
    }
  }

  // 🔴 KAYIP DÜZELTME: Bu fonksiyon, dosya yeniden yazılırken
  // (önceki ortam kesintisi sırasında) kaybolmuştu — borc_provider.dart
  // bunu çağırıyordu, eksikliği derleme hatasına yol açtı.
  Future<Map<String, double>> ozetGetir() async {
    try {
      final db = await _d;
      final now = DateTime.now().toIso8601String();
      final res = await db.rawQuery('''
        SELECT
          COALESCE(SUM(tutar), 0) AS toplam_borc,
          COALESCE(SUM(odenen_tutar), 0) AS toplam_odenen,
          COALESCE(SUM(tutar - odenen_tutar), 0) AS kalan_borc,
          COALESCE(SUM(CASE WHEN odendi = 0 AND son_odeme_tarihi < ?
                        THEN tutar - odenen_tutar ELSE 0 END), 0) AS gecmis_borc
        FROM borclar
        WHERE is_deleted = 0
      ''', [now]);
      if (res.isEmpty) {
        return {'toplam_borc': 0, 'toplam_odenen': 0, 'kalan_borc': 0, 'gecmis_borc': 0};
      }
      final r = res.first;
      return {
        'toplam_borc': (r['toplam_borc'] as num?)?.toDouble() ?? 0,
        'toplam_odenen': (r['toplam_odenen'] as num?)?.toDouble() ?? 0,
        'kalan_borc': (r['kalan_borc'] as num?)?.toDouble() ?? 0,
        'gecmis_borc': (r['gecmis_borc'] as num?)?.toDouble() ?? 0,
      };
    } catch (e, st) {
      LogServisi().hata('BorcDeposu.ozetGetir', hata: e, yigin: st);
      return {'toplam_borc': 0, 'toplam_odenen': 0, 'kalan_borc': 0, 'gecmis_borc': 0};
    }
  }
}
