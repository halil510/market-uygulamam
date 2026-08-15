// lib/servisler/borc/borc_bildirim_servisi.dart
import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import '../../depolar/borc_deposu.dart'; // ✅ Doğru yol: iki üst -> depolar
import '../../uygulama/router/uygulama_router.dart' show rootNavigatorKey;

class BorcBildirimServisi {
  static final BorcBildirimServisi _instance = BorcBildirimServisi._();
  factory BorcBildirimServisi() => _instance;
  BorcBildirimServisi._();

  final _depo = BorcDeposu();
  Timer? _gunlukTimer;
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();

  Future<void> baslat() async {
    await _initNotifications();
    _gunlukTimer = Timer.periodic(const Duration(hours: 6), _kontrolEt);
    Future.delayed(const Duration(seconds: 5), () => _kontrolEt(null));
  }

  Future<void> _initNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    const settings = InitializationSettings(android: android, iOS: ios);
    // ÖNCEDEN bildirime dokunulduğunda hiçbir yere yönlendirme yoktu —
    // kullanıcı "vade yaklaşıyor" bildirimini görüp neyle ilgili
    // olduğunu tahmin etmek zorunda kalıyordu. Artık doğrudan Borç
    // Takip ekranına götürüyor.
    await _notifications.initialize(settings, onDidReceiveNotificationResponse: (response) {
      final ctx = rootNavigatorKey.currentContext;
      if (ctx != null) GoRouter.of(ctx).push('/borc-takip');
    });
  }

  Future<void> _kontrolEt(Timer? timer) async {
    try {
      final yaklasanlar = await _depo.yaklasanlariGetir(gun: 3);
      final gecmisler = await _depo.vadesiGecenleriGetir();

      if (yaklasanlar.isNotEmpty) {
        await _bildirimGonder(
          title: '⚠️ Yaklaşan Ödemeler',
          body: '${yaklasanlar.length} borcunuz için ${yaklasanlar.first.kalanGun} gün kaldı',
          id: 3001,
        );
      }

      if (gecmisler.isNotEmpty) {
        await _bildirimGonder(
          title: '❗ Vadesi Geçmiş Borçlar',
          body: '${gecmisler.length} borcun vadesi geçti! Hemen ödeme yapın.',
          id: 3002,
          priority: Priority.high,
        );
      }
    } catch (e) {
      // log
    }
  }

  Future<void> _bildirimGonder({
    required String title,
    required String body,
    required int id,
    Priority priority = Priority.defaultPriority,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'borc_takip_channel',
      'Borç Takip Bildirimleri',
      importance: Importance.max,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);
    await _notifications.show(id, title, body, details);
  }

  void dispose() => _gunlukTimer?.cancel();
}