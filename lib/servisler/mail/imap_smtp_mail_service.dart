// lib/servisler/mail/imap_smtp_mail_service.dart
//
// Gmail ve Outlook servislerinin ortak IMAP/SMTP mantığı. "Uygulama Şifresi"
// (App Password) yöntemiyle çalışır — OAuth2 gibi Google/Microsoft
// Geliştirici Konsolu'nda uygulama kaydı gerektirmez.
//
// OKUMA (IMAP): imap_ham_istemci.dart — sıfır harici bağımlılık (sadece
// dart:io). enough_mail paketi denendi ama projenin intl/archive/excel
// bağımlılık üçgeniyle KESİN çözülemez bir çakışma yarattığı için
// (bkz. DERIN_YOL_HARITASI.md) minimal, kendi yazdığımız bir istemciyle
// değiştirildi.
//
// GÖNDERME (SMTP): mailer paketi — bu pakette hiçbir çakışma yok, projede
// zaten (başından beri) hazır duruyordu.
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:flutter/foundation.dart';

import 'mail_service.dart';
import 'imap_ham_istemci.dart';

abstract class ImapSmtpMailService implements MailService {
  String get imapHost;
  int get imapPort => 993;
  String get smtpHost;
  int get smtpPort => 587;

  String? _email;
  String? _appSifre;
  String? _sonHata;
  bool _bagli = false;

  @override
  bool get bagli => _bagli;

  @override
  String get hesapAdi => _email ?? '';

  @override
  String? get sonHata => _sonHata;

  @override
  Future<bool> baglan({required String email, required String appSifre}) async {
    _sonHata = null;
    final istemci = ImapHamIstemci(host: imapHost);
    try {
      await istemci.baglan();
      await istemci.girisYap(email, appSifre);
      // Bağlantı gerçekten çalışıyor mu diye gelen kutusunu seçmeyi dene
      await istemci.gelenKutusunuSec();
      await istemci.cikisYap();
      await istemci.kapat();

      _email = email;
      _appSifre = appSifre;
      _bagli = true;
      return true;
    } catch (e) {
      await istemci.kapat();
      if (kDebugMode) debugPrint('🔴 [Mail] Bağlantı hatası: $e');
      final msg = e.toString();
      if (msg.contains('başarısız') || msg.contains('hatalı')) {
        _sonHata = 'E-posta veya uygulama şifresi hatalı. '
            'Normal hesap şifreniz değil, "Uygulama Şifresi" kullanmalısınız.';
      } else if (msg.toLowerCase().contains('socket') ||
          msg.toLowerCase().contains('network') ||
          msg.toLowerCase().contains('timeout') ||
          msg.toLowerCase().contains('zaman aşımı')) {
        _sonHata = 'İnternet bağlantısı kurulamadı. Bağlantınızı kontrol edin.';
      } else {
        _sonHata = 'Bağlantı hatası: $e';
      }
      _bagli = false;
      return false;
    }
  }

  @override
  Future<void> cikis() async {
    _bagli = false;
    _email = null;
    _appSifre = null;
  }

  @override
  Future<List<Mail>> oku({int limit = 50, String? etiket}) async {
    if (!_bagli || _email == null || _appSifre == null) return [];
    final istemci = ImapHamIstemci(host: imapHost);
    try {
      await istemci.baglan();
      await istemci.girisYap(_email!, _appSifre!);
      final hamMesajlar = await istemci.sonMesajlariGetir(limit: limit);
      await istemci.cikisYap();
      await istemci.kapat();
      return hamMesajlar
          .asMap()
          .entries
          .map((e) => Mail(
                id: 'imap_${e.key}_${e.value.tarih.millisecondsSinceEpoch}',
                from: e.value.gonderen,
                to: _email!,
                subject: e.value.konu,
                body: e.value.metinOzeti,
                tarih: e.value.tarih,
                okundu: true,
              ))
          .toList();
    } catch (e) {
      await istemci.kapat();
      if (kDebugMode) debugPrint('🔴 [Mail] Okuma hatası: $e');
      _sonHata = 'Mailler okunamadı: $e';
      return [];
    }
  }

  @override
  Future<bool> gonder({required String to, required String subject, required String body}) async {
    if (!_bagli || _email == null || _appSifre == null) return false;
    try {
      final smtpServer = SmtpServer(
        smtpHost,
        port: smtpPort,
        username: _email,
        password: _appSifre,
        ssl: false,
      );
      final message = Message()
        ..from = Address(_email!)
        ..recipients.add(to)
        ..subject = subject
        ..text = body;
      await send(message, smtpServer);
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('🔴 [Mail] Gönderme hatası: $e');
      _sonHata = 'Mail gönderilemedi: $e';
      return false;
    }
  }
}
