// lib/depolar/vardiya_deposu.dart
//
// MASTER ERP DEEP AUDIT — Madde 2 (Mimari) sertleştirmesi:
// vardiya_ekrani.dart için hiç repository sınıfı yoktu, ekranın kendisi
// doğrudan Veritabani().db üzerinden SQL çalıştırıyordu. Bu dosya o
// erişimi kapsar — davranış BİREBİR korunmuştur, sadece sorumluluk UI
// katmanından buraya taşınmıştır.
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../servisler/bulut/bulut_manager.dart';
import '../veri/database/veritabani.dart';

class VardiyaDeposu {
  final Veritabani _db = Veritabani();
  Future<Database> get _d async => _db.db;

  /// Kapanmamış (kapanis_tarihi IS NULL) en son vardiyayı döner —
  /// [subeId] verilirse SADECE o şubenin vardiyası (bkz. çok şubeli
  /// kurulumda "aktif vardiya" karışma hatasının düzeltmesi).
  Future<Map<String, dynamic>?> aktifVardiyaGetir({int? subeId}) async {
    final db = await _d;
    final subeSarti = subeId != null ? ' AND v.sube_id = ?' : '';
    final subeArgs = subeId != null ? [subeId] : <Object?>[];
    final rows = await db.rawQuery(
        'SELECT v.*, k.ad_soyad FROM vardiyalar v '
        'LEFT JOIN kullanicilar k ON v.kullanici_id = k.id '
        'WHERE v.kapanis_tarihi IS NULL$subeSarti ORDER BY v.id DESC LIMIT 1',
        subeArgs);
    return rows.isNotEmpty ? Map<String, dynamic>.from(rows.first) : null;
  }

  /// Kapanmış vardiyaların geçmişi (en yeniden eskiye).
  Future<List<Map<String, dynamic>>> gecmisVardiyalarGetir({
    int? subeId,
    int limit = 30,
  }) async {
    final db = await _d;
    final subeSarti = subeId != null ? ' AND v.sube_id = ?' : '';
    final args = <Object?>[if (subeId != null) subeId, limit];
    final rows = await db.rawQuery(
        'SELECT v.*, k.ad_soyad FROM vardiyalar v '
        'LEFT JOIN kullanicilar k ON v.kullanici_id = k.id '
        'WHERE v.kapanis_tarihi IS NOT NULL$subeSarti ORDER BY v.id DESC LIMIT ?',
        args);
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  /// Aktif vardiya özeti — satış sayısı/ciro/ödeme yöntemi kırılımı,
  /// [baslangicTarihi]'nden (vardiyanın açılış anı) bu yana.
  Future<Map<String, dynamic>> satisOzetiGetir(String baslangicTarihi) async {
    final db = await _d;
    final rows = await db.rawQuery('''
      SELECT
        COUNT(*) as satis_sayisi,
        COALESCE(SUM(genel_toplam),0) as toplam_ciro,
        COALESCE(SUM(CASE WHEN odeme_yontemi='Nakit' THEN genel_toplam ELSE 0 END),0) as nakit,
        COALESCE(SUM(CASE WHEN odeme_yontemi='Kredi Kartı' THEN genel_toplam ELSE 0 END),0) as kart,
        COALESCE(SUM(CASE WHEN odeme_yontemi='Cari' THEN genel_toplam ELSE 0 END),0) as cari,
        COALESCE(SUM(iskonto_tutar),0) as iskonto,
        COALESCE(SUM(CASE WHEN iptal=1 THEN 1 ELSE 0 END),0) as iptal_sayisi
      FROM satislar
      WHERE datetime(tarih) >= datetime(?) AND iptal=0 AND is_deleted=0
    ''', [baslangicTarihi]);
    return Map<String, dynamic>.from(rows.first);
  }

  /// PDF vardiya raporu için özet — [satisOzetiGetir] ile AYNI zaman
  /// penceresini sorgular ama farklı kolon adları/alan seti döner (PDF
  /// şablonunun beklediği anahtarlarla birebir); davranış değişmesin
  /// diye bilerek AYRI bir metod olarak tutuldu.
  Future<Map<String, dynamic>> pdfSatisOzetiGetir(String baslangicTarihi) async {
    final db = await _d;
    final rows = await db.rawQuery('''
      SELECT COUNT(*) as sayi, COALESCE(SUM(genel_toplam),0) as ciro,
        COALESCE(SUM(CASE WHEN odeme_yontemi='Nakit' THEN genel_toplam ELSE 0 END),0) as nakit,
        COALESCE(SUM(CASE WHEN odeme_yontemi='Kredi Kartı' THEN genel_toplam ELSE 0 END),0) as kart,
        COALESCE(SUM(CASE WHEN odeme_yontemi='Cari' THEN genel_toplam ELSE 0 END),0) as cari_toplam,
        COALESCE(SUM(iskonto_tutar),0) as iskonto
      FROM satislar WHERE datetime(tarih) >= datetime(?) AND iptal=0 AND is_deleted=0
    ''', [baslangicTarihi]);
    return Map<String, dynamic>.from(rows.first);
  }

  /// Yeni vardiya açar.
  Future<Map<String, dynamic>> ac({
    required int kullaniciId,
    required int? subeId,
    required double baslangicKasa,
  }) async {
    final db = await _d;
    final now = DateTime.now().toIso8601String();
    final id = await db.insert('vardiyalar', {
      'global_id': const Uuid().v4(),
      'kullanici_id': kullaniciId,
      'sube_id': subeId,
      'acilis_tarihi': now,
      'acilis_kasasi': baslangicKasa,
      'baslangic_bakiye': baslangicKasa,
      'durum': 'acik',
      'last_updated': now,
    });
    final satir = await db.query('vardiyalar',
        where: 'id = ?', whereArgs: [id], limit: 1);
    final row = Map<String, dynamic>.from(satir.first);
    BulutManager().upsert('vardiyalar', row);
    return row;
  }

  /// Açık vardiyayı kapatır (nakit sayım + fark ile).
  Future<Map<String, dynamic>> kapat({
    required int vardiyaId,
    required double sayim,
    required double fark,
  }) async {
    final db = await _d;
    final now = DateTime.now().toIso8601String();
    await db.update(
        'vardiyalar',
        {
          'kapanis_tarihi': now,
          'kapanis_kasasi': sayim,
          'bitis_bakiye': sayim,
          'nakit_sayim': sayim,
          'fark': fark,
          'durum': 'kapali',
          'last_updated': now,
        },
        where: 'id = ?',
        whereArgs: [vardiyaId]);
    final satir = await db.query('vardiyalar',
        where: 'id = ?', whereArgs: [vardiyaId], limit: 1);
    final row = Map<String, dynamic>.from(satir.first);
    BulutManager().upsert('vardiyalar', row);
    return row;
  }
}
