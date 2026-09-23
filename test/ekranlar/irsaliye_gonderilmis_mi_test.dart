// test/ekranlar/irsaliye_gonderilmis_mi_test.dart
//
// eIrsaliyeGonderilmisMi() (irsaliye_ekrani.dart) — fatura tarafındaki
// eFaturaGonderilmisMi ile aynı kural. 'gonderiliyor' önceden eksikti:
// gönderim sırasında çökmüş bir irsaliye, GİB'deki gerçek durumu
// sorgulanmadan kör kör yeniden gönderilebiliyordu.
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/ekranlar/irsaliye/irsaliye_ekrani.dart';

void main() {
  group('eIrsaliyeGonderilmisMi', () {
    test('gonderiliyor gönderilmiş sayılır (Gönder KAPALI, Sorgula AÇIK)', () {
      expect(eIrsaliyeGonderilmisMi('gonderiliyor'), isTrue);
    });

    test('gonderildi/onaylandi/gib_iptal gönderilmiş sayılır', () {
      expect(eIrsaliyeGonderilmisMi('gonderildi'), isTrue);
      expect(eIrsaliyeGonderilmisMi('onaylandi'), isTrue);
      expect(eIrsaliyeGonderilmisMi('gib_iptal'), isTrue);
    });

    test('hazir/reddedildi/hata/null yeniden gönderilebilir', () {
      expect(eIrsaliyeGonderilmisMi('hazir'), isFalse);
      expect(eIrsaliyeGonderilmisMi('reddedildi'), isFalse);
      expect(eIrsaliyeGonderilmisMi('hata'), isFalse);
      expect(eIrsaliyeGonderilmisMi(null), isFalse);
    });
  });
}
