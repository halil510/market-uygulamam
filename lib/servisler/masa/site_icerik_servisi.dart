// lib/servisler/masa/site_icerik_servisi.dart
//
// Kullanıcı isteği: "işyeri fotoğrafları da uygulamadan yüklensin —
// HTML'i sürekli değiştirip durmayalım." ÖNCEDEN web sitesindeki
// "İşyerimizden Kareler" fotoğrafları HTML dosyasının İÇİNDE sabit
// yazılıydı — her değişiklikte dosyayı düzenleyip Netlify'a yeniden
// yüklemek gerekiyordu. Artık:
//   1. Fotoğraflar uygulamadan Supabase Storage'a yükleniyor
//      (urun_resim_yukleme_servisi ile AYNI kanıtlanmış desen)
//   2. Adres listesi "site_icerik" tablosunda saklanıyor
//   3. Web sitesi açılışta bu listeyi çekip galeriyi kendisi kuruyor
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../bulut/supabase_ayarlari.dart';

class SiteIcerikServisi {
  static final SiteIcerikServisi _instance = SiteIcerikServisi._();
  factory SiteIcerikServisi() => _instance;
  SiteIcerikServisi._();

  static const String _bucket = 'isyeri-fotograflari';
  static const String _anahtar = 'isyeri_gorselleri';
  // FAZ 1 UI/UX: qr_menu_sayfasi.html'deki işletme adı/alt yazı/hakkımızda
  // metni/iletişim/konum/istatistik bilgileri ÖNCEDEN sadece HTML dosyasının
  // içine sabit yazılıydı — her değişiklikte dosyayı elden düzenleyip
  // yeniden yüklemek gerekiyordu. Fotoğraf galerisiyle AYNI kanıtlanmış
  // desen (site_icerik key-value tablosu) kullanılarak buraya taşındı.
  static const String _icerikAnahtari = 'isletme_bilgileri';

  Future<(String, String)?> _ayar() async {
    final url = await SupabaseAyarlari.urlOku();
    final key = await SupabaseAyarlari.keyOku();
    if (url == null || key == null || url.isEmpty || key.isEmpty) return null;
    return (url, key);
  }

  Map<String, String> _h(String key, {String? contentType}) => {
        'apikey': key,
        'Authorization': 'Bearer $key',
        if (contentType != null) 'Content-Type': contentType,
      };

  /// Buluttaki mevcut fotoğraf adreslerini getirir.
  Future<List<String>> gorselleriGetir() async {
    try {
      final a = await _ayar();
      if (a == null) return [];
      final (url, key) = a;
      final r = await http
          .get(
            Uri.parse(
                '$url/rest/v1/site_icerik?anahtar=eq.$_anahtar&select=deger'),
            headers: _h(key),
          )
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return [];
      final rows = jsonDecode(r.body) as List;
      if (rows.isEmpty || rows.first['deger'] == null) return [];
      return (jsonDecode(rows.first['deger'] as String) as List)
          .map((e) => e.toString())
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('SiteIcerik getir hatası: $e');
      return [];
    }
  }

  /// Fotoğraf listesini buluta kaydeder (site_icerik upsert).
  Future<bool> gorselleriKaydet(List<String> adresler) async {
    try {
      final a = await _ayar();
      if (a == null) return false;
      final (url, key) = a;
      final r = await http
          .post(
            Uri.parse('$url/rest/v1/site_icerik?on_conflict=anahtar'),
            headers: {
              ..._h(key, contentType: 'application/json'),
              'Prefer': 'resolution=merge-duplicates,return=minimal',
            },
            body: jsonEncode({
              'anahtar': _anahtar,
              'deger': jsonEncode(adresler),
              'last_updated': DateTime.now().toUtc().toIso8601String(),
            }),
          )
          .timeout(const Duration(seconds: 15));
      return r.statusCode >= 200 && r.statusCode < 300;
    } catch (e) {
      if (kDebugMode) debugPrint('SiteIcerik kaydet hatası: $e');
      return false;
    }
  }

  /// Buluttaki güncel işletme bilgilerini getirir (yoksa null — site
  /// kendi hardcoded yedeğini kullanır, hiçbir şey bozulmaz).
  Future<Map<String, dynamic>?> isletmeBilgileriGetir() async {
    try {
      final a = await _ayar();
      if (a == null) return null;
      final (url, key) = a;
      final r = await http
          .get(
            Uri.parse(
                '$url/rest/v1/site_icerik?anahtar=eq.$_icerikAnahtari&select=deger'),
            headers: _h(key),
          )
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return null;
      final rows = jsonDecode(r.body) as List;
      if (rows.isEmpty || rows.first['deger'] == null) return null;
      return jsonDecode(rows.first['deger'] as String) as Map<String, dynamic>;
    } catch (e) {
      if (kDebugMode) debugPrint('İşletme bilgileri getir hatası: $e');
      return null;
    }
  }

  /// İşletme bilgilerini buluta kaydeder (site_icerik upsert).
  Future<bool> isletmeBilgileriKaydet(Map<String, dynamic> veri) async {
    try {
      final a = await _ayar();
      if (a == null) return false;
      final (url, key) = a;
      final r = await http
          .post(
            Uri.parse('$url/rest/v1/site_icerik?on_conflict=anahtar'),
            headers: {
              ..._h(key, contentType: 'application/json'),
              'Prefer': 'resolution=merge-duplicates,return=minimal',
            },
            body: jsonEncode({
              'anahtar': _icerikAnahtari,
              'deger': jsonEncode(veri),
              'last_updated': DateTime.now().toUtc().toIso8601String(),
            }),
          )
          .timeout(const Duration(seconds: 15));
      return r.statusCode >= 200 && r.statusCode < 300;
    } catch (e) {
      if (kDebugMode) debugPrint('İşletme bilgileri kaydet hatası: $e');
      return false;
    }
  }

  /// Yerel fotoğrafı Storage'a yükler, herkese açık adresini döndürür.
  Future<String?> fotoYukle(String yerelYol) async {
    try {
      final dosya = File(yerelYol);
      if (!await dosya.exists()) return null;
      final a = await _ayar();
      if (a == null) return null;
      final (url, key) = a;

      final uzanti = yerelYol.split('.').last.toLowerCase();
      final dosyaAdi =
          'isyeri_${DateTime.now().millisecondsSinceEpoch}.$uzanti';
      final bytes = await dosya.readAsBytes();

      final r = await http
          .post(
            Uri.parse('$url/storage/v1/object/$_bucket/$dosyaAdi'),
            headers: {
              ..._h(key),
              'Content-Type': switch (uzanti) {
                'png' => 'image/png',
                'webp' => 'image/webp',
                _ => 'image/jpeg',
              },
              'x-upsert': 'true',
            },
            body: bytes,
          )
          .timeout(const Duration(seconds: 30));

      if (r.statusCode == 200 || r.statusCode == 201) {
        return '$url/storage/v1/object/public/$_bucket/$dosyaAdi';
      }
      if (kDebugMode)
        debugPrint('Foto yükleme başarısız (${r.statusCode}): ${r.body}');
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('Foto yükleme hatası: $e');
      return null;
    }
  }

  /// Storage'dan fotoğrafı siler (listeden çıkarma ayrıca yapılır).
  Future<void> fotoSil(String adres) async {
    try {
      final a = await _ayar();
      if (a == null) return;
      final (url, key) = a;
      final parca = '/storage/v1/object/public/$_bucket/';
      if (!adres.contains(parca)) return;
      final dosyaAdi = adres.split(parca).last;
      await http
          .delete(
            Uri.parse('$url/storage/v1/object/$_bucket/$dosyaAdi'),
            headers: _h(key),
          )
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      if (kDebugMode) debugPrint('Foto silme hatası: $e');
    }
  }
}
