// lib/depolar/devir_checkpoint_deposu.dart
// Yıl Sonu Devir motoru — 10 fazlı, resumable state-machine deposu
// (FAZ 1, 2026-09-16, kullanıcı onaylı mimari plan raporu).
//
// Bu depo SADECE devir_checkpoint satırlarının CRUD + idempotent
// get-or-create'ini sağlar. Fazların KENDİSİ (kontrol/backup/snapshot/
// açılış/doğrulama) DevirYoneticiServisi'nde (İLERİKİ FAZ) yaşayacak.
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../cekirdek/sabitler/db_sabitleri.dart';
import '../modeller/devir_checkpoint_model.dart';
import '../servisler/bulut/bulut_manager.dart';
import '../servisler/log_servisi.dart';
import '../veri/database/veritabani.dart';

class DevirCheckpointDeposu {
  final Veritabani _db = Veritabani();
  Future<Database> get _d async => _db.db;

  /// [kaynakDonemId]→[hedefDonemId] (ve [subeId], 0 = şirket geneli)
  /// için TAMAMLANMAMIŞ bir checkpoint var mı? Varsa onu döner (Madde
  /// 17: "işlem yarıda kalsa dahi kaldığı yerden devam edebilmeli").
  Future<DevirCheckpointModel?> acikCheckpointGetir({
    required int kaynakDonemId,
    required int hedefDonemId,
    int subeId = 0,
  }) async {
    try {
      final db = await _d;
      final rows = await db.query(DbSabitler.devirCheckpoint,
          where: 'kaynak_donem_id = ? AND hedef_donem_id = ? AND sube_id = ? '
              'AND durum NOT IN (?, ?)',
          whereArgs: [
            kaynakDonemId,
            hedefDonemId,
            subeId,
            DevirDurumu.completed,
            DevirDurumu.failed,
          ],
          limit: 1);
      return rows.isEmpty ? null : DevirCheckpointModel.fromMap(rows.first);
    } catch (e, st) {
      LogServisi().hata('DevirCheckpointDeposu.acikCheckpointGetir', hata: e, yigin: st);
      return null;
    }
  }

  /// Madde 28 (idempotency): aynı kaynak→hedef (+şube) için TAMAMLANMIŞ
  /// bir checkpoint zaten varsa onu döner — YENİ bir devir başlatmaz.
  /// Yarıda kalmış (COMPLETED/FAILED dışı) bir checkpoint varsa onu
  /// döner (resume). Hiçbiri yoksa yeni bir INIT kaydı oluşturur.
  Future<DevirCheckpointModel> checkpointOlusturVeyaGetir({
    required int kaynakDonemId,
    required int hedefDonemId,
    int subeId = 0,
  }) async {
    final db = await _d;
    final tamamlanmis = await db.query(DbSabitler.devirCheckpoint,
        where: 'kaynak_donem_id = ? AND hedef_donem_id = ? AND sube_id = ? AND durum = ?',
        whereArgs: [kaynakDonemId, hedefDonemId, subeId, DevirDurumu.completed],
        limit: 1);
    if (tamamlanmis.isNotEmpty) return DevirCheckpointModel.fromMap(tamamlanmis.first);

    final acik = await acikCheckpointGetir(
        kaynakDonemId: kaynakDonemId, hedefDonemId: hedefDonemId, subeId: subeId);
    if (acik != null) return acik;

    try {
      final now = DateTime.now();
      final model = DevirCheckpointModel(
        globalId: const Uuid().v4(),
        devirId: const Uuid().v4(),
        kaynakDonemId: kaynakDonemId,
        hedefDonemId: hedefDonemId,
        subeId: subeId,
        baslangicZamani: now,
      );
      final id = await db.insert(DbSabitler.devirCheckpoint, model.toMap());
      final satir = await db.query(DbSabitler.devirCheckpoint,
          where: 'id = ?', whereArgs: [id], limit: 1);
      if (satir.isNotEmpty) {
        BulutManager().upsert(DbSabitler.devirCheckpoint, Map<String, dynamic>.from(satir.first));
      }
      return DevirCheckpointModel.fromMap(satir.first);
    } catch (e, st) {
      LogServisi().hata('DevirCheckpointDeposu.checkpointOlusturVeyaGetir', hata: e, yigin: st);
      rethrow;
    }
  }

  /// Bir fazın SONUNDA çağrılmalı — 'mevcut_faz'ı sadece iş bittikten
  /// SONRA ilerletmek, yarım kalan bir fazın bir sonraki çalıştırmada
  /// BAŞTAN (idempotent şekilde) tekrar denenmesini garanti eder.
  Future<void> guncelle(DevirCheckpointModel checkpoint) async {
    if (checkpoint.id == null) {
      throw ArgumentError('guncelle: id gerekli (yeni checkpoint için checkpointOlusturVeyaGetir kullanın)');
    }
    try {
      final db = await _d;
      final data = checkpoint.toMap();
      data['son_guncelleme'] = DateTime.now().toIso8601String();
      await db.update(DbSabitler.devirCheckpoint, data,
          where: 'id = ?', whereArgs: [checkpoint.id]);
      final satir = await db.query(DbSabitler.devirCheckpoint,
          where: 'id = ?', whereArgs: [checkpoint.id], limit: 1);
      if (satir.isNotEmpty) {
        BulutManager().upsert(DbSabitler.devirCheckpoint, Map<String, dynamic>.from(satir.first));
      }
    } catch (e, st) {
      LogServisi().hata('DevirCheckpointDeposu.guncelle', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<List<DevirCheckpointModel>> tumunuGetir({int? kaynakDonemId}) async {
    try {
      final db = await _d;
      final rows = await db.query(DbSabitler.devirCheckpoint,
          where: kaynakDonemId != null ? 'kaynak_donem_id = ?' : null,
          whereArgs: kaynakDonemId != null ? [kaynakDonemId] : null,
          orderBy: 'baslangic_zamani DESC');
      return rows.map(DevirCheckpointModel.fromMap).toList();
    } catch (e, st) {
      LogServisi().hata('DevirCheckpointDeposu.tumunuGetir', hata: e, yigin: st);
      return [];
    }
  }
}
