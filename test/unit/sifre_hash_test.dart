// test/unit/sifre_hash_test.dart
//
// Bu oturumda tuzsuz (salt'sız) düz SHA-256 güvenlik açığı bulunup
// düzeltildi. Bu testler, düzeltmenin temel özelliklerini (tuz her
// seferinde farklı, aynı şifre+tuz her zaman aynı hash'i üretir,
// farklı tuzlar farklı hash üretir) kalıcı olarak doğruluyor.
import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/cekirdek/utils/sifre_hash.dart';

void main() {
  group('SifreHash.tuzUret', () {
    test('her çağrıda farklı bir tuz üretir', () {
      final tuz1 = SifreHash.tuzUret();
      final tuz2 = SifreHash.tuzUret();
      expect(tuz1, isNot(equals(tuz2)));
    });

    test('üretilen tuz 32 karakter uzunluğunda (16 bayt hex)', () {
      final tuz = SifreHash.tuzUret();
      expect(tuz.length, 32);
    });
  });

  group('SifreHash.hashleTuzlu', () {
    test('aynı şifre + aynı tuz her zaman aynı hash\'i üretir (deterministik)', () {
      const sifre = 'test1234';
      const tuz = 'sabittuz123456';
      final hash1 = SifreHash.hashleTuzlu(sifre, tuz);
      final hash2 = SifreHash.hashleTuzlu(sifre, tuz);
      expect(hash1, equals(hash2));
    });

    test('aynı şifre farklı tuzla FARKLI hash üretir', () {
      const sifre = 'test1234';
      final hash1 = SifreHash.hashleTuzlu(sifre, 'tuz1');
      final hash2 = SifreHash.hashleTuzlu(sifre, 'tuz2');
      expect(hash1, isNot(equals(hash2)));
    });

    test('farklı şifreler aynı tuzla FARKLI hash üretir', () {
      const tuz = 'aynituz';
      final hash1 = SifreHash.hashleTuzlu('sifre1', tuz);
      final hash2 = SifreHash.hashleTuzlu('sifre2', tuz);
      expect(hash1, isNot(equals(hash2)));
    });

    test('gerçek kullanımda: iki farklı kullanıcı aynı şifreyi seçse bile hash\'leri farklı olur', () {
      // Bu, tuzsuz eski şemanın TAM OLARAK BAŞARISIZ olduğu senaryo —
      // rainbow table saldırısını anlamsız kılan şey budur.
      const ortakSifre = '123456';
      final kullanici1Tuz = SifreHash.tuzUret();
      final kullanici2Tuz = SifreHash.tuzUret();
      final kullanici1Hash = SifreHash.hashleTuzlu(ortakSifre, kullanici1Tuz);
      final kullanici2Hash = SifreHash.hashleTuzlu(ortakSifre, kullanici2Tuz);
      expect(kullanici1Hash, isNot(equals(kullanici2Hash)));
    });
  });

  group('SifreHash.eskiHashle (geriye dönük uyumluluk)', () {
    test('aynı şifre her zaman aynı (tuzsuz) hash\'i üretir', () {
      expect(SifreHash.eskiHashle('test'), equals(SifreHash.eskiHashle('test')));
    });

    test('farklı şifreler farklı hash üretir', () {
      expect(SifreHash.eskiHashle('test1'),
          isNot(equals(SifreHash.eskiHashle('test2'))));
    });
  });
}
