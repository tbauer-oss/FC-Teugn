import 'package:fc_teugn_app/core/app_theme.dart';
import 'package:fc_teugn_app/core/models/matchday.dart';
import 'package:fc_teugn_app/core/models/player.dart';
import 'package:fc_teugn_app/core/team_game_format.dart';
import 'package:fc_teugn_app/features/matches/matchday_autopilot_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('matchday autopilot stays compact and usable on a phone',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildAppTheme(),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(390, 844),
              textScaler: TextScaler.linear(1.1),
            ),
            child: Scaffold(
              body: MatchdayAutopilotTab(
                match: _match(),
                allPlayers: _players(),
                editable: true,
                onSquadSaved: (_) async {},
                onLineupSaved: (_) async {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Spieltags-Autopilot'), findsOneWidget);
    expect(find.text('Plan auf einen Blick'), findsOneWidget);
    expect(find.text('Wechselstrategie wählen'), findsOneWidget);
    expect(find.text('Ausgewogen'), findsWidgets);
    expect(find.text('Einsatzzeit'), findsOneWidget);
    expect(find.text('Positionstreu'), findsOneWidget);
    expect(find.text('Startformation'), findsOneWidget);
    expect(find.text('Fairer Wechselplan'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text && (widget.data?.startsWith('auf ') ?? false),
      ),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);

    final horizontalStrategyScroll = find.byWidgetPredicate(
      (widget) =>
          widget is SingleChildScrollView &&
          widget.scrollDirection == Axis.horizontal,
    );
    await tester.drag(horizontalStrategyScroll, const Offset(-360, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Positionstreu'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Hält Haupt-, Neben- und taktische Positionsgruppen besonders konsequent ein.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Stammspieler auf Stammplätze zurückführen'),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('autopilot-restore-starters-switch')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Stammplätze aktiv'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      find.text('Trainerfreigabe'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Trainerfreigabe'), findsOneWidget);
    expect(find.text('Übernehmen & veröffentlichen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

MatchdayModel _match() => MatchdayModel(
      id: 'match-mobile',
      title: 'FC Teugn · Gegner',
      startAt: DateTime(2026, 8, 15, 10),
      meetingAt: DateTime(2026, 8, 15, 9),
      location: 'Platz 1 unten',
      teamId: 'team-1',
      gameFormat: TeamGameFormat.football5,
      details: const MatchDetailsModel(
        opponent: 'Gegner',
        isHome: true,
        status: MatchStatus.planned,
        durationMinutes: 60,
        periodMinutes: 15,
        periodCount: 4,
      ),
    );

List<PlayerModel> _players() => [
      _player('keeper', 'Levin', 'TW', 1, 300),
      _player('left', 'Anna', 'LV', 3, 260),
      _player('right', 'Andi', 'RV', 4, 280),
      _player('midfield', 'Max', 'ZM', 5, 310),
      _player('striker', 'Lukas', 'ST', 6, 290),
      _player('bench-wing', 'Felix', 'RA', 7, 120),
      _player('bench-defence', 'Elias', 'IV', 2, 150),
    ];

PlayerModel _player(
  String id,
  String name,
  String position,
  int shirtNumber,
  int minutes,
) =>
    PlayerModel(
      id: id,
      firstName: name,
      lastName: 'Teugn',
      status: PlayerStatus.active,
      dominantFoot: DominantFoot.right,
      position: position,
      shirtNumber: shirtNumber,
      minutes: minutes,
      ageGroupCode: 'E',
    );
