import 'package:fc_teugn_app/core/api_client.dart';
import 'package:fc_teugn_app/core/app_theme.dart';
import 'package:fc_teugn_app/core/data_repository.dart';
import 'package:fc_teugn_app/core/models/event.dart';
import 'package:fc_teugn_app/core/models/matchday.dart';
import 'package:fc_teugn_app/core/models/tactics_board.dart';
import 'package:fc_teugn_app/core/models/player.dart';
import 'package:fc_teugn_app/core/providers.dart';
import 'package:fc_teugn_app/features/matches/matchday_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _player = PlayerModel(
  id: 'player-1',
  teamId: 'team-e1',
  firstName: 'Lena',
  lastName: 'Beispiel',
  status: PlayerStatus.active,
  dominantFoot: DominantFoot.right,
  position: 'TW',
  shirtNumber: 1,
  ageGroupCode: 'E',
  teamNumber: 1,
);

MatchdayModel _tournament({
  MatchSquadModel? squad,
  DateTime? internalPublishedAt,
  DateTime? familyReleasedAt,
}) =>
    MatchdayModel(
      id: 'tournament-1',
      title: '3. Hopfenbach-Cup',
      startAt: DateTime(2026, 9, 12, 15),
      location: 'Hopfenbach-Arena',
      teamId: 'team-e1',
      attendance: const [
        EventAttendance(
          id: 'attendance-player-1',
          playerId: 'player-1',
          status: AttendanceStatus.yes,
        ),
      ],
      squad: squad,
      eligiblePlayers: const [_player],
      playerPoolAgeGroupCode: 'E',
      canPublishInternal: true,
      canNominateSquad: true,
      canReleaseFamily: true,
      internalPublishedAt: internalPublishedAt,
      familyReleasedAt: familyReleasedAt,
    );

class _TournamentPlanningRepository extends DataRepository {
  _TournamentPlanningRepository()
      : current = _tournament(),
        super(ApiClient(baseUrl: 'http://test'));

  MatchdayModel current;
  String? savedSquadEventId;
  String? savedLineupEventId;
  List<String>? internalRecipientIds;
  bool? internalPushEnabled;
  String? familyReleaseEventId;
  String? tacticsEventId;
  String? approvedOtherEventId;
  bool emptySameDayOptions = false;

  @override
  Future<List<Map<String, dynamic>>> sameDayMatchOptions({
    required String eventId,
    required String playerId,
  }) async =>
      emptySameDayOptions
          ? []
          : [
              {
                'id': 'second-match',
                'title':
                    'FC Teugn E1 gegen einen Gegner mit einem sehr langen Namen',
                'startAt': '2026-09-12T16:00:00Z',
                'approved': false,
              }
            ];

  @override
  Future<EventModel> approveSameDayMatch(
      {required String eventId,
      required String playerId,
      required String otherEventId}) async {
    approvedOtherEventId = otherEventId;
    return EventModel.fromJson({
      'id': eventId,
      'teamId': 'team-e1',
      'title': 'Turnier',
      'type': 'MATCH',
      'startAt': '2026-09-12T13:00:00Z'
    });
  }

  @override
  Future<TacticsBoardSnapshot> loadTacticsBoard(String eventId) async {
    tacticsEventId = eventId;
    return const TacticsBoardSnapshot(revision: 0);
  }

  @override
  Future<MatchdayModel> match(String eventId) async => current;

  @override
  Future<MatchSquadModel> saveMatchSquad({
    required String eventId,
    required List<
            ({
              String playerId,
              NominationStatus status,
              int? plannedMinutes,
            })>
        members,
    String? formation,
  }) async {
    savedSquadEventId = eventId;
    final squad = MatchSquadModel(
      id: 'tournament-squad',
      formation: formation,
      members: [
        for (final member in members)
          SquadMemberModel(
            player: const MatchPlayer(
              id: 'player-1',
              name: 'Lena Beispiel',
              shirtNumber: 1,
              position: 'TW',
            ),
            status: member.status,
          ),
      ],
    );
    current = _tournament(squad: squad);
    return squad;
  }

  @override
  Future<LineupModel> saveLineup({
    required String eventId,
    required String formation,
    required int fieldSize,
    required LineupStatus status,
    required List<LineupPositionModel> positions,
    List<PlannedSubstitutionModel> plannedSubstitutions = const [],
    String? publicNote,
    String? tacticalNote,
  }) async {
    savedLineupEventId = eventId;
    final lineup = LineupModel(
      id: 'tournament-lineup',
      formation: formation,
      fieldSize: fieldSize,
      status: status,
      positions: positions,
      substitutions: plannedSubstitutions,
    );
    final squad = current.squad!;
    current = _tournament(
      squad: MatchSquadModel(
        id: squad.id,
        members: squad.members,
        formation: squad.formation,
        lineup: lineup,
      ),
    );
    return lineup;
  }

  @override
  Future<Map<String, dynamic>> internalPublicationPreview(
    String eventId,
  ) async =>
      {
        'recipients': [
          {
            'id': 'trainer-1',
            'name': 'Trainer Beispiel',
            'functions': ['Trainer'],
            'teams': ['E1-Jugend'],
            'isSender': false,
          },
        ],
        'messagePreview':
            'Kader und Aufstellung für das Turnier werden geteilt.',
      };

  @override
  Future<Map<String, dynamic>> publishMatchInternally(
    String eventId, {
    required List<String> recipientIds,
    bool pushEnabled = true,
  }) async {
    internalRecipientIds = recipientIds;
    internalPushEnabled = pushEnabled;
    return {'recipients': recipientIds.length};
  }

  @override
  Future<Map<String, dynamic>> familyReleasePreview(String eventId) async => {
        'title': '3. Hopfenbach-Cup',
        'isTournament': true,
        'team': 'E1-Jugend',
        'category': 'Turnier',
        'startAt': '2026-09-12T13:00:00.000Z',
        'meetingSummary': 'Treffpunkt: 14:00 Uhr',
        'location': 'Hopfenbach-Arena',
        'audienceMode': 'NOMINATED_SQUAD',
        'recipients': 2,
        'messagePreview':
            'Das Turnier wird für Eltern und Spieler freigegeben.',
      };

  @override
  Future<Map<String, dynamic>> releaseMatchToFamilies(
    String eventId, {
    bool fullTeam = false,
  }) async {
    familyReleaseEventId = eventId;
    return {'alreadyReleased': false, 'recipients': 2};
  }
}

Widget _planningPage(
  _TournamentPlanningRepository repository, {
  double textScale = 1,
  bool staffView = true,
}) =>
    ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repository),
        playersProvider.overrideWith((ref) async => const [_player]),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: MatchdayPage(
            matchId: 'tournament-1',
            staffView: staffView,
            tournamentPlanning: true,
          ),
        ),
      ),
    );

void main() {
  testWidgets('desktop tournament page fits field below its real headers',
      (tester) async {
    tester.view.physicalSize = const Size(1640, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _TournamentPlanningRepository();
    await repository.saveMatchSquad(eventId: 'tournament-1', members: [
      (
        playerId: 'player-1',
        status: NominationStatus.nominated,
        plannedMinutes: null
      )
    ]);
    await tester.pumpWidget(_planningPage(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aufstellung'));
    await tester.pumpAndSettle();
    for (final size in [const Size(1640, 860), const Size(1080, 625)]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      final field =
          tester.getRect(find.byKey(const ValueKey('modern-lineup-pitch')));
      final tabs = tester
          .getRect(find.byKey(const ValueKey('tournament-planning-tabs')));
      expect(field.top, greaterThanOrEqualTo(tabs.bottom));
      expect(field.bottom, lessThan(size.height));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
      'trainer explicitly confirms double match at 320px with large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 650);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _TournamentPlanningRepository();
    await tester.pumpWidget(_planningPage(repository, textScale: 1.5));
    await tester.pumpAndSettle();
    final status = find.byTooltip('Zusage bearbeiten');
    await tester.scrollUntilVisible(status, 140,
        scrollable: find.descendant(
            of: find.byKey(const ValueKey('squad-responsive-list')),
            matching: find.byType(Scrollable)));
    await tester.pumpAndSettle();
    await tester.tap(status);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Doppelspiel freigeben'));
    await tester.pumpAndSettle();
    expect(repository.approvedOtherEventId, isNull);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Für beide zusagen'))
            .onPressed,
        isNull);
    final other =
        find.text('FC Teugn E1 gegen einen Gegner mit einem sehr langen Namen');
    await tester.ensureVisible(other);
    await tester.pumpAndSettle();
    await tester.tap(other);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Für beide zusagen'));
    await tester.pumpAndSettle();
    expect(repository.approvedOtherEventId, 'second-match');
    expect(
        find.textContaining('beide Spiele bleiben zugesagt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no second acceptance cannot silently create an approval',
      (tester) async {
    final repository = _TournamentPlanningRepository()
      ..emptySameDayOptions = true;
    await tester.pumpWidget(_planningPage(repository));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byTooltip('Zusage bearbeiten'), 140,
        scrollable: find.descendant(
            of: find.byKey(const ValueKey('squad-responsive-list')),
            matching: find.byType(Scrollable)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Zusage bearbeiten'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Doppelspiel freigeben'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Bitte zuerst das andere Spiel zusagen'),
        findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Für beide zusagen'))
            .onPressed,
        isNull);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(repository.approvedOtherEventId, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'family sees all tournament players and the complete field without other private replies',
      (tester) async {
    const players = [
      MatchPlayer(id: 'player-1', name: 'Lena Beispiel', shirtNumber: 1),
      MatchPlayer(id: 'player-2', name: 'Mia Beispiel', shirtNumber: 2),
    ];
    final repository = _TournamentPlanningRepository();
    repository.current = _tournament(
      familyReleasedAt: DateTime(2026, 9, 1),
      squad: MatchSquadModel(
        id: 'squad-family',
        members: [
          for (final player in players)
            SquadMemberModel(
              player: player,
              status: NominationStatus.nominated,
              lineupEligible: true,
            )
        ],
        lineup: LineupModel(
          id: 'lineup-family',
          formation: '2-3-1',
          fieldSize: 7,
          status: LineupStatus.published,
          positions: [
            for (var i = 0; i < players.length; i++)
              LineupPositionModel(
                player: players[i],
                positionCode: 'ST',
                x: .25 + i * .5,
                y: .3,
                period: 1,
                isStarter: true,
                isGoalkeeper: false,
                isCaptain: false,
              )
          ],
        ),
      ),
    );
    await tester.pumpWidget(_planningPage(repository, staffView: false));
    await tester.pumpAndSettle();
    expect(find.text('Lena Beispiel'), findsWidgets);
    expect(find.text('Mia Beispiel'), findsWidgets);
    await tester.tap(find.text('Aufstellung'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Mia'), findsWidgets);
    expect(find.text('Aufstellung noch nicht veröffentlicht'), findsNothing);
    expect(find.text('Kader nominieren'), findsNothing);
    expect(find.byKey(const ValueKey('open-tactics-board')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final viewport in const [
    Size(320, 568),
    Size(390, 844),
    Size(673, 841),
  ]) {
    testWidgets(
      'tournament planning exposes squad and lineup at '
      '${viewport.width.toInt()} px',
      (tester) async {
        tester.view.physicalSize = viewport;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          _planningPage(_TournamentPlanningRepository()),
        );
        await tester.pumpAndSettle();

        expect(find.text('Turnier-Kader & Aufstellung'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('tournament-planning-notice')),
          findsOneWidget,
        );
        expect(find.text('Kader'), findsOneWidget);
        expect(find.text('Aufstellung'), findsOneWidget);
        if (viewport.width < 600) {
          expect(
            find.byKey(const ValueKey('tournament-squad-save-action')),
            findsOneWidget,
          );
          expect(find.text('Kader nominieren'), findsOneWidget);
          expect(find.text('Familien freigeben'), findsOneWidget);
          expect(
            find.byKey(
              const ValueKey('match-communication-dense-mobile-actions'),
            ),
            findsOneWidget,
          );
          expect(
            tester
                .getSize(
                  find.byKey(const ValueKey('tournament-planning-notice')),
                )
                .height,
            lessThan(100),
          );
          final tabs = tester.getRect(
            find.byKey(const ValueKey('tournament-planning-tabs')),
          );
          final summary = tester.getRect(
            find.byKey(const ValueKey('tournament-squad-compact-summary')),
          );
          expect(summary.top, greaterThanOrEqualTo(tabs.bottom));
        } else {
          expect(find.text('Entwurf speichern'), findsOneWidget);
          expect(find.text('Spieltag intern teilen'), findsOneWidget);
          expect(find.text('Für Familien freigeben'), findsOneWidget);
        }
        expect(find.text('Übersicht'), findsNothing);
        expect(find.text('Liveticker'), findsNothing);
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Aufstellung'));
        await tester.pumpAndSettle();

        expect(find.text('Zuerst den Kader festlegen'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('compact tournament controls stay separated at large text scale',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _planningPage(
        _TournamentPlanningRepository(),
        textScale: 1.5,
      ),
    );
    await tester.pumpAndSettle();

    final tabs = tester.getRect(
      find.byKey(const ValueKey('tournament-planning-tabs')),
    );
    final summary = tester.getRect(
      find.byKey(const ValueKey('tournament-squad-compact-summary')),
    );
    final actions = tester.getRect(
      find.byKey(const ValueKey('tournament-squad-compact-actions')),
    );
    expect(summary.top, greaterThanOrEqualTo(tabs.bottom));
    expect(actions.top, greaterThanOrEqualTo(summary.bottom));
    expect(find.text('Kader nominieren'), findsOneWidget);
    expect(find.text('Familien freigeben'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('squad and lineup are saved on the tournament event',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _TournamentPlanningRepository();

    await tester.pumpWidget(_planningPage(repository));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('tournament-squad-select-all')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('tournament-squad-save-action')),
    );
    await tester.pumpAndSettle();

    expect(repository.savedSquadEventId, 'tournament-1');
    expect(repository.current.squad?.members, hasLength(1));

    await tester.tap(find.text('Aufstellung'));
    await tester.pumpAndSettle();
    await tester
        .ensureVisible(find.byKey(const ValueKey('lineup-save-action')));
    await tester.tap(find.byKey(const ValueKey('lineup-save-action')));
    await tester.pumpAndSettle();

    expect(repository.savedLineupEventId, 'tournament-1');
    expect(repository.current.squad?.lineup?.positions, hasLength(1));
    // Fullscreen uses the same editable state and saves normalized positions.
    await tester.ensureVisible(find.byTooltip('Aufstellung im Vollbild'));
    await tester.tap(find.byTooltip('Aufstellung im Vollbild'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lineup-fullscreen')), findsOneWidget);
    final player = repository.current.squad!.lineup!.positions.single;
    final marker =
        find.byKey(ValueKey('lineup-player-${player.player.id}')).last;
    await tester.ensureVisible(marker);
    await tester.pumpAndSettle();
    await tester.drag(marker, const Offset(45, -25));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(
        repository.current.squad!.lineup!.positions.single.x, isNot(player.x));
    await tester.tap(find.byTooltip('Vollbild schließen'));
    await tester.pumpAndSettle();
    repository.savedLineupEventId = null;
    await tester
        .ensureVisible(find.byKey(const ValueKey('open-tactics-board')));
    await tester.tap(find.byKey(const ValueKey('open-tactics-board')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tactics-pitch')), findsOneWidget);
    expect(repository.tacticsEventId, 'tournament-1');
    expect(repository.savedLineupEventId, isNull,
        reason: 'Opening tactics never saves the actual lineup');
    await tester.tap(find.byTooltip('Taktikboard schließen'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'tournament plan can be shared internally and released to families',
      (tester) async {
    tester.view.physicalSize = const Size(673, 841);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _TournamentPlanningRepository();

    await tester.pumpWidget(_planningPage(repository));
    await tester.pumpAndSettle();

    await tester.tap(
      find.widgetWithText(OutlinedButton, 'Spieltag intern teilen'),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Kader und Aufstellung für das Turnier werden geteilt.'),
      findsOneWidget,
    );
    await tester.tap(
      find.widgetWithText(FilledButton, 'Jetzt intern teilen'),
    );
    await tester.pumpAndSettle();

    expect(repository.internalRecipientIds, ['trainer-1']);
    expect(repository.internalPushEnabled, isTrue);

    await tester.tap(
      find.widgetWithText(
        FilledButton,
        'Für Familien freigeben',
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Turnier für Eltern und Spieler freigeben?'),
      findsOneWidget,
    );
    expect(find.text('Gegner'), findsNothing);
    await tester.tap(find.text('Jetzt freigeben'));
    await tester.pumpAndSettle();

    expect(repository.familyReleaseEventId, 'tournament-1');
    expect(tester.takeException(), isNull);
  });
}
