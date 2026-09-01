import 'package:fc_teugn_app/core/app_theme.dart';
import 'package:fc_teugn_app/core/models/statistics.dart';
import 'package:fc_teugn_app/features/matches/past_matches_page.dart';
import 'package:fc_teugn_app/features/statistics/statistics_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('match statistics parse scorers, assists and other events', () {
    final overview = StatisticsOverview.fromJson({
      'team': {
        'matches': 1,
        'wins': 1,
        'draws': 0,
        'losses': 0,
        'goalsFor': 2,
        'goalsAgainst': 0,
        'winRate': 100,
        'goalsPerMatch': 2,
        'form': ['WIN'],
      },
      'players': [],
      'matches': [
        {
          'id': 'match-1',
          'startAt': '2026-08-31T16:00:00.000Z',
          'teamName': 'FC Teugn E1',
          'opponent': 'TSV Beispiel',
          'competition': 'Ligaspiel',
          'ourGoals': 2,
          'theirGoals': 0,
          'result': 'WIN',
          'isHome': true,
          'events': [
            {
              'id': 'goal-1',
              'type': 'HOME_GOAL',
              'teamSide': 'OWN',
              'period': 1,
              'elapsedSeconds': 420,
              'ourGoals': 1,
              'theirGoals': 0,
              'scorer': {'id': 'p1', 'name': 'Hanna', 'shirtNumber': 9},
              'assist': {'id': 'p2', 'name': 'Ines', 'shirtNumber': 7},
            },
            {
              'id': 'card-1',
              'type': 'CARD',
              'teamSide': 'NEUTRAL',
              'period': 2,
              'elapsedSeconds': 2100,
              'ourGoals': 2,
              'theirGoals': 0,
              'comment': 'Gelbe Karte',
            },
          ],
        },
      ],
      'seasons': [],
      'privacy': {'individualScope': 'ASSIGNED_TEAMS'},
    });

    final match = overview.matches.single;
    expect(match.teamName, 'FC Teugn E1');
    expect(match.events, hasLength(2));
    expect(match.events.first.type, MatchStatisticEventType.homeGoal);
    expect(match.events.first.isOwnGoal, isTrue);
    expect(match.events.first.scorer?.name, 'Hanna');
    expect(match.events.first.assist?.name, 'Ines');
    expect(match.events.last.type, MatchStatisticEventType.card);
    expect(match.events.last.comment, 'Gelbe Karte');
  });

  for (final width in const [320.0, 390.0, 700.0, 900.0]) {
    testWidgets('past match details stay responsive at $width pixels',
        (tester) async {
      tester.view.physicalSize = Size(width, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(10),
              child: matchHistoryForTesting(
                [_matchWithEvents()],
                scopeLabel: '2026/27',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Vergangene Spiele · 2026/27'), findsOneWidget);
      expect(find.text('FC Teugn E1'), findsOneWidget);
      expect(find.text('TSV Beispielhausen'), findsOneWidget);
      expect(find.text('2 Tore'), findsOneWidget);
      expect(find.text('1 Vorlage'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const ValueKey('past-match-match-1')));
      await tester.pumpAndSettle();

      expect(find.text('Torschützen'), findsOneWidget);
      expect(find.text('Hanna ×2'), findsOneWidget);
      expect(find.text('Vorlagen'), findsOneWidget);
      expect(find.text('Ines'), findsOneWidget);
      expect(find.text('Tor · Hanna'), findsNWidgets(2));
      expect(find.text('Karte'), findsOneWidget);
      expect(find.textContaining('Gelbe Karte'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('past match center opens the original matchday', (tester) async {
    String? openedMatchId;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: matchHistoryForTesting(
              [_matchWithEvents()],
              onOpenMatch: (matchId) => openedMatchId = matchId,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('past-match-match-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-past-match-match-1')));

    expect(openedMatchId, 'match-1');
    expect(tester.takeException(), isNull);
  });

  for (final width in const [320.0, 390.0, 700.0, 900.0]) {
    testWidgets('separate past matches entry stays responsive at $width pixels',
        (tester) async {
      tester.view.physicalSize = Size(width, 500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var opened = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(10),
              child: PastMatchesEntryCard(onTap: () => opened = true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Vergangene Spiele'), findsOneWidget);
      expect(
        find.text('Ergebnisse, Torschützen, Vorlagen & Ereignisse'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('past-matches-entry')));
      expect(opened, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}

MatchResultStatistic _matchWithEvents() => MatchResultStatistic(
      id: 'match-1',
      startAt: DateTime(2026, 8, 31, 18),
      teamName: 'FC Teugn E1',
      opponent: 'TSV Beispielhausen',
      competition: 'Ligaspiel',
      ourGoals: 2,
      theirGoals: 0,
      result: 'WIN',
      isHome: true,
      events: const [
        MatchStatisticEvent(
          id: 'goal-1',
          type: MatchStatisticEventType.homeGoal,
          teamSide: 'OWN',
          period: 1,
          elapsedSeconds: 420,
          ourGoals: 1,
          theirGoals: 0,
          scorer: MatchStatisticParticipant(id: 'p1', name: 'Hanna'),
          assist: MatchStatisticParticipant(id: 'p2', name: 'Ines'),
        ),
        MatchStatisticEvent(
          id: 'goal-2',
          type: MatchStatisticEventType.homeGoal,
          teamSide: 'OWN',
          period: 2,
          elapsedSeconds: 1900,
          ourGoals: 2,
          theirGoals: 0,
          scorer: MatchStatisticParticipant(id: 'p1', name: 'Hanna'),
        ),
        MatchStatisticEvent(
          id: 'card-1',
          type: MatchStatisticEventType.card,
          teamSide: 'NEUTRAL',
          period: 2,
          elapsedSeconds: 2100,
          ourGoals: 2,
          theirGoals: 0,
          comment: 'Gelbe Karte',
        ),
      ],
    );
