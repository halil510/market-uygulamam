// lib/servisler/mail/outlook_service.dart
import 'imap_smtp_mail_service.dart';

/// Outlook / Microsoft 365 — gerçek IMAP (okuma) + SMTP (gönderme)
/// bağlantısı. Hesap ayarlarından oluşturulan Uygulama Şifresi ile çalışır.
class OutlookService extends ImapSmtpMailService {
  @override
  String get imapHost => 'outlook.office365.com';

  @override
  String get smtpHost => 'smtp.office365.com';
}
