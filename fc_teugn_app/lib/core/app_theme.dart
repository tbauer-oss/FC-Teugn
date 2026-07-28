import 'package:flutter/material.dart';

abstract final class AppColors {
  static const navy = Color(0xFF102A43);
  static const blue = Color(0xFF176B87);
  static const teal = Color(0xFF18A999);
  static const orange = Color(0xFFFFB000);
  static const background = Color(0xFFF4F7F9);
  static const line = Color(0xFFDCE5EA);
  static const muted = Color(0xFF627D8C);
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.blue,
    brightness: Brightness.light,
    primary: AppColors.blue,
    secondary: AppColors.teal,
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
        borderSide: const BorderSide(color: AppColors.blue, width: 2),
      ),
      errorBorder: border.copyWith(
        borderSide: BorderSide(color: scheme.error),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
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
