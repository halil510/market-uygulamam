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
import 'aktif_sube_servisi.dart';
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
    // 🔴 DÜZELTME (Madde 18 — Audit Log denetimi, 2026-09-16): 'ayarlar'
    // tablosu hiç yoktu, özet her zaman boş kalıyordu — KDV oranı,
    // fatura no öneki gibi kritik ayar değişiklikleri "kim/ne zaman"
    // dışında hiçbir bilgi taşımıyordu.
    'ayarlar': ['anahtar'],
  };

  /// Bazı kritik tablolar için tek bir alan yeterli açıklayıcı değil —
  /// (Madde 18 denetimi, 2026-09-16) eski/yeni DEĞERİ tutan tam bir diff
  /// sistemi kurmak (her upsert öncesi eski satırı okuyup karşılaştırma)
  /// kapsamlı bir mimari değişiklik gerektirir; bunun yerine, en sık
  /// istismar edilebilecek/denetlenmesi gereken alanlar için TEK satırlık,
  /// düşük riskli bir zenginleştirme eklendi: fiyat, ayar değeri, rol ve
  /// iptal gerekçesi artık özete ekleniyor (önceden sadece "bir şey
  /// değişti" bilgisi vardı, "ne değişti" görünmüyordu).
  String? _zenginlestir(String tablo, Map<String, dynamic> veri, String? ozet,
      {Map<String, dynamic>? eskiVeri}) {
    switch (tablo) {
      case 'urunler':
        final fiyat = veri['satis_fiyati'];
        if (fiyat == null) return ozet;
        // 🔴 DÜZELTME (Madde 14 — Fiyat Onayı denetimi, 2026-09-16): eski
        // fiyat ÖNCEDEN hiç kaydedilmiyordu, sadece yeni değer görünüyordu
        // — "ne değişti" sorusuna cevap yoktu, "şu an ne" cevabı vardı.
        final eskiFiyat = eskiVeri?['satis_fiyati'];
        if (eskiFiyat != null && eskiFiyat != fiyat) {
          return '${ozet ?? 'Ürün'} — ₺$eskiFiyat → ₺$fiyat';
        }
        return '${ozet ?? 'Ürün'} — ₺$fiyat';
      case 'ayarlar':
        final deger = veri['deger'];
        if (deger == null) return ozet;
        return '${ozet ?? 'Ayar'} = $deger';
      case 'kullanicilar':
        final rol = veri['rol'];
        if (rol == null) return ozet;
        return '${ozet ?? 'Kullanıcı'} (rol: $rol)';
      case 'satislar':
        final neden = veri['iptal_nedeni'];
        if (neden == null || neden.toString().trim().isEmpty) return ozet;
        return '${ozet ?? 'Satış'} — neden: $neden';
      default:
        return ozet;
    }
  }

  Future<void> kaydet(String tablo, Map<String, dynamic> veri, {Map<String, dynamic>? eskiVeri}) async {
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
      ozet = _zenginlestir(tablo, veri, ozet, eskiVeri: eskiVeri);

      final cihazId = await SupabaseSyncServisi.cihazId();

      final kayit = {
        'global_id': const Uuid().v4(),
        'tablo_adi': tablo,
        'kayit_id': veri['global_id']?.toString() ?? veri['id']?.toString(),
        'islem_turu': islemTuru,
        'ozet': ozet,
        'kullanici_id': kullanici.aktifId,
        'kullanici_adi': kullanici.aktifAd.isEmpty ? 'Bilinmiyor' : kullanici.aktifAd,
        // 🔴 DÜZELTME (Madde 18/14 denetimi, 2026-09-16): audit_log
        // şemasında sube_id sütunu VARDI ama hiçbir zaman doldurulmuyordu
        // — hangi şubede yapıldığı bilgisi HER satırda sessizce kayboluyordu.
        // Kaydın kendi sube_id'si varsa (satislar/stok_hareket/kasa_
        // hareketleri gibi işlem tabloları) o tercih edilir — o satırın
        // GERÇEKTEN ait olduğu şube budur; yoksa (urunler/cari gibi şube
        // bazlı olmayan tablolar) kullanıcının o an ÇALIŞTIĞI şubeye düşülür.
        'sube_id': veri['sube_id'] ?? AktifSubeServisi().subeId,
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

  // 🔴 DÜZELTME (Madde 18 — Audit Log denetimi, 2026-09-16): başarılı
  // girişler audit_log'a HİÇ düşmüyordu — kullanici_deposu.dart.
  // sonGirisGuncelle() bilinçli olarak BulutManager().upsert
  // ('kullanicilar', ...) çağırmıyor (şifre hash'i dahil tüm satırı her
  // girişte buluta göndermemek için, bkz. o metodun yorumu) — ama bu,
  // "kim ne zaman giriş yaptı" bilgisinin de kaybolması anlamına
  // geliyordu. Başarısız denemeler de sadece SharedPreferences'te
  // (cihaza özel, kalıcı olmayan) bir sayaçta tutuluyordu. Bu metod
  // SADECE audit_log'un kendi (hassas veri içermeyen) satırını yazar —
  // kullanicilar tablosuna hiç dokunmaz, genel kaydet() akışından
  // BAĞIMSIZDIR çünkü kaydet() aktörü AuthServisi().aktifId'den alır —
  // başarısız bir girişte veya PIN ile kullanıcı değiştirmede aktif
  // oturum HENÜZ o kullanıcı olmayabilir, bu yüzden kullaniciId/Adi
  // açıkça parametre olarak alınır.
  Future<void> girisKaydet({
    required int? kullaniciId,
    required String kullaniciAdi,
    required bool basarili,
  }) =>
      olayKaydet(
        tabloAdi: 'kullanicilar',
        kayitId: kullaniciId?.toString(),
        islemTuru: basarili ? 'Giriş' : 'Başarısız Giriş',
        ozet: kullaniciAdi,
        kullaniciId: kullaniciId,
        kullaniciAdi: kullaniciAdi,
      );

  /// Bir tablo satırı değişikliğine bağlı OLMAYAN olayları (giriş, fatura
  /// numara bloğu tahsisi vb.) audit_log'a yazar. [kullaniciId]/[kullaniciAdi]
  /// verilmezse aktif oturum kullanılır. Ana işlemi asla bozmaz.
  Future<void> olayKaydet({
    required String tabloAdi,
    required String islemTuru,
    String? kayitId,
    String? ozet,
    int? kullaniciId,
    String? kullaniciAdi,
  }) async {
    try {
      final db = await Veritabani().db;
      final now = DateTime.now().toIso8601String();
      final cihazId = await SupabaseSyncServisi.cihazId();
      final auth = AuthServisi();
      final ad = kullaniciAdi ?? auth.aktifAd;
      final kayit = {
        'global_id': const Uuid().v4(),
        'tablo_adi': tabloAdi,
        'kayit_id': kayitId,
        'islem_turu': islemTuru,
        'ozet': ozet,
        'kullanici_id': kullaniciId ?? (kullaniciAdi == null ? auth.aktifId : null),
        'kullanici_adi': ad.isEmpty ? 'Bilinmiyor' : ad,
        'sube_id': AktifSubeServisi().subeId,
        'cihaz_id': cihazId,
        'tarih': now,
        'last_updated': now,
      };
      final yeniId = await db.insert('audit_log', kayit);
      final guncelSatir = await db.query('audit_log', where: 'id = ?', whereArgs: [yeniId], limit: 1);
      if (guncelSatir.isNotEmpty) {
        BulutManager().upsert('audit_log', Map<String, dynamic>.from(guncelSatir.first));
      }
    } catch (e) {
      if (kDebugMode) debugPrint('AuditLogServisi.olayKaydet hatası: $e');
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
