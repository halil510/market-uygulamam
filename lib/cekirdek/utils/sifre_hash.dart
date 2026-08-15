// lib/cekirdek/utils/sifre_hash.dart
//
// Şifre hashleme yardımcıları — hem AuthServisi hem KullaniciDeposu
// tarafından kullanılıyor (dairesel import olmaması için ayrı dosyada).
//
// GÜVENLİK NOTU: Önceden şifreler tuzsuz (salt'sız) düz SHA-256 ile
// hashleniyordu — rainbow table saldırılarına açık, modern donanımla
// kaba kuvvete dayanıksız bir yöntemdi. Artık her kullanıcı için
// rastgele bir tuz üretilip, HMAC-SHA256'nın binlerce kez tekrarlanmasıyla
// (basit bir PBKDF2 yaklaşımı) çok daha güvenli bir hash üretiliyor.
import 'dart:convert';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';

class SifreHash {
  static const int tekrarSayisi = 10000;

  /// ESKİ (tuzsuz) hash — sadece geriye dönük uyumluluk/migration
  /// kontrolü için tutuluyor, YENİ şifrelerde KULLANILMIYOR.
  static String eskiHashle(String sifre) =>
      sha256.convert(utf8.encode(sifre)).toString();

  /// Rastgele, kriptografik olarak güvenli 32 karakterlik bir tuz üretir.
  static String tuzUret() {
    final rnd = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Tuzlu, çok turlu hash — HMAC-SHA256'nın [tekrarSayisi] kez iç içe
  /// uygulanmasıyla üretilir.
  static String hashleTuzlu(String sifre, String tuz) {
    List<int> veri = utf8.encode(sifre + tuz);
    final anahtar = utf8.encode(tuz);
    for (var i = 0; i < tekrarSayisi; i++) {
      veri = Hmac(sha256, anahtar).convert(veri).bytes;
    }
    return veri.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
