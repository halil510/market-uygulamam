// lib/uygulama/tema/masaustu_tema.dart
//
// MASAÜSTÜ GÖRÜNÜM İYİLEŞTİRMESİ (yalnızca Windows/Linux/macOS, açık tema)
//
// Telefon için seçilmiş çok açık zemin (#F8F9FE), silik kenarlık ve soluk gri
// yazı, büyük monitörde "cansız / basit" görünüyordu. Bu dosya, SADECE
// masaüstünde daha koyu bir zemin, belirgin kenarlık ve kontrastlı yazı
// paleti uygular. Mobilde [masaustuMu] false olduğundan hiçbir şey değişmez.
import 'dart:io' show Platform;
import 'package:flutter/material.dart';

final bool masaustuMu =
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;

class MasaustuPalet {
  MasaustuPalet._();
  static const zemin = Color(0xFFE6EBF3); // sayfa zemini (beyaz kartlar öne çıkar)
  static const kenar = Color(0xFFBCC6D6); // kart / giriş kenarlığı
  static const ayirac = Color(0xFFCFD7E4); // ince çizgiler
  static const metin = Color(0xFF0F172A); // ana yazı
  static const metin2 = Color(0xFF475569); // ikincil yazı
  static const ipucu = Color(0xFF64748B); // ipucu / pasif yazı
}

/// Açık temayı masaüstü için güçlendirir; koyu tema ve mobil dokunulmaz.
ThemeData masaustuIyilestir(ThemeData t) {
  if (!masaustuMu || t.brightness == Brightness.dark) return t;
  OutlineInputBorder sinir(Color renk, [double kalin = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: renk, width: kalin),
      );
  return t.copyWith(
    scaffoldBackgroundColor: MasaustuPalet.zemin,
    dividerColor: MasaustuPalet.ayirac,
    dividerTheme: const DividerThemeData(
        color: MasaustuPalet.ayirac, thickness: 1, space: 1),
    cardTheme: t.cardTheme.copyWith(
      elevation: 1,
      shadowColor: const Color(0x33000000),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: MasaustuPalet.kenar),
      ),
    ),
    inputDecorationTheme: t.inputDecorationTheme.copyWith(
      fillColor: Colors.white,
      enabledBorder: sinir(MasaustuPalet.kenar),
    ),
  );
}
