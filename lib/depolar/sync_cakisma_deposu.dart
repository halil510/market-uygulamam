// lib/depolar/sync_cakisma_deposu.dart
//
// NOT: sync_cakismalar tablosu KASITLI OLARAK buluta senkronize EDİLMİYOR
// (global_id yok, BulutManager çağrılmıyor) — bu, çakışmayı YAŞAYAN
// cihazın yerel bir denetim/inceleme kaydıdır, iş verisi değildir.
import 'package:sqflite/sqflite.dart';
import '../cekirdek/sabitler/db_sabitleri.dart';
import '../modeller/sync_cakisma_model.dart';
import '../servisler/log_servisi.dart';
import '../veri/database/veritabani.dart';

class SyncCakismaDeposu {
  final Veritabani _db = Veritabani();
  Future<Database> get _d async => _db.db;

  Future<int> ekle(SyncCakismaModel c) async {
    try {
      final db = await _d;
      final m = c.toMap()..remove('id');
      return await db.insert(DbSabitler.syncCakismalar, m);
    } catch (e, st) {
      LogServisi().hata('SyncCakismaDeposu.ekle', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<List<SyncCakismaModel>> listele({bool sadeceCozulmemis = true, int limit = 200}) async {
    try {
      final db = await _d;
      final rows = await db.query(
        DbSabitler.syncCakismalar,
        where: sadeceCozulmemis ? 'cozuldu = 0' : null,
        orderBy: 'tarih DESC',
        limit: limit,
      );
      return rows.map(SyncCakismaModel.fromMap).toList();
    } catch (e, st) {
      LogServisi().hata('SyncCakismaDeposu.listele', hata: e, yigin: st);
      return [];
    }
  }

  Future<int> cozulmemisSayisi() async {
    try {
      final db = await _d;
      final rows = await db.rawQuery(
          'SELECT COUNT(*) as n FROM ${DbSabitler.syncCakismalar} WHERE cozuldu = 0');
      return (rows.first['n'] as int?) ?? 0;
    } catch (e, st) {
      LogServisi().hata('SyncCakismaDeposu.cozulmemisSayisi', hata: e, yigin: st);
      return 0;
    }
  }

  /// Çakışmayı "gelen" (buluttan gelen) değerle çözer.
  ///
  /// 🔴 FAZ 3 (madde 4, 2026-09-21): ÖNCEDEN bu fonksiyon veriye hiç
  /// dokunmuyordu — TÜM tablolarda LWW zaten otomatik uygulanmış
  /// olduğu varsayılıyordu, burası sadece kaydı "çözüldü" işaretliyordu.
  /// Artık "işlem verisi" tablolarında (bkz. SyncCakismaTespit.
  /// islemVerisiMi) Veritabani.supaKayitlariGuncelle() gerçek bir
  /// çakışmada otomatik üzerine YAZMIYOR — yani gelen_kayit henüz hiç
  /// uygulanmamış olabilir. Bu fonksiyon artık [yerelIleCoz] ile AYNI
  /// desende, gelen_kayit'i gerçekten tabloya yazıyor. "Master veri"
  /// tablolarında (LWW zaten uygulanmıştı) bu, AYNI içeriği tekrar
  /// yazmak anlamına gelir — zararsız (idempotent).
  Future<void> gelenIleCoz(int id, {required String kullanici}) async {
    final db = await _d;
    final rows = await db.query(DbSabitler.syncCakismalar, where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return;
    final c = SyncCakismaModel.fromMap(rows.first);
    if (c.gelenKayit != null && c.kayitGlobalId != null) {
      final uygulanacak = Map<String, dynamic>.from(c.gelenKayit!);
      uygulanacak.remove('id');
      await db.update(c.tablo, uygulanacak,
          where: 'global_id = ?', whereArgs: [c.kayitGlobalId]);
    }
    await _cozumIsaretle(id, tip: 'gelen', kullanici: kullanici);
  }

  /// Çakışmayı "yerel" (üzerine yazılmadan önceki) değerle çözer —
  /// kaydedilmiş eski satırı ilgili tabloya GERİ YAZAR ve kaydı kapatır.
  Future<void> yerelIleCoz(int id, {required String kullanici}) async {
    final db = await _d;
    final rows = await db.query(DbSabitler.syncCakismalar, where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return;
    final c = SyncCakismaModel.fromMap(rows.first);
    if (c.yerelKayit != null && c.kayitGlobalId != null) {
      final geriYazilacak = Map<String, dynamic>.from(c.yerelKayit!);
      geriYazilacak.remove('id');
      // Geri yazılan kayıt "şimdi" değiştirilmiş sayılsın ki bir sonraki
      // pull'da tekrar eski (gelen) değerle ezilmesin.
      geriYazilacak['last_updated'] = DateTime.now().toIso8601String();
      await db.update(c.tablo, geriYazilacak,
          where: 'global_id = ?', whereArgs: [c.kayitGlobalId]);
    }
    await _cozumIsaretle(id, tip: 'yerel', kullanici: kullanici);
  }

  /// Manuel düzenleme sonrası (kullanıcı ilgili kaydı kendi ekranından
  /// düzenledi) — sadece kaydı kapatır, veriye dokunmaz.
  Future<void> manuelCoz(int id, {required String kullanici}) =>
      _cozumIsaretle(id, tip: 'manuel', kullanici: kullanici);

  Future<void> _cozumIsaretle(int id, {required String tip, required String kullanici}) async {
    try {
      final db = await _d;
      await db.update(
        DbSabitler.syncCakismalar,
        {
          'cozuldu': 1,
          'cozum_tipi': tip,
          'cozen_kullanici': kullanici,
          'cozum_tarihi': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e, st) {
      LogServisi().hata('SyncCakismaDeposu._cozumIsaretle', hata: e, yigin: st);
      rethrow;
    }
  }
}
