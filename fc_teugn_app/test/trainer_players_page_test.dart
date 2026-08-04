import 'package:fc_teugn_app/core/app_theme.dart';
import 'package:fc_teugn_app/core/models/organization.dart';
import 'package:fc_teugn_app/core/models/player.dart';
import 'package:fc_teugn_app/core/providers.dart';
import 'package:fc_teugn_app/features/trainer/trainer_players_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('mobile team tab renders players without a grey error screen',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const ageGroup = AgeGroupSummary(
      id: 'age-e',
      name: 'E-Jugend',
      code: 'E',
    );
    const team = TeamSummary(
      id: 'team-e1',
      name: 'E1',
      ageGroup: ageGroup,
      seasonName: '2026/27',
    );
    final organization = OrganizationContext(
      club: const ClubSummary(
        id: 'club-1',
        name: 'FC Teugn',
        shortName: 'FCT',
        primaryColor: '#171918',
        accentColor: '#FFE600',
      ),
      season: SeasonSummary(
        id: 'season-1',
        name: '2026/27',
        startDate: DateTime(2026, 7, 1),
        endDate: DateTime(2027, 6, 30),
        isActive: true,
      ),
      currentTeam: team,
      ageGroups: const [ageGroup],
      teams: const [team],
      permissions: const {},
      metrics: const OrganizationMetrics(
        players: 2,
        members: 2,
        upcomingEvents: 0,
        pendingApprovals: 0,
      ),
    );
    final player = PlayerModel(
      id: 'player-1',
      teamId: 'team-e1',
      firstName: 'Max',
      lastName: 'Mustermann',
      birthDate: DateTime(DateTime.now().year - 12, 1, 1),
      nationality: 'Deutschland',
      gender: PlayerGender.male,
      position: 'ZM',
      dominantFoot: DominantFoot.right,
      shirtNumber: 8,
      joinedAt: DateTime(2021, 7, 1),
      photoUrl: 'https://example.test/max.jpg',
      status: PlayerStatus.active,
      teamName: 'E1',
      teamNumber: 1,
      ageGroupCode: 'E',
      starts: 5,
      minutes: 480,
    );
    const playerWithIncompleteName = PlayerModel(
      id: 'player-2',
      teamId: 'team-e1',
      firstName: '',
      lastName: 'OhneVorname',
      position: 'TW',
      dominantFoot: DominantFoot.unknown,
      status: PlayerStatus.active,
      teamName: 'E1',
      teamNumber: 1,
      ageGroupCode: 'E',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playersProvider.overrideWith(
            (ref) async => [player, playerWithIncompleteName],
          ),
          organizationProvider.overrideWith((ref) async => organization),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const MediaQuery(
            data: MediaQueryData(
              size: Size(360, 780),
              textScaler: TextScaler.linear(1.15),
            ),
            child: Scaffold(body: TrainerPlayersPage()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Spieler'), findsWidgets);
    expect(find.text('Max Mustermann'), findsOneWidget);
    expect(find.text('OhneVorname'), findsOneWidget);
    expect(find.text('O'), findsOneWidget);
    expect(find.text('Alle Jugenden'), findsOneWidget);
    const photoKey = ValueKey('player-photo-player-1');
    expect(find.byKey(photoKey), findsOneWidget);
    for (final mode in ['Liste', 'Details', 'Groß', 'Klein']) {
      await tester.tap(find.text(mode));
      await tester.pump();
      expect(
        find.byKey(photoKey),
        findsOneWidget,
        reason: 'Spielerfoto fehlt in der Ansicht $mode',
      );
      if (mode == 'Groß') {
        expect(find.text('12 Jahre'), findsOneWidget);
        expect(find.text('Rechts'), findsOneWidget);
        expect(find.text('m · männlich'), findsOneWidget);
        expect(find.text('Seit 2021'), findsOneWidget);
        expect(find.text('Deutschland'), findsOneWidget);
        expect(find.text('Startelf'), findsNWidgets(2));
        expect(find.text('Minuten'), findsNWidgets(2));
        expect(find.text('480'), findsOneWidget);
      }
    }
    expect(tester.takeException(), isNull);
  });
}
