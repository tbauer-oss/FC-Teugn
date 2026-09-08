import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:fc_teugn_app/features/talents/match_readiness_card.dart';
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
    if (const bool.fromEnvironment('CAPTURE_UI')) {
      await tester.runAsync(() async {
        final textFont = FontLoader('Arial')
          ..addFont(File(const String.fromEnvironment('UI_FONT_PATH'))
              .readAsBytes()
              .then(ByteData.sublistView));
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await Future.wait([textFont.load(), icons.load()]);
      });
    }
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          matchReadinessProvider(_match().id).overrideWith((ref) async => {
                'checks': [
                  {
                    'title': 'Rückmeldungen',
                    'detail': 'Alle Antworten geklärt',
                    'ready': true,
                    'route': '/events/match-mobile'
                  },
                  {
                    'title': 'Fahrgemeinschaften',
                    'detail': '1 Mitfahrt ungeklärt',
                    'ready': false,
                    'route': '/events/match-mobile'
                  },
                  {
                    'title': 'Trikotdienst',
                    'detail': 'Testfamilie',
                    'ready': true,
                    'route': '/matches/match-mobile?tab=overview'
                  },
                ],
                'minutes': [
                  {'name': 'Testspieler', 'planned': 30, 'actual': null}
                ],
                'briefing': 'Testspiel',
                'teamId': 'team'
              })
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(390, 844),
              textScaler: TextScaler.linear(1.5),
            ),
            child: Scaffold(
              body: RepaintBoundary(
                  key: const ValueKey('autopilot-preview'),
                  child: MatchdayAutopilotTab(
                    match: _match(),
                    allPlayers: _players(),
                    editable: true,
                    onSquadSaved: (_) async {},
                    onLineupSaved: (_) async {},
                  )),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    if (const bool.fromEnvironment('CAPTURE_UI')) {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('autopilot-preview')));
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file =
            File('../artifacts/release-1.7.1-build-186/autopilot-mobile.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    expect(find.text('1 offen'), findsOneWidget);
    expect(find.text('Fahrgemeinschaften'), findsNothing);
    expect(find.text('Testspieler').hitTestable(), findsNothing);
    expect(
        tester.getSize(find.byType(MatchReadinessCard)).height, lessThan(110));
    expect(
        tester.getTopLeft(find.text('Spieltags-Autopilot')).dy, lessThan(155));
    await tester.tap(find.text('Organisation'));
    await tester.pumpAndSettle();
    expect(find.text('Fahrgemeinschaften'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Fahrgemeinschaften')).dy,
        lessThan(tester.getTopLeft(find.text('Rückmeldungen')).dy));
    expect(find.text('Spieltagsübersicht'), findsOneWidget);
    expect(find.text('Checklisten & Dienste'), findsOneWidget);
    expect(find.text('Testspieler').hitTestable(), findsNothing);
    await tester.tap(find.text('Organisation'));
    await tester.pumpAndSettle();

    expect(find.text('Spieltags-Autopilot'), findsOneWidget);
    expect(find.text('Plan auf einen Blick'), findsOneWidget);
    expect(find.text('Wechselstrategie wählen'), findsOneWidget);
    expect(find.text('Ausgewogen'), findsWidgets);
    expect(
      find.byKey(const ValueKey('autopilot-strategy-selector-mobile')),
      findsOneWidget,
    );
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

    await tester.ensureVisible(
        find.byKey(const ValueKey('autopilot-strategy-selector-mobile')));
    await tester.tap(
      find.byKey(const ValueKey('autopilot-strategy-selector-mobile')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Positionstreu').last);
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
    final publishText = find.text('Übernehmen & veröffentlichen');
    expect(publishText, findsOneWidget);
    final publishButton = find.ancestor(
      of: publishText,
      matching: find.byWidgetPredicate(
        (widget) => widget is ButtonStyleButton,
      ),
    );
    expect(publishButton, findsOneWidget);
    final textRect = tester.getRect(publishText);
    final buttonRect = tester.getRect(publishButton);
    expect(textRect.top, greaterThanOrEqualTo(buttonRect.top - .5));
    expect(textRect.bottom, lessThanOrEqualTo(buttonRect.bottom + .5));
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
