// lib/saglayicilar/riverpod/auth_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../servisler/auth_servisi.dart';
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

  Future<GirisSonucu> girisYap(String kullaniciAdi, String sifre) async {
    state = const AuthState.yukleniyor();
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
          return GirisSonucu.basarili;
        }
      }
      state = const AuthState.cikisYapildi();
      return GirisSonucu.hataliSifre;
    } on AuthKilitliException catch (e) {
      state = AuthState.hata(e.mesaj); return GirisSonucu.kilitli;
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
KullaniciModel? aktifKullanici(AktifKullaniciRef ref) =>
    ref.watch(authProvider.select((s) => s.kullanici));

@riverpod
bool girisYapildiMi(GirisYapildiMiRef ref) =>
    ref.watch(authProvider.select((s) => s.girisYapildi));

@riverpod
bool isAdmin(IsAdminRef ref) =>
    ref.watch(authProvider.select((s) => s.isAdmin));
