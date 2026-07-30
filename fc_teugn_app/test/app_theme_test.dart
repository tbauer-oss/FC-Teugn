import 'package:fc_teugn_app/core/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
