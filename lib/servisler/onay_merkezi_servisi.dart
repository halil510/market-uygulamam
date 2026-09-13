// lib/servisler/onay_merkezi_servisi.dart
//
// FAZ 9 — Onay Merkezi (erp_roadmap madde 22, kullanıcı onayıyla
// "bildirim tipi" olarak kuruldu — 2026-09-13). Sekiz riskli akışta
// (yüksek iskonto, yüksek iade, risk limiti aşımı, kasa çıkışı, fiyat
// değişimi, stok düzeltme, yüksek gider, borç silme) eşik aşıldığında
// işlem NORMAL TAMAMLANIR — bu servis SADECE bilgi amaçlı bir kayıt
// düşer, hiçbir akışı engellemez/geciktirmez. Yönetici bu kayıtları
// "Onay Merkezi" ekranından sonradan inceler.
import 'package:uuid/uuid.dart';
import '../veri/database/veritabani.dart';
import '../servisler/auth_servisi.dart';
import '../servisler/bulut/bulut_manager.dart';
import '../servisler/log_servisi.dart';

enum OnayTuru {
  yuksekIskonto,
  yuksekIade,
  riskAsimi,
  kasaCikisi,
  fiyatDegisimi,
  stokDuzeltme,
  yuksekGider,
  borcSilme,
}

extension OnayTuruUzanti on OnayTuru {
  String get kod => switch (this) {
        OnayTuru.yuksekIskonto => 'yuksek_iskonto',
        OnayTuru.yuksekIade => 'yuksek_iade',
        OnayTuru.riskAsimi => 'risk_asimi',
        OnayTuru.kasaCikisi => 'kasa_cikisi',
        OnayTuru.fiyatDegisimi => 'fiyat_degisimi',
        OnayTuru.stokDuzeltme => 'stok_duzeltme',
        OnayTuru.yuksekGider => 'yuksek_gider',
        OnayTuru.borcSilme => 'borc_silme',
      };

  String get etiket => switch (this) {
        OnayTuru.yuksekIskonto => 'Yüksek İskonto',
        OnayTuru.yuksekIade => 'Yüksek İade',
        OnayTuru.riskAsimi => 'Risk Limiti Aşımı',
        OnayTuru.kasaCikisi => 'Kasa Çıkışı',
        OnayTuru.fiyatDegisimi => 'Fiyat Değişimi',
        OnayTuru.stokDuzeltme => 'Stok Düzeltme',
        OnayTuru.yuksekGider => 'Yüksek Gider',
        OnayTuru.borcSilme => 'Borç Silme',
      };
}

/// Bu oturumda belirlenen varsayılan eşikler (kullanıcı onayıyla
/// "makul varsayılan" olarak seçildi — mağaza bazlı ayarlanabilirlik
/// istenirse ayrı bir iş olarak `ayarlar` tablosu üzerinden eklenebilir,
/// şu an sabit).
class OnayEsikleri {
  OnayEsikleri._();
  static const double yuksekIskontoOrani = 20.0; // %
  static const double yuksekIadeTutari = 500.0; // ₺
  static const double kasaCikisiTutari = 1000.0; // ₺
  static const double fiyatDegisimiOrani = 30.0; // %
  static const double yuksekGiderTutari = 1000.0; // ₺
  static const double borcSilmeTutari = 100.0; // ₺ (risk limiti eşiği zaten cari.limit_tutari'nden gelir)
  static const double stokDuzeltmeMiktari = 50.0; // birim (adet/kg/vb.)
}

/// Saf fonksiyon: eşik <= 0 ise kontrol devre dışıdır (limitKontrolEt ile
/// AYNI konvansiyon — bkz. CariDeposu.limitKontrolEt).
bool onayEsikiAsildiMi(double tutar, double esik) => esik > 0 && tutar >= esik;

/// Saf fonksiyon: eski fiyata göre mutlak değişim yüzdesini hesaplar.
/// Eski fiyat <= 0 ise null (yüzde değişim tanımsız — ör. ilk fiyat
/// girişi, bu bir "değişim" değil).
double? fiyatDegisimOraniHesapla(double eskiFiyat, double yeniFiyat) {
  if (eskiFiyat <= 0) return null;
  return ((yeniFiyat - eskiFiyat).abs() / eskiFiyat) * 100;
}

class OnayMerkeziServisi {
  /// Eşik aşılmışsa 'onay_talepleri'ne bir kayıt düşer. HİÇBİR ŞEKİLDE
  /// exception fırlatmaz — çağıran işlemin (satış/iade/kasa/vb.) BAŞARILI
  /// tamamlanmış olması, bu bildirim kaydının yazılamamasından ETKİLENMEMELİ.
  Future<void> kaydet({
    required OnayTuru tur,
    required double tutar,
    required double esikTutar,
    String? referansTuru,
    int? referansId,
    String? aciklama,
  }) async {
    if (!onayEsikiAsildiMi(tutar, esikTutar)) return;
    try {
      final db = await Veritabani().db;
      final now = DateTime.now().toIso8601String();
      final gid = const Uuid().v4();
      await db.insert('onay_talepleri', {
        'global_id': gid,
        'tur': tur.kod,
        'referans_turu': referansTuru,
        'referans_id': referansId,
        'tutar': tutar,
        'esik_tutar': esikTutar,
        'aciklama': aciklama,
        'kullanici_id': AuthServisi().aktifId,
        'kullanici_adi': AuthServisi().aktifAd,
        'tarih': now,
        'goruldu': 0,
        'last_updated': now,
        'is_deleted': 0,
      });
      final satir = await db.query('onay_talepleri',
          where: 'global_id = ?', whereArgs: [gid], limit: 1);
      if (satir.isNotEmpty) {
        BulutManager().upsert('onay_talepleri', Map<String, dynamic>.from(satir.first));
      }
    } catch (e, st) {
      // Bilinçli olarak rethrow YOK — bu bildirim tali bir kayıt,
      // ana işlemi (satış/iade/vb.) asla kesintiye uğratmamalı.
      LogServisi().hata('OnayMerkezi.kaydet', hata: e, yigin: st);
    }
  }

  Future<List<Map<String, dynamic>>> listele({bool sadeceGorulmemis = false}) async {
    final db = await Veritabani().db;
    return db.query('onay_talepleri',
        where: sadeceGorulmemis ? 'is_deleted = 0 AND goruldu = 0' : 'is_deleted = 0',
        orderBy: 'tarih DESC');
  }

  Future<int> gorulmemisSayisi() async {
    final db = await Veritabani().db;
    final res = await db.rawQuery(
        'SELECT COUNT(*) AS n FROM onay_talepleri WHERE is_deleted = 0 AND goruldu = 0');
    return (res.first['n'] as int?) ?? 0;
  }

  Future<void> goruldeIsaretle(int id) async {
    final db = await Veritabani().db;
    final now = DateTime.now().toIso8601String();
    await db.update(
        'onay_talepleri',
        {
          'goruldu': 1,
          'goren_kullanici_id': AuthServisi().aktifId,
          'goruldu_tarihi': now,
          'last_updated': now,
        },
        where: 'id = ?',
        whereArgs: [id]);
    final satir = await db.query('onay_talepleri', where: 'id = ?', whereArgs: [id], limit: 1);
    if (satir.isNotEmpty) {
      BulutManager().upsert('onay_talepleri', Map<String, dynamic>.from(satir.first));
    }
  }
}
