// test/servisler/gib_ettn_test.dart
//
// Madde 23 (Fatura/E-Belge) denetimi, 2026-09-20: "Durum Sorgula" butonu
// 'gonderiliyor' durumundaki (gönderim GİB'e gitti ama yanıt uygulama
// tarafında hiç işlenemedi — ör. çökme) bir fatura için devre dışıydı,
// ÜSTELİK eFaturaUuid DB'de null kalabiliyordu — kullanıcı GİB'in
// gerçekte ne yaptığını hiç SORGULAYAMIYORDU. Düzeltme, ETTN'nin
// DETERMİNİSTİK olmasına dayanıyor (GibServisi.ettnHesapla — public
// sarmalayıcı, altındaki _ettnUret2/_ettnFaturaIcin private): aynı
// fatura+deneme_no HER ZAMAN aynı ETTN'i üretir, hiç saklanmamış olsa
// bile yeniden hesaplanabilir. Bu test, o determinizm garantisini
// doğrudan doğrular — GibServisi() constructor'ı DB/network'e
// dokunmadığından (Dio/Uuid sadece alan olarak tutuluyor), Flutter
// binding/DB kurulumu GEREKMİYOR.
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/servisler/gib_servisi.dart';
import 'package:market_plus/modeller/fatura_model.dart';

void main() {
  group('GibServisi.ettnHesapla', () {
    test('aynı fatura (globalId+denemeNo) için HER ZAMAN aynı ETTN üretir — '
        'yeniden hesaplama, hiç saklanmamış bir UUID\'yi kurtarabilmeli', () {
      final fatura = FaturaModel(
        globalId: 'abc-123', tarih: DateTime(2026, 9, 20), eFaturaDenemeNo: 0,
      );

      final ettn1 = GibServisi().ettnHesapla(fatura);
      final ettn2 = GibServisi().ettnHesapla(fatura);

      expect(ettn1, equals(ettn2));
      expect(ettn1, isNotEmpty);
    });

    test('farklı deneme_no FARKLI bir ETTN üretir (reddedilmiş bir '
        'faturanın yeniden gönderiminde mükerrer ETTN riski olmasın diye)', () {
      final fatura0 = FaturaModel(globalId: 'xyz', tarih: DateTime(2026, 9, 20), eFaturaDenemeNo: 0);
      final fatura1 = FaturaModel(globalId: 'xyz', tarih: DateTime(2026, 9, 20), eFaturaDenemeNo: 1);

      expect(GibServisi().ettnHesapla(fatura0), isNot(equals(GibServisi().ettnHesapla(fatura1))));
    });

    test('farklı fatura (farklı globalId) farklı ETTN üretir', () {
      final f1 = FaturaModel(globalId: 'a', tarih: DateTime(2026, 9, 20));
      final f2 = FaturaModel(globalId: 'b', tarih: DateTime(2026, 9, 20));

      expect(GibServisi().ettnHesapla(f1), isNot(equals(GibServisi().ettnHesapla(f2))));
    });

    test('globalId yoksa faturaNo\'ya, o da yoksa id\'ye düşer — yine de deterministik', () {
      final f1 = FaturaModel(faturaNo: 'FTR-001', tarih: DateTime(2026, 9, 20));
      final f2 = FaturaModel(faturaNo: 'FTR-001', tarih: DateTime(2026, 9, 20));

      expect(GibServisi().ettnHesapla(f1), equals(GibServisi().ettnHesapla(f2)));
    });
  });
}
