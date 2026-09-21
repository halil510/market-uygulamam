// lib/cekirdek/sabitler/uygulama_sabitleri.dart
import 'package:flutter/material.dart';

class UygSabitler {
  static const String uygulamaAdi = 'MarketPlus';
  static const String versiyon = '2.3.0';
  static const int dbVersiyon =
      71; // v71: lot_seri(urun_id, aktif) index — FEFO sorgusu full-scan yapıyordu (FAZ 5, 2026-09-21)
  static const int maxHataliGiris = 5;
  static const int kilitSureSaniye = 30;
  static const int cacheEnUzunSure = 5;
  static const int sayfaBasinaKayit = 50;
  static const String varsayilanPara = 'TRY';
  static const String varsayilanKdv = '18';
  static const String varsayilanBirim = 'Adet';
  static const String adminKullanici = 'admin';
  static const List<String> odemeTipleri = [
    'Nakit',
    'Kredi Kartı',
    'Banka',
    'Cari',
    'Havale',
    'QR'
  ];
}

/// Uygulama genelinde tutarlı boşluk değerleri
class AppSpacing {
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 20.0;
  static const double xxl = 24.0;
  static const double xxxl = 32.0;

  static const EdgeInsets paddingXS = EdgeInsets.all(xs);
  static const EdgeInsets paddingSM = EdgeInsets.all(sm);
  static const EdgeInsets paddingMD = EdgeInsets.all(md);
  static const EdgeInsets paddingLG = EdgeInsets.all(lg);
  static const EdgeInsets paddingXL = EdgeInsets.all(xl);

  static const EdgeInsets paddingHSM = EdgeInsets.symmetric(horizontal: sm);
  static const EdgeInsets paddingHMD = EdgeInsets.symmetric(horizontal: md);
  static const EdgeInsets paddingHLG = EdgeInsets.symmetric(horizontal: lg);
  static const EdgeInsets paddingVSM = EdgeInsets.symmetric(vertical: sm);
  static const EdgeInsets paddingVMD = EdgeInsets.symmetric(vertical: md);
  static const EdgeInsets paddingPage = EdgeInsets.all(lg);

  static const EdgeInsets paddingCardContent =
      EdgeInsets.symmetric(horizontal: lg, vertical: md);
}

/// Uygulama genelinde tutarlı border radius değerleri
class AppRadius {
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 20.0;
  static const double full = 999.0;

  static const BorderRadius borderXS = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius borderSM = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius borderMD = BorderRadius.all(Radius.circular(md));
  static const BorderRadius borderLG = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius borderXL = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius borderFull =
      BorderRadius.all(Radius.circular(full));

  static const BorderRadius cardRadius = borderLG;
  static const BorderRadius buttonRadius = borderMD;
  static const BorderRadius inputRadius = borderMD;
  static const BorderRadius chipRadius = borderFull;
}

/// Uygulama genelinde tutarlı metin stilleri
class AppTextStyles {
  static const TextStyle h1 =
      TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1.2);
  static const TextStyle h2 =
      TextStyle(fontSize: 20, fontWeight: FontWeight.w700, height: 1.3);
  static const TextStyle h3 =
      TextStyle(fontSize: 16, fontWeight: FontWeight.w700, height: 1.3);
  static const TextStyle h4 =
      TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.4);
  static const TextStyle body =
      TextStyle(fontSize: 14, fontWeight: FontWeight.normal, height: 1.5);
  static const TextStyle bodySmall =
      TextStyle(fontSize: 12, fontWeight: FontWeight.normal, height: 1.4);
  static const TextStyle caption =
      TextStyle(fontSize: 11, fontWeight: FontWeight.w400, height: 1.3);
  static const TextStyle label =
      TextStyle(fontSize: 13, fontWeight: FontWeight.w500, height: 1.3);
  static const TextStyle price =
      TextStyle(fontSize: 18, fontWeight: FontWeight.w800, height: 1.2);
  static const TextStyle priceLarge =
      TextStyle(fontSize: 24, fontWeight: FontWeight.w900, height: 1.1);
  static const TextStyle button =
      TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.3);
  static const TextStyle overline = TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.2,
      height: 1.2);
}
