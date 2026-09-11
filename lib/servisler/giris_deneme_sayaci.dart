// lib/servisler/giris_deneme_sayaci.dart
//
// Kullanıcı adı başına kalıcı (SharedPreferences'ta tutulan) başarısız
// giriş denemesi sayacı ve kilit mekanizması. AuthServisi'nden ayrı bir
// sınıfa çıkarıldı ki DB'ye (KullaniciDeposu/Veritabani) bağımlı olmadan
// izole test edilebilsin.
//
// 🔴 Derin analizde bulundu: giris_ekrani.dart/kullanici_degistir_ekrani
// .dart'ta "N hatalı denemede kilit" mantığı VARDI ama sadece widget
// state'inde (bellekte) tutuluyordu — uygulama kapatılıp tekrar açılınca
// (POS cihazında fiziksel erişimi olan biri için tek adım) sayaç
// sıfırlanıyor, kilit hiç uygulanmamış oluyordu.
import 'package:shared_preferences/shared_preferences.dart';

class GirisDenemeSayaci {
  final int maxDeneme;
  final Duration kilitSuresi;

  const GirisDenemeSayaci({required this.maxDeneme, required this.kilitSuresi});

  static String _denemeAnahtari(String ka) => 'giris_deneme_$ka';
  static String _kilitAnahtari(String ka) => 'giris_kilit_$ka';

  /// Kullanıcı hâlâ kilitliyse kalan süreyi (saniye) döner, değilse null.
  /// Kilit süresi dolmuşsa sayaç/kilit kaydını temizler.
  Future<int?> kalanKilitSaniyesi(String kullaniciAdi) async {
    final prefs = await SharedPreferences.getInstance();
    final kilitMs = prefs.getInt(_kilitAnahtari(kullaniciAdi));
    if (kilitMs == null) return null;
    final kilitBitis = DateTime.fromMillisecondsSinceEpoch(kilitMs);
    final simdi = DateTime.now();
    if (simdi.isBefore(kilitBitis)) {
      return kilitBitis.difference(simdi).inSeconds;
    }
    await prefs.remove(_kilitAnahtari(kullaniciAdi));
    await prefs.remove(_denemeAnahtari(kullaniciAdi));
    return null;
  }

  /// Başarısız bir deneme kaydeder. Eşiğe ulaşıldıysa kilit başlatır ve
  /// true döner (yeni kilitlendi), aksi halde false döner.
  Future<bool> basarisizDenemeKaydet(String kullaniciAdi) async {
    final prefs = await SharedPreferences.getInstance();
    final anahtar = _denemeAnahtari(kullaniciAdi);
    final sayac = (prefs.getInt(anahtar) ?? 0) + 1;
    if (sayac >= maxDeneme) {
      final kilitBitis = DateTime.now().add(kilitSuresi);
      await prefs.setInt(_kilitAnahtari(kullaniciAdi), kilitBitis.millisecondsSinceEpoch);
      await prefs.setInt(anahtar, 0);
      return true;
    }
    await prefs.setInt(anahtar, sayac);
    return false;
  }

  /// Başarılı girişten sonra sayacı ve kilidi temizler.
  Future<void> temizle(String kullaniciAdi) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_denemeAnahtari(kullaniciAdi));
    await prefs.remove(_kilitAnahtari(kullaniciAdi));
  }
}
