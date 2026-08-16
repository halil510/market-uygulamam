import '../servisler/bulut/bulut_manager.dart'; // sync hook
// lib/depolar/gider_deposu.dart
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../servisler/log_servisi.dart';
import '../veri/database/veritabani.dart';
import '../modeller/gider_model.dart';
import '../servisler/aktif_sube_servisi.dart';

class GiderDeposu {
  final Veritabani _db = Veritabani();
  Future<Database> get _d async => _db.db;

  Future<int> ekle(GiderModel g) async {
    try {
      final db = await _d;
      final now = DateTime.now().toIso8601String();
      final m = g.toMap();
      m.remove('id');
      // 🔴🔴 KRİTİK DÜZELTME (derin analizde bulundu): 'giderler'
      // tablosu global_id ile senkron sisteminde kayıtlı olduğu halde
      // (_uniqueAlan haritası) buraya HİÇ global_id atanmıyordu — her
      // yeni gider, senkron için gerekli çakışma anahtarı olmadan
      // buluta gönderiliyordu.
      m['global_id'] ??= const Uuid().v4();
      m['last_updated'] = now;
      // Kâr-Zarar raporunda giderler artık şubeye göre filtreleniyor —
      // yeni giderin de o filtrede görünmesi için boşsa aktif şubeden
      // otomatik dolduruluyor.
      m['sube_id'] ??= AktifSubeServisi().subeId;
      final _gid = await db.insert('giderler', m);
      final satir = await db.query('giderler', where: 'id = ?', whereArgs: [_gid], limit: 1);
      if (satir.isNotEmpty) BulutManager().upsert('giderler', Map<String, dynamic>.from(satir.first));
      return _gid;
    } catch (e, st) {
      LogServisi().hata('Gider.ekle', hata: e, yigin: st);
      rethrow;
    }
  }

  // 🔴 DÜZELTME (derin analizde bulundu): Bu depoda hiç guncelle()
  // fonksiyonu YOKTU — kullanıcı yanlış girdiği bir gideri (tutar,
  // kategori, açıklama vb.) asla düzeltemiyordu; tek çare silip yeniden
  // eklemekti (ki bu da orijinal kaydın oluşturulma bilgisini kaybeder).
  Future<void> guncelle(GiderModel g) async {
    try {
      if (g.id == null) throw Exception('guncelle() için id gerekli');
      final db = await _d;
      final now = DateTime.now().toIso8601String();
      final m = g.toMap();
      m.remove('id');
      m.remove('global_id'); // global_id oluşturulduktan sonra değişmez
      m['last_updated'] = now;
      await db.update('giderler', m, where: 'id = ?', whereArgs: [g.id]);
      final satir = await db.query('giderler', where: 'id = ?', whereArgs: [g.id], limit: 1);
      if (satir.isNotEmpty) BulutManager().upsert('giderler', Map<String, dynamic>.from(satir.first));
    } catch (e, st) {
      LogServisi().hata('Gider.guncelle', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<void> sil(int id) async {
    try {
      final db = await _d;
      final now = DateTime.now().toIso8601String();
      // 🔴 DÜZELTME: Gerçek HARD DELETE yapılıyordu — tabloda zaten
      // 'deleted_at' sütunu vardı ama hiç kullanılmıyordu. Hard delete,
      // silmenin buluta hiç bildirilememesine ve bulut→yerel çekişte
      // silinen giderin "dirilmesine" yol açıyordu.
      await db.update('giderler', {'deleted_at': now, 'last_updated': now},
          where: 'id = ?', whereArgs: [id]);
      final satir = await db.query('giderler', where: 'id = ?', whereArgs: [id], limit: 1);
      if (satir.isNotEmpty) BulutManager().upsert('giderler', Map<String, dynamic>.from(satir.first));
    } catch (e, st) {
      LogServisi().hata('Gider.sil', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<List<GiderModel>> tumunuGetir({int limit = 200}) async {
    final db = await _d;
    final rows = await db.query(
      'giderler', where: 'deleted_at IS NULL', orderBy: 'tarih DESC', limit: limit);
    return rows.map(GiderModel.fromMap).toList();
  }

  Future<List<GiderModel>> tariheGoreGetir(DateTime bas, DateTime bit) async {
    try {
      final db = await _d;
      final rows = await db.rawQuery(
        'SELECT g.*, k.ad as kategori_adi FROM giderler g '
        'LEFT JOIN gider_kategoriler k ON g.kategori_id = k.id '
        'WHERE datetime(g.tarih) BETWEEN datetime(?) AND datetime(?) AND g.deleted_at IS NULL ORDER BY g.tarih DESC',
        [bas.toIso8601String(), bit.toIso8601String()],
      );
      return rows.map(GiderModel.fromMap).toList();
    } catch (e, st) {
      LogServisi().hata('Gider.metod', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<List<GiderModel>> bugunkunler() async {
    try {
      final db = await _d;
      final rows = await db.rawQuery(
        "SELECT g.*, k.ad as kategori_adi FROM giderler g "
        "LEFT JOIN gider_kategoriler k ON g.kategori_id = k.id "
        // 🔴 KRİTİK DÜZELTME (derin analiz — gün sonu raporu / kasa özeti):
      // SQLite'ın DATE('now') fonksiyonu VARSAYILAN OLARAK UTC kullanır.
      // Ama `tarih` sütunu DateTime.now().toIso8601String() ile YEREL
      // saatle yazılıyor (satis_model.dart, gider_model.dart, kasa
      // hareketleri — hepsi aynı desen).
      //
      // Türkiye UTC+3 olduğu için, YEREL saatle 00:00–03:00 arasında
      // (yani UTC henüz bir önceki güne ait sayılırken) yapılan HER
      // satış/gider/kasa hareketi bu sorgudan DÜŞÜYORDU:
      //
      //   Yerel 01:00 (27 Tem) → tarih sütunu: '2026-07-27T01:00:00'
      //   O ANDA UTC saati     : 26 Tem 22:00 → DATE('now') = '2026-07-26'
      //   DATE(tarih)='2026-07-27' ≠ DATE('now')='2026-07-26' → KAYIP
      //
      // 24 saat açık ya da gece geç saatlere çalışan bir markette, gece
      // yarısından sonraki 3 saatlik satışlar "Gün Sonu Raporu"na hiç
      // girmiyordu. 'localtime' değiştiricisi SQLite'a cihazın kendi
      // saat dilimini kullanmasını söyler — POS cihazı zaten işletmenin
      // kendi lokasyonunda olduğu için bu doğru varsayımdır.
        "WHERE DATE(g.tarih) = DATE('now','localtime') AND g.deleted_at IS NULL ORDER BY g.tarih DESC",
      );
      return rows.map(GiderModel.fromMap).toList();
    } catch (e, st) {
      LogServisi().hata('Gider.metod', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> kategorileriGetir() async {
    try {
      final db = await _d;
      return await db.query('gider_kategoriler', orderBy: 'ad');
    } catch (e, st) {
      LogServisi().hata('Gider.metod', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<double> gunlukToplamGider() async {
    try {
      final db = await _d;
      final res = await db.rawQuery(
        "SELECT SUM(tutar) as toplam FROM giderler WHERE DATE(tarih) = DATE('now','localtime') AND deleted_at IS NULL",
      );
      return (res.first['toplam'] as num?)?.toDouble() ?? 0;
    } catch (e, st) {
      LogServisi().hata('Gider.gunlukToplamGider', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<Map<String, double>> aylikKategoriDagilimi() async {
    try {
      final db = await _d;
      final res = await db.rawQuery(
        "SELECT k.ad as kategori, SUM(g.tutar) as toplam "
        "FROM giderler g LEFT JOIN gider_kategoriler k ON g.kategori_id = k.id "
        "WHERE strftime('%Y-%m', g.tarih) = strftime('%Y-%m', 'now','localtime') AND g.deleted_at IS NULL "
        "GROUP BY g.kategori_id ORDER BY toplam DESC",
      );
      return {for (final r in res) (r['kategori'] as String? ?? ''): (r['toplam'] as num?)?.toDouble() ?? 0};
    } catch (e, st) {
      LogServisi().hata('Gider.metod', hata: e, yigin: st);
      rethrow;
    }
  }


  // aralikToplamGider - gün sonu raporu için eklendi
  Future<double> aralikToplamGider(DateTime bas, DateTime bit) async {
    try {
      final db = await _d;
      final res = await db.rawQuery(
        'SELECT SUM(tutar) as toplam FROM giderler WHERE datetime(tarih) BETWEEN datetime(?) AND datetime(?) AND deleted_at IS NULL',
        [bas.toIso8601String(), bit.toIso8601String()],
      );
      return (res.first['toplam'] as num?)?.toDouble() ?? 0;
    } catch (e, st) {
      LogServisi().hata('Gider.aralikToplamGider', hata: e, yigin: st);
      rethrow;
    }
  }
}
