import 'package:fc_teugn_app/features/talents/goal_development_view.dart';
import 'package:fc_teugn_app/features/talents/talents_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final Json development = {
  'goal': {
    'title': 'Ballkontrolle',
    'description': 'Kontrollierte Annahme',
    'player': {'firstName': 'Testkind', 'lastName': 'Teugn'}
  },
  'from': '2030-09-01',
  'to': '2030-10-01',
  'statistics': {
    'appearances': 2,
    'minutes': 45,
    'goals': 1,
    'assists': 0,
    'recordedMatches': 2,
    'attendedTrainings': 3,
    'recordedTrainings': 4
  },
  'timeline': [
    {
      'kind': 'GOAL',
      'at': '2030-09-05',
      'title': 'Zielbeobachtung',
      'text': 'Kontrolle verbessert',
      'progress': 40
    },
    {
      'kind': 'NOTE',
      'at': '2030-09-04',
      'title': 'Annahme im Training',
      'text': 'Bestehende Notiz'
    },
    {
      'kind': 'MATCH',
      'at': '2030-09-03',
      'title': 'Testspiel',
      'text': '25 Min. · 1 Tor'
    },
  ],
};

void main() {
  test('combined export includes goal, existing notes and period statistics',
      () {
    final report = goalDevelopmentReport(development);
    expect(report, contains('Testkind Teugn · Ballkontrolle'));
    expect(report, contains('45 Minuten'));
    expect(report, contains('Bestehende Notiz'));
    expect(report, contains('Spielstatistik'));
    expect(report, contains('40 %'));
    expect(
        developmentStatistics({'recordedMatches': 0, 'recordedTrainings': 0}),
        contains('noch keine'));
  });
  testWidgets(
      'child development remains readable with large text on a small phone',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 740));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
        overrides: [
          goalDevelopmentProvider('goal')
              .overrideWith((ref) async => development),
        ],
        child: const MaterialApp(
            home: MediaQuery(
          data: MediaQueryData(
              size: Size(320, 740), textScaler: TextScaler.linear(2)),
          child: GoalDevelopmentView(goalId: 'goal'),
        ))));
    await tester.pumpAndSettle();
    expect(find.text('Testkind Teugn · Ballkontrolle'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Bestehende Notiz'), 300);
    expect(find.text('Bestehende Notiz'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
