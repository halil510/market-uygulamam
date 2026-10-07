// lib/uygulama/router/rotalar/borc_rotalari.dart
//
// Borç takip modülü rotaları — ana router dosyasından modülerleştirmenin
// bir parçası olarak ayrıldı. İçerik ana dosyadan birebir taşındı.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../ekranlar/borc/borc_dashboard_ekrani.dart';
import '../../../ekranlar/borc/borc_detay_ekrani.dart';
import '../../../ekranlar/borc/borc_odeme_ekrani.dart';
import '../../../modeller/borc_model.dart';

List<GoRoute> borcRotalari(GlobalKey<NavigatorState> rootNavigatorKey) => [
        GoRoute(path: '/borc-dashboard', name: 'borc_dashboard', parentNavigatorKey: rootNavigatorKey,
          builder: (_, _) => const BorcDashboardEkrani()),
        GoRoute(path: '/borc-detay/:id', name: 'borc_detay', parentNavigatorKey: rootNavigatorKey,
          builder: (_, s) {
            final id = int.tryParse(s.pathParameters['id'] ?? '');
            // Geçersiz id'de int.parse çökmesi yerine ödenecek borç seçimi.
            return id == null ? const BorcOdemeEkrani() : BorcDetayEkrani(borcId: id);
          }),
        // Borç bilgisi olmadan: ödenecek borç seçilir.
        GoRoute(path: '/borc-odeme', name: 'borc_odeme_secim', parentNavigatorKey: rootNavigatorKey,
          builder: (_, s) => BorcOdemeEkrani(borc: _extraBorc(s))),
        // 🔴 DÜZELTME (2026-10-07): :id artık gerçekten kullanılıyor; extra
        // yoksa borç id ile yüklenir. Eskiden builder içinden post-frame
        // pop yapılıyordu — her yeniden çizimde tekrar tetiklenip alttaki
        // ekranları da kapatabiliyor, geri dönülecek sayfa yoksa çöküyordu.
        GoRoute(path: '/borc-odeme/:id', name: 'borc_odeme', parentNavigatorKey: rootNavigatorKey,
          builder: (_, s) => BorcOdemeEkrani(
                borc: _extraBorc(s),
                borcId: int.tryParse(s.pathParameters['id'] ?? ''),
              )),
      ];

/// `extra` yalnızca gerçekten BorcModel ise kullanılır (`as` dönüşümü,
/// durum geri yüklemesinde farklı tipte gelen extra ile TypeError veriyordu).
BorcModel? _extraBorc(GoRouterState s) {
  final extra = s.extra;
  return extra is BorcModel ? extra : null;
}
