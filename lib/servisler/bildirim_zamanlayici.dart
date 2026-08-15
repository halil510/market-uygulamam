// lib/servisler/bildirim_zamanlayici.dart
//
// İki görevi birden yapar:
//   1. Kritik stok bildirimi — her gün 09:00'da kontrol, stok = 0 olanlara push
//   2. Otomatik yedekleme — her gün 23:30'da kontrol eder; Ayarlar >
//      Yedekleme'deki "yedek_sikligi" ayarına göre (günlük/haftalık)
//      yedek gerekiyorsa sessizce alır.
//
// Kullanım (UygulamaBaslat.baslat() içinde):
//   await BildirimZamanlayici().baslat();
//
// Bağımlılık: flutter_local_notifications: ^17.x
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import '../uygulama/router/uygulama_router.dart' show rootNavigatorKey;
import '../depolar/urun_deposu.dart';
import '../servisler/yedekleme_servisi.dart';
import '../veri/database/veritabani.dart';

class BildirimZamanlayici {
  static final BildirimZamanlayici _i = BildirimZamanlayici._();
  factory BildirimZamanlayici() => _i;
  BildirimZamanlayici._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Timer? _gunlukTimer;
  Timer? _haftalikTimer;
  bool   _baslatildi = false;

  // ── Başlat ────────────────────────────────────────────────────────────
  Future<void> baslat() async {
    if (_baslatildi) return;
    _baslatildi = true;

    await _pluginiBaslat();
    _gunlukKontrolZamanla();
    _haftalikYedekZamanla();
  }

  Future<void> _pluginiBaslat() async {
    const androidSetting = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSetting     = DarwinInitializationSettings(
      requestAlertPermission:  true,
      requestBadgePermission:  true,
      requestSoundPermission:  false,
    );
    await _plugin.initialize(
      const InitializationSettings(android: androidSetting, iOS: iosSetting),
      // ÖNCEDEN bildirime dokunulduğunda HİÇBİR YERE yönlendirme
      // yapılmıyordu — kullanıcı sadece uygulamayı önceden bulunduğu
      // ekranda buluyordu, "3 ürün kritik stokta" bildirimi neyle
      // ilgili olduğunu TAHMİN etmek zorunda kalıyordu. Artık her
      // bildirim türü kendi ilgili ekranına doğrudan götürüyor.
      onDidReceiveNotificationResponse: (response) {
        final rota = switch (response.payload) {
          'kritik_stok' => '/stok',
          'yedekleme'   => '/ayarlar/yedek',
          _ => null,
        };
        if (rota == null) return;
        final ctx = rootNavigatorKey.currentContext;
        if (ctx != null) GoRouter.of(ctx).push(rota);
      },
    );
    // Android 13+ için runtime izni
    if (Platform.isAndroid) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }
  }

  // ── Günlük stok kontrolü ──────────────────────────────────────────────
  void _gunlukKontrolZamanla() {
    final simdi    = DateTime.now();
    final hedefSaat = DateTime(simdi.year, simdi.month, simdi.day, 9, 0);
    // Bugün 09:00 geçmişse yarın
    var bekleme = hedefSaat.difference(simdi);
    if (bekleme.isNegative) bekleme += const Duration(days: 1);

    _gunlukTimer = Timer(bekleme, () {
      _kritikStokKontrol();
      // Her gün tekrarla
      _gunlukTimer = Timer.periodic(const Duration(days: 1), (_) {
        _kritikStokKontrol();
      });
    });
  }

  Future<void> _kritikStokKontrol() async {
    try {
      final kritikler = await UrunDeposu().kritikStoklar();
      if (kritikler.isEmpty) return;

      final tukenenler = kritikler.where((u) => u.stok <= 0).toList();
      final azalanlar  = kritikler.where((u) => u.stok > 0).toList();

      if (tukenenler.isNotEmpty) {
        await _bildirimGonder(
          id:     1001,
          baslik: '${tukenenler.length} ürün tükendi!',
          icerik: tukenenler.take(3).map((u) => u.urunAdi).join(', ') +
              (tukenenler.length > 3 ? '...' : ''),
          oncelik: Importance.high,
          payload: 'kritik_stok',
        );
      }

      if (azalanlar.isNotEmpty) {
        await _bildirimGonder(
          id:     1002,
          baslik: '${azalanlar.length} ürün kritik stokta',
          icerik: azalanlar.take(3).map((u) =>
              '${u.urunAdi}: ${u.stok.toStringAsFixed(0)} ${u.birimAdi}').join(', '),
          oncelik: Importance.defaultImportance,
          payload: 'kritik_stok',
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Kritik stok kontrol hatası: $e');
    }
  }

  // ── Otomatik yedek ────────────────────────────────────────────────────
  // Her gün 23:30'da kontrol eder — yedek gerekiyorsa alır
  // Ayardan "yedek_sıklık" okunur: 'gunluk' veya 'haftalik'
  void _haftalikYedekZamanla() {
    final simdi = DateTime.now();
    // Her gün 23:30'da kontrol
    var hedef = DateTime(simdi.year, simdi.month, simdi.day, 23, 30);
    var bekleme = hedef.difference(simdi);
    if (bekleme.isNegative) bekleme += const Duration(days: 1);

    _haftalikTimer = Timer(bekleme, () {
      _otomatikYedekKontrol();
      _haftalikTimer = Timer.periodic(const Duration(days: 1), (_) {
        _otomatikYedekKontrol();
      });
    });
  }

  Future<void> _otomatikYedekKontrol() async {
    try {
      final yedek = YedeklemeServisi();
      
      // Yedek sıklığını ayardan oku (varsayılan: günlük)
      final db = await Veritabani().db;
      final rows = await db.query('ayarlar',
          where: "anahtar = 'yedek_sikligi'");
      final sikligi = rows.isEmpty
          ? 'gunluk'
          : rows.first['deger'] as String? ?? 'gunluk';
      
      final gunAralik = sikligi == 'haftalik' ? 7 : 1;
      final gerekli   = await yedek.yedekGerekliMi(gunAralik: gunAralik);
      
      if (!gerekli) {
        if (kDebugMode) debugPrint('Yedek henüz gerekli değil');
        return;
      }

      final yol = await yedek.yedekAl(otomatik: true);
      if (kDebugMode) debugPrint('Otomatik yedek alındı: $yol');
      
      await _bildirimGonder(
        id:     2001,
        baslik: 'Otomatik yedek alındı ✓',
        icerik: 'Verileriniz güvenle yedeklendi.',
        oncelik: Importance.low,
        payload: 'yedekleme',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('Otomatik yedek hatası: $e');
      // Yedek hatası bildirim gönder
      await _bildirimGonder(
        id:     2002,
        baslik: 'Yedek alınamadı!',
        icerik: 'Lütfen Ayarlar > Yedekleme ekranından manuel yedek alın.',
        oncelik: Importance.high,
        payload: 'yedekleme',
      );
    }
  }

  // ── Bildirim gönder ───────────────────────────────────────────────────
  Future<void> _bildirimGonder({
    required int id,
    required String baslik,
    required String icerik,
    Importance oncelik = Importance.defaultImportance,
    String? payload,
  }) async {
    try {
      await _plugin.show(
        id,
        baslik,
        icerik,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'marketplus_$id',
            'MarketPlus Bildirimleri',
            importance: oncelik,
            priority:   oncelik == Importance.high ? Priority.high : Priority.defaultPriority,
            icon:       '@mipmap/ic_launcher',
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: false,
          ),
        ),
        payload: payload,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('Bildirim gönderme hatası: $e');
    }
  }

  // ── Anında kritik stok kontrol (manuel tetikle) ───────────────────────
  Future<void> simdiKontrolEt() => _kritikStokKontrol();

  void durdur() {
    _gunlukTimer?.cancel();
    _haftalikTimer?.cancel();
    _baslatildi = false;
  }
}
