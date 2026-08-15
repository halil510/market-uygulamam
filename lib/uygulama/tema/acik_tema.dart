// lib/uygulama/tema/acik_tema.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─── Renk Paleti ──────────────────────────────────────────────────────────
class AppRenkler {
  static const primary    = Color(0xFF4361EE);
  static const secondary  = Color(0xFF3A0CA3);
  static const accent     = Color(0xFF7209B7);
  static const success    = Color(0xFF2ECC71);
  static const warning    = Color(0xFFF39C12);
  static const error      = Color(0xFFE74C3C);
  static const info       = Color(0xFF3498DB);
  static const surface    = Color(0xFFFFFFFF);
  static const background = Color(0xFFF8F9FE);
  static const cardBg     = Color(0xFFFFFFFF);
  static const divider    = Color(0xFFE8ECF4);
  static const textPrimary   = Color(0xFF1A1D2E);
  static const textSecondary = Color(0xFF6B7280);
  static const textHint      = Color(0xFF9CA3AF);
}

ThemeData acikTema() {
  const primary = AppRenkler.primary;
  final cs = ColorScheme.fromSeed(
    seedColor: primary,
    brightness: Brightness.light,
    primary: primary,
    secondary: AppRenkler.secondary,
    surface: AppRenkler.surface,
    error: AppRenkler.error,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: cs,
    scaffoldBackgroundColor: AppRenkler.background,
    fontFamily: 'Poppins',

    // ── AppBar ────────────────────────────────────────────────────────────
    iconTheme: const IconThemeData(
      color: AppRenkler.textPrimary,
      size: 24,
    ),

    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 1,
      backgroundColor: AppRenkler.surface,
      foregroundColor: AppRenkler.textPrimary,
      iconTheme: const IconThemeData(color: AppRenkler.textPrimary, size: 24),
      actionsIconTheme: const IconThemeData(color: AppRenkler.primary, size: 24),
      centerTitle: false,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
      titleTextStyle: const TextStyle(
        fontFamily: 'Poppins',
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: AppRenkler.textPrimary,
        letterSpacing: -0.3,
      ),
      shadowColor: Colors.black.withAlpha(20),
    ),

    // ── Kart ──────────────────────────────────────────────────────────────
    cardTheme: CardThemeData(
      elevation: 0,
      color: AppRenkler.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppRenkler.divider, width: 1),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
    ),

    // ── Metin Girişi ──────────────────────────────────────────────────────
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppRenkler.background,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppRenkler.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppRenkler.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppRenkler.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppRenkler.error, width: 2),
      ),
      labelStyle: const TextStyle(
        fontFamily: 'Poppins', fontSize: 13,
        color: AppRenkler.textSecondary, fontWeight: FontWeight.w500),
      hintStyle: const TextStyle(
        fontFamily: 'Poppins', fontSize: 13, color: AppRenkler.textHint),
      prefixIconColor: AppRenkler.textSecondary,
      suffixIconColor: AppRenkler.textSecondary,
    ),

    // ── Butonlar ──────────────────────────────────────────────────────────
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
        shadowColor: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
        minimumSize: const Size(double.infinity, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(
          fontFamily: 'Poppins', fontSize: 14,
          fontWeight: FontWeight.w600, letterSpacing: 0.3),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primary,
        side: const BorderSide(color: primary),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(
          fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primary,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(
          fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),

    // ── Chip ──────────────────────────────────────────────────────────────
    chipTheme: ChipThemeData(
      backgroundColor: AppRenkler.background,
      selectedColor: const Color(0x1A4361EE),
      labelStyle: const TextStyle(
        fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w500),
      side: const BorderSide(color: AppRenkler.divider),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    ),

    // ── Snackbar ──────────────────────────────────────────────────────────
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppRenkler.textPrimary,
      contentTextStyle: const TextStyle(
        fontFamily: 'Poppins', fontSize: 13,
        color: Colors.white, fontWeight: FontWeight.w500),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 4,
    ),

    // ── Dialog ────────────────────────────────────────────────────────────
    dialogTheme: DialogThemeData(
      backgroundColor: AppRenkler.surface,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: const TextStyle(
        fontFamily: 'Poppins', fontSize: 17,
        fontWeight: FontWeight.w700, color: AppRenkler.textPrimary),
      contentTextStyle: const TextStyle(
        fontFamily: 'Poppins', fontSize: 14, color: AppRenkler.textSecondary),
    ),

    // ── BottomSheet ───────────────────────────────────────────────────────
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppRenkler.surface,
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),

    // ── NavigationBar ─────────────────────────────────────────────────────
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppRenkler.surface,
      elevation: 0,
      indicatorColor: const Color(0x1A4361EE),
      indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
        color: states.contains(WidgetState.selected)
            ? AppRenkler.primary
            : AppRenkler.textSecondary,
        size: 24,
        opticalSize: 24,
      )),
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
        fontFamily: 'Poppins',
        fontSize: 11,
        fontWeight: states.contains(WidgetState.selected)
            ? FontWeight.w700 : FontWeight.w500,
        color: states.contains(WidgetState.selected)
            ? AppRenkler.primary : AppRenkler.textSecondary,
      )),
    ),

    // ── Drawer ────────────────────────────────────────────────────────────
    drawerTheme: const DrawerThemeData(
      backgroundColor: AppRenkler.surface,
      elevation: 16,
    ),

    // ── ListTile ──────────────────────────────────────────────────────────
    listTileTheme: const ListTileThemeData(
      iconColor: AppRenkler.primary,
      textColor: AppRenkler.textPrimary,
      titleTextStyle: TextStyle(
        fontFamily: 'Poppins', fontSize: 14,
        fontWeight: FontWeight.w500, color: AppRenkler.textPrimary),
      subtitleTextStyle: TextStyle(
        fontFamily: 'Poppins', fontSize: 12, color: AppRenkler.textSecondary),
    ),

    // ── Divider ───────────────────────────────────────────────────────────
    dividerTheme: const DividerThemeData(
      color: AppRenkler.divider, thickness: 1, space: 1),

    // ── Metin Stilleri ────────────────────────────────────────────────────
    textTheme: const TextTheme(
      displayLarge:  TextStyle(fontFamily:'Poppins', fontSize:57, fontWeight:FontWeight.w700, color:AppRenkler.textPrimary, letterSpacing:-1),
      displayMedium: TextStyle(fontFamily:'Poppins', fontSize:45, fontWeight:FontWeight.w700, color:AppRenkler.textPrimary),
      displaySmall:  TextStyle(fontFamily:'Poppins', fontSize:36, fontWeight:FontWeight.w600, color:AppRenkler.textPrimary),
      headlineLarge: TextStyle(fontFamily:'Poppins', fontSize:28, fontWeight:FontWeight.w700, color:AppRenkler.textPrimary, letterSpacing:-0.5),
      headlineMedium:TextStyle(fontFamily:'Poppins', fontSize:22, fontWeight:FontWeight.w600, color:AppRenkler.textPrimary),
      headlineSmall: TextStyle(fontFamily:'Poppins', fontSize:18, fontWeight:FontWeight.w600, color:AppRenkler.textPrimary),
      titleLarge:    TextStyle(fontFamily:'Poppins', fontSize:16, fontWeight:FontWeight.w600, color:AppRenkler.textPrimary),
      titleMedium:   TextStyle(fontFamily:'Poppins', fontSize:14, fontWeight:FontWeight.w600, color:AppRenkler.textPrimary),
      titleSmall:    TextStyle(fontFamily:'Poppins', fontSize:13, fontWeight:FontWeight.w500, color:AppRenkler.textPrimary),
      bodyLarge:     TextStyle(fontFamily:'Poppins', fontSize:16, fontWeight:FontWeight.w400, color:AppRenkler.textPrimary),
      bodyMedium:    TextStyle(fontFamily:'Poppins', fontSize:14, fontWeight:FontWeight.w400, color:AppRenkler.textPrimary),
      bodySmall:     TextStyle(fontFamily:'Poppins', fontSize:12, fontWeight:FontWeight.w400, color:AppRenkler.textSecondary),
      labelLarge:    TextStyle(fontFamily:'Poppins', fontSize:14, fontWeight:FontWeight.w600, color:AppRenkler.primary),
      labelMedium:   TextStyle(fontFamily:'Poppins', fontSize:12, fontWeight:FontWeight.w500, color:AppRenkler.primary),
      labelSmall:    TextStyle(fontFamily:'Poppins', fontSize:11, fontWeight:FontWeight.w500, color:AppRenkler.textSecondary),
    ),

    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: ZoomPageTransitionsBuilder(),
        TargetPlatform.iOS:     ZoomPageTransitionsBuilder(),
      },
    ),

    // ── FloatingActionButton ──────────────────────────────────────────────
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: primary,
      foregroundColor: Colors.white,
      elevation: 4,
      // shape belirtmiyoruz — normal FAB yuvarlak, extended FAB StadiumBorder (Flutter default)
    ),

    // ── Switch & Checkbox ─────────────────────────────────────────────────
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? primary : AppRenkler.divider),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? primary : Colors.transparent),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
  );
}
