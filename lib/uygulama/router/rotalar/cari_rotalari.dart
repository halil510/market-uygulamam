// lib/uygulama/router/rotalar/cari_rotalari.dart
//
// Cari modülü rotaları (detay, hareket, tahsilat, puan, ekle) — ana router
// dosyasından modülerleştirmenin bir parçası olarak ayrıldı. İçerik ana
// dosyadan birebir taşındı, davranış değişmedi.
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../ekranlar/cari/cari_detay_ekrani.dart';
import '../../../ekranlar/cari/cari_hareket_ekrani.dart';
import '../../../ekranlar/cari/tahsilat_odeme_ekrani.dart';
import '../../../ekranlar/cari/musteri_puan_ekrani.dart';
import '../../../ekranlar/cari/cari_ekle_ekrani.dart';
import '../../../modeller/cari_model.dart';

List<GoRoute> cariRotalari(GlobalKey<NavigatorState> rootNavigatorKey) => [
        GoRoute(path: '/cari/detay/:id', name: 'cari_detay', parentNavigatorKey: rootNavigatorKey,
          builder: (c, s) => CariDetayEkrani(cariId: int.parse(s.pathParameters['id']!))),
        GoRoute(path: '/cari/hareket/:id', name: 'cari_hareket', parentNavigatorKey: rootNavigatorKey,
          builder: (c, s) => CariHareketEkrani(cariId: int.parse(s.pathParameters['id']!))),
        GoRoute(path: '/cari/tahsilat/:id', name: 'cari_tahsilat', parentNavigatorKey: rootNavigatorKey,
          builder: (c, s) => TahsilatOdemeEkrani(cariId: int.parse(s.pathParameters['id']!))),
        GoRoute(path: '/cari/puan/:id', name: 'cari_puan', parentNavigatorKey: rootNavigatorKey,
          builder: (c, s) {
            final extra = s.extra as Map<String, dynamic>?;
            return MusteriPuanEkrani(
              cariId: int.parse(s.pathParameters['id']!),
              cariUnvan: extra?['unvan'] as String? ?? '',
            );
          }),
        GoRoute(path: '/cari/ekle', name: 'cari_ekle', parentNavigatorKey: rootNavigatorKey,
          builder: (c, s) => CariEkleEkrani(duzenlenecekCari: s.extra as CariModel?)),
      ];
