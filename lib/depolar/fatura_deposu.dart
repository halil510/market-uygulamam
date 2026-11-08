// lib/depolar/fatura_deposu.dart
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../servisler/log_servisi.dart';
import '../servisler/bulut/bulut_manager.dart';
import '../servisler/fatura_seri/fatura_seri_blok_servisi.dart';
import '../veri/database/veritabani.dart';
import '../modeller/fatura_model.dart';
import '../cekirdek/utils/tarih_utils.dart';

class FaturaDeposu {
  final Veritabani _db = Veritabani();
  Future<Database> get _d async => _db.db;

  /// Bir satışın zaten faturalandırılıp faturalandırılmadığını kontrol
  /// eder — muhasebe kuralı gereği kesilmiş bir faturaya sahip satış
  /// doğrudan silinemez (bkz. cari_detay_paneli.dart._silmeyeCalis).
  /// Madde 2 mimari denetimi.
  Future<bool> satisIcinFaturaVarMi(int satisId) async {
    final db = await _d;
    final rows = await db.query('faturalar',
        where: 'satis_id = ? AND (deleted_at IS NULL)', whereArgs: [satisId], limit: 1);
    return rows.isNotEmpty;
  }

  Future<bool> faturaNoKullanildiMi(String faturaNo) async {
    final db = await _d;
    final rows = await db.query('faturalar',
        columns: ['id'], where: 'fatura_no = ?', whereArgs: [faturaNo], limit: 1);
    return rows.isNotEmpty;
  }

  /// ELLE numaralı fatura kaydı (Fatura Ekle ekranında numara yazıldığında).
  /// Otomatik numara için [ekleMerkeziSeriIle] kullanılır.
  Future<int> ekle(FaturaModel fatura, List<FaturaDetayModel> kalemler) async {
    // 🔴 Derin analizde bulundu: fatura_detaylari kalemlerine global_id
    // atanmıyordu ve işlem sonrası BulutManager hiç çağrılmıyordu —
    // faturalar sadece manuel senkronla buluta gidiyordu.
    //
    // 🔴 DÜZELTME (2026-11-06, CLAUDE.md §5.4 / bulgu #3): numara çakışınca
    // ÖNCEDEN yerel "en büyük + 1" ile ve sabit 'FAT' serisiyle YENİ bir
    // numara üretilip SESSİZCE yeniden deneniyordu — kağıt faturanın numarası
    // değişiyor ve merkezi seri bloğu dışında numara üretiliyordu. Elle
    // girilen numara kullanıcınındır: çakışırsa kayıt yapılmaz, açık hata
    // döner (ekran zaten önceden kontrol ediyor; bu, araya senkronla gelen
    // aynı numaralı fatura içindir).
    final db = await _d;
    final int faturaId;
    try {
      faturaId = await db.transaction((txn) async {
        final faturaMap = fatura.toMap();
        faturaMap['global_id'] ??= const Uuid().v4();
        faturaMap.remove('id');
        final id = await txn.insert('faturalar', faturaMap);
        for (final k in kalemler) {
          final km = k.toMap();
          km['global_id'] ??= const Uuid().v4();
          km.remove('id');
          km['fatura_id'] = id;
          await txn.insert('fatura_detaylari', km);
        }
        return id;
      });
    } catch (e, st) {
      final mesaj = e.toString().toLowerCase();
      final cakismaMi = mesaj.contains('unique') && mesaj.contains('fatura_no');
      if (cakismaMi) {
        throw Exception('"${fatura.faturaNo}" numaralı bir fatura zaten var. '
            'Farklı bir numara yazın ya da alanı boş bırakıp otomatik '
            'atanmasını sağlayın.');
      }
      LogServisi().hata('Fatura.ekle', hata: e, yigin: st);
      rethrow;
    }

    // Transaction başarılı — buluta bildir (commit sonrası, taze satırla).
    // Bildirim hatası kaydı geri almaz ama artık log'a düşer (§5.7).
    try {
      await BulutManager().satiriBildir(db, 'faturalar', faturaId);
      final detaySatirlar = await db.query('fatura_detaylari', where: 'fatura_id = ?', whereArgs: [faturaId]);
      for (final d in detaySatirlar) {
        BulutManager().upsert('fatura_detaylari', Map<String, dynamic>.from(d));
      }
    } catch (e, st) {
      LogServisi().hata('Fatura.ekle (bulut bildirimi)', hata: e, yigin: st);
    }
    return faturaId;
  }

  /// [ekle]'nin MERKEZİ SERİ/BLOK sistemini kullanan sürümü — bkz.
  /// CENTRAL_DOCUMENT_NUMBERING_DEEP_AUDIT.md. `fatura.faturaNo` burada
  /// YOK SAYILIR — numara, [FaturaSeriBlokServisi] tarafından yerel
  /// bloktan (ya da gerekirse önce buluttan yeni bir blok alınarak)
  /// ATOMİK olarak, TAM OLARAK BU INSERT ile AYNI SQLite transaction'ı
  /// içinde üretilir — "numarayı oku" ile "kaydet" arasında hiçbir
  /// boşluk (TOCTOU) kalmaz, ve birden fazla terminal artık ASLA aynı
  /// numarayı üretemez (bloklar Postgres'te atomik tahsis edilir).
  ///
  /// [ekle]'nin eski (yerel MAX+1) yolu SİLİNMEDİ — bilerek: manuel
  /// fatura girişi ekranı hâlâ onu kullanıyor (kullanıcı numarayı
  /// görüp elle düzenleyebiliyor, bu ayrı bir iş kararı — bkz. rapor
  /// §26/24). Bu yeni yol SADECE otomatik (satış/iade→fatura) akış
  /// için kullanılıyor.
  Future<int> ekleMerkeziSeriIle(
    FaturaModel fatura,
    List<FaturaDetayModel> kalemler, {
    required String seri,
  }) async {
    final blokServisi = FaturaSeriBlokServisi();
    for (var deneme = 0; deneme < 2; deneme++) {
      await blokServisi.blokHazirOldugundanEminOl(seri);
      try {
        final db = await _d;
        final faturaId = await db.transaction((txn) async {
          final tuketilen = await blokServisi.faturaNoTuket(txn, seri);
          final faturaNo =
              '$seri${tuketilen.yil}${tuketilen.numara.toString().padLeft(9, '0')}';
          final faturaMap = fatura.toMap();
          faturaMap['global_id'] ??= const Uuid().v4();
          faturaMap.remove('id');
          faturaMap['fatura_no'] = faturaNo;
          final id = await txn.insert('faturalar', faturaMap);
          for (final k in kalemler) {
            final km = k.toMap();
            km['global_id'] ??= const Uuid().v4();
            km.remove('id');
            km['fatura_id'] = id;
            await txn.insert('fatura_detaylari', km);
          }
          return id;
        });

        try {
          await BulutManager().satiriBildir(db, 'faturalar', faturaId);
          final detaySatirlar = await db.query('fatura_detaylari', where: 'fatura_id = ?', whereArgs: [faturaId]);
          for (final d in detaySatirlar) {
            BulutManager().upsert('fatura_detaylari', Map<String, dynamic>.from(d));
          }
        } catch (e) {
          if (kDebugMode) debugPrint('Fatura bulut bildirimi hatası: $e');
        }
        return faturaId;
      } on BlokTukendiException catch (e, st) {
        if (deneme == 0) continue; // bir kez daha dene — yeni blok alınmış olmalı
        LogServisi().hata('FaturaDeposu.ekleMerkeziSeriIle', hata: e, yigin: st);
        rethrow;
      } catch (e, st) {
        // Bloktaki numara bu arada (ör. manuel Fatura Ekle ekranınca)
        // kullanılmışsa: bir sonraki blokHazirOldugundanEminOl onu atlar.
        final mesaj = e.toString().toLowerCase();
        final cakismaMi = mesaj.contains('unique') && mesaj.contains('fatura_no');
        if (cakismaMi && deneme == 0) continue;
        LogServisi().hata('FaturaDeposu.ekleMerkeziSeriIle', hata: e, yigin: st);
        rethrow;
      }
    }
    throw BlokTukendiException('Fatura numarası tahsis edilemedi, lütfen tekrar deneyin.');
  }

  Future<FaturaModel?> idileGetir(int id) async {
    try {
      final db = await _d;
      final rows = await db.rawQuery(
        'SELECT f.*, c.unvan as cari_unvan, '
        'COALESCE(NULLIF(c.vergi_no, \'\'), c.tc_kimlik) as cari_vergi_no, '
        'c.vergi_dairesi as cari_vergi_dairesi, c.mukellef_durumu as cari_mukellef_durumu, '
        'ca.adres as cari_adres_ham, ca.ilce as cari_ilce, ca.il as cari_il '
        'FROM faturalar f '
        'LEFT JOIN cari c ON f.cari_id = c.id '
        'LEFT JOIN cari_adres ca ON ca.cari_id = f.cari_id AND ca.varsayilan = 1 WHERE f.id = ?',
        [id],
      );
      if (rows.isEmpty) return null;
      final detayRows = await db.query('fatura_detaylari',
          where: 'fatura_id = ?', whereArgs: [id]);
      final kalemler = detayRows.map(FaturaDetayModel.fromMap).toList();
      return FaturaModel.fromMap(rows.first, detaylar: kalemler);
    } catch (e, st) {
      LogServisi().hata('Fatura.idileGetir', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<FaturaModel?> faturaNoileGetir(String faturaNo) async {
    try {
      final db = await _d;
      final rows = await db.rawQuery(
        'SELECT f.*, c.unvan as cari_unvan, '
        'COALESCE(NULLIF(c.vergi_no, \'\'), c.tc_kimlik) as cari_vergi_no, '
        'c.vergi_dairesi as cari_vergi_dairesi, c.mukellef_durumu as cari_mukellef_durumu, '
        'ca.adres as cari_adres_ham, ca.ilce as cari_ilce, ca.il as cari_il '
        'FROM faturalar f '
        'LEFT JOIN cari c ON f.cari_id = c.id '
        'LEFT JOIN cari_adres ca ON ca.cari_id = f.cari_id AND ca.varsayilan = 1 WHERE f.fatura_no = ?',
        [faturaNo],
      );
      if (rows.isEmpty) return null;
      return await idileGetir(rows.first['id'] as int);
    } catch (e, st) {
      LogServisi().hata('Fatura.faturaNoileGetir', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<List<FaturaModel>> listele({
    DateTime? basTarih,
    DateTime? bitTarih,
    int? cariId,
    String? odemeDurumu,
    String? eFaturaDurum,
    int limit = 50,
  }) async {
    final db = await _d;
    final whereParts = ["f.durum != 'silindi'"];
    final List<dynamic> args = [];

    if (basTarih != null) { whereParts.add(TarihUtils.sonrasiSql('f.tarih', basTarih)); args.add(basTarih.toIso8601String()); }
    if (bitTarih != null) { whereParts.add(TarihUtils.oncesiSql('f.tarih', bitTarih)); args.add(bitTarih.toIso8601String()); }
    if (cariId != null) { whereParts.add('f.cari_id = ?'); args.add(cariId); }
    if (odemeDurumu != null) { whereParts.add('f.odeme_durumu = ?'); args.add(odemeDurumu); }
    if (eFaturaDurum != null) { whereParts.add('f.e_fatura_durum = ?'); args.add(eFaturaDurum); }

    final where = whereParts.join(' AND ');
    final rows = await db.rawQuery(
      'SELECT f.*, c.unvan as cari_unvan, '
        'COALESCE(NULLIF(c.vergi_no, \'\'), c.tc_kimlik) as cari_vergi_no, '
        'c.vergi_dairesi as cari_vergi_dairesi, c.mukellef_durumu as cari_mukellef_durumu, '
        'ca.adres as cari_adres_ham, ca.ilce as cari_ilce, ca.il as cari_il '
        'FROM faturalar f '
      'LEFT JOIN cari c ON f.cari_id = c.id '
        'LEFT JOIN cari_adres ca ON ca.cari_id = f.cari_id AND ca.varsayilan = 1 '
      'WHERE $where ORDER BY f.tarih DESC LIMIT $limit',
      args,
    );
    return rows.map((r) => FaturaModel.fromMap(r)).toList();
  }

  Future<void> eFaturaDurumGuncelle(int id, String durum, {
    String? uuid, String? html, String? xml, String? yanit,
  }) async {
    final db = await _d;
    final now = DateTime.now().toIso8601String();
    // 🔴 DÜZELTME: Önceden sadece 'updated_at' bümleniyordu — bu,
    // senkron sisteminin kullandığı sütun DEĞİL (o 'last_updated').
    // e-Fatura durumu diğer cihazlara hiç gitmiyordu.
    final data = <String, dynamic>{
      'e_fatura_durum': durum,
      'updated_at': now,
      'last_updated': now,
    };
    if (uuid != null) data['e_fatura_uuid'] = uuid;
    if (html != null) data['e_fatura_html'] = html;
    if (xml != null) data['e_fatura_xml'] = xml;
    if (yanit != null) data['uygulama_yaniti'] = yanit;
    if (durum == 'gonderildi') data['gonderim_tarihi'] = now;
    await db.update('faturalar', data, where: 'id = ?', whereArgs: [id]);
    await BulutManager().satiriBildir(db, 'faturalar', id);
  }

  /// GİB tarafından REDDEDİLMİŞ bir faturayı yeniden göndermeden hemen
  /// önce çağrılır — deneme sayacını artırır ki GibServisi YENİ (eski
  /// reddedilmiş denemeyle çakışmayan) bir ETTN üretsin (bkz. gib_servisi
  /// .dart _ettnFaturaIcin). SADECE 'reddedildi' durumundan çağrılmalı —
  /// ağ hatası ('hata') sonrası tekrar denemede bu ÇAĞRILMAMALI (o durumda
  /// AYNI ETTN ile tekrar denemek kasıtlı ve güvenli — mükerrer gönderim
  /// korumasının ta kendisi).
  Future<void> eFaturaYenidenGondermeyeHazirla(int id) async {
    final db = await _d;
    final rows = await db.query('faturalar', columns: ['e_fatura_deneme_no'], where: 'id = ?', whereArgs: [id], limit: 1);
    final mevcut = rows.isNotEmpty ? (rows.first['e_fatura_deneme_no'] as int? ?? 0) : 0;
    final now = DateTime.now().toIso8601String();
    await db.update('faturalar', {
      'e_fatura_deneme_no': mevcut + 1,
      'last_updated': now,
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> odemeDurumGuncelle(int id, String odemeDurumu, double odenenTutar) async {
    try {
      final db = await _d;
      final fatura = await idileGetir(id);
      if (fatura == null) return;
      final kalan = (fatura.genelToplam - odenenTutar).clamp(0, double.infinity);
      await db.update('faturalar', {
        'odeme_durumu': odemeDurumu,
        'odenen_tutar': odenenTutar,
        'kalan_tutar': kalan,
        'last_updated': DateTime.now().toIso8601String(),
      }, where: 'id = ?', whereArgs: [id]);
      await BulutManager().satiriBildir(db, 'faturalar', id);
    } catch (e, st) {
      LogServisi().hata('Fatura.odemeDurumGuncelle', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<void> iptalEt(int id) async {
    try {
      final db = await _d;
      await db.update('faturalar', {'durum': 'iptal', 'last_updated': DateTime.now().toIso8601String()},
          where: 'id = ?', whereArgs: [id]);
      await BulutManager().satiriBildir(db, 'faturalar', id);
    } catch (e, st) {
      LogServisi().hata('Fatura.iptalEt', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> istatistikler() async {
    try {
      final db = await _d;
      final res = await db.rawQuery(
        "SELECT COUNT(*) as toplam, "
        "COUNT(CASE WHEN odeme_durumu = 'beklemede' THEN 1 END) as bekleyen, "
        "COUNT(CASE WHEN odeme_durumu = 'odendi' THEN 1 END) as odendi_sayisi, "
        "COUNT(CASE WHEN e_fatura_durum = 'gonderildi' THEN 1 END) as e_gonderildi, "
        "SUM(genel_toplam) as toplam_tutar, "
        "SUM(kalan_tutar) as toplam_kalan "
        "FROM faturalar WHERE durum = 'aktif'",
      );
      return res.isEmpty ? {} : Map<String, dynamic>.from(res.first);
    } catch (e, st) {
      LogServisi().hata('Fatura.metod', hata: e, yigin: st);
      rethrow;
    }
  }

  Future<void> odemeKaydet(int faturaId, double odenenTutar) async {
    try {
      final db = await _d;
      final rows = await db.query('faturalar', where: 'id = ?', whereArgs: [faturaId]);
      if (rows.isEmpty) return;
      final mevcutOdenen = (rows.first['odenen_tutar'] as num?)?.toDouble() ?? 0;
      final genelToplam  = (rows.first['genel_toplam'] as num?)?.toDouble() ?? 0;
      final yeniOdenen   = mevcutOdenen + odenenTutar;
      final yeniKalan    = (genelToplam - yeniOdenen).clamp(0.0, double.infinity);
      final yeniDurum    = yeniKalan <= 0.01 ? 'odendi' : 'beklemede';
      await db.update('faturalar', {
        'odenen_tutar': yeniOdenen, 'kalan_tutar': yeniKalan, 'odeme_durumu': yeniDurum,
        'last_updated': DateTime.now().toIso8601String(),
      }, where: 'id = ?', whereArgs: [faturaId]);
      await BulutManager().satiriBildir(db, 'faturalar', faturaId);
    } catch (e, st) {
      LogServisi().hata('Fatura.odemeKaydet', hata: e, yigin: st);
      rethrow;
    }
  }
}
