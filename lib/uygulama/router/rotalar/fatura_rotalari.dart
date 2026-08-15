// lib/uygulama/router/rotalar/fatura_rotalari.dart
//
// Fatura modülü rotaları — ana router dosyasından modülerleştirmenin bir
// parçası olarak ayrıldı. İçerik ana dosyadan birebir taşındı, davranış
// değişmedi.
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../ekranlar/fatura/fatura_detay_ekrani.dart';
import '../../../ekranlar/fatura/fatura_ekle_ekrani.dart';
import '../../../modeller/fatura_model.dart';

List<GoRoute> faturaRotalari(GlobalKey<NavigatorState> rootNavigatorKey) => [
        GoRoute(path: '/fatura/detay/:id', name: 'fatura_detay', parentNavigatorKey: rootNavigatorKey,
          builder: (c, s) => FaturaDetayEkrani(faturaId: int.parse(s.pathParameters['id']!))),
        GoRoute(path: '/fatura/yeni', name: 'fatura_yeni', parentNavigatorKey: rootNavigatorKey,
          builder: (c, s) => FaturaEkleEkrani(mevcutFatura: s.extra as FaturaModel?)),
      ];
