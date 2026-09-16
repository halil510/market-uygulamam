// lib/depolar/cari_adres_deposu.dart
//
// MASTER ERP DEEP AUDIT — Madde 2 (Mimari) sertleştirmesi: 'cari_adres'
// tablosunun TÜM CRUD'u iki AYRI ekranda (cari_ekle_ekrani.dart —
// varsayılan/fatura adresi; toptan/cari_detay_paneli.dart — çoklu
// sevkiyat adresi) doğrudan Veritabani().db üzerinden, dedike bir
// repository olmadan yapılıyordu. Bu dosya ikisini de kapsar; davranış
// BİREBİR korunmuştur.
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../servisler/bulut/bulut_manager.dart';
import '../veri/database/veritabani.dart';

class CariAdresDeposu {
  final Veritabani _db = Veritabani();
  Future<Database> get _d async => _db.db;

  /// Bir cariye ait TÜM adresleri (varsayılan önce) döner — sevkiyat
  /// adresleri listesi için.
  Future<List<Map<String, dynamic>>> hepsiGetir(int cariId) async {
    final db = await _d;
    final rows = await db.query('cari_adres',
        where: 'cari_id = ?', whereArgs: [cariId], orderBy: 'varsayilan DESC');
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  /// Varsayılan (Fatura) adresi döner — cari formunda önceden dolu
  /// göstermek için.
  Future<Map<String, dynamic>?> varsayilanAdresGetir(int cariId) async {
    final db = await _d;
    final rows = await db.query('cari_adres',
        where: 'cari_id = ?', whereArgs: [cariId],
        orderBy: 'varsayilan DESC', limit: 1);
    return rows.isNotEmpty ? Map<String, dynamic>.from(rows.first) : null;
  }

  /// Varsayılan (Fatura) adresi ekler/günceller (UPSERT) — cari
  /// formundaki tek adres alanı için. Tüm alanlar boşsa hiçbir şey
  /// yazmaz (mevcut davranış).
  Future<void> varsayilanAdresKaydet({
    required int cariId,
    required String adres,
    String? il,
    String? ilce,
    String? postaKodu,
  }) async {
    if (adres.isEmpty &&
        (il == null || il.isEmpty) &&
        (ilce == null || ilce.isEmpty) &&
        (postaKodu == null || postaKodu.isEmpty)) {
      return;
    }
    final db = await _d;
    final mevcut = await db.query('cari_adres',
        where: 'cari_id = ? AND varsayilan = 1', whereArgs: [cariId], limit: 1);
    final data = <String, dynamic>{
      'cari_id': cariId,
      'adres_tipi': 'Fatura',
      'adres': adres,
      'il': (il == null || il.isEmpty) ? null : il,
      'ilce': (ilce == null || ilce.isEmpty) ? null : ilce,
      'posta_kodu': (postaKodu == null || postaKodu.isEmpty) ? null : postaKodu,
      'varsayilan': 1,
      'last_updated': DateTime.now().toIso8601String(),
    };
    if (mevcut.isNotEmpty) {
      await db.update('cari_adres', data,
          where: 'id = ?', whereArgs: [mevcut.first['id']]);
    } else {
      data['global_id'] = const Uuid().v4();
      await db.insert('cari_adres', data);
    }
    final satir = await db.query('cari_adres',
        where: 'cari_id = ? AND varsayilan = 1', whereArgs: [cariId], limit: 1);
    if (satir.isNotEmpty) {
      BulutManager().upsert('cari_adres', Map<String, dynamic>.from(satir.first));
    }
  }

  /// Yeni bir sevkiyat/fatura/depo adresi ekler.
  Future<void> ekle({
    required int cariId,
    required String adresTipi,
    required String adres,
    String? il,
    String? ilce,
    required bool varsayilanMi,
  }) async {
    final db = await _d;
    final now = DateTime.now().toIso8601String();
    final id = await db.insert('cari_adres', {
      'global_id': const Uuid().v4(),
      'cari_id': cariId,
      'adres_tipi': adresTipi,
      'adres': adres,
      'ilce': (ilce == null || ilce.isEmpty) ? null : ilce,
      'il': (il == null || il.isEmpty) ? null : il,
      'varsayilan': varsayilanMi ? 1 : 0,
      'last_updated': now,
    });
    final satir = await db.query('cari_adres', where: 'id = ?', whereArgs: [id], limit: 1);
    if (satir.isNotEmpty) {
      BulutManager().upsert('cari_adres', Map<String, dynamic>.from(satir.first));
    }
  }

  /// Bir adresi siler.
  ///
  /// 🔴 DÜZELTME (bu refactor sırasında bulundu): 'cari_adres' tablosunda
  /// 'is_deleted' sütunu YOK (hard-delete tablosu) — eski kod sildikten
  /// sonra BulutManager'ı hiç çağırmıyordu. Sonuç: silme buluta hiç
  /// bildirilmiyordu; bir sonraki tam "buluttan al" senkronunda bu satır
  /// bulutta hâlâ durduğu için YEREL olarak GERİ GELİYORDU (resurrection)
  /// — projede daha önce başka tablolarda bulunan "hard delete + bildirim
  /// yok" hata sınıfının aynısı. Artık silmeden önce global_id okunup
  /// BulutManager().sil() ile bildiriliyor.
  Future<void> sil(int id) async {
    final db = await _d;
    final satir = await db.query('cari_adres',
        columns: ['global_id'], where: 'id = ?', whereArgs: [id], limit: 1);
    final globalId = satir.isNotEmpty ? satir.first['global_id']?.toString() : null;
    await db.delete('cari_adres', where: 'id = ?', whereArgs: [id]);
    if (globalId != null && globalId.isNotEmpty) {
      BulutManager().sil('cari_adres', globalId);
    }
  }
}
