// lib/servisler/ai/ai_model_secici.dart
//
// 🔴 NEDEN BU DOSYA VAR
//
// Google, Gemini model adlarını düzenli olarak kullanımdan kaldırıyor.
// Bu projede model adı 6 AYRI YERE elle yazılmıştı ve her kapatmada
// hepsi tek tek düzeltilmek zorunda kalınıyordu:
//
//   gemini-1.5-flash    → kapatıldı (404)
//   gemini-flash-latest → "deneysel, production için uygun değil"
//   gemini-2.5-flash    → "no longer available to NEW USERS"  ← şu anki hata
//
// Sonuncusu özellikle sinsi: model hâlâ "kullanımdan kalkmadı" ama
// YENİ projelerden erişim kapatılmış. Yani dokümantasyona bakıp
// "hâlâ geçerli" diye düşünmek yetmiyor.
//
// ÇÖZÜM — üç katmanlı:
//   1. Model adı TEK yerde (bu dosya)
//   2. YEDEK LİSTESİ: bir model 404/"no longer available" verirse
//      otomatik olarak sıradaki denenir
//   3. AYARDAN GEÇERSİZ KILMA: kullanıcı Ayarlar'dan kendi model adını
//      yazabilir — Google yarın hepsini kapatsa bile uygulamayı
//      yeniden derlemeye gerek kalmaz
//
// Çalışan model bulununca hafızada tutulur; sonraki isteklerde
// doğrudan o kullanılır (her seferinde baştan denemez).
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AiModelSecici {
  AiModelSecici._();

  /// Ayarlar'dan okunan kullanıcı tercihi (varsa her şeyin önüne geçer).
  static const String ayarAnahtari = 'ai_model_adi';

  /// Denenecek modeller — sırayla.
  ///
  /// Sıralama mantığı: önce güncel ve üretim için önerilenler, sonra
  /// eskiler. Biri "no longer available" derse sıradakine geçilir.
  ///
  /// NOT: Bu liste bir TAHMİN değil, Google'ın kendi geçiş
  /// dokümantasyonundan alındı (Firebase AI Logic, 2026-03/04):
  /// "update to a newer model like gemini-2.5-flash-lite".
  static const List<String> yedekModeller = [
    'gemini-2.5-flash-lite',  // Google'ın resmi geçiş önerisi
    'gemini-2.5-flash',       // önceki varsayılan (yeni projelerde kapalı)
    'gemini-flash-latest',    // takma ad — deneysel ama son çare olarak çalışır
    'gemini-2.0-flash',       // eski kararlı
  ];

  /// Bu oturumda çalıştığı doğrulanmış model.
  static String? _calisanModel;

  /// Kullanıcının ayardan verdiği model (bir kez okunur).
  static String? _kullaniciModeli;
  static bool _ayarOkundu = false;

  static Future<void> _ayarOku() async {
    if (_ayarOkundu) return;
    _ayarOkundu = true;
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getString(ayarAnahtari)?.trim();
      if (v != null && v.isNotEmpty) _kullaniciModeli = v;
    } catch (_) {
      // ayar okunamazsa varsayılan listeyle devam
    }
  }

  /// Denenecek model listesi — öncelik sırasıyla.
  static Future<List<String>> adaylar() async {
    await _ayarOku();
    final liste = <String>[];
    if (_kullaniciModeli != null) liste.add(_kullaniciModeli!);
    if (_calisanModel != null && !liste.contains(_calisanModel)) {
      liste.add(_calisanModel!);
    }
    for (final m in yedekModeller) {
      if (!liste.contains(m)) liste.add(m);
    }
    return liste;
  }

  /// Tek denemelik kullanımlar için ilk (en olası) model adı.
  ///
  /// Sohbet gibi kritik akışlar `adaylar()` ile TÜM listeyi deneyip
  /// yedeğe düşer. Görsel/ürün analizi gibi tek atımlık çağrılarda ise
  /// bu kısayol kullanılır: kullanıcı ayarı varsa o, yoksa bu oturumda
  /// çalıştığı doğrulanmış model, o da yoksa listenin ilki.
  static Future<String> ilkAday() async => (await adaylar()).first;

  /// Bir modelin çalıştığını işaretle — sonraki çağrılar doğrudan bunu kullanır.
  static void calistiIsaretle(String model) {
    if (_calisanModel != model) {
      _calisanModel = model;
      if (kDebugMode) debugPrint('AI modeli: $model');
    }
  }

  /// Hata "bu model artık yok" anlamına mı geliyor?
  ///
  /// Google bu durumu birden fazla biçimde bildiriyor; hepsini yakalar.
  static bool modelYokHatasi(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('no longer available') ||
        s.contains('not found') ||
        s.contains('404') ||
        s.contains('is not supported') ||
        s.contains('unsupported model');
  }

  /// Kullanıcıya gösterilecek açıklayıcı mesaj (tüm modeller başarısızsa).
  static String tumModellerBasarisizMesaji() =>
      'Hiçbir Gemini modeline erişilemedi. Google model adlarını '
      'değiştirmiş olabilir.\n\n'
      'Ayarlar ▸ Yapay Zekâ ekranından güncel bir model adı '
      'girebilirsiniz (ör. gemini-2.5-flash-lite). Uygulamayı yeniden '
      'kurmanıza gerek yok.';

  /// Ayardan model adını kaydet.
  static Future<void> modelKaydet(String model) async {
    final p = await SharedPreferences.getInstance();
    final temiz = model.trim();
    if (temiz.isEmpty) {
      await p.remove(ayarAnahtari);
      _kullaniciModeli = null;
    } else {
      await p.setString(ayarAnahtari, temiz);
      _kullaniciModeli = temiz;
    }
    _calisanModel = null;   // yeniden keşfedilsin
    _ayarOkundu = true;
  }

  /// Ayardaki mevcut model adı (arayüzde göstermek için).
  static Future<String?> mevcutAyar() async {
    await _ayarOku();
    return _kullaniciModeli;
  }
}
