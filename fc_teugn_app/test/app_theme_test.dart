import 'package:fc_teugn_app/core/app_theme.dart';
import 'package:fc_teugn_app/core/app_theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _contrast(Color first, Color second) {
  final bright =
      first.computeLuminance() > second.computeLuminance() ? first : second;
  final dark = identical(bright, first) ? second : first;
  return (bright.computeLuminance() + .05) / (dark.computeLuminance() + .05);
}

void main() {
  test('bright club yellow is reserved for surfaces, not text on white', () {
    final theme = buildAppTheme();

    expect(theme.colorScheme.primary, AppColors.gold);
    expect(theme.colorScheme.primary, isNot(AppColors.yellow));
    expect(theme.tabBarTheme.labelColor, AppColors.black);
    expect(theme.tabBarTheme.indicatorColor, AppColors.gold);
    expect(theme.tabBarTheme.labelColor, isNot(AppColors.yellow));
    expect(theme.chipTheme.labelStyle?.color, AppColors.black);
    expect(theme.chipTheme.secondaryLabelStyle?.color, AppColors.black);
    expect(theme.chipTheme.selectedColor, AppColors.yellowSoft);
  });

  test('dark mode keeps primary and secondary text clearly readable', () {
    final theme = buildAppTheme(brightness: Brightness.dark);
    final colors = theme.extension<AppSurfaceColors>()!;

    expect(theme.brightness, Brightness.dark);
    expect(_contrast(colors.text, colors.surface), greaterThanOrEqualTo(7));
    expect(
      _contrast(colors.textMuted, colors.surface),
      greaterThanOrEqualTo(4.5),
    );
    expect(theme.navigationBarTheme.backgroundColor, colors.surface);
    expect(theme.cardTheme.color, colors.surface);
  });

  test('system appearance remains the privacy-safe default preference', () {
    expect(AppThemePreference.system.themeMode, ThemeMode.system);
    expect(AppThemePreference.light.themeMode, ThemeMode.light);
    expect(AppThemePreference.dark.themeMode, ThemeMode.dark);
  });
}
