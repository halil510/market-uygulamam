import 'package:flutter_test/flutter_test.dart';
import 'package:market_plus/servisler/auth_servisi.dart';

void main() {
  group('AuthServisi.hashle — şifre güvenliği', () {
    test('aynı şifre her zaman aynı hash\'i üretir (deterministik)', () {
      final h1 = AuthServisi.hashle('gizliSifre123');
      final h2 = AuthServisi.hashle('gizliSifre123');
      expect(h1, equals(h2));
    });

    test('farklı şifreler farklı hash üretir', () {
      final h1 = AuthServisi.hashle('sifre1');
      final h2 = AuthServisi.hashle('sifre2');
      expect(h1, isNot(equals(h2)));
    });

    test('hash SONUCU orijinal şifreyi içermez (düz metin değil)', () {
      const sifre = 'benimSifrem2026';
      final hash = AuthServisi.hashle(sifre);
      expect(hash.contains(sifre), isFalse);
    });

    test('SHA-256 hash 64 hex karakter uzunluğunda olmalı', () {
      final hash = AuthServisi.hashle('test');
      expect(hash.length, equals(64));
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(hash), isTrue);
    });

    test('boş şifre bile çökmeden hashlenir', () {
      expect(() => AuthServisi.hashle(''), returnsNormally);
    });

    test('küçük/büyük harf farkı farklı hash üretir', () {
      final h1 = AuthServisi.hashle('Sifre');
      final h2 = AuthServisi.hashle('sifre');
      expect(h1, isNot(equals(h2)));
    });
  });
}
