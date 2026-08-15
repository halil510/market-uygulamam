// lib/tasarim_sistemi/ts_token.dart
//
// TASARIM SİSTEMİ — TEK KAYNAK (SINGLE SOURCE OF TRUTH)
// ------------------------------------------------------------------
// Uygulamadaki TÜM renk, boşluk, radius, gölge ve yazı tipi değerleri
// buradan gelir. Ekranlarda asla sabit (magic number) renk/boşluk
// yazılmaz — her zaman TsRenk / TsBosluk / TsRadius / TsMetin kullanılır.
//
// Amaç: Logo Yazılım / kurumsal ERP hissi veren, tutarlı, sade bir görünüm.
// ------------------------------------------------------------------
import 'package:flutter/material.dart';

/// Marka & durum renkleri. acik_tema.dart / koyu_tema.dart içindeki
/// AppRenkler ile birebir aynı paleti kullanır — burada tema-bağımsız
/// yardımcı erişim ve ek yarı-tonlar sağlanır.
class TsRenk {
  TsRenk._();

  static const primary = Color(0xFF4361EE);
  static const primaryKoyu = Color(0xFF3A0CA3);
  // Masa/restoran modülü tonları — TsModulRenk.masa ile birebir aynı,
  // const bağlamlarda (ör. `const Color(...)`) doğrudan kullanılabilsin
  // diye burada da sabit olarak tutuluyor.
  static const masaKoyu = Color(0xFF4E342E);
  static const masaAcik = Color(0xFF6D4C41);
  static const accent = Color(0xFF7209B7);

  static const basarili = Color(0xFF2ECC71);
  static const uyari = Color(0xFFF39C12);
  static const hata = Color(0xFFE74C3C);
  static const bilgi = Color(0xFF3498DB);
  static const notr = Color(0xFF6B7280);

  static const beyaz = Color(0xFFFFFFFF);
  static const arkaplanAcik = Color(0xFFF8F9FE);
  static const kartAcik = Color(0xFFFFFFFF);
  static const ayiracAcik = Color(0xFFE8ECF4);

  static const arkaplanKoyu = Color(0xFF12141F);
  static const kartKoyu = Color(0xFF1C1F2E);
  static const ayiracKoyu = Color(0xFF2A2E42);

  static const metinBirincilAcik = Color(0xFF1A1D2E);
  static const metinIkincilAcik = Color(0xFF6B7280);
  static const metinIpucuAcik = Color(0xFF9CA3AF);

  static const metinBirincilKoyu = Color(0xFFEDEEF5);
  static const metinIkincilKoyu = Color(0xFF9BA1B5);

  /// Durum rengine göre %12 opaklıkta zemin rengi üretir (badge/chip için).
  static Color zemin(Color renk, {double opaklik = 0.12}) =>
      renk.withValues(alpha: opaklik);

  static Color kart(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark ? kartKoyu : kartAcik;

  static Color arkaplan(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark ? arkaplanKoyu : arkaplanAcik;

  static Color ayirac(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark ? ayiracKoyu : ayiracAcik;

  static Color metinBirincil(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark
          ? metinBirincilKoyu
          : metinBirincilAcik;

  static Color metinIkincil(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark
          ? metinIkincilKoyu
          : metinIkincilAcik;
}

/// 4pt tabanlı boşluk skalası. Ekranlarda EdgeInsets.all(16) yerine
/// TsBosluk.md gibi anlamlı isimler kullanılır.
class TsBosluk {
  TsBosluk._();
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const xxxl = 32.0;
}

class TsRadius {
  TsRadius._();
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const pill = 999.0;
}

class TsGolge {
  TsGolge._();

  static List<BoxShadow> yumusak = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.05),
      blurRadius: 10,
      offset: const Offset(0, 3),
    ),
  ];

  static List<BoxShadow> renkli(Color renk) => [
        BoxShadow(
          color: renk.withValues(alpha: 0.28),
          blurRadius: 14,
          offset: const Offset(0, 5),
        ),
      ];
}

/// Tipografi skalası — Poppins font ailesiyle tutarlı ağırlık/boyut seti.
class TsMetin {
  TsMetin._();

  static const baslikXL = TextStyle(
      fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.4);
  static const baslikL = TextStyle(
      fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.3);
  static const baslikM = TextStyle(
      fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.2);
  static const govde = TextStyle(fontSize: 14, fontWeight: FontWeight.w400);
  static const govdeVurgu =
      TextStyle(fontSize: 14, fontWeight: FontWeight.w600);
  static const kucuk = TextStyle(fontSize: 12, fontWeight: FontWeight.w400);
  static const kucukVurgu =
      TextStyle(fontSize: 12, fontWeight: FontWeight.w700);
  static const etiket = TextStyle(
      fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.2);
}
