// lib/servisler/auth/biyometrik_giris_servisi.dart
//
// Giriş ekranının cihaz-güvenli depo ve parmak izi işleri — giris_ekrani.dart'tan
// ayrıldı (2026-10-07 refactor): ekran yalnız sonucu gösterir.
//
// 🔴 GÜVENLİK DÜZELTMESİ: 'biyometrik_sifre' anahtarı ÖNCEDEN kullanıcının
// ham şifresini saklıyordu. Artık şifre hiç saklanmıyor; sadece rastgele,
// tuzlanmış hash'i DB'de tutulan bir token saklanıyor (bkz. AuthServisi.
// girisYapBiyometrikToken / BiyometrikDeposu). Eski anahtar sadece bir
// kereliğine sessizce yeni şemaya taşınıp siliniyor (bkz. durumKontrol).
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../../depolar/kullanici_deposu.dart';
import '../auth_servisi.dart';

class BiyometrikGirisServisi {
  static const _eskiSifreAnahtari = 'biyometrik_sifre';
  static const _tokenAnahtari = 'biyometrik_token';
  static const _kullaniciAnahtari = 'kullanici_adi';
  static const _secure = FlutterSecureStorage();

  final LocalAuthentication _localAuth;
  BiyometrikGirisServisi({LocalAuthentication? localAuth})
      : _localAuth = localAuth ?? LocalAuthentication();

  /// Bu cihazda en son giriş yapan kullanıcı adı.
  Future<String?> sonKullanici() => _secure.read(key: _kullaniciAnahtari);

  /// Cihaz parmak izini destekliyor mu, destekliyorsa kayıtlı token var mı.
  Future<({bool destekli, bool mevcut})> durumKontrol() async {
    final destekleniyor = await _localAuth.isDeviceSupported();
    final mevcutBiyometrikler = await _localAuth.getAvailableBiometrics();
    var kayitliToken = await _secure.read(key: _tokenAnahtari);
    kayitliToken ??= await _eskiKaydiTasi();
    final destekli = destekleniyor && mevcutBiyometrikler.isNotEmpty;
    return (destekli: destekli, mevcut: destekli && kayitliToken != null);
  }

  /// Bir önceki sürümden kalma, ham şifre içeren eski anahtarı bulursa
  /// sessizce yeni token şemasına taşır (kullanıcı yeniden "kaydolmak"
  /// zorunda kalmaz) ve eski anahtarı siler. Şifre yeni şemada HİÇ
  /// saklanmaz — sadece token üretmek için bir kereliğine kullanılır.
  Future<String?> _eskiKaydiTasi() async {
    final eskiSifre = await _secure.read(key: _eskiSifreAnahtari);
    final kullaniciAdi = await _secure.read(key: _kullaniciAnahtari);
    if (eskiSifre == null || kullaniciAdi == null) {
      if (eskiSifre != null) await _secure.delete(key: _eskiSifreAnahtari);
      return null;
    }
    try {
      final kullanici = await KullaniciDeposu().girisKontrol(kullaniciAdi, eskiSifre);
      if (kullanici?.id == null) {
        await _secure.delete(key: _eskiSifreAnahtari);
        return null;
      }
      final token = await AuthServisi().biyometrikKaydet(kullanici!.id!);
      await _secure.write(key: _tokenAnahtari, value: token);
      await _secure.delete(key: _eskiSifreAnahtari);
      return token;
    } catch (e) {
      if (kDebugMode) debugPrint('Biyometrik kayıt taşıma hatası: $e');
      await _secure.delete(key: _eskiSifreAnahtari);
      return null;
    }
  }

  Future<bool> parmakIziDogrula() => _localAuth.authenticate(
        localizedReason: 'Giriş yapmak için parmak izinizi okutun',
        biometricOnly: true,
        persistAcrossBackgrounding: true, // local_auth 3: eski stickyAuth
      );

  /// Parmak iziyle girişte kullanılacak kayıtlı kullanıcı ve token.
  Future<({String kullanici, String token})?> kayitliBilgi() async {
    final kullanici = await _secure.read(key: _kullaniciAnahtari);
    final token = await _secure.read(key: _tokenAnahtari);
    if (kullanici == null || token == null) return null;
    return (kullanici: kullanici, token: token);
  }

  /// Şifreli başarılı girişten sonra: kullanıcıyı hatırla, parmak izi için
  /// token üret. Şifre ARTIK saklanmıyor — sadece bu cihaza özel rastgele bir
  /// token üretilip hash'i DB'de tutuluyor (bkz. AuthServisi.biyometrikKaydet).
  Future<void> girisiHatirla(String kullaniciAdi, int? kullaniciId) async {
    await _secure.write(key: _kullaniciAnahtari, value: kullaniciAdi);
    if (kullaniciId == null) return;
    final token = await AuthServisi().biyometrikKaydet(kullaniciId);
    await _secure.write(key: _tokenAnahtari, value: token);
  }
}
