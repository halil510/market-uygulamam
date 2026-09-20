// lib/servisler/gib/gib_ayar_yoneticisi.dart
//
// GİB entegrasyon ayarlarının (API URL, kullanıcı adı/şifre, mali mühür
// şifresi, firma bilgileri, test modu) TEK kaynaktan (SQLite 'ayarlar'
// tablosu + flutter_secure_storage) yüklenmesi ve eski, kullanılmayan
// SharedPreferences kayıtlarından güvenli depoya taşınması.
//
// (Madde 2 mimari denetimi — gib_servisi.dart 1045 satırlık tek dosyaydı,
// ayarlar yükleme/taşıma mantığı kendi başına ~95 satırlık bağımsız bir
// sorumluluktu. Buraya TAŞINDI — DAVRANIŞ DEĞİŞMEDİ, saf bir extract
// class refactor'ü. Orijinal yorumlar/gerekçeler aynen korunuyor.)
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite/sqflite.dart';
import '../../veri/database/veritabani.dart';

class GibAyarYoneticisi {
  String? apiUrl;
  String? kullaniciAdi;
  String? sifre;
  // 🔴 NOT (kullanıcı isteği üzerine derin analiz): Bu alan okunuyor
  // (aşağıda) ama XML'de/imzalama işleminde KULLANILMIYOR — bu BİLEREK
  // böyle bırakıldı, eksiklik değil: Gerçek mali mühür imzalama
  // (XAdES-BES, kriptografik özel anahtar + HSM/akıllı kart erişimi
  // gerektirir) entegratör tarafında, ENTEGRATÖRÜN KENDİ sunucusunda
  // yapılır — bir mobil uygulamanın bunu taklit etmeye çalışması hem
  // güvenlik riski hem de teknik olarak yanlış olurdu. Bu şifre alanı,
  // SADECE kullandığınız entegratörün REST API'si bunu (nadir de olsa)
  // istek gövdesinde bekliyorsa kullanılmak üzere saklanıyor —
  // kullandığınız entegratörün dokümantasyonuna göre 'gonder()'
  // fonksiyonundaki istek gövdesine eklenmesi gerekebilir.
  String? maliMuhurSifre;
  String? firmaVkn;
  String firmaAdi = '';
  String firmaAdres = '';
  String firmaVergiDairesi = '';
  bool testModu = true;

  Future<void> yukle() async {
    try {
      // ÖNCEDEN BURADA ÇOK CİDDİ BİR MİMARİ HATA VARDI: bu fonksiyon
      // SharedPreferences'tan okuyordu, AMA gib_ayar_ekrani.dart (ayar
      // giriş ekranı) her zaman SQLite 'ayarlar' tablosuna yazıyordu —
      // yani kullanıcı ayarlar ekranına ne girip kaydederse kaydetsin,
      // GERÇEK GİB SERVİSİ BUNU HİÇBİR ZAMAN GÖRMÜYORDU (iki farklı
      // depolama sistemi, birbirinden habersiz). Artık TEK kaynak
      // (SQLite 'ayarlar' tablosu) kullanılıyor — ayarlar ekranıyla
      // birebir aynı yerden okunuyor. Ayrıca kimlik doğrulama tek bir
      // "API Key" yerine gerçek entegratör mimarisine uygun Kullanıcı
      // Adı + Şifre olarak güncellendi.
      final db = await Veritabani().db;
      final rows = await db.query('ayarlar', where:
          "anahtar IN ('gib_api_url','gib_kullanici_adi',"
          "'firma_vergi_no','firma_adi','firma_adres',"
          "'firma_vergi_dairesi','gib_test_modu')");
      final map = {for (final r in rows) r['anahtar'] as String: r['deger'] as String};

      // ÖNCEDEN gib_sifre/gib_mali_muhur_sifre de SQLite'tan (düz metin)
      // okunuyordu — güvenlik açığıydı. Artık ayarlar ekranıyla AYNI
      // güvenli depolamadan (flutter_secure_storage) okunuyor.
      const secure = FlutterSecureStorage();

      testModu = map['gib_test_modu'] != '0';
      final kayitliUrl = map['gib_api_url'] ?? '';
      // 🔴🔴🔴 KRİTİK DÜZELTME (bağımsız araştırmayla doğrulandı — bkz.
      // GİB'in kendi e-Arşiv Portal Entegrasyon Kılavuzu): ÖNCEDEN, kullanıcı
      // hiçbir URL girmediğinde buraya GİB'İN KENDİ PORTAL ADRESİ
      // (earsivportal.efatura.gov.tr) varsayılan olarak atanıyordu. Ama bu
      // adres, mali mühür/e-imza veya İnteraktif Vergi Dairesi şifresiyle
      // MANUEL giriş yapılan bir web portalıdır — programatik bir REST
      // API'si YOKTUR ("efatura.gov.tr üzerinden ... API yoktur; yazılım
      // entegrasyonuna imkan vermez"). Bu dosyanın çağırdığı uç noktalar
      // (/general/GlobalCompany, /invoice/send vb.) SADECE özel
      // entegratörlerin (Nilvera, Uyumsoft, Foriba vb.) REST API'lerinde
      // bulunur. Yanlış varsayılan yüzünden, kullanıcı entegratör bilgilerini
      // hiç girmese bile 'ayarliMi' true dönüyor ve sistem sessizce GİB'in
      // kendi (çalışmayacak) portal adresine istek atmaya çalışıyordu —
      // kullanıcı "ayarlarınızı girin" yerine anlamsız bir bağlantı hatası
      // görüyordu. Artık URL boşsa null bırakılıyor; 'ayarliMi' bunu
      // yakalayıp NET bir "entegratör API adresinizi girin" mesajı veriyor.
      apiUrl = kayitliUrl.isNotEmpty ? kayitliUrl : null;

      kullaniciAdi      = map['gib_kullanici_adi'];
      sifre             = await secure.read(key: 'gib_sifre');
      maliMuhurSifre    = await secure.read(key: 'gib_mali_muhur_sifre');
      firmaVkn          = map['firma_vergi_no'];
      firmaAdi          = map['firma_adi'] ?? '';
      firmaAdres        = map['firma_adres'] ?? '';
      firmaVergiDairesi = map['firma_vergi_dairesi'] ?? '';

      // 🔴🔴 GÜVEN KURTARMA GÖÇÜ (2026-09-14 derin analizde bulundu):
      // fatura_ayar_ekrani.dart'ın "e-Fatura" sekmesi ÖNCEDEN GİB
      // kullanıcı adı/şifre/URL'sini bu servisin hiç bakmadığı AYRI bir
      // depoya (SharedPreferences) yazıyordu — o ekranı kullanan biri
      // "kaydedildi" görüp aslında hiçbir zaman gerçek ayara ulaşmamış
      // olabilir. O ekrandaki alanlar artık kaldırıldı, ama bu cihazda
      // hâlâ o eski, kullanılmayan veriler duruyor olabilir. Gerçek
      // ayar (SQLite/secure storage) HÂLÂ BOŞSA ve eski SharedPreferences
      // kaydı DOLUYSA, sessizce buraya taşınır — kullanıcı yeniden
      // girmek zorunda kalmaz. Gerçek ayar zaten doluysa dokunulmaz.
      if ((kullaniciAdi == null || kullaniciAdi!.isEmpty) && apiUrl == null) {
        try {
          final prefs = await SharedPreferences.getInstance();
          final eskiUrl = prefs.getString('gib_api_url');
          final eskiKullanici = prefs.getString('gib_kullanici');
          final eskiSifre = prefs.getString('gib_sifre');
          if ((eskiUrl?.isNotEmpty ?? false) && (eskiKullanici?.isNotEmpty ?? false)) {
            await db.insert('ayarlar', {'anahtar': 'gib_api_url', 'deger': eskiUrl},
                conflictAlgorithm: ConflictAlgorithm.replace);
            await db.insert('ayarlar', {'anahtar': 'gib_kullanici_adi', 'deger': eskiKullanici},
                conflictAlgorithm: ConflictAlgorithm.replace);
            if (eskiSifre?.isNotEmpty ?? false) {
              await secure.write(key: 'gib_sifre', value: eskiSifre);
            }
            apiUrl = eskiUrl;
            kullaniciAdi = eskiKullanici;
            sifre = eskiSifre;
            // 🔴 Derin denetimde bulundu (P2): taşıma başarılı olduktan
            // sonra eski, düz-metin SharedPreferences kayıtları (özellikle
            // 'gib_sifre') HİÇ silinmiyordu — güvenli depoya kopyalandıktan
            // sonra bile şifre, cihazda korumasız bir ikinci kopya olarak
            // kalıcı biçimde duruyordu. Artık taşıma tamamlanınca temizleniyor.
            await prefs.remove('gib_api_url');
            await prefs.remove('gib_kullanici');
            await prefs.remove('gib_sifre');
            if (kDebugMode) debugPrint('GİB ayarları eski (kullanılmayan) depodan taşındı');
          }
        } catch (e) {
          if (kDebugMode) debugPrint('GİB eski ayar taşıma hatası: $e');
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('GIB ayar yükleme hatası: $e');
    }
  }

  bool get ayarliMi =>
      apiUrl != null && kullaniciAdi != null && sifre != null && firmaVkn != null;

  /// Kullanıcı Adı+Şifre'den Basic Auth başlığı üretir — gerçek
  /// entegratör API'lerinin (Foriba, Sovos, Uyumsoft vb.) yaygın kimlik
  /// doğrulama yöntemi budur.
  String get authHeader =>
      'Basic ${base64Encode(utf8.encode('$kullaniciAdi:$sifre'))}';
}
