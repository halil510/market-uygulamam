// lib/depolar/donem_kilit_deposu.dart
// Yıl Sonu Devir — çoklu cihaz kilidi (2026-09-21, kullanıcı onayı, FAZ
// 4). Aynı (donem_id, sube_id) çiftinin İKİ cihazdan eşzamanlı devir
// almasını önler — lease (kiralama) tabanlı: kilit süresiz değil, bir
// TTL'den eski kalırsa (cihaz çökmüş/ağ kopmuş) başka bir cihaz
// devralabilir, uygulama sonsuza dek kilitli kalmaz.
//
// Basit, tek amaçlı bir kayıt olduğu için (kullanıcıya listelenen bir
// ekran yok) ayrı bir model sınıfı yerine doğrudan Map ile çalışıyor —
// diğer basit/iç depolarla (ör. sync_cakisma_deposu) aynı desen.
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../servisler/log_servisi.dart';
import '../veri/database/veritabani.dart';

class DonemKilitDeposu {
  final Veritabani _db = Veritabani();
  Future<Database> get _d async => _db.db;

  static const _varsayilanTtl = Duration(minutes: 5);

  /// Kilidi almayı dener. Döner:
  /// - true: kilit BU cihazda (yeni alındı, zaten bu cihazdaydı, veya
  ///   eski sahibi TTL'i aştığı için devralındı).
  /// - false: kilit BAŞKA bir cihazda VE hâlâ taze (devir başlatılamaz).
  Future<bool> kilitAl({
    required int donemId,
    required int subeId,
    required String cihazId,
    Duration ttl = _varsayilanTtl,
  }) async {
    try {
      final db = await _d;
      final now = DateTime.now();
      return await db.transaction((txn) async {
        final mevcut = await txn.query('donem_kilit',
            where: 'donem_id = ? AND sube_id = ?',
            whereArgs: [donemId, subeId],
            limit: 1);

        if (mevcut.isEmpty) {
          await txn.insert('donem_kilit', {
            'global_id': const Uuid().v4(),
            'donem_id': donemId,
            'sube_id': subeId,
            'cihaz_id': cihazId,
            'kilit_zamani': now.toIso8601String(),
            'son_yenileme': now.toIso8601String(),
            'last_updated': now.toIso8601String(),
          });
          return true;
        }

        final satir = mevcut.first;
        final sahipCihaz = satir['cihaz_id'] as String?;
        final sonYenileme =
            DateTime.tryParse(satir['son_yenileme'] as String? ?? '');
        final taze =
            sonYenileme != null && now.difference(sonYenileme) < ttl;

        if (sahipCihaz == cihazId) {
          // Aynı cihaz — resumable devir (Madde 17/27) kaldığı yerden
          // devam ediyor olabilir, kilidi yeniler.
          await txn.update(
              'donem_kilit',
              {
                'son_yenileme': now.toIso8601String(),
                'last_updated': now.toIso8601String()
              },
              where: 'id = ?',
              whereArgs: [satir['id']]);
          return true;
        }

        if (taze) {
          return false; // başka bir cihaz aktif olarak devir alıyor
        }

        // Stale (TTL aşılmış) — devral.
        await txn.update(
            'donem_kilit',
            {
              'cihaz_id': cihazId,
              'kilit_zamani': now.toIso8601String(),
              'son_yenileme': now.toIso8601String(),
              'last_updated': now.toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [satir['id']]);
        return true;
      });
    } catch (e, st) {
      LogServisi().hata('DonemKilitDeposu.kilitAl', hata: e, yigin: st);
      // Kilit mekanizması kendisi bozulursa devri TAMAMEN engellemek
      // yerine (yeni bir kullanılamazlık riski yaratmak) izin ver —
      // best-effort koruma, devir motorunun kendi checkpoint/idempotency
      // güvenceleri (Madde 28) hâlâ devrede.
      return true;
    }
  }

  /// Kilidi bırakır — SADECE bu cihaz sahipse siler (başka bir cihazın
  /// kilidini yanlışlıkla düşürmez).
  Future<void> kilitBirak({
    required int donemId,
    required int subeId,
    required String cihazId,
  }) async {
    try {
      final db = await _d;
      await db.delete('donem_kilit',
          where: 'donem_id = ? AND sube_id = ? AND cihaz_id = ?',
          whereArgs: [donemId, subeId, cihazId]);
    } catch (e, st) {
      LogServisi().hata('DonemKilitDeposu.kilitBirak', hata: e, yigin: st);
    }
  }
}
