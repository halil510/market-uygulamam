// test/ekranlar/fatura_gonderilmis_mi_test.dart
//
// Madde 23 (Fatura/E-Belge) denetimi, 2026-09-20 — eFaturaGonderilmisMi()
// (fatura_detay_ekrani.dart, top-level saf fonksiyon) "Durum Sorgula" /
// "Gönder" butonlarının devre dışı bırakılma mantığını belirler. Bug:
// 'gonderiliyor' durumu ÖNCEDEN bu kontrolde YOKTU — gönderim GİB'e
// gitmiş ama yanıt uygulama tarafında hiç işlenememiş (ör. çökme) bir
// fatura için "Durum Sorgula" butonu DEVRE DIŞI kalıyordu, kullanıcı
// GİB'in gerçek durumunu hiç sorgulayamıyordu.
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/ekranlar/fatura/fatura_detay_ekrani.dart';

void main() {
  group('eFaturaGonderilmisMi', () {
    test('gonderiliyor artık "gönderilmiş" sayılır (Durum Sorgula AÇIK, '
        'Gönder KAPALI olsun diye) — önceden BURADA EKSİKTİ', () {
      expect(eFaturaGonderilmisMi('gonderiliyor'), isTrue);
    });

    test('gonderildi/onaylandi/gib_iptal — gönderilmiş sayılır (mevcut davranış)', () {
      expect(eFaturaGonderilmisMi('gonderildi'), isTrue);
      expect(eFaturaGonderilmisMi('onaylandi'), isTrue);
      expect(eFaturaGonderilmisMi('gib_iptal'), isTrue);
    });

    test('hazir/reddedildi/hata/null — gönderilmiş SAYILMAZ (kullanıcı '
        'düzeltip yeniden gönderebilmeli)', () {
      expect(eFaturaGonderilmisMi('hazir'), isFalse);
      expect(eFaturaGonderilmisMi('reddedildi'), isFalse);
      expect(eFaturaGonderilmisMi('hata'), isFalse);
      expect(eFaturaGonderilmisMi(null), isFalse);
    });
  });
}
