// lib/depolar/fatura_deposu.dart
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../servisler/log_servisi.dart';
import '../servisler/bulut/bulut_manager.dart';
import '../veri/database/veritabani.dart';
import '../modeller/fatura_model.dart';

class FaturaDeposu {
  final Veritabani _db = Veritabani();
  Future<Database> get _d async => _db.db;

  /// ÖNCEDEN CİDDİ BİR HUKUKİ UYUMLULUK RİSKİ VARDI: fatura numarası,
  /// gerçek bir artan sayaç yerine "şu anki zaman damgası mod 1 milyar"
  /// ile üretiliyordu (fatura_ekle_ekrani.dart, initState). Bu SIRALI
  /// DEĞİLDİ (GİB'in zorunlu kıldığı "boşluksuz, artan sıra numarası"
  /// kuralını ihliyordu) ve zaman damgası ~11.5 günde bir döngüye
  /// girdiği için ÇAKIŞMA (mükerrer numara) riski taşıyordu. Artık bu
  /// fonksiyon, o yıl+seri için VERİTABANINDA KAYITLI EN YÜKSEK
  /// numarayı bulup bir fazlasını döndürüyor — gerçekten sıralı ve
  /// kalıcı.
  Future<String> siradakiFaturaNoUret({String seri = 'FAT'}) async {
    try {
      final db = await _d;
      final yil = DateTime.now().year;
      final onek = '$seri$yil';
      final rows = await db.rawQuery(
        'SELECT fatura_no FROM faturalar WHERE fatura_no LIKE ? '
        'ORDER BY fatura_no DESC LIMIT 1',
        ['$onek%'],
      );
      var sonraki = 1;
      if (rows.isNotEmpty) {
        final mevcut = rows.first['fatura_no'] as String?;
        if (mevcut != null && mevcut.length >= onek.length + 9) {
          final siraStr = mevcut.substring(onek.length, onek.length + 9);
          final sira = int.tryParse(siraStr);
          if (sira != null) sonraki = sira + 1;
        }
      }
      return '$onek${sonraki.toString().padLeft(9, '0')}';
    } catch (e, st) {
      LogServisi().hata('FaturaDeposu.siradakiFaturaNoUret', hata: e, yigin: st);
      // Son çare — en azından çalışsın, ama bu durum loglanıyor ve
      // kullanıcı yine de kaydetmeden önce numarayı görüp
      // düzenleyebiliyor.
      final yil = DateTime.now().year;
      return '$seri$yil${DateTime.now().millisecondsSinceEpoch % 1000000000}'.padRight(16, '0').substring(0, 16);
    }
  }

  Future<int> ekle(FaturaModel fatura, List<FaturaDetayModel> kalemler) async {
    // 🔴 Derin analizde bulundu: fatura_detaylari kalemlerine global_id
    // atanmıyordu ve işlem sonrası BulutManager hiç çağrılmıyordu —
    // faturalar sadece manuel senkronla buluta gidiyordu. Ayrıca
    // fatura_no üretimi (siradakiFaturaNoUret) ile bu kayıt arasında
    // küçük bir yarış durumu (race condition) penceresi var — iki
    // cihaz aynı anda çağırırsa aynı numarayı üretebilir. Veritabanı
    // seviyesinde fatura_no UNIQUE olduğu için bu durumda veri
    // BOZULMAZ (ikinci kayıt reddedilir) ama kullanıcıya hata döner.
    // Bu nadir durumda, YENİ bir numara üretip TEK SEFER yeniden
    // deniyoruz — kullanıcı hatayla karşılaşmadan işlem tamamlanır.
    String? yeniFaturaNo;
    for (var deneme = 0; deneme < 2; deneme++) {
      try {
        final db = await _d;
        final faturaId = await db.transaction((txn) async {
          final faturaMap = fatura.toMap();
          faturaMap['global_id'] ??= const Uuid().v4();
          faturaMap.remove('id');
          if (yeniFaturaNo != null) faturaMap['fatura_no'] = yeniFaturaNo;
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

        // Transaction başarılı — buluta bildir.
        try {
          final faturaSatir = await db.query('faturalar', where: 'id = ?', whereArgs: [faturaId], limit: 1);
          if (faturaSatir.isNotEmpty) {
            BulutManager().upsert('faturalar', Map<String, dynamic>.from(faturaSatir.first));
          }
          final detaySatirlar = await db.query('fatura_detaylari', where: 'fatura_id = ?', whereArgs: [faturaId]);
          for (final d in detaySatirlar) {
            BulutManager().upsert('fatura_detaylari', Map<String, dynamic>.from(d));
          }
        } catch (e) {
          if (kDebugMode) debugPrint('Fatura bulut bildirimi hatası: $e');
        }
        return faturaId;
      } catch (e, st) {
        final mesaj = e.toString().toLowerCase();
        final cakismaMi = mesaj.contains('unique') && mesaj.contains('fatura_no');
        if (cakismaMi && deneme == 0) {
          // Yeni bir numara üret ve tek sefer tekrar dene.
          yeniFaturaNo = await siradakiFaturaNoUret();
          continue;
        }
        LogServisi().hata('Fatura.ekle', hata: e, yigin: st);
        rethrow;
      }
    }
    throw Exception('Fatura numarası çakışması çözülemedi, lütfen tekrar deneyin.');
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
      return idileGetir(rows.first['id'] as int);
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

    if (basTarih != null) { whereParts.add('datetime(f.tarih) >= datetime(?)'); args.add(basTarih.toIso8601String()); }
    if (bitTarih != null) { whereParts.add('datetime(f.tarih) <= datetime(?)'); args.add(bitTarih.toIso8601String()); }
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
    final guncelSatir = await db.query('faturalar', where: 'id = ?', whereArgs: [id], limit: 1);
    if (guncelSatir.isNotEmpty) {
      BulutManager().upsert('faturalar', Map<String, dynamic>.from(guncelSatir.first));
    }
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
      final guncelSatir = await db.query('faturalar', where: 'id = ?', whereArgs: [id], limit: 1);
      if (guncelSatir.isNotEmpty) {
        BulutManager().upsert('faturalar', Map<String, dynamic>.from(guncelSatir.first));
      }
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
      final guncelSatir = await db.query('faturalar', where: 'id = ?', whereArgs: [id], limit: 1);
      if (guncelSatir.isNotEmpty) {
        BulutManager().upsert('faturalar', Map<String, dynamic>.from(guncelSatir.first));
      }
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
      final guncelSatir = await db.query('faturalar', where: 'id = ?', whereArgs: [faturaId], limit: 1);
      if (guncelSatir.isNotEmpty) {
        BulutManager().upsert('faturalar', Map<String, dynamic>.from(guncelSatir.first));
      }
    } catch (e, st) {
      LogServisi().hata('Fatura.odemeKaydet', hata: e, yigin: st);
      rethrow;
    }
  }
}
