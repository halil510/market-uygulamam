// lib/uygulama/router/rotalar/masa_rotalari.dart
//
// Masa/restoran modülü rotaları — ana router dosyasından modülerleştirmenin
// bir parçası olarak ayrıldı. İçerik ana dosyadan birebir taşındı, davranış
// değişmedi.
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../ekranlar/masa/masa_liste_ekrani.dart';
import '../../../ekranlar/masa/masa_detay_ekrani.dart';
import '../../../ekranlar/masa/masa_urun_ekle_ekrani.dart';
import '../../../ekranlar/masa/mutfak_ekrani.dart';
import '../../../ekranlar/masa/qr_menu_ekrani.dart';
import '../../../ekranlar/masa/masa_qr_goster_ekrani.dart';
import '../../../ekranlar/masa/qr_menu_urun_secim_ekrani.dart';
import '../../../modeller/masa_model.dart';

List<GoRoute> masaRotalari(GlobalKey<NavigatorState> rootNavigatorKey) => [
        GoRoute(path: '/masa/yonet', parentNavigatorKey: rootNavigatorKey, builder: (_, _) => const MasaListeEkrani(yonetim: true)),
        GoRoute(path: '/masa', name: 'masa', parentNavigatorKey: rootNavigatorKey, builder: (_, _) => const MasaListeEkrani()),
        GoRoute(path: '/mutfak', name: 'mutfak', parentNavigatorKey: rootNavigatorKey, builder: (_, _) => const MutfakEkrani()),
        // Kullanıcı isteği: 400 üründen QR menüde hangilerinin
        // görüneceğini seçebileceği ekran.
        GoRoute(path: '/masa/qr-urun-secim', name: 'qr_urun_secim', parentNavigatorKey: rootNavigatorKey,
          builder: (c, s) => const QrMenuUrunSecimEkrani(),
        ),
        GoRoute(path: '/qr-menu/:masaId/:masaAdi', name: 'qr_menu', parentNavigatorKey: rootNavigatorKey,
          builder: (c, s) => QrMenuEkrani(
            masaId: int.parse(s.pathParameters['masaId']!),
            masaAdi: _masaAdiCoz(s.pathParameters['masaAdi']!),
          ),
        ),
        // Kullanıcı isteği: müşteriler kendi telefonuyla QR okutup
        // sipariş versin — bu rota, o taranabilir QR kodun GÖSTERİLDİĞİ
        // ekrana gidiyor (yerel HTTP sunucu + gerçek QR kod görseli).
        GoRoute(path: '/masa/qr-goster/:masaId/:masaAdi', name: 'masa_qr_goster', parentNavigatorKey: rootNavigatorKey,
          builder: (c, s) => MasaQrGosterEkrani(
            masaId: int.parse(s.pathParameters['masaId']!),
            masaAdi: _masaAdiCoz(s.pathParameters['masaAdi']!),
          ),
        ),
        GoRoute(path: '/masa/detay/:id', name: 'masa_detay', parentNavigatorKey: rootNavigatorKey,
          builder: (c, s) {
            final id = int.parse(s.pathParameters['id']!);
            final extra = s.extra as Map<String, dynamic>?;
            return MasaDetayEkrani(
              masa: MasaModel(
                id: id,
                ad: extra?['ad'] as String? ?? 'Masa $id',
                kategori: extra?['kategori'] as String? ?? 'Salon',
                kapasite: extra?['kapasite'] as int? ?? 4,
                durum: extra?['durum'] as String? ?? 'bos',
              ),
            );
          },
        ),
        GoRoute(path: '/masa/urun-ekle/:masaId', name: 'masa_urun_ekle', parentNavigatorKey: rootNavigatorKey,
          builder: (c, s) => MasaUrunEkleEkrani(masaId: int.parse(s.pathParameters['masaId']!)),
        ),
      ];

/// go_router yol parametresini kısmen çözebildiği için (ör. "Bahçe 1" →
/// "Bah%E7e 1" benzeri) Uri.decodeComponent "Illegal percent encoding"
/// ile çöküyordu; Türkçe karakterli masa adları güvenle çözülür.
String _masaAdiCoz(String ham) {
  try {
    return Uri.decodeComponent(ham);
  } catch (_) {
    return ham;
  }
}
