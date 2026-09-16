// lib/depolar/donem_deposu.dart
// Yıl Sonu Devir / Dönem Kapatma / Arşivleme sistemi — FAZ 1 (2026-09-16,
// kullanıcı onaylı mimari plan raporu).
//
// Bu depo SADECE 'donemler' ve 'donem_sube_durumlari' tablolarının temel
// CRUD'unu sağlar — devir motoru mantığı (kontrol/backup/snapshot/açılış
// fazları) DevirYoneticiServisi'nde (İLERİKİ FAZ) yaşayacak. Diğer tüm
// depolarla AYNI desen: BulutManager ile yazma-sonrası bildirim,
// LogServisi ile hata yakalama.
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../cekirdek/sabitler/db_sabitleri.dart';
import '../modeller/donem_model.dart';
import '../servisler/bulut/bulut_manager.dart';
import '../servisler/log_servisi.dart';
import '../veri/database/veritabani.dart';

class DonemDeposu {
  final Veritabani _db = Veritabani();
  Future<Database> get _d async => _db.db;

  // ── Dönemler ────────────────────────────────────────────────────────

  /// Şu an AÇIK olan dönemi döner — bulunamazsa null (henüz hiç dönem
  /// oluşturulmamış olabilir, ör. uygulamanın ilk kurulumunda).
  Future<DonemModel?> aktifDonemGetir() async {
    try {
      final db = await _d;
      final rows = await db.query(DbSabitler.donemler,
          where: 'durum = ?',
          whereArgs: [DonemDurumu.acik],
          orderBy: 'donem_yili DESC',
          limit: 1);
      return rows.isEmpty ? null : DonemModel.fromMap(rows.first);
    } catch (e, st) {
      LogServisi().hata('DonemDeposu.aktifDonemGetir', hata: e, yigin: st);
      return null;
    }
  }

  Future<DonemModel?> yilaGoreGetir(int yil) async {
    try {
      final db = await _d;
      final rows = await db.query(DbSabitler.donemler,
          where: 'donem_yili = ?', whereArgs: [yil], limit: 1);
      return rows.isEmpty ? null : DonemModel.fromMap(rows.first);
    } catch (e, st) {
      LogServisi().hata('DonemDeposu.yilaGoreGetir', hata: e, yigin: st);
      return null;
    }
  }

  /// Geçmiş dönemler dahil TÜMÜ, en yeni yıl önce (Madde 26 — "Dönem
  /// Seçimi" listesi için).
  Future<List<DonemModel>> tumunuGetir() async {
    try {
      final db = await _d;
      final rows = await db.query(DbSabitler.donemler, orderBy: 'donem_yili DESC');
      return rows.map(DonemModel.fromMap).toList();
    } catch (e, st) {
      LogServisi().hata('DonemDeposu.tumunuGetir', hata: e, yigin: st);
      return [];
    }
  }

  /// Yeni bir dönem oluşturur (ör. uygulamanın ilk kurulumunda "bu yıl
  /// için dönem yok" durumunda otomatik, veya devir motorunun FAZ 8'inde
  /// hedef dönem olarak). [donemYili] için zaten bir kayıt varsa (UNIQUE
  /// kısıtı) hata fırlatır — çağıran önce [yilaGoreGetir] ile kontrol etmeli.
  Future<int> donemOlustur(DonemModel donem) async {
    try {
      final db = await _d;
      final data = donem.toMap();
      data['global_id'] ??= const Uuid().v4();
      final id = await db.insert(DbSabitler.donemler, data);
      final satir = await db.query(DbSabitler.donemler, where: 'id = ?', whereArgs: [id], limit: 1);
      if (satir.isNotEmpty) {
        BulutManager().upsert(DbSabitler.donemler, Map<String, dynamic>.from(satir.first));
      }
      return id;
    } catch (e, st) {
      LogServisi().hata('DonemDeposu.donemOlustur', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<void> donemGuncelle(DonemModel donem) async {
    if (donem.id == null) {
      throw ArgumentError('donemGuncelle: id gerekli (yeni dönem için donemOlustur kullanın)');
    }
    try {
      final db = await _d;
      await db.update(DbSabitler.donemler, donem.toMap(),
          where: 'id = ?', whereArgs: [donem.id]);
      final satir = await db.query(DbSabitler.donemler,
          where: 'id = ?', whereArgs: [donem.id], limit: 1);
      if (satir.isNotEmpty) {
        BulutManager().upsert(DbSabitler.donemler, Map<String, dynamic>.from(satir.first));
      }
    } catch (e, st) {
      LogServisi().hata('DonemDeposu.donemGuncelle', hata: e, yigin: st);
      rethrow;
    }
  }

  // ── Şube Durumları ──────────────────────────────────────────────────

  Future<List<DonemSubeDurumuModel>> subeDurumlariGetir(int donemId) async {
    try {
      final db = await _d;
      final rows = await db.query(DbSabitler.donemSubeDurumlari,
          where: 'donem_id = ?', whereArgs: [donemId]);
      return rows.map(DonemSubeDurumuModel.fromMap).toList();
    } catch (e, st) {
      LogServisi().hata('DonemDeposu.subeDurumlariGetir', hata: e, yigin: st);
      return [];
    }
  }

  /// [donemId] için, verilen TÜM [subeIdleri]'nde OPEN durumda birer
  /// şube-durum satırı garanti eder (yoksa oluşturur) — bir dönem
  /// açıldığında (veya ilk kez bir şube eklendiğinde) çağrılması beklenir.
  /// Idempotent: zaten var olan (donem_id, sube_id) çiftini atlar.
  Future<void> subeDurumlariniBaslat(int donemId, List<int> subeIdleri) async {
    try {
      final db = await _d;
      final mevcutlar = await db.query(DbSabitler.donemSubeDurumlari,
          columns: ['sube_id'], where: 'donem_id = ?', whereArgs: [donemId]);
      final mevcutSubeIdler = mevcutlar.map((r) => r['sube_id'] as int).toSet();
      for (final subeId in subeIdleri) {
        if (mevcutSubeIdler.contains(subeId)) continue;
        final data = DonemSubeDurumuModel(donemId: donemId, subeId: subeId).toMap();
        data['global_id'] = const Uuid().v4();
        final id = await db.insert(DbSabitler.donemSubeDurumlari, data);
        final satir = await db.query(DbSabitler.donemSubeDurumlari,
            where: 'id = ?', whereArgs: [id], limit: 1);
        if (satir.isNotEmpty) {
          BulutManager()
              .upsert(DbSabitler.donemSubeDurumlari, Map<String, dynamic>.from(satir.first));
        }
      }
    } catch (e, st) {
      LogServisi().hata('DonemDeposu.subeDurumlariniBaslat', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<void> subeDurumuGuncelle(DonemSubeDurumuModel durum) async {
    if (durum.id == null) {
      throw ArgumentError('subeDurumuGuncelle: id gerekli');
    }
    try {
      final db = await _d;
      await db.update(DbSabitler.donemSubeDurumlari, durum.toMap(),
          where: 'id = ?', whereArgs: [durum.id]);
      final satir = await db.query(DbSabitler.donemSubeDurumlari,
          where: 'id = ?', whereArgs: [durum.id], limit: 1);
      if (satir.isNotEmpty) {
        BulutManager()
            .upsert(DbSabitler.donemSubeDurumlari, Map<String, dynamic>.from(satir.first));
      }
    } catch (e, st) {
      LogServisi().hata('DonemDeposu.subeDurumuGuncelle', hata: e, yigin: st);
      rethrow;
    }
  }

  /// Madde 29: "Genel şirket dönemi ancak bütün gerekli şubeler
  /// tamamlandığında kapanabilir." — DevirYoneticiServisi'nin FAZ 9'da
  /// (dönem kapanışı) bu kontrolü yapması beklenir.
  Future<bool> tumSubelerKapandiMi(int donemId) async {
    try {
      final db = await _d;
      final rows = await db.query(DbSabitler.donemSubeDurumlari,
          where: 'donem_id = ? AND durum NOT IN (?, ?)',
          whereArgs: [donemId, DonemDurumu.kapali, DonemDurumu.arsivlendi]);
      return rows.isEmpty;
    } catch (e, st) {
      LogServisi().hata('DonemDeposu.tumSubelerKapandiMi', hata: e, yigin: st);
      // Emin olunamazsa güvenli tarafta kalınır — "kapanmadı" say.
      return false;
    }
  }
}
