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
          builder: (_, __) => const BorcDashboardEkrani()),
        GoRoute(path: '/borc-detay/:id', name: 'borc_detay', parentNavigatorKey: rootNavigatorKey,
          builder: (c, s) => BorcDetayEkrani(borcId: int.parse(s.pathParameters['id']!))),
        GoRoute(path: '/borc-odeme/:id', name: 'borc_odeme', parentNavigatorKey: rootNavigatorKey,
          builder: (c, s) {
            final borc = s.extra as BorcModel?;
            if (borc != null) return BorcOdemeEkrani(borc: borc);
            // 'extra' olarak BorcModel gönderilmeden bu rotaya girilirse
            // artık sessizce boş ekran yerine geri dönülüyor + uyarı basılıyor.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (c.mounted) c.pop();
            });
            return const Scaffold(body: Center(child: Text('Borç bilgisi eksik')));
          }),
      ];
