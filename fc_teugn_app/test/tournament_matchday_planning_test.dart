import 'package:fc_teugn_app/core/api_client.dart';
import 'package:fc_teugn_app/core/app_theme.dart';
import 'package:fc_teugn_app/core/data_repository.dart';
import 'package:fc_teugn_app/core/models/matchday.dart';
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
        home: const Scaffold(
          body: MatchdayPage(
            matchId: 'tournament-1',
            staffView: true,
            tournamentPlanning: true,
          ),
        ),
      ),
    );

void main() {
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
          expect(find.text('Veröffentlichen'), findsWidgets);
          expect(find.text('Familien'), findsOneWidget);
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
          expect(find.text('Mit Trainerteam teilen'), findsOneWidget);
          expect(find.text('Für Eltern & Spieler freigeben'), findsOneWidget);
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
    expect(find.text('Veröffentlichen'), findsWidgets);
    expect(find.text('Familien'), findsOneWidget);
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
    await tester.tap(find.text('Entwurf'));
    await tester.pumpAndSettle();

    expect(repository.savedLineupEventId, 'tournament-1');
    expect(repository.current.squad?.lineup?.positions, hasLength(1));
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
      find.widgetWithText(OutlinedButton, 'Mit Trainerteam teilen'),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Kader und Aufstellung für das Turnier werden geteilt.'),
      findsOneWidget,
    );
    await tester.tap(
      find.widgetWithText(FilledButton, 'Mit Trainerteam teilen'),
    );
    await tester.pumpAndSettle();

    expect(repository.internalRecipientIds, ['trainer-1']);
    expect(repository.internalPushEnabled, isTrue);

    await tester.tap(
      find.widgetWithText(
        FilledButton,
        'Für Eltern & Spieler freigeben',
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
