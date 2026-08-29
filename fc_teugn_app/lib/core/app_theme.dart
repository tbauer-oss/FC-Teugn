import 'package:flutter/material.dart';

abstract final class AppColors {
  static const black = Color(0xFF171918);
  static const charcoal = Color(0xFF292C2A);
  static const yellow = Color(0xFFFFE600);
  static const yellowSoft = Color(0xFFFFF7B2);
  static const gold = Color(0xFF756300);
  static const yellowDark = gold;
  static const success = Color(0xFF16815A);

  // Kompatibilität für bestehende, bewusst helle Markenflächen.
  static const navy = black;
  static const blue = gold;
  static const teal = success;
  static const orange = gold;
  static const background = Color(0xFFF7F7F3);
  static const line = Color(0xFFE3E1D6);
  static const muted = Color(0xFF686B67);
}

@immutable
class AppSurfaceColors extends ThemeExtension<AppSurfaceColors> {
  const AppSurfaceColors({
    required this.canvas,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceMuted,
    required this.text,
    required this.textMuted,
    required this.outline,
    required this.shadow,
    required this.brandSoft,
    required this.successSoft,
    required this.dangerSoft,
  });

  final Color canvas;
  final Color surface;
  final Color surfaceRaised;
  final Color surfaceMuted;
  final Color text;
  final Color textMuted;
  final Color outline;
  final Color shadow;
  final Color brandSoft;
  final Color successSoft;
  final Color dangerSoft;

  static const light = AppSurfaceColors(
    canvas: Color(0xFFF5F5F0),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF0F0EA),
    text: AppColors.black,
    textMuted: Color(0xFF61645F),
    outline: Color(0xFFDEDED4),
    shadow: Color(0x140E1511),
    brandSoft: AppColors.yellowSoft,
    successSoft: Color(0xFFE3F3EC),
    dangerSoft: Color(0xFFFFE9E7),
  );

  static const dark = AppSurfaceColors(
    canvas: Color(0xFF0F1210),
    surface: Color(0xFF181C19),
    surfaceRaised: Color(0xFF202521),
    surfaceMuted: Color(0xFF262C27),
    text: Color(0xFFF5F7F3),
    textMuted: Color(0xFFB6BEB7),
    outline: Color(0xFF3A423B),
    shadow: Color(0x99000000),
    brandSoft: Color(0xFF3B3600),
    successSoft: Color(0xFF123B2D),
    dangerSoft: Color(0xFF49211F),
  );

  @override
  AppSurfaceColors copyWith({
    Color? canvas,
    Color? surface,
    Color? surfaceRaised,
    Color? surfaceMuted,
    Color? text,
    Color? textMuted,
    Color? outline,
    Color? shadow,
    Color? brandSoft,
    Color? successSoft,
    Color? dangerSoft,
  }) =>
      AppSurfaceColors(
        canvas: canvas ?? this.canvas,
        surface: surface ?? this.surface,
        surfaceRaised: surfaceRaised ?? this.surfaceRaised,
        surfaceMuted: surfaceMuted ?? this.surfaceMuted,
        text: text ?? this.text,
        textMuted: textMuted ?? this.textMuted,
        outline: outline ?? this.outline,
        shadow: shadow ?? this.shadow,
        brandSoft: brandSoft ?? this.brandSoft,
        successSoft: successSoft ?? this.successSoft,
        dangerSoft: dangerSoft ?? this.dangerSoft,
      );

  @override
  AppSurfaceColors lerp(
    covariant ThemeExtension<AppSurfaceColors>? other,
    double t,
  ) {
    if (other is! AppSurfaceColors) return this;
    return AppSurfaceColors(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      text: Color.lerp(text, other.text, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      outline: Color.lerp(outline, other.outline, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      brandSoft: Color.lerp(brandSoft, other.brandSoft, t)!,
      successSoft: Color.lerp(successSoft, other.successSoft, t)!,
      dangerSoft: Color.lerp(dangerSoft, other.dangerSoft, t)!,
    );
  }
}

extension AppThemeContext on BuildContext {
  AppSurfaceColors get appColors =>
      Theme.of(this).extension<AppSurfaceColors>() ?? AppSurfaceColors.light;

  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;

  Color get appSuccess =>
      isDarkMode ? const Color(0xFF72E2B4) : AppColors.success;

  Color get appWarning => isDarkMode ? const Color(0xFFFFE875) : AppColors.gold;

  Color get appInfo =>
      isDarkMode ? const Color(0xFF91CBFF) : const Color(0xFF17628C);

  Color get appDanger =>
      isDarkMode ? const Color(0xFFFF9A92) : Theme.of(this).colorScheme.error;
}

ThemeData buildAppTheme({Brightness brightness = Brightness.light}) {
  final dark = brightness == Brightness.dark;
  final surfaces = dark ? AppSurfaceColors.dark : AppSurfaceColors.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.yellow,
    brightness: brightness,
    primary: dark ? const Color(0xFFFFE866) : AppColors.gold,
    onPrimary: AppColors.black,
    primaryContainer: surfaces.brandSoft,
    onPrimaryContainer: surfaces.text,
    secondary: dark ? const Color(0xFFF2F5F0) : AppColors.black,
    onSecondary: dark ? AppColors.black : Colors.white,
    surface: surfaces.surface,
    onSurface: surfaces.text,
    surfaceContainerHighest: surfaces.surfaceMuted,
    outline: surfaces.outline,
    outlineVariant: surfaces.outline,
  );
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide(color: surfaces.outline),
  );
  final baseTextTheme = ThemeData(
    brightness: brightness,
    fontFamily: 'Arial',
  ).textTheme;
  final textTheme = baseTextTheme.copyWith(
    displaySmall: baseTextTheme.displaySmall?.copyWith(
      fontSize: 36,
      height: 1.12,
      fontWeight: FontWeight.w900,
      letterSpacing: -1.1,
      color: surfaces.text,
    ),
    headlineMedium: baseTextTheme.headlineMedium?.copyWith(
      fontSize: 28,
      height: 1.16,
      fontWeight: FontWeight.w900,
      letterSpacing: -0.7,
      color: surfaces.text,
    ),
    headlineSmall: baseTextTheme.headlineSmall?.copyWith(
      fontSize: 22,
      height: 1.18,
      fontWeight: FontWeight.w900,
      letterSpacing: -0.3,
      color: surfaces.text,
    ),
    titleLarge: baseTextTheme.titleLarge?.copyWith(
      fontSize: 18,
      fontWeight: FontWeight.w900,
      color: surfaces.text,
    ),
    titleMedium: baseTextTheme.titleMedium?.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.w800,
      color: surfaces.text,
    ),
    bodyLarge: baseTextTheme.bodyLarge?.copyWith(
      fontSize: 16,
      height: 1.48,
      color: surfaces.text,
    ),
    bodyMedium: baseTextTheme.bodyMedium?.copyWith(
      fontSize: 14,
      height: 1.42,
      color: surfaces.textMuted,
    ),
    bodySmall: baseTextTheme.bodySmall?.copyWith(color: surfaces.textMuted),
    labelLarge: baseTextTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w800,
    ),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    extensions: [surfaces],
    scaffoldBackgroundColor: surfaces.canvas,
    fontFamily: 'Arial',
    textTheme: textTheme,
    cardTheme: CardThemeData(
      color: surfaces.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shadowColor: surfaces.shadow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: surfaces.outline),
      ),
    ),
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      backgroundColor: surfaces.surface,
      foregroundColor: surfaces.text,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        color: surfaces.text,
        fontSize: 20,
        fontWeight: FontWeight.w900,
        letterSpacing: -.25,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surfaces.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surfaces.surface,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: surfaces.surface,
      showDragHandle: true,
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      elevation: 0,
      backgroundColor: surfaces.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: dark ? const Color(0xFF4B4500) : AppColors.yellowSoft,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? surfaces.text
              : surfaces.textMuted,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          color: states.contains(WidgetState.selected)
              ? surfaces.text
              : surfaces.textMuted,
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w900
              : FontWeight.w700,
        ),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: surfaces.surface,
      indicatorColor: dark ? const Color(0xFF4B4500) : AppColors.yellowSoft,
      selectedIconTheme: IconThemeData(color: surfaces.text),
      unselectedIconTheme: IconThemeData(color: surfaces.textMuted),
      selectedLabelTextStyle: TextStyle(
        color: surfaces.text,
        fontWeight: FontWeight.w900,
      ),
      unselectedLabelTextStyle: TextStyle(color: surfaces.textMuted),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaces.surfaceRaised,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      errorBorder: border.copyWith(
        borderSide: BorderSide(color: scheme.error),
      ),
      helperStyle: TextStyle(color: surfaces.textMuted),
      hintStyle: TextStyle(color: surfaces.textMuted),
      labelStyle: TextStyle(color: surfaces.textMuted),
      helperMaxLines: 3,
      errorMaxLines: 3,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.yellow,
        foregroundColor: AppColors.black,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: dark ? const Color(0xFFFFE866) : AppColors.gold,
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: surfaces.text,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        side: BorderSide(color: surfaces.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: surfaces.surfaceMuted,
      selectedColor: surfaces.brandSoft,
      disabledColor: surfaces.surfaceMuted,
      side: BorderSide(color: surfaces.outline),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      labelStyle: TextStyle(
        color: dark ? surfaces.text : AppColors.black,
        fontWeight: FontWeight.w800,
        fontSize: 12,
      ),
      secondaryLabelStyle: TextStyle(
        color: dark ? surfaces.text : AppColors.black,
        fontWeight: FontWeight.w900,
        fontSize: 12,
      ),
      iconTheme: IconThemeData(color: scheme.primary),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: dark ? surfaces.text : AppColors.black,
      unselectedLabelColor: surfaces.textMuted,
      indicatorColor: dark ? const Color(0xFFFFE866) : AppColors.gold,
      dividerColor: surfaces.outline,
      labelStyle: const TextStyle(fontWeight: FontWeight.w900),
      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
    dividerTheme: DividerThemeData(color: surfaces.outline, thickness: 1),
    popupMenuTheme: PopupMenuThemeData(
      color: surfaces.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xFF303630) : AppColors.charcoal,
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
    ),
  );
}
