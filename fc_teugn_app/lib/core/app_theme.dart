import 'package:flutter/material.dart';

abstract final class AppColors {
  static const black = Color(0xFF171918);
  static const charcoal = Color(0xFF292C2A);
  static const yellow = Color(0xFFFFE600);
  static const yellowDark = Color(0xFF9B8300);
  static const success = Color(0xFF16815A);

  // Bestehende semantische Namen bleiben kompatibel, tragen aber die Vereins-CI.
  static const navy = black;
  static const blue = yellowDark;
  static const teal = success;
  static const orange = yellow;
  static const background = Color(0xFFF7F7F3);
  static const line = Color(0xFFE3E1D6);
  static const muted = Color(0xFF686B67);
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.yellow,
    brightness: Brightness.light,
    primary: AppColors.yellow,
    onPrimary: AppColors.black,
    secondary: AppColors.black,
    onSecondary: Colors.white,
    surface: Colors.white,
  );

  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: const BorderSide(color: AppColors.line),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    fontFamily: 'Arial',
    textTheme: const TextTheme(
      displaySmall: TextStyle(
        fontSize: 36,
        height: 1.12,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.1,
        color: AppColors.navy,
      ),
      headlineMedium: TextStyle(
        fontSize: 28,
        height: 1.18,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.6,
        color: AppColors.navy,
      ),
      headlineSmall: TextStyle(
        fontSize: 22,
        height: 1.2,
        fontWeight: FontWeight.w800,
        color: AppColors.navy,
      ),
      titleLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppColors.navy,
      ),
      bodyLarge: TextStyle(fontSize: 16, height: 1.5, color: AppColors.navy),
      bodyMedium: TextStyle(fontSize: 14, height: 1.45, color: AppColors.muted),
      labelLarge: TextStyle(fontWeight: FontWeight.w700),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.line),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: AppColors.yellowDark, width: 2),
      ),
      errorBorder: border.copyWith(
        borderSide: BorderSide(color: scheme.error),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.yellow,
        foregroundColor: AppColors.black,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        side: const BorderSide(color: AppColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.background,
      side: const BorderSide(color: AppColors.line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.line, thickness: 1),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}
