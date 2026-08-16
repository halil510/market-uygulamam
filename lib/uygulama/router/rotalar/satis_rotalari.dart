// lib/uygulama/router/rotalar/satis_rotalari.dart
//
// Satış modülü rotaları (sıcak/soğuk satış, fiş önizleme, detay, para üstü)
// — ana router dosyasından modülerleştirmenin bir parçası olarak ayrıldı.
// İçerik ana dosyadan birebir taşındı, davranış değişmedi.
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../ekranlar/satis/sicak_soguk_satis_ekrani.dart';
import '../../../ekranlar/toptan/toptan_satis_ekrani.dart';
import '../../../ekranlar/toptan/toptan_dashboard_ekrani.dart';
import '../../../ekranlar/toptan/toptan_urun_listesi_ekrani.dart';
import '../../../ekranlar/toptan/bekleyen_siparisler_ekrani.dart';
import '../../../ekranlar/satis/fis_onizleme_ekrani.dart';
import '../../../ekranlar/satis/satis_detay_ekrani.dart';
import '../../../ekranlar/satis/para_ustu_ekrani.dart';
import '../../../ekranlar/satis/hizli_tus_yonetim_ekrani.dart';

List<GoRoute> satisRotalari(GlobalKey<NavigatorState> rootNavigatorKey) => [
        GoRoute(path: '/satis/sicak', name: 'sicak_satis', parentNavigatorKey: rootNavigatorKey, builder: (_, __) => const SicakSogukSatisEkrani(tip: SatisTipi.sicak)),
        GoRoute(path: '/satis/soguk', name: 'soguk_satis', parentNavigatorKey: rootNavigatorKey, builder: (_, __) => const SicakSogukSatisEkrani(tip: SatisTipi.soguk)),
        GoRoute(path: '/satis/fis-onizleme', parentNavigatorKey: rootNavigatorKey, builder: (c, s) => FisOnizlemeEkrani(satis: s.extra as dynamic)),
        GoRoute(path: '/toptan/satis', name: 'toptan_satis', parentNavigatorKey: rootNavigatorKey, builder: (c, s) => const ToptanSatisEkrani()),
        GoRoute(path: '/toptan/dashboard', name: 'toptan_dashboard', parentNavigatorKey: rootNavigatorKey, builder: (c, s) => const ToptanDashboardEkrani()),
        GoRoute(path: '/toptan/urunler', name: 'toptan_urunler', parentNavigatorKey: rootNavigatorKey, builder: (c, s) => const ToptanUrunListesiEkrani()),
        GoRoute(path: '/toptan/bekleyen-siparisler', name: 'toptan_bekleyen_siparisler', parentNavigatorKey: rootNavigatorKey, builder: (c, s) => const BekleyenSiparislerEkrani()),
        GoRoute(path: '/satis/detay/:id', name: 'satis_detay', parentNavigatorKey: rootNavigatorKey,
          builder: (c, s) => SatisDetayEkrani(satisId: int.parse(s.pathParameters['id']!))),
        GoRoute(path: '/satis/para-ustu', name: 'para_ustu', parentNavigatorKey: rootNavigatorKey,
          builder: (c, s) => ParaUstuEkrani(odenmesiGereken: (s.extra as double?) ?? 0.0)),
        // 🆕 Hızlı tuş (favori ürün) yönetimi — Ayarlar ve Ürün
        // menülerinden de açılabilsin diye rota olarak tanımlandı.
        GoRoute(path: '/satis/hizli-tuslar', name: 'hizli_tuslar', parentNavigatorKey: rootNavigatorKey,
          builder: (c, s) => const HizliTusYonetimEkrani()),
      ];
