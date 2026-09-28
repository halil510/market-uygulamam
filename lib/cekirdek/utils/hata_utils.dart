// lib/cekirdek/utils/hata_utils.dart
//
// Kullanıcıya gösterilecek hata metni üretir. Dart'ın `Exception`
// sınıfı, iş mantığının bilinçli attığı ("Bu sipariş zaten teslim
// alınmış." gibi) kullanıcı-dostu mesajların önüne otomatik olarak
// "Exception: " ekler — bu ön ek geliştiriciye anlamlı, kasiyer/garson
// gibi son kullanıcıya ise teknik ve güven verici olmayan görünür.
//
// Ağ hataları (Dio/Socket/Timeout/http) ise ham haliyle İngilizce ve
// uzun ("DioException [bad response]: This exception was thrown…") —
// uygulama robotu bu metinlerin ekranda kullanıcıya gösterildiğini
// yakaladı; artık anlaşılır Türkçe bir cümleye çevriliyor.
String kullaniciyaHataMetni(Object hata) {
  final metin = hata.toString();

  final agHatasi = RegExp(
          r'DioException|SocketException|Failed host lookup|Connection (refused|reset|closed)|'
          r'TimeoutException|ClientException|HandshakeException|Network is unreachable')
      .hasMatch(metin);
  if (agHatasi) {
    final kod = RegExp(r'status code of (\d{3})').firstMatch(metin)?.group(1);
    if (kod != null) {
      return 'Sunucu isteği kabul etmedi (hata kodu $kod). Lütfen daha sonra tekrar deneyin.';
    }
    if (metin.contains('Timeout') || metin.contains('timed out')) {
      return 'Sunucu zamanında yanıt vermedi. İnternet bağlantınızı kontrol edip tekrar deneyin.';
    }
    return 'Sunucuya ulaşılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.';
  }

  const on = 'Exception: ';
  return metin.startsWith(on) ? metin.substring(on.length) : metin;
}

/// "X yapılamadı: $e" gibi hazır bir bildirim metnindeki ham hata kısmını
/// sadeleştirir (bkz. BildirimServisi.hata/uyari — tüm ekranlar için tek
/// noktadan). Ön metin korunur: "TCMB listesi alınamadı: DioException…"
/// → "TCMB listesi alınamadı: Sunucuya ulaşılamadı…".
String bildirimMetniniSadelestir(String mesaj) {
  final ham = RegExp(
          r'DioException|SocketException|Failed host lookup|TimeoutException|ClientException|'
          r'HandshakeException|Exception: ')
      .firstMatch(mesaj);
  if (ham == null) return mesaj;
  return mesaj.substring(0, ham.start) + kullaniciyaHataMetni(mesaj.substring(ham.start));
}
