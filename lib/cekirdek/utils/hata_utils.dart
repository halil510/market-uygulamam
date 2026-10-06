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
// yakaladı; artık anlaşılır Türkçe bir cümleye çevriliyor. Aynı şekilde
// veritabanı (SQLite), biçim/tip ve dosya hataları da çevrilir; teknik
// ayrıntı bildirim yerine uygulama günlüğünde kalır.

/// Ham hata metnini tanıyan kalıplar (sadeleştirme başlangıcı olarak da kullanılır).
final RegExp _hamHataBaslangici = RegExp(
    r'DioException|SocketException|Failed host lookup|TimeoutException|ClientException|'
    r'HandshakeException|DatabaseException|SqfliteFfiException|SqliteException|'
    r'PostgrestException|AuthException|FormatException|FileSystemException|'
    r'PlatformException|MissingPluginException|RangeError|NoSuchMethodError|'
    r"type '[^']*' is not a subtype|Null check operator|Bad state:|Exception: ");

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

  // ── Veritabanı (SQLite / Supabase Postgrest) ──
  if (RegExp(r'DatabaseException|SqfliteFfiException|SqliteException|PostgrestException')
      .hasMatch(metin)) {
    if (metin.contains('UNIQUE constraint failed') ||
        metin.contains('duplicate key') ||
        metin.contains('23505')) {
      return 'Bu kayıt zaten mevcut (aynı kod/barkod/numara başka bir kayıtta kullanılıyor).';
    }
    if (metin.contains('FOREIGN KEY constraint failed') ||
        metin.contains('23503')) {
      return 'Bu kayıt başka kayıtlarla ilişkili olduğu için işlem yapılamadı.';
    }
    if (metin.contains('NOT NULL constraint failed') ||
        metin.contains('23502')) {
      return 'Zorunlu bir alan boş bırakılmış. Lütfen formu kontrol edin.';
    }
    if (metin.contains('database is locked') || metin.contains('SQLITE_BUSY')) {
      return 'Veritabanı şu an meşgul. Birkaç saniye sonra tekrar deneyin.';
    }
    if (metin.contains('no such table') || metin.contains('no such column')) {
      return 'Veritabanı güncel değil. Uygulamayı yeniden başlatıp tekrar deneyin.';
    }
    if (metin.contains('disk I/O') || metin.contains('database or disk is full')) {
      return 'Veritabanına yazılamadı. Disk dolu olabilir; boş alanı kontrol edin.';
    }
    return 'Veritabanı işlemi tamamlanamadı. Tekrar deneyin; sorun sürerse Ayarlar > Günlük ekranına bakın.';
  }

  if (RegExp(r'AuthException').hasMatch(metin)) {
    return 'Oturum doğrulanamadı. Lütfen tekrar giriş yapın.';
  }
  if (metin.contains('FormatException')) {
    return 'Girilen değer beklenen biçimde değil. Lütfen kontrol edin.';
  }
  if (metin.contains('FileSystemException')) {
    if (metin.contains('Permission denied') || metin.contains('Access is denied') ||
        metin.contains('errno = 5')) {
      return 'Dosyaya erişim izni yok. Dosya başka bir programda açık olabilir.';
    }
    if (metin.contains('No such file') || metin.contains('cannot find')) {
      return 'Dosya bulunamadı.';
    }
    return 'Dosya işlemi tamamlanamadı.';
  }
  if (RegExp(r'PlatformException|MissingPluginException').hasMatch(metin)) {
    return 'Bu özellik bu cihazda kullanılamıyor veya izin verilmedi.';
  }
  if (RegExp(r"RangeError|NoSuchMethodError|type '[^']*' is not a subtype|Null check operator")
      .hasMatch(metin)) {
    return 'Beklenmeyen bir hata oluştu. İşlem tamamlanamadı; tekrar deneyin.';
  }

  const on = 'Exception: ';
  if (metin.startsWith(on)) return metin.substring(on.length);
  const bs = 'Bad state: ';
  if (metin.startsWith(bs)) return metin.substring(bs.length);
  return metin;
}

/// "X yapılamadı: $e" gibi hazır bir bildirim metnindeki ham hata kısmını
/// sadeleştirir (bkz. BildirimServisi.hata/uyari — tüm ekranlar için tek
/// noktadan). Ön metin korunur: "TCMB listesi alınamadı: DioException…"
/// → "TCMB listesi alınamadı: Sunucuya ulaşılamadı…".
String bildirimMetniniSadelestir(String mesaj) {
  final ham = _hamHataBaslangici.firstMatch(mesaj);
  if (ham == null) return mesaj;
  return mesaj.substring(0, ham.start) +
      kullaniciyaHataMetni(mesaj.substring(ham.start));
}
