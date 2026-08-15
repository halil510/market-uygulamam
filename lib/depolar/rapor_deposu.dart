// lib/depolar/rapor_deposu.dart
import '../veri/database/veritabani.dart';
import 'package:sqflite/sqflite.dart';
import '../servisler/log_servisi.dart';

class RaporDeposu {
  final Veritabani _db = Veritabani();
  Future<Database> get _d async => _db.db;

  Future<Map<String, double>> aylikOzet(int yil, int ay) async {
    try {
      final db = await _d;
      final res = await db.rawQuery(
        "SELECT SUM(genel_toplam) as ciro, COUNT(*) as satis_sayisi, "
        "SUM(iskonto_tutar) as iskonto FROM satislar "
        "WHERE strftime('%Y', tarih) = ? AND strftime('%m', tarih) = ? AND iptal = 0 AND is_deleted = 0",
        [yil.toString(), ay.toString().padLeft(2, '0')],
      );
      if (res.isEmpty) return {};
      final r = res.first;
      return {
        'ciro': (r['ciro'] as num?)?.toDouble() ?? 0,
        'satis_sayisi': (r['satis_sayisi'] as num?)?.toDouble() ?? 0,
        'iskonto': (r['iskonto'] as num?)?.toDouble() ?? 0,
      };
    } catch (e, st) {
      LogServisi().hata('Rapor.metod', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> enCokSatilanUrunler({int limit = 10}) async {
    try {
      final db = await _d;
      return await db.rawQuery(
        'SELECT sk.urun_adi, SUM(sk.miktar) as toplam_miktar, SUM(sk.toplam_tutar) as toplam_tutar '
        'FROM satis_kalem sk JOIN satislar s ON sk.satis_id = s.id '
        'WHERE s.iptal = 0 AND s.is_deleted = 0 AND DATE(s.tarih) >= DATE("now", "-30 days") '
        'GROUP BY sk.urun_id ORDER BY toplam_miktar DESC LIMIT ?',
        [limit],
      );
    } catch (e, st) {
      LogServisi().hata('Rapor.metod', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> aylikCiroGrafigi(int yil) async {
    try {
      final db = await _d;
      return await db.rawQuery(
        "SELECT strftime('%m', tarih) as ay, SUM(genel_toplam) as ciro "
        "FROM satislar WHERE strftime('%Y', tarih) = ? AND iptal = 0 AND is_deleted = 0 "
        "GROUP BY strftime('%m', tarih) ORDER BY ay",
        [yil.toString()],
      );
    } catch (e, st) {
      LogServisi().hata('Rapor.metod', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<Map<String, double>> stokDegerlendirme() async {
    try {
      final db = await _d;
      final res = await db.rawQuery(
        'SELECT SUM(stok * alis_fiyat) as toplam_deger, '
        'COUNT(CASE WHEN stok <= minimum_stok AND minimum_stok > 0 THEN 1 END) as kritik_sayisi '
        'FROM urunler WHERE aktif = 1 AND is_deleted = 0',
      );
      if (res.isEmpty) return {};
      final r = res.first;
      return {
        'toplam_deger': (r['toplam_deger'] as num?)?.toDouble() ?? 0,
        'kritik_sayisi': (r['kritik_sayisi'] as num?)?.toDouble() ?? 0,
      };
    } catch (e, st) {
      LogServisi().hata('Rapor.metod', hata: e, yigin: st);
      rethrow;
    }
  }
}
