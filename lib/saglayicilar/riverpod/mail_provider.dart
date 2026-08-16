// lib/saglayicilar/riverpod/mail_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../servisler/mail/mail_service.dart';
import '../../servisler/mail/gmail_service.dart';
import '../../servisler/mail/outlook_service.dart';
import '../../servisler/mail/mail_parser.dart';

enum MailSaglayici { gmail, outlook }

const _guvenliDepo = FlutterSecureStorage();
const _kEmailKey = 'mail_hesap_email';
const _kSifreKey = 'mail_hesap_app_sifre';
const _kSaglayiciKey = 'mail_hesap_saglayici';

/// Daha önce başarıyla bağlanılmış bir hesap varsa bilgilerini okur.
/// Şifre cihazda (Keychain/Keystore üzerinden) şifrelenmiş saklanır —
/// asla düz metin SharedPreferences'a yazılmaz.
class MailKimlikBilgisi {
  final String? email;
  final String? appSifre;
  final MailSaglayici saglayici;
  const MailKimlikBilgisi({this.email, this.appSifre, required this.saglayici});
}

final mailKayitliKimlikProvider = FutureProvider<MailKimlikBilgisi>((ref) async {
  final email = await _guvenliDepo.read(key: _kEmailKey);
  final sifre = await _guvenliDepo.read(key: _kSifreKey);
  final saglayiciStr = await _guvenliDepo.read(key: _kSaglayiciKey);
  final saglayici = saglayiciStr == 'outlook' ? MailSaglayici.outlook : MailSaglayici.gmail;
  return MailKimlikBilgisi(email: email, appSifre: sifre, saglayici: saglayici);
});

Future<void> mailKimlikBilgisiKaydet({
  required String email,
  required String appSifre,
  required MailSaglayici saglayici,
}) async {
  await _guvenliDepo.write(key: _kEmailKey, value: email);
  await _guvenliDepo.write(key: _kSifreKey, value: appSifre);
  await _guvenliDepo.write(key: _kSaglayiciKey, value: saglayici.name);
}

Future<void> mailKimlikBilgisiSil() async {
  await _guvenliDepo.delete(key: _kEmailKey);
  await _guvenliDepo.delete(key: _kSifreKey);
  await _guvenliDepo.delete(key: _kSaglayiciKey);
}

final mailSaglayiciProvider = StateProvider<MailSaglayici>((ref) => MailSaglayici.gmail);

/// Bu servis örneği UYGULAMA ÇALIŞTIĞI SÜRECE aynı kalır (keepAlive) —
/// böylece bağlantı kurulduktan sonra state kaybolmaz.
final mailServiceProvider = Provider<MailService>((ref) {
  ref.keepAlive();
  final saglayici = ref.watch(mailSaglayiciProvider);
  switch (saglayici) {
    case MailSaglayici.gmail:
      return GmailService();
    case MailSaglayici.outlook:
      return OutlookService();
  }
});

/// Mail listesini yeniden çekmek için: ref.invalidate(mailListesiProvider)
final mailListesiProvider = FutureProvider.autoDispose<List<Mail>>((ref) async {
  final service = ref.watch(mailServiceProvider);
  if (!service.bagli) return [];
  return await service.oku(limit: 50);
});

/// mail_parser.dart'taki hazır regex mantığıyla gelen kutusundan otomatik
/// fatura/borç tespiti.
final mailBorcProvider = Provider.autoDispose<List<Map<String, dynamic>>>((ref) {
  final mails = ref.watch(mailListesiProvider).valueOrNull ?? [];
  return MailParser.borcTespitEt(mails);
});
