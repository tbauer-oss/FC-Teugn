import 'dart:io';

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
    expect(theme.iconTheme.color, colors.text);
    expect(theme.disabledColor, isNot(colors.outline));
    expect(
      _contrast(colors.text, colors.brandSoft),
      greaterThanOrEqualTo(7),
    );
    expect(
      _contrast(theme.disabledColor, colors.surface),
      greaterThanOrEqualTo(4.5),
    );
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      '${brightness.name} status colors meet WCAG contrast on app surfaces',
      (tester) async {
        late List<Color> accents;
        late AppSurfaceColors surfaces;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(brightness: brightness),
            home: Builder(
              builder: (context) {
                surfaces = context.appColors;
                accents = [
                  context.appSuccess,
                  context.appWarning,
                  context.appInfo,
                  context.appDanger,
                ];
                return const SizedBox.shrink();
              },
            ),
          ),
        );

        for (final accent in accents) {
          expect(
            _contrast(accent, surfaces.surface),
            greaterThanOrEqualTo(4.5),
            reason: '$accent must stay readable on ${surfaces.surface}',
          );
          expect(
            _contrast(accent, surfaces.surfaceRaised),
            greaterThanOrEqualTo(4.5),
            reason: '$accent must stay readable on ${surfaces.surfaceRaised}',
          );
        }
      },
    );
  }

  test('feature code does not reintroduce legacy non-adaptive color aliases',
      () {
    const forbidden = <String>[
      'AppColors.muted',
      'AppColors.background',
      'AppColors.line',
      'AppColors.teal',
      'AppColors.success',
      'AppColors.orange',
    ];
    final violations = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      if (file.path.endsWith('core${Platform.pathSeparator}app_theme.dart')) {
        continue;
      }
      final source = file.readAsStringSync();
      for (final token in forbidden) {
        if (source.contains(token)) violations.add('${file.path}: $token');
      }
      if (RegExp(
        r'(?:color|foregroundColor)\s*:\s*AppColors\.gold',
      ).hasMatch(source)) {
        violations.add('${file.path}: fixed gold foreground');
      }
    }

    expect(violations, isEmpty);
  });

  test('feature surfaces do not pair dark-mode content with light backgrounds',
      () {
    final violations = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final normalized = entity.path.replaceAll('\\', '/');
      if (normalized.endsWith('/core/app_theme.dart') ||
          normalized.endsWith(
              '/features/players/widgets/digital_signature_capture.dart') ||
          normalized.endsWith('/features/matches/bfv_browser_page.dart')) {
        continue;
      }
      final lines = entity.readAsLinesSync();
      for (var index = 0; index < lines.length; index++) {
        final line = lines[index];
        final before =
            lines.sublist(index > 3 ? index - 3 : 0, index + 1).join(' ');
        final after = lines
            .sublist(
                index, index + 13 < lines.length ? index + 13 : lines.length)
            .join(' ');
        final isDirectColorProperty = RegExp(r'^\s*color\s*:').hasMatch(line);
        final isBackgroundProperty =
            RegExp(r'^\s*backgroundColor\s*:').hasMatch(line);
        final isSurfaceContext = isBackgroundProperty ||
            (isDirectColorProperty &&
                (before.contains('BoxDecoration(') ||
                    before.contains('Material(') ||
                    before.contains('Card(') ||
                    before.contains('CircleAvatar(')));
        final hardLight = RegExp(
          r'^\s*(?:backgroundColor|color)\s*:\s*(?:const\s+)?(?:Colors\.white\s*,|Color\(0xFF[FE][0-9A-Fa-f]{5}\)\s*,)',
        ).hasMatch(line);
        if (isSurfaceContext &&
            hardLight &&
            !after.contains('ClubLogo(') &&
            !after.contains('AppColors.black')) {
          violations.add('${entity.path}:${index + 1}: hard light surface');
        }

        final fixedBrandSurface = RegExp(
          r'^\s*(?:backgroundColor|color)\s*:\s*AppColors\.(?:yellow|yellowSoft)\s*,',
        ).hasMatch(line);
        final progressTrack = before.contains('LinearProgressIndicator(');
        if (isSurfaceContext &&
            fixedBrandSurface &&
            !progressTrack &&
            !before.contains('AppColors.black') &&
            !after.contains('AppColors.black')) {
          violations.add(
            '${entity.path}:${index + 1}: bright brand surface without dark foreground',
          );
        }
      }
    }

    expect(violations, isEmpty);
  });

  test('fixed app chrome exposes all three theme choices', () {
    final source = File('lib/features/shell/app_shell.dart').readAsStringSync();
    expect(source, contains("ValueKey('fixed-header-theme-switch')"));
    expect(source, contains('AppThemePreference.values'));
    expect(source, contains('AppThemePreference.system'));
    expect(source, contains('AppThemePreference.light'));
    expect(source, contains('AppThemePreference.dark'));
  });

  test('system appearance remains the privacy-safe default preference', () {
    expect(AppThemePreference.system.themeMode, ThemeMode.system);
    expect(AppThemePreference.light.themeMode, ThemeMode.light);
    expect(AppThemePreference.dark.themeMode, ThemeMode.dark);
  });
}
