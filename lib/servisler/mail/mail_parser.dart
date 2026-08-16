// lib/servisler/mail/mail_parser.dart
import 'mail_service.dart';

class MailParser {
  static const _borcPatterns = [
    r'(?i)borç|borc|ödeme|öde|fatura|kredi kartı|kredi karti|taksit',
    r'(?i)vadesi[ ]?geçen|vadesi[ ]?gecen|gecikme|gecikmis',
    r'(?i)son[ ]?ödeme|son[ ]?odeme|tarihi|tarih',
  ];

  static List<Map<String, dynamic>> borcTespitEt(List<Mail> mails) {
    final sonuclar = <Map<String, dynamic>>[];
    for (final mail in mails) {
      final text = '${mail.subject} ${mail.body}';
      final eslesme = _borcPatterns.any((p) => RegExp(p).hasMatch(text));
      if (eslesme) {
        sonuclar.add({
          'mail': mail,
          'tutar': _tutarCikar(text),
          'sonOdeme': _sonOdemeCikar(text),
          'firma': _firmaCikar(mail.from),
        });
      }
    }
    return sonuclar;
  }

  static double _tutarCikar(String text) {
    final match = RegExp(r'(\d+)[,.](\d{2})\s*(TL|₺|TRY)').firstMatch(text);
    if (match != null) {
      return double.tryParse('${match.group(1)}.${match.group(2)}') ?? 0;
    }
    final match2 = RegExp(r'(\d+)\s*(TL|₺|TRY)').firstMatch(text);
    if (match2 != null) {
      return double.tryParse(match2.group(1) ?? '0') ?? 0;
    }
    return 0;
  }

  static DateTime? _sonOdemeCikar(String text) {
    // 🔴 DÜZELTME: Önceden her iki desen için de (DD.MM.YYYY VE
    // YYYY.MM.DD) AYNI grup sırası (groups[2]=yıl, groups[1]=ay,
    // groups[0]=gün) varsayılıyordu. Bu, YYYY.MM.DD deseni eşleştiğinde
    // (groups[0]=yıl, groups[1]=ay, groups[2]=gün) yıl/gün'ün yer
    // değiştirmesine yol açıyordu (ör. "2024.03.15" → DateTime(15, 3,
    // 2024) gibi geçersiz bir tarih denemesi) — bu her zaman exception
    // fırlatıp sessizce null dönüyordu, yani bu format ASLA doğru
    // ayrıştırılamıyordu.
    final ddmmyyyy = RegExp(r'(\d{2})[./](\d{2})[./](\d{4})').firstMatch(text);
    if (ddmmyyyy != null) {
      try {
        return DateTime(
          int.parse(ddmmyyyy.group(3)!),
          int.parse(ddmmyyyy.group(2)!),
          int.parse(ddmmyyyy.group(1)!),
        );
      } catch (_) { /* bozuk/desteklenmeyen MIME parçası — o parça atlanır, mail okunmaya devam eder */ }
    }
    final yyyymmdd = RegExp(r'(\d{4})[./](\d{2})[./](\d{2})').firstMatch(text);
    if (yyyymmdd != null) {
      try {
        return DateTime(
          int.parse(yyyymmdd.group(1)!),
          int.parse(yyyymmdd.group(2)!),
          int.parse(yyyymmdd.group(3)!),
        );
      } catch (_) { /* bozuk/desteklenmeyen MIME parçası — o parça atlanır, mail okunmaya devam eder */ }
    }
    return null;
  }

  static String _firmaCikar(String from) {
    final match = RegExp(r'"?(.+?)"?\s*[<]?').firstMatch(from);
    return match?.group(1)?.trim() ?? from;
  }
}