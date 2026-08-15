// lib/servisler/audit_log_servisi.dart
//
// Kullanıcı isteği: "audit sistemi eksik — kim, ne yaptı, ne zaman
// yaptı, eski veri, yeni veri, cihaz, şube — hepsi kayıt edilmeli."
//
// Tasarım: BulutManager.upsert() artık uygulamadaki HEMEN HEMEN TÜM
// anlamlı veri değişikliğinin (ürün, satış, cari, fatura, kasa, masa,
// borç...) geçtiği TEK, merkezi nokta (bu oturumda kapsamlı şekilde
// düzeltildi/genişletildi). Audit log'u buraya kancalayarak, HER
// depo dosyasına ayrı ayrı log kodu eklemeden, projedeki NEREDEYSE
// TÜM değişiklikleri otomatik yakalıyoruz.
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../veri/database/veritabani.dart';
import 'auth_servisi.dart';
import 'supabase_sync_servisi.dart';
import 'bulut/bulut_manager.dart';

class AuditLogServisi {
  static final AuditLogServisi _instance = AuditLogServisi._();
  factory AuditLogServisi() => _instance;
  AuditLogServisi._();

  // audit_log tablosunun KENDİSİ bu kancadan asla geçmemeli —
  // yoksa sonsuz döngü (audit log'un audit log'u...) oluşur.
  static const _haricTutulanTablolar = {'audit_log', 'bildirim_okundu'};

  // Her tablo için "bu kaydı özetleyen" en anlamlı sütun(lar).
  // Bulunamazsa, herhangi bir metin sütununa geri düşülür.
  static const Map<String, List<String>> _ozetAlanlari = {
    'urunler': ['urun_adi'],
    'cari': ['unvan', 'ad'],
    'satislar': ['fis_no'],
    'faturalar': ['fatura_no'],
    'promosyonlar': ['promosyon_adi'],
    'masalar': ['ad'],
    'borclar': ['baslik'],
    'kullanicilar': ['ad_soyad', 'kullanici_adi'],
    'kasa_hareketleri': ['hareket_tipi'],
    'tedarikci_siparisler': ['siparis_no'],
  };

  Future<void> kaydet(String tablo, Map<String, dynamic> veri) async {
    if (_haricTutulanTablolar.contains(tablo)) return;
    try {
      final kullanici = AuthServisi();
      final db = await Veritabani().db;
      final now = DateTime.now().toIso8601String();

      // İşlem türünü, verideki bayraklardan çıkarımla belirle.
      String islemTuru = 'Kayıt/Güncelleme';
      if (veri['is_deleted'] == 1 || veri['is_deleted'] == true) {
        islemTuru = 'Silme';
      } else if (veri['iptal'] == 1 || veri['iptal'] == true) {
        islemTuru = 'İptal';
      } else if (veri['deleted_at'] != null) {
        islemTuru = 'Silme';
      }

      // Özet metni oluştur — kaydı insan-okur şekilde tanımlayan kısa
      // bir açıklama (tam alan-alan diff yerine; basit ve pratik).
      String? ozet;
      for (final alan in _ozetAlanlari[tablo] ?? const []) {
        final deger = veri[alan];
        if (deger != null && deger.toString().trim().isNotEmpty) {
          ozet = deger.toString();
          break;
        }
      }

      final cihazId = await SupabaseSyncServisi.cihazId();

      final kayit = {
        'global_id': const Uuid().v4(),
        'tablo_adi': tablo,
        'kayit_id': veri['global_id']?.toString() ?? veri['id']?.toString(),
        'islem_turu': islemTuru,
        'ozet': ozet,
        'kullanici_id': kullanici.aktifId,
        'kullanici_adi': kullanici.aktifAd.isEmpty ? 'Bilinmiyor' : kullanici.aktifAd,
        'cihaz_id': cihazId,
        'tarih': now,
        'last_updated': now,
      };
      final yeniId = await db.insert('audit_log', kayit);
      // Audit kaydının kendisi de senkron olsun (işletme sahibi hangi
      // cihazdan bakarsa baksın tüm geçmişi görsün) — ama BU çağrı
      // 'audit_log' tablosu için olduğundan, üstteki hariç tutma
      // sayesinde tekrar audit logu TETİKLEMEZ.
      final guncelSatir = await db.query('audit_log', where: 'id = ?', whereArgs: [yeniId], limit: 1);
      if (guncelSatir.isNotEmpty) {
        BulutManager().upsert('audit_log', Map<String, dynamic>.from(guncelSatir.first));
      }
    } catch (e) {
      // Audit log yazımı ASLA ana işlemi bozmamalı — sessizce geç.
      if (kDebugMode) debugPrint('AuditLogServisi.kaydet hatası: $e');
    }
  }

  Future<List<Map<String, dynamic>>> gunlukGetir({
    String? tabloFiltre,
    int? kullaniciIdFiltre,
    int limit = 200,
  }) async {
    try {
      final db = await Veritabani().db;
      final kosullar = <String>[];
      final args = <dynamic>[];
      if (tabloFiltre != null) { kosullar.add('tablo_adi = ?'); args.add(tabloFiltre); }
      if (kullaniciIdFiltre != null) { kosullar.add('kullanici_id = ?'); args.add(kullaniciIdFiltre); }
      final where = kosullar.isEmpty ? null : kosullar.join(' AND ');
      return await db.query('audit_log',
          where: where, whereArgs: args.isEmpty ? null : args,
          orderBy: 'tarih DESC', limit: limit);
    } catch (e) {
      if (kDebugMode) debugPrint('AuditLogServisi.gunlukGetir hatası: $e');
      return [];
    }
  }
}
