// lib/servisler/mail/gmail_service.dart
import 'imap_smtp_mail_service.dart';

/// Gmail — gerçek IMAP (okuma) + SMTP (gönderme) bağlantısı.
/// Google Hesabı > Güvenlik > Uygulama Şifreleri'nden alınan 16 haneli
/// şifre ile çalışır (normal hesap şifresi DEĞİL).
class GmailService extends ImapSmtpMailService {
  @override
  String get imapHost => 'imap.gmail.com';

  @override
  String get smtpHost => 'smtp.gmail.com';
}
