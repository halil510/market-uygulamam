// lib/uygulama/router/rotalar/banka_rotalari.dart
//
// Banka, kredi kartı ve mail bağlantı rotaları — ana router dosyasından
// (uygulama_router.dart) modülerleştirmenin bir parçası olarak ayrıldı.
// İçerik ana dosyadan birebir taşındı, davranış değişmedi.
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../ekranlar/banka/banka_liste_ekrani.dart';
import '../../../ekranlar/banka/banka_ekle_ekrani.dart';
import '../../../ekranlar/banka/banka_detay_ekrani.dart';
import '../../../ekranlar/banka/banka_hesap_liste_ekrani.dart';
import '../../../ekranlar/banka/banka_hesap_ekle_ekrani.dart';
import '../../../ekranlar/banka/kredi_karti_liste_ekrani.dart';
import '../../../ekranlar/banka/kredi_karti_ekle_ekrani.dart';
import '../../../ekranlar/banka/kredi_karti_detay_ekrani.dart';
import '../../../ekranlar/banka/banka_hareket_ekrani.dart';
import '../../../ekranlar/mail/mail_baglanti_ekrani.dart';
import '../../../modeller/banka_model.dart';
import '../../../modeller/kredi_karti_model.dart';

List<GoRoute> bankaRotalari(GlobalKey<NavigatorState> rootNavigatorKey) => [
        // Banka
        GoRoute(path: '/banka', name: 'banka_liste', parentNavigatorKey: rootNavigatorKey,
          builder: (_, __) => const BankaListeEkrani()),
        GoRoute(path: '/banka/ekle', name: 'banka_ekle', parentNavigatorKey: rootNavigatorKey,
          builder: (c, s) => BankaEkleEkrani(duzenlenecek: s.extra as BankaModel?)),
        GoRoute(path: '/banka/detay/:id', name: 'banka_detay', parentNavigatorKey: rootNavigatorKey,
          builder: (c, s) => BankaDetayEkrani(bankaId: int.parse(s.pathParameters['id']!))),

        // Banka Hesap Listesi
        GoRoute(path: '/banka/hesaplar/:bankaId', name: 'banka_hesap_liste', parentNavigatorKey: rootNavigatorKey,
          builder: (c, s) => BankaHesapListeEkrani(bankaId: int.parse(s.pathParameters['bankaId']!))),

        // Banka Hesap Ekle
        GoRoute(path: '/banka/hesap-ekle/:bankaId', name: 'banka_hesap_ekle', parentNavigatorKey: rootNavigatorKey,
          builder: (c, s) => BankaHesapEkleEkrani(bankaId: int.parse(s.pathParameters['bankaId']!))),

        // Kredi Kartı
        GoRoute(path: '/kredi-karti', name: 'kredi_karti_liste', parentNavigatorKey: rootNavigatorKey,
          builder: (c, s) => KrediKartiListeEkrani(bankaId: s.extra as int?)),
        GoRoute(path: '/kredi-karti/ekle', name: 'kredi_karti_ekle', parentNavigatorKey: rootNavigatorKey,
          builder: (c, s) => KrediKartiEkleEkrani(duzenlenecek: s.extra as KrediKartiModel?)),

        // Kredi Kartı Detay
        GoRoute(path: '/kredi-karti/detay/:id', name: 'kredi_karti_detay', parentNavigatorKey: rootNavigatorKey,
          builder: (c, s) => KrediKartiDetayEkrani(kartId: int.parse(s.pathParameters['id']!))),

        // Banka Hareketleri
        // DÜZELTME: 'extra' artık iki farklı çağıran tarafından iki farklı
        // tipte geliyordu — banka_hesap_liste_ekrani.dart 'extra: hesap.id'
        // (int) gönderirken, kredi_karti_detay_ekrani.dart
        // 'extra: {'krediKartiId': k.id}' (Map) gönderiyordu. Eski builder
        // sadece 'int?' bekliyordu; kredi kartı tarafından gelen çağrıda
        // "type 'Map<String, int>' is not a subtype of type 'int?'" hatası
        // fırlatırdı. Artık her iki çağıran taraf da Map gönderiyor
        // (tutarlı), builder da hem hesapId hem krediKartiId'yi okuyabiliyor;
        // eski int? formatı da geriye dönük uyumluluk için destekleniyor.
        GoRoute(path: '/banka-hareket', name: 'banka_hareket', parentNavigatorKey: rootNavigatorKey,
          builder: (c, s) {
            final extra = s.extra;
            if (extra is Map) {
              return BankaHareketEkrani(
                hesapId: extra['hesapId'] as int?,
                krediKartiId: extra['krediKartiId'] as int?,
              );
            }
            return BankaHareketEkrani(hesapId: extra as int?);
          }),

        // Mail
        GoRoute(path: '/mail-baglanti', name: 'mail_baglanti', parentNavigatorKey: rootNavigatorKey,
          builder: (_, __) => const MailBaglantiEkrani()),

        GoRoute(
          path: '/banka/kredi-kartlari/:bankaId',
          name: 'banka_kredi_kartlari',
          parentNavigatorKey: rootNavigatorKey,
          builder: (c, s) {
            final bankaId = int.tryParse(s.pathParameters['bankaId']!);
            return KrediKartiListeEkrani(bankaId: bankaId);
          },
        ),
      ];
