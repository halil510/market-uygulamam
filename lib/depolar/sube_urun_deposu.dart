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

  /// Verilen (urun_id, sube_id) satırını TEK transaction içinde okuyup
  /// yazar — [stokDus]/[stokGir] içindeki "oku sonra yaz" adımını atomik
  /// yapmak için kullanılır.
  Future<void> _farkUygulaTxn(dynamic txn, int urunId, int subeId, double fark) async {
    final now = DateTime.now().toIso8601String();
    final rows = await txn.query('sube_urun',
        where: 'urun_id = ? AND sube_id = ?', whereArgs: [urunId, subeId], limit: 1);
    if (rows.isEmpty) {
      await txn.insert('sube_urun', {
        'global_id': const Uuid().v4(),
        'urun_id': urunId, 'sube_id': subeId,
        'stok': fark, 'son_guncelleme': now, 'last_updated': now,
      });
    } else {
      final mevcut = (rows.first['stok'] as num?)?.toDouble() ?? 0.0;
      await txn.update('sube_urun',
          {'stok': mevcut + fark, 'son_guncelleme': now, 'last_updated': now},
          where: 'urun_id = ? AND sube_id = ?', whereArgs: [urunId, subeId]);
    }
  }

  /// Şubedeki stoğu belirtilen miktar kadar AZALTIR (satış, iade-çıkış vb.).
  /// Negatife düşmesini engellemez (StokDeposu tarafında zaten kontrol
  /// ediliyor) — burada sadece o şubenin payı düşülür.
  ///
  /// 🔴 Derin analizde bulundu: önceden "oku (stokGetir) sonra yaz
  /// (stokAyarla)" transaction'sız yapılıyordu — aynı üründe aynı şubede
  /// neredeyse eş zamanlı iki satış birbirinin okuduğu değeri geçersiz
  /// kılabilir (lost update), sube_urun toplamı gerçek stoktan sapabilirdi.
  /// Artık okuma+yazma TEK transaction içinde.
  Future<void> stokDus(int urunId, int subeId, double miktar) async {
    try {
      final db = await _d;
      await db.transaction((txn) => _farkUygulaTxn(txn, urunId, subeId, -miktar));
      final satir = await satirGetir(urunId, subeId);
      if (satir != null) BulutManager().upsert('sube_urun', Map<String, dynamic>.from(satir));
    } catch (e, st) {
      LogServisi().hata('SubeUrun.stokDus', hata: e, yigin: st);
      rethrow;
    }
  }

  /// Şubedeki stoğu belirtilen miktar kadar ARTIRIR (alım, iade-giriş vb.).
  Future<void> stokGir(int urunId, int subeId, double miktar) async {
    try {
      final db = await _d;
      await db.transaction((txn) => _farkUygulaTxn(txn, urunId, subeId, miktar));
      final satir = await satirGetir(urunId, subeId);
      if (satir != null) BulutManager().upsert('sube_urun', Map<String, dynamic>.from(satir));
    } catch (e, st) {
      LogServisi().hata('SubeUrun.stokGir', hata: e, yigin: st);
      rethrow;
    }
  }

  /// Bir şubeden diğerine stok transferi (Depo Transfer ekranı için).
  /// Tek bir mantıksal işlem olarak hem kaynağı düşürür hem hedefi artırır.
  ///
  /// 🔴🔴 KRİTİK DÜZELTME (derin analizde bulundu): Önceden bu fonksiyon
  /// stokDus() + stokGir() çağırıyordu — ikisi de KENDİ AYRI
  /// transaction'ını açıyordu. Kaynağı düşüren işlem başarılı olup
  /// hedefi artıran işlem başarısız olursa (uygulama çökmesi, DB hatası
  /// vb.) ürün miktarı KAYNAKTA AZALMIŞ, HEDEFTE HİÇ ARTMAMIŞ — yani
  /// TAMAMEN KAYBOLMUŞ oluyordu. Protokol §9'un "stok hareketinden
  /// hesaplanan miktar ile gerçek miktar uyuşmalı" ilkesini doğrudan
  /// ihlal ediyordu. Artık her iki güncelleme TEK transaction'da.
  Future<void> transferEt({
    required int urunId,
    required int kaynakSubeId,
    required int hedefSubeId,
    required double miktar,
  }) async {
    if (miktar <= 0) throw Exception('Transfer miktarı sıfırdan büyük olmalı');
    final db = await _d;
    final now = DateTime.now().toIso8601String();

    Future<void> satirUpsertTxn(dynamic txn, int subeId, double yeniStok) async {
      final rows = await txn.query('sube_urun',
          where: 'urun_id = ? AND sube_id = ?', whereArgs: [urunId, subeId], limit: 1);
      if (rows.isEmpty) {
        await txn.insert('sube_urun', {
          'global_id': const Uuid().v4(),
          'urun_id': urunId, 'sube_id': subeId,
          'stok': yeniStok, 'son_guncelleme': now, 'last_updated': now,
        });
      } else {
        await txn.update('sube_urun',
            {'stok': yeniStok, 'son_guncelleme': now, 'last_updated': now},
            where: 'urun_id = ? AND sube_id = ?', whereArgs: [urunId, subeId]);
      }
    }

    await db.transaction((txn) async {
      final kaynakRows = await txn.query('sube_urun',
          where: 'urun_id = ? AND sube_id = ?', whereArgs: [urunId, kaynakSubeId], limit: 1);
      final kaynakStok = kaynakRows.isEmpty
          ? 0.0 : (kaynakRows.first['stok'] as num?)?.toDouble() ?? 0.0;
      if (kaynakStok < miktar) {
        throw Exception('Kaynak şubede yeterli stok yok (mevcut: $kaynakStok)');
      }

      final hedefRows = await txn.query('sube_urun',
          where: 'urun_id = ? AND sube_id = ?', whereArgs: [urunId, hedefSubeId], limit: 1);
      final hedefStok = hedefRows.isEmpty
          ? 0.0 : (hedefRows.first['stok'] as num?)?.toDouble() ?? 0.0;

      await satirUpsertTxn(txn, kaynakSubeId, kaynakStok - miktar);
      await satirUpsertTxn(txn, hedefSubeId, hedefStok + miktar);
    });

    // Bulut senkronu — transaction commit olduktan SONRA (bkz.
    // KasaDeposu.hareketEkleTxn'deki aynı gerekçe).
    try {
      final kaynakSatir = await satirGetir(urunId, kaynakSubeId);
      if (kaynakSatir != null) BulutManager().upsert('sube_urun', Map<String, dynamic>.from(kaynakSatir));
      final hedefSatir = await satirGetir(urunId, hedefSubeId);
      if (hedefSatir != null) BulutManager().upsert('sube_urun', Map<String, dynamic>.from(hedefSatir));
    } catch (e, st) {
      LogServisi().hata('SubeUrun.transferEt (bulut bildirimi)', hata: e, yigin: st);
    }
  }
}
