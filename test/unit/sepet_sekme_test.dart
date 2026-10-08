// test/unit/sepet_sekme_test.dart
//
// Masaüstü çoklu alışveriş sekmesi (kullanıcı isteği 2026-10-09): aynı anda
// birden çok müşteri; her sekmenin kendi sepeti/müşterisi; satışı biten ek
// sekme kapanır, sekme 1 kalıcı; satış işlenirken sekme değişmez; en fazla 10.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/modeller/cari_model.dart';
import 'package:market_plus/modeller/urun_model.dart';
import 'package:market_plus/saglayicilar/riverpod/sepet_provider.dart';

UrunModel _u(String ad, double fiyat) =>
    UrunModel(urunAdi: ad, satisFiyati: fiyat, birimAdi: 'Adet', kdvOran: '20', stok: 10);

void main() {
  late ProviderContainer c;
  setUp(() => c = ProviderContainer());
  tearDown(() => c.dispose());
  Sepet n() => c.read(sepetProvider.notifier);
  SepetDurum d() => c.read(sepetProvider);

  test('her sekmenin kendi sepeti ve müşterisi var', () {
    n().ekle(_u('Ekmek', 17.5));
    n().musteriSec(const CariModel(id: 1, unvan: 'Ali'));
    expect(n().yeniSekme(), isTrue);
    expect(d().bos, isTrue);
    expect(d().musteri, isNull);
    n().ekle(_u('Su', 10), miktar: 3);
    expect(n().sekmeler.map((s) => s.no), [1, 2]);

    n().sekmeSec(0);
    expect(d().kalemler.single.urun.urunAdi, 'Ekmek');
    expect(d().musteri?.unvan, 'Ali');
    n().ekle(_u('Ekmek', 17.5)); // 1. müşteriye devam
    expect(d().genelToplam, 35);

    n().sekmeSec(1);
    expect(d().genelToplam, 30);
    final ozet = n().sekmeler;
    expect(ozet[0].toplam, 35);
    expect(ozet[0].musteri, 'Ali');
    expect(ozet[1].urunSayisi, 1);
  });

  test('satışı biten ek sekme kapanır, sekme 1\'e dönülür; sekme 1 boşalıp kalır', () {
    n().ekle(_u('Ekmek', 17.5));
    n().yeniSekme();
    n().ekle(_u('Su', 10));
    n().satisTamamlandi(); // 2. müşteri ödedi
    expect(n().sekmeler.length, 1);
    expect(n().aktifSekme, 0);
    expect(d().kalemler.single.urun.urunAdi, 'Ekmek', reason: '1. müşterinin sepeti korunur');
    n().satisTamamlandi(); // 1. müşteri ödedi
    expect(n().sekmeler.length, 1);
    expect(d().bos, isTrue, reason: 'sekme 1 boş ve hazır kalır');
  });

  test('ortadaki sekme kapanınca diğerleri ve aktif sekme doğru kalır', () {
    n().ekle(_u('A', 1));
    n().yeniSekme();
    n().ekle(_u('B', 2));
    n().yeniSekme();
    n().ekle(_u('C', 3));
    n().sekmeKapat(1); // ortadaki (B) kapanır, aktif C
    expect(n().sekmeler.map((s) => s.no), [1, 3]);
    expect(n().aktifSekme, 1);
    expect(d().kalemler.single.urun.urunAdi, 'C');
    expect(n().yeniSekme(), isTrue);
    expect(n().sekmeler.map((s) => s.no), [1, 3, 2], reason: 'boşalan numara yeniden kullanılır');
  });

  test('satış işlenirken sekme açılmaz/değişmez', () {
    n().ekle(_u('A', 1));
    n().yeniSekme();
    n().ekle(_u('B', 2));
    n().satisBasladi();
    expect(n().sekmeSec(0), isFalse);
    expect(n().yeniSekme(), isFalse);
    expect(d().kalemler.single.urun.urunAdi, 'B');
    n().satisTamamlandi();
    expect(n().aktifSekme, 0);
    expect(d().kalemler.single.urun.urunAdi, 'A');
  });

  test('en fazla 10 sekme', () {
    for (var i = 0; i < 9; i++) {
      expect(n().yeniSekme(), isTrue);
    }
    expect(n().sekmeler.length, Sepet.maksSekme);
    expect(n().yeniSekme(), isFalse);
  });
}
