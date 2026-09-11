// lib/servisler/masa/urun_resim_yukleme_servisi.dart
//
// Kullanıcı isteği: "ürün kaydederken görsel otomatik olarak buluta
// yüklensin" — QR bulut menüde ürün görselleri görünebilsin diye.
// ÖNCEDEN ürün görselleri sadece cihazın KENDİ dosya sisteminde
// (resim_yolu) saklanıyordu — bu, müşterinin telefonundan asla
// erişilemez bir konumdu. Bu servis, kaydedilen görseli Supabase
// Storage'a (bulut) yükleyip, sonucunda oluşan HERKESE AÇIK adresi
// döndürüyor — bu adres "resim_url" sütununda saklanıyor.
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../bulut/supabase_ayarlari.dart';

class UrunResimYuklemeServisi {
  static final UrunResimYuklemeServisi _instance = UrunResimYuklemeServisi._();
  factory UrunResimYuklemeServisi() => _instance;
  UrunResimYuklemeServisi._();

  static const String _bucket = 'urun-resimleri';

  /// Yerel görsel dosyasını Supabase Storage'a yükler, başarılıysa
  /// herkese açık adresi döndürür. Başarısız olursa (internet yok,
  /// bucket henüz oluşturulmamış vb.) null döner — bu durumda ürün
  /// KAYDI hiçbir şekilde ENGELLENMEZ, sadece bulut görseli olmadan
  /// devam eder (yerel görsel gösterimini etkilemez).
  Future<String?> yukle(String yerelDosyaYolu, int urunId) async {
    try {
      final dosya = File(yerelDosyaYolu);
      if (!await dosya.exists()) return null;

      final url = await SupabaseAyarlari.urlOku();
      final key = await SupabaseAyarlari.keyOku();
      if (url == null || key == null || url.isEmpty || key.isEmpty) return null;

      final uzanti = yerelDosyaYolu.split('.').last.toLowerCase();
      final dosyaAdi = 'urun_$urunId.$uzanti';
      final bytes = await dosya.readAsBytes();

      final yanit = await http.post(
        Uri.parse('$url/storage/v1/object/$_bucket/$dosyaAdi'),
        headers: {
          'apikey': key,
          'Authorization': 'Bearer $key',
          'Content-Type': _mimeTuru(uzanti),
          'x-upsert': 'true', // aynı ürün tekrar yüklenirse üzerine yazsın
        },
        body: bytes,
      ).timeout(const Duration(seconds: 20));

      if (yanit.statusCode == 200 || yanit.statusCode == 201) {
        return '$url/storage/v1/object/public/$_bucket/$dosyaAdi';
      }
      if (kDebugMode) {
        debugPrint('Görsel yükleme başarısız (${yanit.statusCode}): ${yanit.body}');
      }
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('Görsel yükleme hatası: $e');
      return null;
    }
  }

  String _mimeTuru(String uzanti) => switch (uzanti) {
        'png' => 'image/png',
        'gif' => 'image/gif',
        'webp' => 'image/webp',
        _ => 'image/jpeg',
      };
}
