// lib/uygulama/tema/koyu_tema.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'acik_tema.dart';

ThemeData koyuTema() {
  const primary = AppRenkler.primary;
  const darkBg    = Color(0xFF0D0F1A);
  const darkCard  = Color(0xFF151729);
  const darkSurf  = Color(0xFF1C1F35);
  const darkDiv   = Color(0xFF2A2D42);
  const darkText  = Color(0xFFE8EAFF);
  const darkTextS = Color(0xFF8B90B8);

  final cs = ColorScheme.fromSeed(
    seedColor: primary,
    brightness: Brightness.dark,
    primary: primary,
    secondary: AppRenkler.secondary,
    surface: darkCard,
    error: AppRenkler.error,
    // ✅ listTileTheme parametresi KALDIRILDI (burada olmamalı)
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: cs,
    scaffoldBackgroundColor: darkBg,
    fontFamily: 'Poppins',

    // ✅ ListTileTheme BURAYA taşındı
    listTileTheme: const ListTileThemeData(
      iconColor: Color(0xFF4361EE),
      textColor: Color(0xFFE8EAFF),
    ),

    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 1,
      backgroundColor: darkCard,
      foregroundColor: darkText,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      titleTextStyle: const TextStyle(
        fontFamily: 'Poppins', fontSize: 17,
        fontWeight: FontWeight.w600, color: darkText),
      iconTheme: const IconThemeData(color: darkText, size: 22),
      actionsIconTheme: IconThemeData(color: primary, size: 22),
    ),

    cardTheme: CardThemeData(
      elevation: 0,
      color: darkCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: darkDiv, width: 1),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: darkSurf,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: darkDiv),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: darkDiv),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primary, width: 2),
      ),
      labelStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: darkTextS),
      hintStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: darkTextS),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        foregroundColor: Colors.white,  // yazı her zaman beyaz
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          overflow: TextOverflow.ellipsis,
        ),
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 0,
      ),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
        minimumSize: const Size(double.infinity, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),

    chipTheme: ChipThemeData(
      backgroundColor: darkSurf,
      selectedColor: const Color(0x334361EE),
      labelStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: darkText),
      side: const BorderSide(color: darkDiv),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),

    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: darkSurf,
      contentTextStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: darkText),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: darkCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 17, fontWeight: FontWeight.w700, color: darkText),
      contentTextStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 14, color: darkTextS),
    ),

    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),

    dividerTheme: const DividerThemeData(color: darkDiv, thickness: 1, space: 1),

    textTheme: TextTheme(
      displayLarge:   TextStyle(fontFamily:'Poppins', fontSize:57, fontWeight:FontWeight.w700, color:darkText),
      headlineLarge:  TextStyle(fontFamily:'Poppins', fontSize:28, fontWeight:FontWeight.w700, color:darkText),
      headlineMedium: TextStyle(fontFamily:'Poppins', fontSize:22, fontWeight:FontWeight.w600, color:darkText),
      headlineSmall:  TextStyle(fontFamily:'Poppins', fontSize:18, fontWeight:FontWeight.w600, color:darkText),
      titleLarge:     TextStyle(fontFamily:'Poppins', fontSize:16, fontWeight:FontWeight.w600, color:darkText),
      titleMedium:    TextStyle(fontFamily:'Poppins', fontSize:14, fontWeight:FontWeight.w600, color:darkText),
      titleSmall:     TextStyle(fontFamily:'Poppins', fontSize:13, fontWeight:FontWeight.w500, color:darkText),
      bodyLarge:      TextStyle(fontFamily:'Poppins', fontSize:16, fontWeight:FontWeight.w400, color:darkText),
      bodyMedium:     TextStyle(fontFamily:'Poppins', fontSize:14, fontWeight:FontWeight.w400, color:darkText),
      bodySmall:      TextStyle(fontFamily:'Poppins', fontSize:12, fontWeight:FontWeight.w400, color:darkTextS),
      labelLarge:     TextStyle(fontFamily:'Poppins', fontSize:14, fontWeight:FontWeight.w600, color:primary),
      labelMedium:    TextStyle(fontFamily:'Poppins', fontSize:12, fontWeight:FontWeight.w500, color:primary),
      labelSmall:     TextStyle(fontFamily:'Poppins', fontSize:11, fontWeight:FontWeight.w500, color:darkTextS),
    ),

    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: primary,
      foregroundColor: Colors.white,
      elevation: 4,
    ),
  );
}