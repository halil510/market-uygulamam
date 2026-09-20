// lib/depolar/efatura_log_deposu.dart
//
// 'efatura_log' tablosu için depo — GİB gönderim/durum/iptal
// denemelerinin izini tutar. Önceden bu DB erişimi gib_servisi.dart
// (bir SERVİS) içinde yaşıyordu; katman disiplini gereği (Madde 2
// mimari denetimi: "Repository yerine servis/depo karmaşası var mı?")
// projenin geri kalanındaki tüm tablo erişimiyle aynı desene (depolar/)
// taşındı. DAVRANIŞ DEĞİŞMEDİ.
import 'package:flutter/foundation.dart';
import '../veri/database/veritabani.dart';

class EfaturaLogDeposu {
  Future<void> kaydet({
    required int referansId,
    required String referansTuru,
    required String islemTipi,
    required String durum,
    String? uuid,
    String? istekXml,
    String? yanitXml,
    String? hataMesaj,
  }) async {
    try {
      final db = await Veritabani().db;
      await db.insert('efatura_log', {
        'referans_id':   referansId,
        'referans_turu': referansTuru,
        'uuid':          uuid,
        'islem_tipi':    islemTipi,
        'durum':         durum,
        'istek_xml':     istekXml,
        'yanit_xml':     yanitXml,
        'hata_mesaj':    hataMesaj,
        'tarih':         DateTime.now().toIso8601String(),
      });
    } catch (e) {
      if (kDebugMode) debugPrint('GIB log hatası: $e');
    }
  }

  /// DB'den fatura için son log kaydını getir
  Future<Map<String, dynamic>?> sonLogGetir(int faturaId) async {
    try {
      final db = await Veritabani().db;
      final rows = await db.query('efatura_log',
          where: "referans_id = ? AND referans_turu = 'fatura'",
          whereArgs: [faturaId],
          orderBy: 'id DESC',
          limit: 1);
      return rows.isNotEmpty ? rows.first : null;
    } catch (_) { return null; }
  }
}
