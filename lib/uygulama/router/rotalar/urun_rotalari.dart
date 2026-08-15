// lib/uygulama/router/rotalar/urun_rotalari.dart
//
// Ürün modülü rotaları (PLU, detay, ekle, toplu işlem, kategori, marka,
// birim) — ana router dosyasından modülerleştirmenin bir parçası olarak
// ayrıldı. İçerik ana dosyadan birebir taşındı, davranış değişmedi.
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../ekranlar/urun/plu_yonetim_ekrani.dart';
import '../../../ekranlar/urun/urun_detay_ekrani.dart';
import '../../../ekranlar/urun/urun_ekle_ekrani.dart';
import '../../../ekranlar/urun/toplu_islem_ekrani.dart';
import '../../../ekranlar/urun/toplu_fiyat_ekrani.dart';
import '../../../ekranlar/urun/kategori_ekrani.dart';
import '../../../ekranlar/urun/marka_ekrani.dart';
import '../../../ekranlar/birim/birim_ekrani.dart';
import '../../../modeller/urun_model.dart';

List<GoRoute> urunRotalari(GlobalKey<NavigatorState> rootNavigatorKey) => [
        GoRoute(path: '/urun/plu', name: 'plu_yonetim', parentNavigatorKey: rootNavigatorKey, builder: (_, __) => const PluYonetimEkrani()),
        GoRoute(path: '/urun/detay/:id', name: 'urun_detay', parentNavigatorKey: rootNavigatorKey,
          builder: (c, s) => UrunDetayEkrani(urunId: int.parse(s.pathParameters['id']!))),
        GoRoute(path: '/urun/ekle', name: 'urun_ekle', parentNavigatorKey: rootNavigatorKey,
          builder: (c, s) {
            final e = s.extra;
            if (e is UrunModel) return UrunEkleEkrani(duzenlenecekUrun: e);
            if (e is Map && e['barkod'] != null) return UrunEkleEkrani(baslangicBarkod: e['barkod']);
            return const UrunEkleEkrani();
          }),
        GoRoute(path: '/urun/toplu-islem', name: 'urun_toplu_islem', parentNavigatorKey: rootNavigatorKey,
          builder: (c, s) => TopluIslemEkrani(secilenIds: s.extra is List<int> ? s.extra as List<int> : [])),
        GoRoute(path: '/urun/toplu-fiyat', name: 'urun_toplu_fiyat', parentNavigatorKey: rootNavigatorKey, builder: (_, __) => const TopluFiyatEkrani()),
        GoRoute(path: '/urun/kategori', name: 'urun_kategori', parentNavigatorKey: rootNavigatorKey, builder: (_, __) => const KategoriEkrani()),
        GoRoute(path: '/urun/marka', name: 'urun_marka', parentNavigatorKey: rootNavigatorKey, builder: (_, __) => const MarkaEkrani()),
        GoRoute(path: '/birim', name: 'birim', parentNavigatorKey: rootNavigatorKey, builder: (_, __) => const BirimEkrani()),
      ];
