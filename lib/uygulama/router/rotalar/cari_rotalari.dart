// lib/uygulama/router/rotalar/cari_rotalari.dart
//
// Cari modülü rotaları (detay, hareket, tahsilat, puan, ekle) — ana router
// dosyasından modülerleştirmenin bir parçası olarak ayrıldı. İçerik ana
// dosyadan birebir taşındı, davranış değişmedi.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../ekranlar/cari/cari_detay_ekrani.dart';
import '../../../ekranlar/cari/cari_hareket_ekrani.dart';
import '../../../ekranlar/cari/tahsilat_odeme_ekrani.dart';
import '../../../ekranlar/cari/musteri_puan_ekrani.dart';
import '../../../ekranlar/cari/cari_ekle_ekrani.dart';
import '../../../ekranlar/cari/cari_liste_ekrani.dart';
import '../../../ekranlar/cari/cari_secim_baglami.dart';
import '../../../modeller/cari_model.dart';

List<GoRoute> cariRotalari(GlobalKey<NavigatorState> rootNavigatorKey) => [
        GoRoute(path: '/cari/detay/:id', name: 'cari_detay', parentNavigatorKey: rootNavigatorKey,
          builder: (c, s) => CariDetayEkrani(cariId: int.parse(s.pathParameters['id']!))),
        // Menüdeki "Cari Hareket" ve "Tahsilat/Ödeme" kimliksiz gelir — bu
        // rotalar yokken ikisi de "Bu sayfa bulunamadı" gösteriyordu.
        _cariSecRotasi(rootNavigatorKey, '/cari/hareket', 'cari_hareket_sec',
            'Cari Hareket — hareketlerini görmek istediğiniz cariye tıklayın'),
        _cariSecRotasi(rootNavigatorKey, '/cari/tahsilat', 'cari_tahsilat_sec',
            'Tahsilat / Ödeme — işlem yapılacak cariye tıklayın'),
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

/// Kimliksiz [yol] için önce cari seçtirir; seçilen carinin `[yol]/:id`
/// ekranı seçim ekranının YERİNE açılır (Geri, menüden önceki ekrana döner).
GoRoute _cariSecRotasi(GlobalKey<NavigatorState> rootNavigatorKey, String yol,
        String ad, String mesaj) =>
    GoRoute(
      path: yol,
      name: ad,
      parentNavigatorKey: rootNavigatorKey,
      builder: (c, s) => Builder(
        builder: (ctx) => Scaffold(
          body: CariSecimBaglami(
            onSec: (cari) => ctx.pushReplacement('$yol/${cari.id}'),
            child: Column(children: [
              CariSecimCubugu(mesaj: mesaj, onKapat: () => ctx.pop()),
              const Expanded(child: CariListeEkrani()),
            ]),
          ),
        ),
      ),
    );
