// lib/servisler/bulut/otomatik_bulut_cekme.dart
//
// OTOMATİK BULUTTAN ÇEKME (kullanıcı isteği 2026-09-28).
//
// Gönderim zaten otomatikti (BulutManager kuyruğu, 8 sn). Ama diğer
// kasaların/cihazların verisi (satış, stok, cari bakiye…) yalnızca "Buluttan
// Al" butonuna basınca ya da Masa ekranı açıkken geliyordu — çok kasalı
// kullanımda bir kasa, diğerinin sattığı ürünün stoğunu ya da tahsil ettiği
// carinin bakiyesini eski görüyordu.
//
// Bu servis uygulama AÇIK ve ÖNDE olduğu sürece belirli aralıkla (varsayılan
// 60 sn, Ayarlar > Bulut Senkronizasyon'dan değiştirilebilir / kapatılabilir)
// yalnız DEĞİŞEN kayıtları çeker:
//   • bulut yapılandırılmamışsa, internet yoksa, uygulama arka plandaysa
//     çekmez; uygulama öne gelince hemen bir kez çeker,
//   • hata alırsa aralığı katlayarak (en fazla 5 dk) seyrekleştirir,
//   • elle "Buluttan Al" / Masa ekranı çekmesiyle çakışmaz
//     (SupabaseSyncServisi.buluttanAl zaten tek uçuşlu — devam edeni paylaşır).
// Değişiklik geldiğinde [sonDegisiklik] güncellenir; ekranlar dinleyip yenilenir.
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../veri/database/veritabani.dart';
import '../log_servisi.dart';
import '../supabase_sync_servisi.dart';
import 'bulut_manager.dart';

class OtomatikBulutCekme with WidgetsBindingObserver {
  static final OtomatikBulutCekme _instance = OtomatikBulutCekme._();
  factory OtomatikBulutCekme() => _instance;
  OtomatikBulutCekme._();

  /// Ayar anahtarı: saniye cinsinden aralık, 0 = kapalı.
  static const ayarAnahtari = 'mp_oto_cekme_sn';
  static const varsayilanSaniye = 60;
  static const secenekler = <int>[30, 60, 120, 300, 0];
  static const _enUzun = Duration(minutes: 5);

  /// Son çekmede buluttan en az bir kayıt geldiyse o anın zamanı.
  final sonDegisiklik = ValueNotifier<DateTime?>(null);

  /// Son başarılı kontrol zamanı (değişiklik olsun olmasın) — ekranda gösterim.
  final sonKontrol = ValueNotifier<DateTime?>(null);

  Timer? _zamanlayici;
  bool _basladi = false;
  bool _calisiyor = false;
  bool _onde = true;
  int _ardisikHata = 0;
  int _aralikSn = varsayilanSaniye;

  static Future<int> aralikOku() async =>
      (await SharedPreferences.getInstance()).getInt(ayarAnahtari) ?? varsayilanSaniye;

  /// Ayarı kaydeder ve zamanlayıcıyı yeni aralıkla yeniden kurar.
  Future<void> aralikAyarla(int saniye) async {
    await (await SharedPreferences.getInstance()).setInt(ayarAnahtari, saniye);
    _aralikSn = saniye;
    _ardisikHata = 0;
    _planla();
  }

  Future<void> baslat() async {
    if (_basladi) return;
    _basladi = true;
    WidgetsBinding.instance.addObserver(this);
    _aralikSn = await aralikOku();
    _planla();
  }

  void durdur() {
    _zamanlayici?.cancel();
    _zamanlayici = null;
    if (_basladi) WidgetsBinding.instance.removeObserver(this);
    _basladi = false;
  }

  /// Sonraki çekme için bekleme: hata yoksa ayar aralığı; ardışık hatada
  /// her seferinde iki katı (en fazla 5 dk).
  @visibleForTesting
  static Duration beklemeHesapla(int aralikSn, int ardisikHata) {
    final temel = Duration(seconds: aralikSn);
    if (ardisikHata <= 0) return temel;
    final katsayi = 1 << (ardisikHata > 5 ? 5 : ardisikHata);
    final bekleme = temel * katsayi;
    return bekleme > _enUzun ? _enUzun : bekleme;
  }

  void _planla() {
    _zamanlayici?.cancel();
    if (!_basladi || _aralikSn <= 0) return;
    _zamanlayici = Timer(beklemeHesapla(_aralikSn, _ardisikHata), () async {
      await simdiCek();
      _planla();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final onceOnde = _onde;
    _onde = state == AppLifecycleState.resumed;
    // Arka plandan dönünce beklemeden güncel veriyi al.
    if (_onde && !onceOnde && _aralikSn > 0) {
      unawaited(simdiCek().then((_) => _planla()));
    }
  }

  /// Koşullar uygunsa değişenleri şimdi çeker. Döner: gelen kayıt sayısı
  /// (çekme yapılmadıysa null).
  Future<int?> simdiCek() async {
    if (_calisiyor || !_onde) return null;
    final durum = BulutManager().durum.value;
    if (durum == BulutDurum.yapilandirilmamis) return null;
    _calisiyor = true;
    try {
      final baglanti = await Connectivity().checkConnectivity();
      if (baglanti.every((b) => b == ConnectivityResult.none)) return null;

      final db = Veritabani();
      final sonuc = await SupabaseSyncServisi.buluttanAl(
        kayitEkle: (t, k) => db.supaKayitlariEkle(t, k),
        kayitGuncelle: (t, k) => db.supaKayitlariGuncelle(t, k),
        sadeceDegisenler: true,
      );
      if (!sonuc.basarili) {
        _ardisikHata++;
        LogServisi().uyari('OtomatikBulutCekme: otomatik çekme hatası ($_ardisikHata. kez)',
            ek: sonuc.hatalar.take(2).join(' | '));
        return 0;
      }
      _ardisikHata = 0;
      final gelen = sonuc.toplamEklenen + sonuc.toplamGuncellenen + sonuc.toplamSilinen;
      sonKontrol.value = DateTime.now();
      if (gelen > 0) sonDegisiklik.value = DateTime.now();
      return gelen;
    } catch (e, st) {
      _ardisikHata++;
      LogServisi().hata('OtomatikBulutCekme', hata: e, yigin: st);
      return null;
    } finally {
      _calisiyor = false;
    }
  }
}
