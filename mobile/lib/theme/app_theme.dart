import 'package:flutter/material.dart';

class AppColors {
  const AppColors._();

  static const ink = Color(0xFF080812);
  static const panel = Color(0xFF12101D);
  static const panelSoft = Color(0xFF1B1729);
  static const line = Color(0xFF393047);
  static const text = Color(0xFFF4F7F1);
  static const muted = Color(0xFFA4AEA3);
  static const lime = Color(0xFFF1A0FF);
  static const mint = Color(0xFF73D8FF);
  static const coral = Color(0xFFFF5D83);
}

class AppTheme {
  const AppTheme._();

  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.lime,
      brightness: Brightness.dark,
      surface: AppColors.panel,
    );
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'sans-serif',
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.ink,
      colorScheme: scheme.copyWith(
        primary: AppColors.lime,
        secondary: AppColors.mint,
        surface: AppColors.panel,
        outline: AppColors.line,
        onPrimary: AppColors.ink,
      ),
      textTheme: const TextTheme(
        displaySmall: TextStyle(
          fontFamily: 'sans-serif-condensed',
          fontWeight: FontWeight.w900,
          letterSpacing: -1.5,
          height: .95,
        ),
        headlineSmall: TextStyle(
          fontFamily: 'sans-serif-condensed',
          fontWeight: FontWeight.w800,
          letterSpacing: -.6,
        ),
        titleLarge: TextStyle(
          fontFamily: 'sans-serif-condensed',
          fontWeight: FontWeight.w800,
          letterSpacing: -.3,
        ),
        titleMedium: TextStyle(
          fontFamily: 'sans-serif-medium',
          fontWeight: FontWeight.w700,
          letterSpacing: -.15,
        ),
        bodyMedium: TextStyle(height: 1.35, letterSpacing: -.05),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.panelSoft,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.lime),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.lime,
          foregroundColor: AppColors.ink,
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          backgroundColor: const Color(0x661B1128),
          foregroundColor: AppColors.text,
          side: const BorderSide(color: Color(0x30FFFFFF)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: AppColors.text,
          fontFamily: 'sans-serif-condensed',
          fontSize: 23,
          fontWeight: FontWeight.w900,
          letterSpacing: -.3,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.panel,
        modalBackgroundColor: AppColors.panel,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
    );
  }
}
