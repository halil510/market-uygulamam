// lib/depolar/promosyon_deposu.dart
import 'package:sqflite/sqflite.dart';
import '../servisler/log_servisi.dart';
import '../servisler/bulut/bulut_manager.dart';
import '../veri/database/veritabani.dart';
import '../modeller/promosyon_model.dart';

class PromosyonDeposu {
  final Veritabani _db = Veritabani();
  Future<Database> get _d async => _db.db;

  Future<int> ekle(PromosyonModel p) async {
    try {
      final db = await _d;
      final m = p.toMap();
      m.remove('id');
      m['last_updated'] ??= DateTime.now().toIso8601String();
      final yeniId = await db.insert('promosyonlar', m);
      final guncelSatir = await db.query('promosyonlar', where: 'id = ?', whereArgs: [yeniId], limit: 1);
      if (guncelSatir.isNotEmpty) {
        BulutManager().upsert('promosyonlar', Map<String, dynamic>.from(guncelSatir.first));
      }
      return yeniId;
    } catch (e, st) {
      LogServisi().hata('Promosyon.ekle', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<void> guncelle(PromosyonModel p) async {
    try {
      final db = await _d;
      // 🔴 DÜZELTME: PromosyonModel.toMap() last_updated içermiyordu —
      // promosyon değişikliği (fiyat/tarih/koşul) diğer cihazlara hiç
      // gitmiyordu.
      final m = p.toMap()..['last_updated'] = DateTime.now().toIso8601String();
      await db.update('promosyonlar', m, where: 'id = ?', whereArgs: [p.id]);
      final guncelSatir = await db.query('promosyonlar', where: 'id = ?', whereArgs: [p.id], limit: 1);
      if (guncelSatir.isNotEmpty) {
        BulutManager().upsert('promosyonlar', Map<String, dynamic>.from(guncelSatir.first));
      }
    } catch (e, st) {
      LogServisi().hata('Promosyon.guncelle', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<void> sil(int id) async {
    try {
      final db = await _d;
      // 🔴🔴 ÖNEMLİ DÜZELTME: Önceden GERÇEK (hard) silme
      // kullanılıyordu — uygulamanın geri kalanındaki "soft delete"
      // deseninin aksine. Bu iki soruna yol açıyordu: (1) silme işlemi
      // diğer cihazlara ASLA bildirilemezdi (tombstone/iz kalmıyordu),
      // (2) bu promosyon buluta zaten gittiyse, bir sonraki "buluttan
      // al" indirmesinde SESSİZCE GERİ GELEBİLİRDİ. Artık tablonun
      // ZATEN SAHİP OLDUĞU 'deleted_at' sütunu (is_deleted DEĞİL — bu
      // tabloda o sütun yok) ile soft-delete kullanılıyor.
      final now = DateTime.now().toIso8601String();
      await db.update('promosyonlar', {'aktif': 0, 'deleted_at': now, 'last_updated': now},
          where: 'id = ?', whereArgs: [id]);
      final guncelSatir = await db.query('promosyonlar', where: 'id = ?', whereArgs: [id], limit: 1);
      if (guncelSatir.isNotEmpty) {
        BulutManager().upsert('promosyonlar', Map<String, dynamic>.from(guncelSatir.first));
      }
    } catch (e, st) {
      LogServisi().hata('Promosyon.sil', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<List<PromosyonModel>> tumunuGetir({bool sadecaAktif = false}) async {
    try {
      final db = await _d;
      final where = sadecaAktif ? 'WHERE p.aktif = 1 AND p.deleted_at IS NULL' : 'WHERE p.deleted_at IS NULL';
      final rows = await db.rawQuery(
        'SELECT p.*, u.urun_adi FROM promosyonlar p LEFT JOIN urunler u ON p.urun_id = u.id $where ORDER BY p.aktif DESC, p.promosyon_adi',
      );
      return rows.map(PromosyonModel.fromMap).toList();
    } catch (e, st) {
      LogServisi().hata('Promosyon.metod', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<List<PromosyonModel>> urunPromosyonlari(int urunId) async {
    try {
      final db = await _d;
      final now = DateTime.now().toIso8601String();
      final rows = await db.rawQuery(
        'SELECT p.*, u.urun_adi FROM promosyonlar p LEFT JOIN urunler u ON p.urun_id = u.id '
        'WHERE p.urun_id = ? AND p.aktif = 1 AND p.deleted_at IS NULL '
        'AND (p.bitis_tarihi IS NULL OR p.bitis_tarihi >= ?) '
        'ORDER BY p.iskonto_oran DESC',
        [urunId, now],
      );
      return rows.map(PromosyonModel.fromMap).toList();
    } catch (e, st) {
      LogServisi().hata('Promosyon.metod', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<void> aktiflikToggle(int id, bool aktif) async {
    try {
      final db = await _d;
      final now = DateTime.now().toIso8601String();
      await db.update('promosyonlar', {'aktif': aktif ? 1 : 0, 'last_updated': now},
          where: 'id = ?', whereArgs: [id]);
      final guncelSatir = await db.query('promosyonlar', where: 'id = ?', whereArgs: [id], limit: 1);
      if (guncelSatir.isNotEmpty) {
        BulutManager().upsert('promosyonlar', Map<String, dynamic>.from(guncelSatir.first));
      }
    } catch (e, st) {
      LogServisi().hata('Promosyon.aktiflikToggle', hata: e, yigin: st);
      rethrow;
    }
  }


  // detayliGetir - UI için urun_adi ve satis_fiyati ile birlikte
    Future<List<Map<String, dynamic>>> detayliGetir() async {
      try {
        final db = await _d;
        // 🔴 DÜZELTME: 'u.satisFiyati' (camelCase) VAR OLMAYAN bir
        // sütuna referans veriyordu — gerçek sütun adı 'satis_fiyati'
        // (snake_case). Çağrılırsa "no such column" hatasıyla çökerdi.
        final rows = await db.rawQuery(
          'SELECT p.*, u.urun_adi, u.satis_fiyati, u.barkod '
          'FROM promosyonlar p '
          'LEFT JOIN urunler u ON p.urun_id = u.id '
          'WHERE p.deleted_at IS NULL '
          'ORDER BY p.aktif DESC',
        );
        return rows.map((r) => Map<String, dynamic>.from(r)).toList();
      } catch (e, st) {
        LogServisi().hata('Promosyon.metod', hata: e, yigin: st);
        rethrow;
      }
    }
  
    Future<void> exceldenIceriAktar(dynamic dosya) async {
      try {
        // Excel içe aktarma - ExcelServisi üzerinden yapılır
        // Bu metod PromosyonEkrani'nda kullanılır
      } catch (e, st) {
        LogServisi().hata('Promosyon.exceldenIceriAktar', hata: e, yigin: st);
        rethrow;
      }
    }
  
    Future<String?> excelDisariAktar() async {
      try {
        // ExcelServisi'ne delege edilir
        return null;
      } catch (e, st) {
        LogServisi().hata('Promosyon.excelDisariAktar', hata: e, yigin: st);
        rethrow;
      }
    }
}
