// lib/servisler/mail/mail_service.dart
abstract class MailService {
  /// Gerçek IMAP/SMTP bağlantısı kurar (Google/Microsoft "Uygulama Şifresi"
  /// ile). Başarısız olursa false döner — false döndüğünde çağıran taraf
  /// `sonHata` üzerinden kullanıcıya gösterilecek anlaşılır bir mesaj
  /// okuyabilir.
  Future<bool> baglan({required String email, required String appSifre});

  Future<void> cikis();
  bool get bagli;
  String get hesapAdi;

  /// Son bağlantı/okuma/gönderme denemesinde oluşan, kullanıcıya
  /// gösterilebilecek anlaşılır hata mesajı (yoksa null).
  String? get sonHata;

  Future<List<Mail>> oku({int limit = 50, String? etiket});
  Future<bool> gonder({required String to, required String subject, required String body});
}

class Mail {
  final String id;
  final String from;
  final String to;
  final String subject;
  final String body;
  final DateTime tarih;
  final bool okundu;
  final List<String> etiketler;

  const Mail({
    required this.id,
    required this.from,
    required this.to,
    required this.subject,
    required this.body,
    required this.tarih,
    this.okundu = false,
    this.etiketler = const [],
  });
}
