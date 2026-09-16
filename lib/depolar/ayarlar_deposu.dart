// lib/depolar/ayarlar_deposu.dart
//
// MASTER ERP DEEP AUDIT — Madde 2 (Mimari) sertleştirmesi: 'ayarlar'
// (basit anahtar/değer) tablosunun CRUD'u 5 AYRI ekranda
// (yedekleme_ekrani, fis_tasarim_ekrani, yazici_ayar_ekrani,
// ayarlar_ekrani, gib_ayar_ekrani) birbirinden habersiz, neredeyse
// birebir aynı kodla tekrarlanıyordu — her biri kendi
// "INSERT OR REPLACE + BulutManager bildir" kopyasına sahipti. Bu dosya
// tek doğruluk kaynağıdır; davranış (anahtar PRIMARY KEY olduğu için
// INSERT OR REPLACE, ardından last_updated'lı satırı buluta bildirme)
// BİREBİR korunmuştur.
import 'package:sqflite/sqflite.dart';
import '../servisler/bulut/bulut_manager.dart';
import '../veri/database/veritabani.dart';

class AyarlarDeposu {
  final Veritabani _db = Veritabani();
  Future<Database> get _d async => _db.db;

  /// Tek bir ayarın değerini okur — yoksa null.
  Future<String?> getir(String anahtar) async {
    final db = await _d;
    final rows = await db.query('ayarlar',
        where: 'anahtar = ?', whereArgs: [anahtar], limit: 1);
    return rows.isNotEmpty ? rows.first['deger'] as String? : null;
  }

  /// Belirtilen anahtarların değerlerini tek sorguda {anahtar: değer}
  /// olarak döner — bir ekranın ihtiyaç duyduğu birkaç ayarı toplu
  /// okumak için (fiş tasarımı, yazıcı ayarı, GİB ayarı ekranlarındaki
  /// kullanım deseni).
  Future<Map<String, String>> coguGetir(List<String> anahtarlar) async {
    if (anahtarlar.isEmpty) return {};
    final db = await _d;
    final ph = anahtarlar.map((_) => '?').join(',');
    final rows = await db.query('ayarlar',
        where: 'anahtar IN ($ph)', whereArgs: anahtarlar);
    return {
      for (final r in rows) r['anahtar'] as String: r['deger'] as String? ?? ''
    };
  }

  /// TÜM ayarları {anahtar: değer} olarak döner (ana Ayarlar ekranı).
  Future<Map<String, String>> hepsiGetir() async {
    final db = await _d;
    final rows = await db.query('ayarlar');
    return {
      for (final r in rows) r['anahtar'] as String: r['deger']?.toString() ?? ''
    };
  }

  /// Tek bir ayarı ekler/günceller (anahtar PRIMARY KEY olduğu için
  /// INSERT OR REPLACE ile) ve buluta bildirir.
  Future<void> kaydet(String anahtar, String deger) async {
    final db = await _d;
    final now = DateTime.now().toIso8601String();
    await db.rawInsert(
      'INSERT OR REPLACE INTO ayarlar(anahtar, deger, guncelleme, last_updated) VALUES(?,?,?,?)',
      [anahtar, deger, now, now],
    );
    final satir = await db.query('ayarlar',
        where: 'anahtar = ?', whereArgs: [anahtar], limit: 1);
    if (satir.isNotEmpty) {
      BulutManager().upsert('ayarlar', Map<String, dynamic>.from(satir.first));
    }
  }

  /// Birden fazla ayarı sırayla kaydeder (her biri kendi PRIMARY KEY
  /// satırı olduğu için tek transaction gerektirmez — [kaydet] ile
  /// aynı garanti: her anahtar kendi başına atomik).
  Future<void> topluKaydet(Map<String, String> ayarlar) async {
    for (final e in ayarlar.entries) {
      await kaydet(e.key, e.value);
    }
  }
}
