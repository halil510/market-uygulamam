// test/ekranlar/iade_oturum_belge_test.dart
//
// Derin denetim (2026-11-09) #7 #8, yüksek: aynı iade belgesinde ödeme
// yöntemi (Cari ↔ Nakit) ya da cari değiştirilince kalem silme kasaya hayali
// giriş / cariye çift alacak yazıyor, ikinci carinin alacağı belge silinince
// geri alınmıyordu. Artık yöntem/cari değişince yeni iade fişi açılır.
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/ekranlar/satis/iade_ekrani.dart';

void main() {
  bool karar({int? oturum = 7, String? oYontem = 'Cari', int? oCari = 1,
          required String yontem, int? cari = 1}) =>
      iadeOturumuYeniBelgeGerekir(
          oturumIadeId: oturum, oturumYontem: oYontem, oturumCariId: oCari,
          yontem: yontem, cariId: cari);

  test('açık belge yoksa yeni belge kararı gerekmez', () {
    expect(karar(oturum: null, yontem: 'Nakit'), isFalse);
  });

  test('aynı yöntem ve cari → aynı belgeye devam', () {
    expect(karar(yontem: 'Cari'), isFalse);
  });

  test('#7 belge Cari iken Nakit seçilince yeni belge açılır', () {
    expect(karar(yontem: 'Nakit'), isTrue);
  });

  test('#8 belge cari A ile açıkken cari B seçilince yeni belge açılır', () {
    expect(karar(yontem: 'Cari', cari: 2), isTrue);
  });

  test('#8 kayıtsız müşteriyle açılan belgeye kayıtlı cari eklenince yeni belge', () {
    expect(karar(oYontem: 'Nakit', oCari: null, yontem: 'Nakit', cari: 3), isTrue);
  });
}
