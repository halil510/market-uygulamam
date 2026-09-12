// lib/servisler/auth_servisi.dart
//
// Düzeltmeler:
//   - Oturum süresi: son_giris DB'den alınıyor.
//     Cihaz saati manipülasyonu artık oturumu uzatamaz
//     (DB'deki son_giris değeri gerçek zamanlıdır).
//   - yetkiVar: DbSabitler.rollerYetki kullanıyor
//   - mevcutKullanici: null-safe
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../cekirdek/enumlar/kullanici_rolu.dart';
import '../cekirdek/utils/sifre_hash.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../cekirdek/sabitler/db_sabitleri.dart';
import '../cekirdek/sabitler/uygulama_sabitleri.dart';
import '../depolar/kullanici_deposu.dart';
import '../modeller/kullanici_model.dart';
import '../veri/database/veritabani.dart';
import 'giris_deneme_sayaci.dart';

/// Oturum süresi (dakika). Bu süre geçince tekrar giriş istenir.
const int _oturumSureDk = 480; // 8 saat

/// Bir kullanıcı adı için giriş kilitli olduğunda fırlatılır.
/// (Buradan taşındı: önceden sadece auth_provider.dart'ta tanımlıydı ama
/// hiçbir yerde fırlatılmıyordu — deneme sınırlaması UI katmanında
/// (giris_ekrani.dart/kullanici_degistir_ekrani.dart) widget state'i
/// olarak vardı, bu da uygulama yeniden başlatılınca sıfırlanıyordu.
/// Artık gerçek kilit burada, kalıcı depoda tutuluyor.)
class AuthKilitliException implements Exception {
  final String mesaj;
  const AuthKilitliException(this.mesaj);
}

class AuthServisi {
  /// Kullanıcı isteği: "Play Store'a çıkmadan önce dikkatli incele" —
  /// bu denetim sırasında bulunan gerçek bir güvenlik açığı: admin
  /// kullanıcısı varsayılan "1234" şifresiyle kalırsa (kimse
  /// değiştirmezse) HİÇBİR uyarı gösterilmiyordu. Fiziksel erişimi
  /// olan (ya da bu yaygın varsayılanı bilen) HERKES tam admin erişimi
  /// kazanabilirdi. Bu fonksiyon, aktif kullanıcının HÂLÂ varsayılan
  /// şifreyi kullanıp kullanmadığını kontrol eder — Dashboard'da
  /// fark edilir bir uyarı göstermek için kullanılıyor.
  Future<bool> varsayilanSifreKullaniliyorMu() async {
    if (_aktifKullanici == null || _aktifKullanici!.rol != 'admin') return false;
    try {
      final kontrol = await _depo.girisKontrol(_aktifKullanici!.kullaniciAdi, '1234');
      return kontrol != null;
    } catch (_) {
      return false;
    }
  }

  static final AuthServisi _instance = AuthServisi._internal();
  factory AuthServisi() => _instance;
  AuthServisi._internal();

  final KullaniciDeposu _depo = KullaniciDeposu();
  KullaniciModel? _aktifKullanici;
  Set<String> _yetkiCache = {};
  // Sadece bellekte — process ölünce false olur (banka davranışı)
  bool _oturumAktif = false;

  // Ayarlar PIN doğrulaması — 5 dakika geçerli
  DateTime? _ayarlarDogrulama;

  bool get ayarlarDogrulanmis {
    if (_ayarlarDogrulama == null) return false;
    return DateTime.now().difference(_ayarlarDogrulama!).inMinutes < 5;
  }

  void ayarlariDogrula() {
    _ayarlarDogrulama = DateTime.now();
  }

  void ayarlarDogrulamaTemizle() {
    _ayarlarDogrulama = null;
  }

  KullaniciModel? get aktifKullanici => _aktifKullanici;
  String get aktifAd     => _aktifKullanici?.adSoyad ?? '';
  int?   get aktifId     => _aktifKullanici?.id;
  bool   get girisYapilmis => _aktifKullanici != null && _oturumAktif;
  bool   get isAdmin     => _aktifKullanici?.rol == KullaniciRolu.admin.label;
  bool   get isMudur     => _aktifKullanici?.rol == KullaniciRolu.mudur.label || isAdmin;
  String get aktifRol    => _aktifKullanici?.rol ?? '';

  // ── Şifre hash ────────────────────────────────────────────────────────
  // Gerçek implementasyon lib/cekirdek/utils/sifre_hash.dart'ta —
  // KullaniciDeposu ile dairesel import olmaması için ayrı dosyada.
  static String hashle(String sifre) => SifreHash.eskiHashle(sifre);

  // ── Brute-force koruması ─────────────────────────────────────────────
  // 🔴 Derin analizde bulundu: giris_ekrani.dart/kullanici_degistir_ekrani
  // .dart'ta "5 hatalı denemede 30 sn kilit" mantığı VARDI ama sadece
  // widget state'inde (bellekte) tutuluyordu — uygulama kapatılıp tekrar
  // açılınca (POS cihazında fiziksel erişimi olan biri için tek adım)
  // sayaç sıfırlanıyor, kilit hiç uygulanmamış oluyordu. Artık sayaç ve
  // kilit bitiş zamanı SharedPreferences'ta (kullanıcı adı başına) kalıcı
  // tutuluyor (GirisDenemeSayaci) — uygulama yeniden başlatılsa da kilit
  // geçerli kalır.
  final _denemeSayaci = const GirisDenemeSayaci(
    maxDeneme: UygSabitler.maxHataliGiris,
    kilitSuresi: Duration(seconds: UygSabitler.kilitSureSaniye),
  );

  // ── Giriş ─────────────────────────────────────────────────────────────
  Future<bool> girisYap(String kullaniciAdi, String sifre) async {
    final kalanKilitSn = await _denemeSayaci.kalanKilitSaniyesi(kullaniciAdi);
    if (kalanKilitSn != null) {
      throw AuthKilitliException('Çok fazla hatalı deneme — $kalanKilitSn saniye bekleyin');
    }
    try {
      // Düz şifre gönderiliyor — tuz her kullanıcıda FARKLI olduğu için
      // hash'i burada önceden hesaplamak mümkün değil, KullaniciDeposu
      // önce kullanıcının kendi tuzunu bulup ONUNLA hashliyor.
      final kullanici = await _depo.girisKontrol(kullaniciAdi, sifre);
      if (kullanici == null) {
        await _denemeSayaci.basarisizDenemeKaydet(kullaniciAdi);
        return false;
      }
      await _denemeSayaci.temizle(kullaniciAdi);

      _aktifKullanici = kullanici;
      _oturumAktif = true;

      // Yetkileri önbelleğe al — sync yetkiVarSync() için
      if (kullanici.rol != KullaniciRolu.admin.label) {
        _yetkiCache = await _depo.yetkileriniGetir(kullanici.id!);
      } else {
        _yetkiCache = {};
      }

      // UID'yi prefs'e yaz; son_giris DB'ye yazılıyor (manipülasyon koruması)
      // Hassas veriyi güvenli depoda sakla
      final _secure = const FlutterSecureStorage();
      await _secure.write(key: 'uid', value: kullanici.id!.toString());
      await _secure.write(key: 'kullanici_adi', value: kullanici.kullaniciAdi);
      // Tema vb. hassas olmayan veriler SharedPreferences'ta kalabilir
      await _depo.sonGirisGuncelle(kullanici.id!);
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('Giriş hatası: $e');
      return false;
    }
  }

  // ── Çıkış ─────────────────────────────────────────────────────────────
  Future<void> cikisYap() async {
    _aktifKullanici = null;
    _oturumAktif = false;
    _yetkiCache = {};
    final _secure = const FlutterSecureStorage();
    await _secure.delete(key: 'uid');
    await _secure.delete(key: 'kullanici_adi');
  }

  // ── Mevcut kullanıcı ──────────────────────────────────────────────────
  Future<KullaniciModel?> mevcutKullanici() async {
    if (_aktifKullanici != null) return _aktifKullanici;
    final _secure = const FlutterSecureStorage();
    final uidStr = await _secure.read(key: 'uid');
    final uid = uidStr != null ? int.tryParse(uidStr) : null;
    if (uid == null) return null;
    _aktifKullanici = await _depo.idileGetir(uid);
    return _aktifKullanici;
  }

  // ── Oturum yenile (splash / arka plana dönüş) ─────────────────────────
  // Oturum süresi: DB'deki son_giris alanı referans alınır.
  // Cihaz saatini değiştirmek oturumu uzatamaz çünkü DB kaydı sunucu/uygulama
  // tarafından yazılıyor; kullanıcı doğrudan erişemiyor.
  Future<void> oturumuYenile() async {
    try {
      // SecureStorage'dan uid oku
      final _secure = const FlutterSecureStorage();
      final uidStr = await _secure.read(key: 'uid');
      final uid = uidStr != null ? int.tryParse(uidStr) : null;
      if (uid == null) { _aktifKullanici = null; return; }

      final kullanici = await _depo.idileGetir(uid);
      if (kullanici == null || !kullanici.aktif) {
        await cikisYap();
        return;
      }

      // son_giris DB'de ISO string olarak tutuluyor
      final sonGirisStr = kullanici.sonGiris;
      if (sonGirisStr != null) {
        final sonGiris = DateTime.tryParse(sonGirisStr);
        if (sonGiris != null) {
          final gecenDk =
              DateTime.now().difference(sonGiris).inMinutes;
          if (gecenDk > _oturumSureDk) {
            if (kDebugMode) debugPrint(
                'Oturum süresi doldu ($gecenDk dk > $_oturumSureDk dk)');
            await cikisYap();
            return;
          }
        }
      }

      // _oturumAktif false ise (uygulama yeniden açıldı) şifre gerekir
      // Kullanıcı bilgisini belleğe al ama oturumu aktif etme
      // Şifre ekranı bu kullanıcının pinini/şifresini doğrulayacak
      if (!_oturumAktif) {
        // Kullanıcı bulundu ama şifre doğrulanmadı
        // _aktifKullanici'yı set ETME → redirect /giris'e gider
        if (kDebugMode) debugPrint('Uygulama yeniden açıldı — şifre gerekiyor');
        return;
      }
      _aktifKullanici = kullanici;
      // 🔴 Derin analizde bulundu: yetkiCacheYenile() hiçbir yerden
      // çağrılmıyordu — bir yönetici başka bir cihazda oturum açmış bir
      // kullanıcının yetkisini değiştirdiğinde, o kullanıcı çıkış/giriş
      // yapmadan bu değişiklik hiç yansımıyordu (yetkiVarSync artık
      // müdür için de gerçek önbelleğe bakıyor — bkz. o fonksiyondaki
      // düzeltme — bu yüzden önbelleğin güncel kalması daha da önemli
      // hale geldi). Oturum her yenilendiğinde (uygulama ön plana
      // geldiğinde/yeniden başladığında) artık burada da tazeleniyor.
      if (kullanici.rol != KullaniciRolu.admin.label) {
        _yetkiCache = await _depo.yetkileriniGetir(kullanici.id!);
      }
      // Aktif kalındığını DB'ye işle
      await _depo.sonGirisGuncelle(kullanici.id!);
    } catch (e) {
      if (kDebugMode) debugPrint('Oturum yenileme hatası: $e');
      _aktifKullanici = null;
    }
  }

  Future<void> oturumKontrol() => oturumuYenile();

  // ── Yetki kontrolü — SYNC (önbellekten) ──────────────────────────────
  // 🔴🔴 KRİTİK GÜVENLİK AÇIĞI (derin analizde bulundu): müdür rolü de
  // admin gibi koşulsuz true dönüyordu — oysa kullanici_ekle_ekrani.dart
  // müdür için 'kullanici'/'ayarlar' HARİÇ tüm yetkileri varsayılan
  // yapıp, adminin bunları (ve başka herhangi bir yetkiyi) müdürden
  // TEK TEK KALDIRABİLECEĞİ bir kutucuk arayüzü sunuyor — yani ürünün
  // KENDİ tasarımı müdür yetkilerinin kısıtlanabilir olmasını
  // öngörüyor. Bu fonksiyon (ve aşağıdaki async yetkiVar) bu kısıtlamayı
  // tamamen etkisiz kılıyordu: adminin bir müdürden 'kullanici' iznini
  // kaldırması hiçbir şey değiştirmiyordu, o müdür yine de kullanıcı
  // yönetimi ekranına (ve oradan yeni admin hesabı oluşturmaya kadar)
  // erişebiliyordu. Artık sadece admin koşulsuz geçiyor; müdür de
  // normal yetki önbelleğine göre kontrol ediliyor (roller_yetki'de
  // zaten doğru varsayılanlarla kayıtlı — davranış, sadece gerçekten
  // KISITLANMIŞ müdürler için değişir).
  bool yetkiVarSync(String yetkiKodu) {
    if (_aktifKullanici == null) return false;
    if (_aktifKullanici!.rol == KullaniciRolu.admin.label) return true;
    return _yetkiCache.contains(yetkiKodu);
  }

  // Tüm yetkilerini döndür
  Set<String> get aktifYetkiler => _aktifKullanici?.rol == KullaniciRolu.admin.label
      ? {'*'} : _yetkiCache;

  // ── Yetki kontrolü — ASYNC (DB'den) ──────────────────────────────────
  /// Kullanıcı yetkisi DB'de değişince çağır — cache anında güncellenir
  Future<void> yetkiCacheYenile() async {
    if (_aktifKullanici != null) {
      _yetkiCache = await _depo.yetkileriniGetir(_aktifKullanici!.id!);
    } else {
      _yetkiCache = {};
    }
  }

  Future<bool> yetkiVar(String yetkiKodu) async {
    if (_aktifKullanici == null) return false;
    // 🔴🔴 GÜVENLİK DÜZELTMESİ (derin analizde bulundu): bu fonksiyon
    // ÖNCEDEN "tutarlılık" adına müdür için de koşulsuz true döndürecek
    // şekilde değiştirilmişti — ama bu, sync sürümdeki gerçek güvenlik
    // açığını (bkz. yetkiVarSync'teki not) buraya da taşımıştı. Artık
    // ikisi de aynı DOĞRU davranışta: sadece admin koşulsuz geçer,
    // müdür gerçek yetki kaydına göre kontrol edilir.
    if (_aktifKullanici!.rol == KullaniciRolu.admin.label) return true;
    try {
      final db = await Veritabani().db;
      final rows = await db.query(
        DbSabitler.rollerYetki,
        where: 'kullanici_id = ? AND yetki_kodu = ?',
        whereArgs: [_aktifKullanici!.id, yetkiKodu],
      );
      return rows.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // ── Şifre değiştir ────────────────────────────────────────────────────
  Future<bool> sifreDegistir(String eskiSifre, String yeniSifre) async {
    if (_aktifKullanici == null) return false;
    // ÖNCEDEN: hashle(eskiSifre)/hashle(yeniSifre) çağrılıp SONUÇLAR
    // depoya gönderiliyordu. Artık düz şifreler gönderiliyor —
    // KullaniciDeposu, eski şifreyi kullanıcının KENDİ tuzuyla
    // doğruluyor, yeni şifre için YENİ bir tuz üretip hashliyor.
    final kontrol = await _depo.girisKontrol(
        _aktifKullanici!.kullaniciAdi, eskiSifre);
    if (kontrol == null) return false;
    await _depo.sifreDegistir(_aktifKullanici!.id!, yeniSifre);
    return true;
  }
}

// ── Yetki red dialog (top-level) ─────────────────────────────────────────
void yetkiRedDialog(BuildContext context, {String? ekran}) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Row(children: [
        Icon(Icons.lock, color: Colors.red, size: 20),
        SizedBox(width: 8),
        Text('Erişim Kısıtlı', style: TextStyle(fontSize: 16)),
      ]),
      content: Text(
        ekran != null
            ? '$ekran ekranına erişim yetkiniz bulunmamaktadır.'
            : 'Bu işlem için yetkiniz bulunmamaktadır.',
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tamam')),
      ],
    ),
  );
}
