// lib/uygulama/tema/uygulama_temasi.dart
import 'package:flutter/material.dart';
import 'acik_tema.dart';
import 'koyu_tema.dart';

export 'acik_tema.dart' show AppRenkler;

class UygulamaTemasi {
  static ThemeData getTema(String adi) {
    switch (adi) {
      case 'dark':  return koyuTema();
      case 'blue':  return _mavi();
      case 'green': return _yesil();
      case 'ocean': return _okyanus();
      default:      return acikTema();
    }
  }

  static ThemeData _mavi() => acikTema().copyWith(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF0077B6),
      primary: const Color(0xFF0077B6),
    ),
  );

  static ThemeData _yesil() => acikTema().copyWith(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF2DC653),
      primary: const Color(0xFF2DC653),
    ),
  );

  static ThemeData _okyanus() => acikTema().copyWith(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF006D77),
      primary: const Color(0xFF006D77),
    ),
  );
}

/// BuildContext yardımcıları
extension ThemeColors on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  Color get scaffoldBg => isDark
      ? const Color(0xFF0D0F1A)
      : const Color(0xFFF8F9FE);

  Color get cardBg => isDark
      ? const Color(0xFF151729)
      : Colors.white;

  Color get dividerColor => isDark
      ? Colors.white12
      : const Color(0xFFE8ECF4);

  Color get textPrimary => isDark
      ? const Color(0xFFE8EAFF)
      : const Color(0xFF1A1D2E);

  Color get textSecondary => isDark
      ? const Color(0xFF8B90B8)
      : const Color(0xFF6B7280);

  Color get textHint => isDark
      ? const Color(0xFF555B8A)
      : const Color(0xFF9CA3AF);

  Color get inputFill => isDark
      ? const Color(0xFF1C1F35)
      : const Color(0xFFF8F9FE);

  Color get borderColor => isDark
      ? const Color(0xFF2A2D42)
      : const Color(0xFFE8ECF4);

  Color get shimmerBase => isDark
      ? const Color(0xFF1C1F35)
      : const Color(0xFFEEF0F6);

  Color get shimmerHighlight => isDark
      ? const Color(0xFF252840)
      : const Color(0xFFF8F9FE);

  ThemeData get tema => Theme.of(this);
  ColorScheme get cs  => Theme.of(this).colorScheme;
  Color get primary   => cs.primary;
}
