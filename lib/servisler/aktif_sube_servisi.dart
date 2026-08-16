// lib/servisler/aktif_sube_servisi.dart
//
// ÖNCEDEN "aktif şube" kavramı SADECE sube_ekrani.dart içinde yerel bir
// state değişkeniydi — hiçbir başka ekran (satış, kasa, raporlar) bunu
// okuyamıyordu, yani "çoklu şube" desteği aslında yalnızca bir etiketten
// ibaretti, gerçek bir veri ayrışması/filtreleme yoktu.
//
// Bu servis, uygulama genelinde TEK GERÇEK KAYNAK (single source of
// truth) olarak "şu an hangi şubede çalışıyoruz" bilgisini tutar:
//   - Kullanıcının kendi şubesi atanmışsa (personel.sube_id), varsayılan
//     olarak O ŞUBEYE kilitlenir — sıradan personel şube değiştiremez.
//   - Admin/Müdür rolündeki kullanıcılar şubeler arasında geçiş
//     yapabilir VEYA "Tüm Şubeler" (null) görünümünü seçebilir.
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_servisi.dart';
import '../veri/database/veritabani.dart';

class AktifSubeServisi extends ChangeNotifier {
  static final AktifSubeServisi _instance = AktifSubeServisi._();
  factory AktifSubeServisi() => _instance;
  AktifSubeServisi._();

  int? _aktifSubeId;
  String? _aktifSubeAdi;
  bool _hazir = false;

  /// null ise "Tüm Şubeler" (yalnızca admin/müdür için) demektir.
  int? get subeId => _aktifSubeId;
  String get subeAdi => _aktifSubeAdi ?? 'Tüm Şubeler';
  bool get tumSubelerModu => _aktifSubeId == null;
  bool get hazir => _hazir;

  /// Kullanıcının KENDİ şubesine kilitli olup olmadığı — admin/müdür
  /// değilse ve bir şubeye atanmışsa true döner (şube değiştiremez).
  bool get kilitliMi {
    final kullanici = AuthServisi().aktifKullanici;
    if (kullanici == null) return false;
    if (kullanici.isAdmin || kullanici.isMudur) return false;
    return kullanici.subeId != null;
  }

  /// Uygulama açılışında (splash veya giriş sonrası) çağrılır.
  Future<void> baslat() async {
    final kullanici = AuthServisi().aktifKullanici;
    final prefs = await SharedPreferences.getInstance();

    if (kullanici != null && kullanici.subeId != null &&
        !(kullanici.isAdmin || kullanici.isMudur)) {
      // Sıradan personel — kendi şubesine kilitli, tercih sorulmaz.
      _aktifSubeId = kullanici.subeId;
      // 🔴 DÜZELTME: _aktifSubeAdi hiç ayarlanmıyordu — kilitli bir
      // personel gerçekte belirli bir şubeye atanmış olsa bile, ekranda
      // (ör. Dashboard'daki şube rozeti) yanlışlıkla "Tüm Şubeler"
      // gösteriliyordu (subeAdi getter'ı null ise bu varsayılana düşer).
      try {
        final db = await Veritabani().db;
        final rows = await db.query('subeler',
            columns: ['sube_adi'], where: 'id = ?', whereArgs: [kullanici.subeId], limit: 1);
        if (rows.isNotEmpty) _aktifSubeAdi = rows.first['sube_adi'] as String?;
      } catch (_) {
        // Şube adı çekilemezse sessizce geç — subeId zaten doğru, sadece
        // etiket eksik kalır.
      }
    } else {
      // Admin/Müdür veya şubesiz kullanıcı — son seçilen şube hatırlanır.
      final kayitli = prefs.getInt('aktif_sube_id');
      _aktifSubeId = kayitli == 0 ? null : kayitli; // 0 = "Tüm Şubeler" kodlaması
      // 🔴 Aynı düzeltme: burada da _aktifSubeAdi hiç ayarlanmıyordu —
      // uygulama yeniden başlatıldığında, önceden seçilmiş bir şube
      // geri yüklense bile etiket "Tüm Şubeler" görünüyordu.
      if (_aktifSubeId != null) {
        try {
          final db = await Veritabani().db;
          final rows = await db.query('subeler',
              columns: ['sube_adi'], where: 'id = ?', whereArgs: [_aktifSubeId], limit: 1);
          if (rows.isNotEmpty) _aktifSubeAdi = rows.first['sube_adi'] as String?;
        } catch (_) {
          // sessizce geç
        }
      }
    }
    _hazir = true;
    notifyListeners();
  }

  /// Şube değiştirir (sadece admin/müdür veya şubesiz kullanıcı
  /// kullanabilir — kilitliMi true ise çağıran taraf bu fonksiyonu
  /// hiç göstermemeli).
  Future<void> subeDegistir(int? yeniSubeId, {String? yeniSubeAdi}) async {
    if (kilitliMi) return; // güvenlik: kilitliyse sessizce yok say
    _aktifSubeId = yeniSubeId;
    _aktifSubeAdi = yeniSubeAdi;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('aktif_sube_id', yeniSubeId ?? 0);
    notifyListeners();
  }

  /// Bir SQL sorgusuna şube filtresi eklemek için yardımcı — aktif şube
  /// seçiliyse "AND sube_id = ?" ekler, "Tüm Şubeler" modundaysa hiçbir
  /// şey eklemez. Kullanım:
  ///   final (kosul, args) = AktifSubeServisi().filtreEkle('kasa_hareketleri.tarih > ?', [tarih]);
  (String, List<Object?>) filtreEkle(String temelKosul, List<Object?> temelArgs, {String tabloOneki = ''}) {
    if (_aktifSubeId == null) return (temelKosul, temelArgs);
    final subeKolonu = tabloOneki.isEmpty ? 'sube_id' : '$tabloOneki.sube_id';
    final yeniKosul = temelKosul.isEmpty
        ? '$subeKolonu = ?'
        : '$temelKosul AND $subeKolonu = ?';
    return (yeniKosul, [...temelArgs, _aktifSubeId]);
  }
}
