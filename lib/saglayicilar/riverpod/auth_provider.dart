// lib/saglayicilar/riverpod/auth_provider.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../cekirdek/utils/hata_utils.dart';
import '../../servisler/auth_servisi.dart';
import '../../servisler/audit_log_servisi.dart';
import '../../modeller/kullanici_model.dart';
import 'sepet_provider.dart';

part 'auth_provider.g.dart';

enum AuthDurum { yukleniyor, girisYapildi, cikisYapildi }
enum GirisSonucu { basarili, hataliSifre, kilitli, hata }

// AuthKilitliException artık auth_servisi.dart'ta tanımlı (kalıcı
// brute-force kilidini fırlatan yer orası) — bu dosya onu zaten yukarıda
// import ediyor.

class AuthState {
  final AuthDurum durum;
  final KullaniciModel? kullanici;
  final String? hataMesaji;

  const AuthState({required this.durum, this.kullanici, this.hataMesaji});
  const AuthState.yukleniyor()  : durum = AuthDurum.yukleniyor,   kullanici = null, hataMesaji = null;
  const AuthState.girisYapildi(KullaniciModel this.kullanici) : durum = AuthDurum.girisYapildi, hataMesaji = null;
  const AuthState.cikisYapildi(): durum = AuthDurum.cikisYapildi, kullanici = null, hataMesaji = null;
  const AuthState.hata(String this.hataMesaji) : durum = AuthDurum.cikisYapildi, kullanici = null;

  bool get girisYapildi => durum == AuthDurum.girisYapildi;
  bool get yukleniyor   => durum == AuthDurum.yukleniyor;
  bool get isAdmin      => kullanici?.rol == 'admin';
  bool get isMudur      => kullanici?.rol == 'mudur' || isAdmin;
  bool get isBayi       => kullanici?.isBayi ?? false;
  int? get bayiCariId   => kullanici?.bayiCariId;
  String get aktifRol   => kullanici?.rol ?? 'misafir';
  String get aktifAd    => kullanici?.adSoyad ?? '';
}

@riverpod
class Auth extends _$Auth {
  final _servis = AuthServisi();

  @override
  AuthState build() {
    Future.microtask(_oturumKontrol);
    return const AuthState.yukleniyor();
  }

  Future<void> _oturumKontrol() async {
    try {
      await _servis.oturumuYenile();
      final k = _servis.aktifKullanici;
      state = k != null ? AuthState.girisYapildi(k) : const AuthState.cikisYapildi();
    } catch (_) {
      state = const AuthState.cikisYapildi();
    }
  }

  /// Son başarısız giriş denemesinin hata metni (#77: açık oturum korunduğunda
  /// state.hataMesaji önceki oturumu gösterir; ekran bunu okur).
  String? sonHataMesaji;

  Future<GirisSonucu> girisYap(String kullaniciAdi, String sifre) async {
    // DERİN DENETİM (2026-11-09, #77): "Kullanıcı Değiştir" açık oturumda
    // çağrılır. Önceden durum hemen 'yukleniyor'a, hatada 'cikisYapildi'ya
    // geçiyordu — router tek hatalı PIN'de mevcut oturumu kapatıp giriş
    // ekranına atıyordu. Açık oturum varken (servis kullanıcıyı başarısız
    // denemede değiştirmez) durum yalnız başarıda değişir.
    final oncekiOturum =
        state.girisYapildi && _servis.aktifKullanici != null ? state : null;
    AuthState basarisiz(AuthState yeni) {
      sonHataMesaji = yeni.hataMesaji;
      return oncekiOturum ?? yeni;
    }
    if (oncekiOturum == null) state = const AuthState.yukleniyor();
    try {
      final basarili = await _servis.girisYap(kullaniciAdi, sifre);
      if (basarili) {
        final k = _servis.aktifKullanici;
        if (k != null) {
          state = AuthState.girisYapildi(k);
          // 🔴🔴 Derin analizde bulundu: sepetProvider @Riverpod(keepAlive:
          // true) — uygulama ömrü boyunca canlı kalır ve hiçbir yerde
          // temizlenmiyordu. Bu cihaz PAYLAŞIMLI bir terminal olduğu ve
          // "Kullanıcı Değiştir" (PIN ile, uygulamayı kapatmadan) akışı
          // desteklendiği için: Kasiyer A sepete ürün ekleyip cihazı
          // Kasiyer B'ye bırakırsa, B PIN ile giriş yaptığında A'nın
          // doldurduğu sepeti (ürünler + bağlı müşteri) GÖRÜR ve
          // tamamlarsa satış YANLIŞLIKLA B'nin kasiyerId'siyle kaydedilir
          // — hem veri sızıntısı hem yanlış audit/kasiyer ataması. Her
          // başarılı giriş/kullanıcı değişiminde sepet artık temizleniyor.
          ref.read(sepetProvider.notifier).temizle();
          // 🔴 DÜZELTME (Madde 18 — Audit Log): başarılı girişler
          // önceden audit_log'a hiç düşmüyordu (bkz. AuditLogServisi.
          // girisKaydet yorumu).
          unawaited(AuditLogServisi().girisKaydet(
              kullaniciId: k.id, kullaniciAdi: k.adSoyad, basarili: true));
          return GirisSonucu.basarili;
        }
      }
      state = basarisiz(const AuthState.cikisYapildi());
      unawaited(AuditLogServisi().girisKaydet(
          kullaniciId: null, kullaniciAdi: kullaniciAdi, basarili: false));
      return GirisSonucu.hataliSifre;
    } on AuthKilitliException catch (e) {
      state = basarisiz(AuthState.hata(e.mesaj));
      unawaited(AuditLogServisi().girisKaydet(
          kullaniciId: null, kullaniciAdi: kullaniciAdi, basarili: false));
      return GirisSonucu.kilitli;
    } catch (e) {
      // Şifre yanlışlığı DEĞİL, sistem hatası (ör. veritabanı açılamadı):
      // ekran bunu "Hatalı şifre" saymamalı — mesaj state.hataMesaji'nda.
      state = basarisiz(AuthState.hata(kullaniciyaHataMetni(e)));
      return GirisSonucu.hata;
    }
  }

  /// Parmak izi ile giriş — bkz. AuthServisi.girisYapBiyometrikToken.
  /// Şifreyle girişten farklı olarak brute-force kilidi/hata sayacı YOK
  /// (token 256-bit rastgele, tahmin edilemez); token geçersizse çağıran
  /// ekran kullanıcıyı şifreyle girişe yönlendirir.
  Future<GirisSonucu> girisYapBiyometrik(String kullaniciAdi, String token) async {
    state = const AuthState.yukleniyor();
    try {
      final basarili = await _servis.girisYapBiyometrikToken(kullaniciAdi, token);
      if (basarili) {
        final k = _servis.aktifKullanici;
        if (k != null) {
          state = AuthState.girisYapildi(k);
          ref.read(sepetProvider.notifier).temizle();
          unawaited(AuditLogServisi().girisKaydet(
              kullaniciId: k.id, kullaniciAdi: k.adSoyad, basarili: true));
          return GirisSonucu.basarili;
        }
      }
      state = const AuthState.cikisYapildi();
      return GirisSonucu.hataliSifre;
    } catch (e) {
      state = AuthState.hata(e.toString()); return GirisSonucu.hata;
    }
  }

  Future<void> cikisYap() async {
    try {
      await _servis.cikisYap();
    } finally {
      state = const AuthState.cikisYapildi();
      // Bkz. girisYap()'taki aynı not — çıkışta da paylaşımlı cihazda
      // bir sonraki kullanıcının önceki sepeti görmemesi için temizleniyor.
      ref.read(sepetProvider.notifier).temizle();
    }
  }

  bool yetkiVarSync(String k) => _servis.yetkiVarSync(k);
  Future<bool> yetkiVar(String k) => _servis.yetkiVar(k);
}

// Granular — sadece ilgili parça rebuild olur
@riverpod
KullaniciModel? aktifKullanici(Ref ref) =>
    ref.watch(authProvider.select((s) => s.kullanici));

@riverpod
bool girisYapildiMi(Ref ref) =>
    ref.watch(authProvider.select((s) => s.girisYapildi));

@riverpod
bool isAdmin(Ref ref) =>
    ref.watch(authProvider.select((s) => s.isAdmin));
