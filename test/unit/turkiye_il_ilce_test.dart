// test/unit/turkiye_il_ilce_test.dart
//
// Kullanıcı isteği: "il ve ilçeler otomatik gelsin, denizli dediğimde
// denizli ilçeleri gelsin." Bu testler veri bütünlüğünü (81 il) ve
// arama/eşleştirme mantığını (Türkçe karakter/aksan duyarsız) doğrular.
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/cekirdek/veri/turkiye_il_ilce.dart';

void main() {
  group('TurkiyeIlIlce veri bütünlüğü', () {
    test('tam olarak 81 il var', () {
      expect(TurkiyeIlIlce.iller.length, equals(81));
    });

    test('her ilin en az bir ilçesi var', () {
      for (final il in TurkiyeIlIlce.iller) {
        expect(TurkiyeIlIlce.ilIlceler[il], isNotEmpty, reason: il);
      }
    });

    test('bilinen büyük iller listede', () {
      for (final il in ['İstanbul', 'Ankara', 'İzmir', 'Denizli', 'Bursa']) {
        expect(TurkiyeIlIlce.iller, contains(il));
      }
    });
  });

  group('İl arama (yazarak filtreleme)', () {
    test('"denizli" yazınca Denizli bulunur', () {
      expect(TurkiyeIlIlce.illeriAra('denizli'), contains('Denizli'));
    });

    test('Türkçe büyük/küçük harf duyarsız (İZMİR → İzmir)', () {
      expect(TurkiyeIlIlce.illeriAra('İZMİR'), contains('İzmir'));
    });

    test('aksan/nokta duyarsız (corum → Çorum, agri → Ağrı)', () {
      expect(TurkiyeIlIlce.illeriAra('corum'), contains('Çorum'));
      expect(TurkiyeIlIlce.illeriAra('agri'), contains('Ağrı'));
    });

    test('kısmi eşleşme çalışır (kara → Karabük, Karaman, Kars...)', () {
      final sonuc = TurkiyeIlIlce.illeriAra('kara');
      expect(sonuc, isNotEmpty);
      expect(sonuc.every((il) => il.toLowerCase().contains('kara') ||
          il.toLowerCase().replaceAll('ı', 'i').contains('kara')), isTrue);
    });

    test('boş sorguda tüm iller döner', () {
      expect(TurkiyeIlIlce.illeriAra(''), hasLength(81));
    });

    test('anlamsız sorguda boş liste döner', () {
      expect(TurkiyeIlIlce.illeriAra('zzzzqqqq'), isEmpty);
    });
  });

  group('İlçe arama (bir ile bağlı filtreleme)', () {
    test('Denizli seçiliyken "pamuk" yazınca Pamukkale ilçesi bulunur', () {
      final sonuc = TurkiyeIlIlce.ilceleriAra('pamuk', il: 'Denizli');
      expect(sonuc, contains('Pamukkale'));
    });

    test('bir ile bağlı arama, BAŞKA ilin ilçesini DÖNMEZ', () {
      // "Merkez" onlarca ilde var ama il="Bolu" verilince SADECE Bolu'nun
      // ilçeleri arasından aranmalı.
      final sonuc = TurkiyeIlIlce.ilceleriAra('merkez', il: 'Bolu');
      expect(sonuc, equals(['Merkez']));
    });

    test('il verilmezse Türkiye genelinde arar', () {
      final sonuc = TurkiyeIlIlce.ilceleriAra('kadıköy');
      expect(sonuc, contains('Kadıköy'));
    });

    test('tanınmayan/boş il ile Türkiye genelinde arar (kısıtlamaz)', () {
      final sonuc = TurkiyeIlIlce.ilceleriAra('efeler', il: 'Bilinmeyen Yer');
      expect(sonuc, contains('Efeler')); // gerçekte Aydın'a ait
    });
  });

  group('ilBul — serbest yazılmış il adını doğru isme çözer', () {
    test('doğru yazımda kendini bulur', () {
      expect(TurkiyeIlIlce.ilBul('Denizli'), equals('Denizli'));
    });

    test('küçük harf/aksansız yazımda da bulur', () {
      expect(TurkiyeIlIlce.ilBul('izmir'), equals('İzmir'));
      expect(TurkiyeIlIlce.ilBul('corum'), equals('Çorum'));
    });

    test('boş/null için null döner', () {
      expect(TurkiyeIlIlce.ilBul(null), isNull);
      expect(TurkiyeIlIlce.ilBul(''), isNull);
    });

    test('kısmi (tam olmayan) eşleşme için null döner — sadece TAM eşleşme kabul edilir', () {
      expect(TurkiyeIlIlce.ilBul('deniz'), isNull);
    });
  });
}
