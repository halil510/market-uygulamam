// lib/servisler/bulut/supabase_ayarlari.dart
//
// Supabase bağlantı URL'si ve API anahtarının TEK okuma/yazma noktası.
//
// 🔴 Derin analizde bulundu: bu anahtar — kullanıcı isterse RLS'i atlayan
// tam yetkili bir "sb_secret_" servis anahtarı da girebiliyor (bkz.
// bulut_sync_ekrani.dart'taki "Secret anahtar kaydedildi ✓ — tam yetkili
// senkron aktif" akışı) — önceden SharedPreferences'ta DÜZ METİN
// saklanıyordu; aynı projede Gemini API anahtarı zaten
// flutter_secure_storage kullanıyordu (ai_vision_servisi.dart). Artık
// aynı desen burada da uygulanıyor. Eski düz metin değerler ilk okumada
// otomatik güvenli depoya taşınıp SharedPreferences'tan silinir.
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SupabaseAyarlari {
  static const _secure = FlutterSecureStorage();
  static const _kUrl = 'mp_supabase_url_secure';
  static const _kKey = 'mp_supabase_key_secure';

  // Eski (düz metin) anahtarlar — sadece bir kerelik taşıma için okunur.
  // 'mp_supa_*' daha da eski, kullanılmayan bir isimlendirmeydi
  // (bkz. bulut_manager.dart'taki geriye dönük uyumluluk notu).
  static const _eskiUrlAnahtarlari = ['mp_supabase_url', 'mp_supa_url'];
  static const _eskiKeyAnahtarlari = ['mp_supabase_key', 'mp_supa_key'];

  static Future<void> _eskiDegerleriTasi() async {
    final urlVar = await _secure.read(key: _kUrl);
    final keyVar = await _secure.read(key: _kKey);
    if (urlVar != null && keyVar != null) return; // zaten taşınmış

    final prefs = await SharedPreferences.getInstance();
    String? eskiUrl, eskiKey;
    for (final k in _eskiUrlAnahtarlari) {
      final v = prefs.getString(k);
      if (v != null && v.isNotEmpty) { eskiUrl = v; break; }
    }
    for (final k in _eskiKeyAnahtarlari) {
      final v = prefs.getString(k);
      if (v != null && v.isNotEmpty) { eskiKey = v; break; }
    }
    if (eskiUrl != null && eskiKey != null) {
      await _secure.write(key: _kUrl, value: eskiUrl);
      await _secure.write(key: _kKey, value: eskiKey);
    }
    // Düz metin izlerini her durumda temizle.
    for (final k in [..._eskiUrlAnahtarlari, ..._eskiKeyAnahtarlari]) {
      await prefs.remove(k);
    }
  }

  static Future<String?> urlOku() async {
    await _eskiDegerleriTasi();
    return _secure.read(key: _kUrl);
  }

  static Future<String?> keyOku() async {
    await _eskiDegerleriTasi();
    return _secure.read(key: _kKey);
  }

  static Future<void> kaydet({required String url, required String key}) async {
    await _secure.write(key: _kUrl, value: url);
    await _secure.write(key: _kKey, value: key);
  }

  static Future<void> temizle() async {
    await _secure.delete(key: _kUrl);
    await _secure.delete(key: _kKey);
  }
}
