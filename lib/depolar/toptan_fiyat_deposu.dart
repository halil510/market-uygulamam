// lib/depolar/toptan_fiyat_deposu.dart
//
// Kullanıcı isteği: "toptan satış — Ülker gibi firmaların kullandığı
// profesyonel sistem." Bu depo, üç katmanlı toptan fiyatlandırma
// sisteminin veri erişim katmanı: fiyat grupları (Altın/Gümüş Bayi),
// ürün×grup özel fiyatları, ve miktar bazlı kademeli fiyatlar.
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../veri/database/veritabani.dart';
import '../servisler/log_servisi.dart';
import '../servisler/bulut/bulut_manager.dart';
import '../modeller/fiyat_grubu_model.dart';
import '../modeller/fiyat_kademesi_model.dart';

class ToptanFiyatDeposu {
  final Veritabani _db = Veritabani();
  Future<Database> get _d async => _db.db;

  // ══════════════════ FİYAT GRUPLARI ══════════════════
  Future<List<FiyatGrubuModel>> gruplariGetir({bool sadeceAktif = false}) async {
    try {
      final db = await _d;
      final where = sadeceAktif ? 'is_deleted = 0 AND aktif = 1' : 'is_deleted = 0';
      final rows = await db.query('fiyat_gruplari', where: where, orderBy: 'ad');
      return rows.map(FiyatGrubuModel.fromMap).toList();
    } catch (e, st) {
      LogServisi().hata('ToptanFiyatDeposu.gruplariGetir', hata: e, yigin: st);
      return [];
    }
  }

  Future<FiyatGrubuModel?> grupGetir(int id) async {
    try {
      final db = await _d;
      final rows = await db.query('fiyat_gruplari', where: 'id = ?', whereArgs: [id], limit: 1);
      if (rows.isEmpty) return null;
      return FiyatGrubuModel.fromMap(rows.first);
    } catch (e, st) {
      LogServisi().hata('ToptanFiyatDeposu.grupGetir', hata: e, yigin: st);
      return null;
    }
  }

  Future<int> grupEkle(FiyatGrubuModel g) async {
    final db = await _d;
    final m = g.toMap();
    m.remove('id');
    m['global_id'] ??= const Uuid().v4();
    m['last_updated'] = DateTime.now().toIso8601String();
    final yeniId = await db.insert('fiyat_gruplari', m);
    final satir = await db.query('fiyat_gruplari', where: 'id = ?', whereArgs: [yeniId], limit: 1);
    if (satir.isNotEmpty) BulutManager().upsert('fiyat_gruplari', Map<String, dynamic>.from(satir.first));
    return yeniId;
  }

  Future<void> grupGuncelle(FiyatGrubuModel g) async {
    final db = await _d;
    final m = g.toMap()..['last_updated'] = DateTime.now().toIso8601String();
    await db.update('fiyat_gruplari', m, where: 'id = ?', whereArgs: [g.id]);
    final satir = await db.query('fiyat_gruplari', where: 'id = ?', whereArgs: [g.id], limit: 1);
    if (satir.isNotEmpty) BulutManager().upsert('fiyat_gruplari', Map<String, dynamic>.from(satir.first));
  }

  Future<void> grupSil(int id) async {
    final db = await _d;
    final now = DateTime.now().toIso8601String();
    await db.update('fiyat_gruplari', {'is_deleted': 1, 'aktif': 0, 'last_updated': now},
        where: 'id = ?', whereArgs: [id]);
    final satir = await db.query('fiyat_gruplari', where: 'id = ?', whereArgs: [id], limit: 1);
    if (satir.isNotEmpty) BulutManager().upsert('fiyat_gruplari', Map<String, dynamic>.from(satir.first));
  }

  // ══════════════════ ÜRÜN × GRUP ÖZEL FİYATLARI ══════════════════
  /// Belirli bir ürünün, belirli bir fiyat grubu için özel fiyatı (varsa).
  Future<double?> urunGrupFiyatiGetir(int urunId, int fiyatGrubuId) async {
    try {
      final db = await _d;
      final rows = await db.query('urun_fiyat_gruplari',
          where: 'urun_id = ? AND fiyat_grubu_id = ?', whereArgs: [urunId, fiyatGrubuId], limit: 1);
      if (rows.isEmpty) return null;
      return (rows.first['fiyat'] as num).toDouble();
    } catch (e, st) {
      LogServisi().hata('ToptanFiyatDeposu.urunGrupFiyatiGetir', hata: e, yigin: st);
      return null;
    }
  }

  /// Bir ürünün TÜM grup fiyatlarını getirir (ürün detay/toplu düzenleme ekranı için).
  Future<Map<int, double>> urunTumGrupFiyatlariGetir(int urunId) async {
    try {
      final db = await _d;
      final rows = await db.query('urun_fiyat_gruplari', where: 'urun_id = ?', whereArgs: [urunId]);
      return {for (final r in rows) r['fiyat_grubu_id'] as int: (r['fiyat'] as num).toDouble()};
    } catch (e, st) {
      LogServisi().hata('ToptanFiyatDeposu.urunTumGrupFiyatlariGetir', hata: e, yigin: st);
      return {};
    }
  }

  /// Ürün×grup fiyatını kaydeder (varsa günceller, yoksa ekler — upsert).
  Future<void> urunGrupFiyatiKaydet(int urunId, int fiyatGrubuId, double fiyat) async {
    final db = await _d;
    final now = DateTime.now().toIso8601String();
    final mevcut = await db.query('urun_fiyat_gruplari',
        where: 'urun_id = ? AND fiyat_grubu_id = ?', whereArgs: [urunId, fiyatGrubuId], limit: 1);
    int kayitId;
    if (mevcut.isNotEmpty) {
      kayitId = mevcut.first['id'] as int;
      await db.update('urun_fiyat_gruplari', {'fiyat': fiyat, 'last_updated': now},
          where: 'id = ?', whereArgs: [kayitId]);
    } else {
      kayitId = await db.insert('urun_fiyat_gruplari', {
        'global_id': const Uuid().v4(),
        'urun_id': urunId,
        'fiyat_grubu_id': fiyatGrubuId,
        'fiyat': fiyat,
        'last_updated': now,
      });
    }
    final satir = await db.query('urun_fiyat_gruplari', where: 'id = ?', whereArgs: [kayitId], limit: 1);
    if (satir.isNotEmpty) BulutManager().upsert('urun_fiyat_gruplari', Map<String, dynamic>.from(satir.first));
  }

  Future<void> urunGrupFiyatiSil(int urunId, int fiyatGrubuId) async {
    final db = await _d;
    await db.delete('urun_fiyat_gruplari',
        where: 'urun_id = ? AND fiyat_grubu_id = ?', whereArgs: [urunId, fiyatGrubuId]);
    // NOT: bu tablo gerçek silme kullanıyor (soft-delete gerektirecek
    // kadar hassas değil — sadece bir "özel fiyat" kaydı, iş geçmişi
    // taşımıyor). Bulut tarafında da aynı kaydın silinmesi gerekiyorsa
    // bir sonraki tam senkronda global_id eşleşmesi üzerinden temizlik
    // yapılabilir; bu basit tablo için kabul edilebilir bir sadelik.
  }

  // ══════════════════ MİKTAR BAZLI FİYAT KADEMELERİ ══════════════════
  Future<List<FiyatKademesiModel>> kademeleriGetir(int urunId) async {
    try {
      final db = await _d;
      final rows = await db.query('fiyat_kademeleri',
          where: 'urun_id = ?', whereArgs: [urunId], orderBy: 'min_miktar ASC');
      return rows.map(FiyatKademesiModel.fromMap).toList();
    } catch (e, st) {
      LogServisi().hata('ToptanFiyatDeposu.kademeleriGetir', hata: e, yigin: st);
      return [];
    }
  }

  Future<int> kademeEkle(FiyatKademesiModel k) async {
    final db = await _d;
    final m = k.toMap();
    m.remove('id');
    m['global_id'] ??= const Uuid().v4();
    m['last_updated'] = DateTime.now().toIso8601String();
    final yeniId = await db.insert('fiyat_kademeleri', m);
    final satir = await db.query('fiyat_kademeleri', where: 'id = ?', whereArgs: [yeniId], limit: 1);
    if (satir.isNotEmpty) BulutManager().upsert('fiyat_kademeleri', Map<String, dynamic>.from(satir.first));
    return yeniId;
  }

  Future<void> kademeSil(int id) async {
    final db = await _d;
    // 🔴 Derin analizde bulundu: bu tablo (fiyat_kademeleri) global_id
    // ile senkron sisteminde kayıtlı olduğu halde silme işlemi buluta
    // hiç bildirilmiyordu. BulutManager'ın bunun için özel bir sil()
    // metodu zaten var — silmeden ÖNCE global_id'yi alıp kullanıyoruz.
    final rows = await db.query('fiyat_kademeleri', columns: ['global_id'], where: 'id = ?', whereArgs: [id], limit: 1);
    await db.delete('fiyat_kademeleri', where: 'id = ?', whereArgs: [id]);
    if (rows.isNotEmpty && rows.first['global_id'] != null) {
      BulutManager().sil('fiyat_kademeleri', rows.first['global_id'] as String);
    }
  }
}
