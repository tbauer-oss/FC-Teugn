import 'dart:ui';

import 'package:fc_teugn_app/core/app_theme.dart';
import 'package:fc_teugn_app/core/models/competition.dart';
import 'package:fc_teugn_app/core/widgets/adaptive_layout.dart';
import 'package:fc_teugn_app/features/matches/tournament_opponent_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

OpponentModel _opponent(int index) => OpponentModel(
      id: 'opponent-$index',
      ageGroupId: 'age-e',
      opponentClubId: 'club-$index',
      clubName: 'Verein $index',
      teamDesignation: 'E1',
      displayName: 'Verein $index E1',
    );

void main() {
  testWidgets('searchable picker stays bounded and closable on a small phone',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var selectedId = 'opponent-2';
    final opponents = List.generate(40, _opponent);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 568),
            textScaler: TextScaler.linear(1.3),
          ),
          child: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) => Center(
                child: TournamentOpponentPickerField(
                  key: const ValueKey('opponent-field'),
                  opponentId: selectedId,
                  opponents: opponents,
                  onChanged: (value) => update(() => selectedId = value!),
                  onAddOpponent: () async => null,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('opponent-field')));
    await tester.pumpAndSettle();

    final sheet = tester.getRect(
      find.byKey(const ValueKey('tournament-opponent-picker-sheet')),
    );
    expect(sheet.height, lessThan(568));
    expect(sheet.width, lessThanOrEqualTo(320));
    expect(
      find.byKey(const ValueKey('tournament-opponent-picker-close')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('tournament-opponent-picker-add')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.enterText(
      find.byKey(const ValueKey('tournament-opponent-picker-search')),
      'Verein 37',
    );
    await tester.pump();
    expect(find.text('Verein 37 E1'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey('tournament-opponent-picker-results'),
        ),
        matching: find.text('Verein 2 E1'),
      ),
      findsNothing,
    );

    await tester.tap(find.text('Verein 37 E1'));
    await tester.pumpAndSettle();
    expect(selectedId, 'opponent-37');
    expect(find.text('Verein 37 E1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('picker remains inside one vertical foldable pane',
      (tester) async {
    const viewport = Size(673, 841);
    await tester.binding.setSurfaceSize(viewport);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: viewport,
            displayFeatures: [
              DisplayFeature(
                bounds: Rect.fromLTWH(330, 0, 13, 841),
                type: DisplayFeatureType.hinge,
                state: DisplayFeatureState.unknown,
              ),
            ],
          ),
          child: AdaptiveHingePane(
            child: Scaffold(
              body: TournamentOpponentPickerField(
                key: const ValueKey('foldable-opponent-field'),
                opponentId: null,
                opponents: [_opponent(1), _opponent(2)],
                onChanged: (_) {},
                onAddOpponent: () async => null,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('foldable-opponent-field')),
    );
    await tester.pumpAndSettle();

    final sheet = tester.getRect(
      find.byKey(const ValueKey('tournament-opponent-picker-sheet')),
    );
    expect(
      sheet.right <= 330 || sheet.left >= 343,
      isTrue,
      reason: 'Auswahlschublade liegt bei $sheet über dem Scharnier.',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('picker remains inside one horizontal foldable pane',
      (tester) async {
    const viewport = Size(480, 800);
    await tester.binding.setSurfaceSize(viewport);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: viewport,
            displayFeatures: [
              DisplayFeature(
                bounds: Rect.fromLTWH(0, 390, 480, 20),
                type: DisplayFeatureType.hinge,
                state: DisplayFeatureState.unknown,
              ),
            ],
          ),
          child: AdaptiveHingePane(
            child: Scaffold(
              body: TournamentOpponentPickerField(
                key: const ValueKey('horizontal-fold-opponent-field'),
                opponentId: null,
                opponents: [_opponent(1), _opponent(2)],
                onChanged: (_) {},
                onAddOpponent: () async => null,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('horizontal-fold-opponent-field')),
    );
    await tester.pumpAndSettle();

    final sheet = tester.getRect(
      find.byKey(const ValueKey('tournament-opponent-picker-sheet')),
    );
    expect(sheet.bottom <= 390 || sheet.top >= 410, isTrue);
    expect(tester.takeException(), isNull);
  });
}
