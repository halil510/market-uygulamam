// lib/depolar/sube_urun_deposu.dart
//
// Şube bazlı stok deposu — 'sube_urun' tablosu şemada ÖNCEDEN vardı
// (global_id bile v14→v15'te eklenmişti) ama hiçbir depo/servis onu
// kullanmıyordu; tamamen atıl bir özellikti. Bu dosya, o tabloyu
// gerçekten kullanılabilir hale getirir.
//
// ÖNEMLİ TASARIM KARARI (güvenlik/uyumluluk için): urunler.stok alanı
// KALDIRILMADI — TOPLAM (tüm şubelerin toplamı) stok olarak korunuyor.
// Mevcut onlarca ekran/rapor zaten urunler.stok'u "toplam stok" olarak
// okuyor; bunu kaldırmak devasa ve riskli bir değişiklik olurdu. Bunun
// yerine, sube_urun EK bir katman olarak devreye giriyor: StokDeposu
// artık HEM urunler.stok'u (toplam) HEM sube_urun'u (o anki aktif
// şubenin payını) güncelliyor. Böylece:
//   - Mevcut hiçbir ekran/rapor bozulmaz (urunler.stok hâlâ doğru toplamı verir)
//   - Yeni ekranlar/raporlar artık ürün+şube bazında GERÇEK stok görebilir
//
// NOT: 'sube_urun' tablosunun ayrı bir 'id' sütunu YOKTUR — birleşik
// anahtarı (urun_id, sube_id)'dir. Bu yüzden bu depodaki her fonksiyon
// sorgularını 'id' değil bu birleşik anahtara göre yapar.
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../veri/database/veritabani.dart';
import '../servisler/bulut/bulut_manager.dart';
import '../servisler/log_servisi.dart';

class SubeUrunDeposu {
  final Veritabani _db = Veritabani();
  Future<Database> get _d async => _db.db;

  /// Bir ürünün belirli bir şubedeki satırını getirir (yoksa null).
  Future<Map<String, dynamic>?> satirGetir(int urunId, int subeId) async {
    final db = await _d;
    final rows = await db.query('sube_urun',
        where: 'urun_id = ? AND sube_id = ?', whereArgs: [urunId, subeId], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  /// Bir ürünün belirli bir şubedeki GÜNCEL stok miktarını getirir.
  /// Satır hiç yoksa (bu ürün o şubede hiç hareket görmemiş) 0 döner.
  Future<double> stokGetir(int urunId, int subeId) async {
    final satir = await satirGetir(urunId, subeId);
    return (satir?['stok'] as num?)?.toDouble() ?? 0;
  }

  /// Bir ürünün TÜM şubelerdeki stok dağılımını getirir (şube adıyla
  /// birlikte) — ürün detay ekranında "şube bazlı stok" göstermek için.
  Future<List<Map<String, dynamic>>> tumSubelerdekiStok(int urunId) async {
    final db = await _d;
    return db.rawQuery('''
      SELECT su.*, s.sube_adi
      FROM sube_urun su
      JOIN subeler s ON s.id = su.sube_id
      WHERE su.urun_id = ? AND s.is_deleted = 0 AND s.aktif = 1
      ORDER BY s.sube_adi ASC
    ''', [urunId]);
  }

  /// Verilen şubede stoğu MUTLAK bir değere ayarlar (satır yoksa oluşturur).
  /// stokDus/stokGir bu fonksiyonun üzerine inşa edilir.
  Future<void> stokAyarla(int urunId, int subeId, double yeniMiktar) async {
    try {
      final db = await _d;
      final now = DateTime.now().toIso8601String();
      final mevcut = await satirGetir(urunId, subeId);
      if (mevcut == null) {
        await db.insert('sube_urun', {
          'global_id': const Uuid().v4(),
          'urun_id': urunId, 'sube_id': subeId,
          'stok': yeniMiktar,
          'son_guncelleme': now, 'last_updated': now,
        });
      } else {
        await db.update('sube_urun',
            {'stok': yeniMiktar, 'son_guncelleme': now, 'last_updated': now},
            where: 'urun_id = ? AND sube_id = ?', whereArgs: [urunId, subeId]);
      }
      final satir = await satirGetir(urunId, subeId);
      if (satir != null) BulutManager().upsert('sube_urun', Map<String, dynamic>.from(satir));
    } catch (e, st) {
      LogServisi().hata('SubeUrun.stokAyarla', hata: e, yigin: st);
      rethrow;
    }
  }

  /// Şubedeki stoğu belirtilen miktar kadar AZALTIR (satış, iade-çıkış vb.).
  /// Negatife düşmesini engellemez (StokDeposu tarafında zaten kontrol
  /// ediliyor) — burada sadece o şubenin payı düşülür.
  Future<void> stokDus(int urunId, int subeId, double miktar) async {
    final mevcut = await stokGetir(urunId, subeId);
    await stokAyarla(urunId, subeId, mevcut - miktar);
  }

  /// Şubedeki stoğu belirtilen miktar kadar ARTIRIR (alım, iade-giriş vb.).
  Future<void> stokGir(int urunId, int subeId, double miktar) async {
    final mevcut = await stokGetir(urunId, subeId);
    await stokAyarla(urunId, subeId, mevcut + miktar);
  }

  /// Bir şubeden diğerine stok transferi (Depo Transfer ekranı için).
  /// Tek bir mantıksal işlem olarak hem kaynağı düşürür hem hedefi artırır.
  Future<void> transferEt({
    required int urunId,
    required int kaynakSubeId,
    required int hedefSubeId,
    required double miktar,
  }) async {
    if (miktar <= 0) throw Exception('Transfer miktarı sıfırdan büyük olmalı');
    final kaynakStok = await stokGetir(urunId, kaynakSubeId);
    if (kaynakStok < miktar) {
      throw Exception('Kaynak şubede yeterli stok yok (mevcut: $kaynakStok)');
    }
    await stokDus(urunId, kaynakSubeId, miktar);
    await stokGir(urunId, hedefSubeId, miktar);
  }
}
