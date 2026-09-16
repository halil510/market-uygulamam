// lib/depolar/birim_deposu.dart
//
// MASTER ERP DEEP AUDIT — Madde 2 (Mimari) sertleştirmesi: birim_ekrani.dart
// için hiç repository sınıfı yoktu — hem statik "birim listesi getir"
// yardımcıları hem ekle/düzenle/sil akışı doğrudan Veritabani().db
// üzerinden SQL çalıştırıyordu. Bu dosya o erişimi kapsar. Davranış
// BİREBİR korunmuştur; BirimEkrani.birimListesiGetir()/
// birimListesiCarpanliGetir() (başka ekranlarca da çağrılan public API)
// artık bu sınıfa delege ediyor, imzaları değişmedi.
import 'package:sqflite/sqflite.dart';
import '../servisler/bulut/bulut_manager.dart';
import '../veri/database/veritabani.dart';

class BirimDeposu {
  final Veritabani _db = Veritabani();
  Future<Database> get _d async => _db.db;

  static const List<String> varsayilanlar = [
    'ADET', 'KG', 'GR', 'LİTRE', 'ML', 'PAKET', 'KOLİ', 'KUTU', 'ÇIFT', 'METRE', 'M²',
  ];

  /// Varsayılan + kayıtlı (aktif) tüm birim adlarını döner.
  Future<List<String>> hepsiGetir() async {
    try {
      final db = await _d;
      final rows = await db.query('birimler', where: 'aktif = 1', columns: ['ad']);
      final kayitli = rows.map((r) => r['ad'] as String).toList();
      return {...varsayilanlar, ...kayitli}.toList()..sort();
    } catch (_) {
      return varsayilanlar.toList()..sort();
    }
  }

  /// Varsayılan + kayıtlı tüm birimleri (ad, çarpan) çiftleri olarak
  /// döner — kayıtlı olmayan birimler çarpan=1 varsayar.
  Future<List<(String ad, double carpan)>> hepsiCarpanliGetir() async {
    try {
      final db = await _d;
      final rows = await db.query('birimler', where: 'aktif = 1', columns: ['ad', 'carpan']);
      final kayitliMap = <String, double>{
        for (final r in rows) r['ad'] as String: (r['carpan'] as num?)?.toDouble() ?? 1,
      };
      final tumAdlar = {...varsayilanlar, ...kayitliMap.keys}.toList()..sort();
      return tumAdlar.map((ad) => (ad, kayitliMap[ad] ?? 1.0)).toList();
    } catch (_) {
      return varsayilanlar.map((ad) => (ad, 1.0)).toList();
    }
  }

  /// Yeni birim ekler — daha önce silinmiş (aktif=0) aynı adlı birim
  /// varsa geri aktifleştirir ('ad' UNIQUE olduğu için çakışmayı önler).
  Future<void> ekleVeyaAktifEt(String ad, double carpan) async {
    final db = await _d;
    final now = DateTime.now().toIso8601String();
    final mevcut = await db.query('birimler', where: 'ad = ?', whereArgs: [ad], limit: 1);
    if (mevcut.isNotEmpty) {
      await db.update('birimler', {'aktif': 1, 'carpan': carpan, 'last_updated': now},
          where: 'ad = ?', whereArgs: [ad]);
    } else {
      await db.insert('birimler', {'ad': ad, 'aktif': 1, 'carpan': carpan, 'last_updated': now});
    }
    final satir = await db.query('birimler', where: 'ad = ?', whereArgs: [ad], limit: 1);
    if (satir.isNotEmpty) {
      BulutManager().upsert('birimler', Map<String, dynamic>.from(satir.first));
    }
  }

  /// Bir birimin çarpanını günceller — satır henüz yoksa (varsayılan
  /// listeden, hiç db kaydı olmayan bir birim) oluşturur.
  Future<void> carpanGuncelle(String ad, double carpan) async {
    final db = await _d;
    final now = DateTime.now().toIso8601String();
    final mevcut = await db.query('birimler', where: 'ad = ?', whereArgs: [ad], limit: 1);
    if (mevcut.isNotEmpty) {
      await db.update('birimler', {'carpan': carpan, 'last_updated': now},
          where: 'ad = ?', whereArgs: [ad]);
    } else {
      await db.insert('birimler', {'ad': ad, 'aktif': 1, 'carpan': carpan, 'last_updated': now});
    }
    final satir = await db.query('birimler', where: 'ad = ?', whereArgs: [ad], limit: 1);
    if (satir.isNotEmpty) {
      BulutManager().upsert('birimler', Map<String, dynamic>.from(satir.first));
    }
  }

  /// Soft-delete (aktif=0).
  Future<void> sil(String ad) async {
    final db = await _d;
    final now = DateTime.now().toIso8601String();
    await db.update('birimler', {'aktif': 0, 'last_updated': now},
        where: 'ad = ?', whereArgs: [ad]);
    final satir = await db.query('birimler', where: 'ad = ?', whereArgs: [ad], limit: 1);
    if (satir.isNotEmpty) {
      BulutManager().upsert('birimler', Map<String, dynamic>.from(satir.first));
    }
  }
}
