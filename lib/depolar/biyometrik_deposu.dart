// lib/depolar/biyometrik_deposu.dart
//
// Parmak izi ile giriş için cihaza özel, rastgele bir "biyometrik token"
// üretip doğrulayan depo. Kullanıcının GERÇEK şifresi hiçbir zaman burada
// ya da secure storage'da saklanmaz — sadece bu tokenın tuzlu hash'i,
// tamamen izole ve Supabase'e SENKRON EDİLMEYEN bir tabloda tutulur
// (bkz. migrasyon_yonetici.dart _v59denV60a). Ham token sadece
// FlutterSecureStorage'da (cihazda) kalır.
import 'dart:math' as math;
import 'package:sqflite/sqflite.dart';
import '../cekirdek/sabitler/db_sabitleri.dart';
import '../cekirdek/utils/sifre_hash.dart';
import '../veri/database/veritabani.dart';

class BiyometrikDeposu {
  final Veritabani _db = Veritabani();
  Future<Database> get _d async => _db.db;

  /// 256-bit rastgele, kriptografik olarak güvenli bir token üretir.
  static String tokenUret() {
    final rnd = math.Random.secure();
    final bytes = List<int>.generate(32, (_) => rnd.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Verilen kullanıcı için yeni bir biyometrik kayıt oluşturur (varsa
  /// önceki kayıt üzerine yazılır — aynı cihazda tek seferde tek kullanıcı
  /// için geçerli, mevcut davranışla birebir aynı sınırlama).
  Future<void> kaydet(int kullaniciId, String token) async {
    final db = await _d;
    final tuz = SifreHash.tuzUret();
    final hash = SifreHash.hashleTuzlu(token, tuz);
    await db.insert(
      DbSabitler.biyometrikKayitlari,
      {
        'kullanici_id': kullaniciId,
        'token_hash': hash,
        'tuz': tuz,
        'olusturma_tarihi': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Token'ı ilgili kullanıcının kayıtlı hash'iyle karşılaştırır.
  Future<bool> dogrula(int kullaniciId, String token) async {
    final db = await _d;
    final rows = await db.query(
      DbSabitler.biyometrikKayitlari,
      where: 'kullanici_id = ?',
      whereArgs: [kullaniciId],
    );
    if (rows.isEmpty) return false;
    final row = rows.first;
    final tuz = row['tuz'] as String;
    final kayitliHash = row['token_hash'] as String;
    return SifreHash.hashleTuzlu(token, tuz) == kayitliHash;
  }

  Future<void> sil(int kullaniciId) async {
    final db = await _d;
    await db.delete(
      DbSabitler.biyometrikKayitlari,
      where: 'kullanici_id = ?',
      whereArgs: [kullaniciId],
    );
  }
}
