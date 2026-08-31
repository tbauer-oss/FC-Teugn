import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mobile matchday uses full readable labels and compact controls', () {
    final matchday =
        File('lib/features/matches/matchday_page.dart').readAsStringSync();
    final autopilot = File(
      'lib/features/matches/matchday_autopilot_tab.dart',
    ).readAsStringSync();

    expect(matchday, contains("label: 'Aufstellung'"));
    expect(matchday, isNot(contains("label: 'Elf'")));
    expect(matchday, contains('width: 78'));
    expect(matchday, contains('isScrollable: true'));
    expect(
      autopilot,
      contains("ValueKey('autopilot-strategy-selector-mobile')"),
    );
    expect(autopilot, contains('DropdownButtonFormField<AutopilotStrategy>'));
  });

  test('mobile family, performance and approval views expose dense variants',
      () {
    final family = File(
      'lib/features/shared/family_responses.dart',
    ).readAsStringSync();
    final statistics = File(
      'lib/features/statistics/statistics_page.dart',
    ).readAsStringSync();
    final approvals = File(
      'lib/features/trainer/trainer_approvals_page.dart',
    ).readAsStringSync();

    expect(family, contains("ValueKey('family-response-summary-scroll')"));
    expect(family, contains('denseMobileHeader: true'));
    expect(statistics, contains('compact: compact'));
    expect(statistics, contains('Expanded(child: metrics[index])'));
    expect(approvals, contains('denseMobileHeader: true'));
    expect(approvals, contains("'Kind: \$childName'"));
  });

  test('foldables expose the full window to feature-specific two-pane layouts',
      () {
    final app = File('lib/app.dart').readAsStringSync();
    final shell = File('lib/features/shell/app_shell.dart').readAsStringSync();
    final adaptive = File(
      'lib/core/widgets/adaptive_layout.dart',
    ).readAsStringSync();
    final calendar =
        File('lib/features/calendar/calendar_page.dart').readAsStringSync();
    final organization = File(
      'lib/features/organization/organization_page.dart',
    ).readAsStringSync();
    final communications = File(
      'lib/features/communications/communications_page.dart',
    ).readAsStringSync();
    final matchday =
        File('lib/features/matches/matchday_page.dart').readAsStringSync();

    expect(shell, isNot(contains('AdaptiveHingePane(')));
    expect(app, contains('final appContent = AppLoadingHost('));
    expect(app, contains('AdaptiveHingePane(child: child'));
    expect(adaptive, contains('class AdaptiveHingePane'));
    expect(adaptive, contains('class AdaptiveTwoPane'));
    expect(adaptive, contains('separatesHorizontally'));
    expect(adaptive, contains('separatesVertically'));
    expect(calendar, contains("ValueKey('calendar-foldable-month')"));
    expect(
      organization,
      contains("ValueKey('organization-foldable-team-grid')"),
    );
    expect(communications, contains('AdaptiveTwoPane('));
    expect(matchday, contains("ValueKey('matchday-foldable-lineup')"));
  });
}
