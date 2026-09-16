// lib/uygulama/router/rotalar/ayarlar_rotalari.dart
//
// Ayarlar modülü rotaları — ShellRoute içinde (bottom nav ile birlikte)
// yaşayan rotalar. Ana router dosyasından modülerleştirmenin bir parçası
// olarak ayrıldı. İçerik ana dosyadan birebir taşındı, davranış değişmedi.
//
// NOT: Bunlar Shell içi rotalar olduğu için rootNavigatorKey almazlar
// (banka/borç/urun/cari/fatura/satis/masa rotalarının aksine).
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../ekranlar/ayarlar/ayarlar_giris_ekrani.dart';
import '../../../ekranlar/ayarlar/ayarlar_ekrani.dart';
import '../../../ekranlar/ayarlar/yazdirma_merkezi_ekrani.dart';
import '../../../ekranlar/ayarlar/yedekleme_ekrani.dart';
import '../../../ekranlar/ayarlar/sync_ekrani.dart';
import '../../../ekranlar/ayarlar/bulut_sync_ekrani.dart';
import '../../../ekranlar/ayarlar/site_fotograflari_ekrani.dart';
import '../../../ekranlar/ayarlar/site_icerik_ekrani.dart';
import '../../../ekranlar/ayarlar/audit_log_ekrani.dart';
import '../../../ekranlar/ayarlar/sync_cakismalari_ekrani.dart';
import '../../../ekranlar/ayarlar/veri_sagligi_ekrani.dart';
import '../../../ekranlar/ayarlar/donem_yonetimi_ekrani.dart';
import '../../../ekranlar/toptan/fiyat_gruplari_ekrani.dart';
import '../../../ekranlar/ayarlar/gib_ayar_ekrani.dart';
import '../../../ekranlar/ayarlar/log_ekrani.dart';
import '../../../ekranlar/ayarlar/doviz_kuru_ekrani.dart';
import '../../../ekranlar/ayarlar/ai_asistan_ayar_ekrani.dart';
import '../../../ekranlar/ayarlar/hata_izleme_ekrani.dart';

List<GoRoute> ayarlarRotalari(GlobalKey<NavigatorState> rootNavigatorKey) => [
      GoRoute(
          path: '/ayarlar',
          name: 'ayarlar_giris',
          builder: (_, __) => const AyarlarGirisEkrani()),
      GoRoute(
          path: '/ayarlar/icerik',
          name: 'ayarlar',
          builder: (_, __) => const AyarlarEkrani()),
      GoRoute(
          path: '/ayarlar/yazici',
          name: 'ayarlar_yazici',
          parentNavigatorKey: rootNavigatorKey,
          builder: (_, __) => const YazdirmaMerkeziEkrani(baslangicSekmesi: 0)),
      GoRoute(
          path: '/ayarlar/yazdirma',
          name: 'yazdirma_merkezi',
          parentNavigatorKey: rootNavigatorKey,
          builder: (_, __) => const YazdirmaMerkeziEkrani()),
      GoRoute(
          path: '/ayarlar/yedek',
          name: 'ayarlar_yedek',
          parentNavigatorKey: rootNavigatorKey,
          builder: (_, __) => const YedeklemeEkrani()),
      GoRoute(
          path: '/ayarlar/sync',
          name: 'ayarlar_sync',
          parentNavigatorKey: rootNavigatorKey,
          builder: (_, __) => const SyncEkrani()),
      GoRoute(
          path: '/ayarlar/bulut-sync',
          name: 'ayarlar_bulut_sync',
          parentNavigatorKey: rootNavigatorKey,
          builder: (_, __) => const BulutSyncEkrani()),
      GoRoute(
          path: '/ayarlar/hata-izleme',
          name: 'ayarlar_hata_izleme',
          parentNavigatorKey: rootNavigatorKey,
          builder: (_, __) => const HataIzlemeEkrani()),
      GoRoute(
          path: '/ayarlar/site-fotograflari',
          name: 'ayarlar_site_fotograflari',
          parentNavigatorKey: rootNavigatorKey,
          builder: (_, __) => const SiteFotograflariEkrani()),
      GoRoute(
          path: '/ayarlar/site-icerik',
          name: 'ayarlar_site_icerik',
          parentNavigatorKey: rootNavigatorKey,
          builder: (_, __) => const SiteIcerikEkrani()),
      GoRoute(
          path: '/ayarlar/audit-log',
          name: 'ayarlar_audit_log',
          parentNavigatorKey: rootNavigatorKey,
          builder: (_, __) => const AuditLogEkrani()),
      GoRoute(
          path: '/ayarlar/sync-cakismalari',
          name: 'ayarlar_sync_cakismalari',
          parentNavigatorKey: rootNavigatorKey,
          builder: (_, __) => const SyncCakismalariEkrani()),
      GoRoute(
          path: '/ayarlar/veri-sagligi',
          name: 'ayarlar_veri_sagligi',
          parentNavigatorKey: rootNavigatorKey,
          builder: (_, __) => const VeriSagligiEkrani()),
      GoRoute(
          path: '/ayarlar/donem-yonetimi',
          name: 'ayarlar_donem_yonetimi',
          parentNavigatorKey: rootNavigatorKey,
          builder: (_, __) => const DonemYonetimiEkrani()),
      GoRoute(
          path: '/toptan/fiyat-gruplari',
          name: 'fiyat_gruplari',
          parentNavigatorKey: rootNavigatorKey,
          builder: (_, __) => const FiyatGruplariEkrani()),
      GoRoute(
          path: '/ayarlar/gib',
          name: 'ayarlar_gib',
          parentNavigatorKey: rootNavigatorKey,
          builder: (_, __) => const GibAyarEkrani()),
      GoRoute(
          path: '/ayarlar/log',
          name: 'ayarlar_log',
          parentNavigatorKey: rootNavigatorKey,
          builder: (_, __) => const LogEkrani()),
      GoRoute(
          path: '/ayarlar/doviz',
          name: 'ayarlar_doviz',
          parentNavigatorKey: rootNavigatorKey,
          builder: (_, __) => const DovizKuruEkrani()),
      GoRoute(
          path: '/ayarlar/ai-asistan',
          name: 'ayarlar_ai_asistan',
          parentNavigatorKey: rootNavigatorKey,
          builder: (_, __) => const AiAsistanAyarEkrani()),
    ];
