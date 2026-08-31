import 'package:fc_teugn_app/core/app_theme.dart';
import 'package:fc_teugn_app/core/models/organization.dart';
import 'package:fc_teugn_app/core/models/player.dart';
import 'package:fc_teugn_app/core/providers.dart';
import 'package:fc_teugn_app/features/players/player_profile_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'player profile stays readable on a narrow phone with large text',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const player = PlayerModel(
        id: 'player-1',
        teamId: 'team-1',
        firstName: 'Maximilian',
        lastName: 'Mustermann-Langname',
        preferredName: 'Max',
        position: 'Zentrales Mittelfeld',
        secondaryPosition: 'Rechter Flügel',
        dominantFoot: DominantFoot.right,
        shirtNumber: 10,
        status: PlayerStatus.injured,
        injuryType: 'OTHER',
        injuryDetails: 'Reizung nach Fremdeinwirkung',
        teamName: 'E1-Jugend',
        teamNumber: 1,
        ageGroupCode: 'E',
        goals: 12,
        assists: 9,
        appearances: 18,
        starts: 14,
        minutes: 720,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playerProvider.overrideWith((ref, playerId) async => player),
          ],
          child: MaterialApp(
            theme: buildAppTheme(),
            home: const MediaQuery(
              data: MediaQueryData(
                size: Size(360, 800),
                textScaler: TextScaler.linear(1.35),
              ),
              child: Scaffold(
                body: PlayerProfilePage(
                  playerId: 'player-1',
                  staffView: true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Maximilian Mustermann-Langname'), findsOneWidget);
      expect(find.text('Sportliches Profil'), findsOneWidget);
      final exception = tester.takeException();
      expect(
        exception,
        isNull,
        reason: exception is FlutterError
            ? exception.toStringDeep()
            : exception?.toString(),
      );
    },
  );

  testWidgets(
    'editing offers the same personal master data as player creation',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const ageGroup = AgeGroupSummary(
        id: 'age-e',
        name: 'E-Jugend',
        code: 'E',
      );
      const team = TeamSummary(
        id: 'team-1',
        name: 'E1-Jugend',
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
          players: 1,
          members: 1,
          upcomingEvents: 0,
          pendingApprovals: 0,
        ),
      );
      final player = PlayerModel(
        id: 'player-1',
        teamId: 'team-1',
        firstName: 'Max',
        lastName: 'Muster',
        birthDate: DateTime(2015, 4, 8),
        joinedAt: DateTime(2022, 7, 1),
        passNumber: 'BFV-001234',
        gender: PlayerGender.diverse,
        dominantFoot: DominantFoot.right,
        status: PlayerStatus.injured,
        injuryType: 'OTHER',
        injuryDetails: 'Reizung nach Fremdeinwirkung',
        teamName: 'E1-Jugend',
        capabilities: const PlayerCapabilities(canEdit: true),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playerProvider.overrideWith((ref, playerId) async => player),
            organizationProvider.overrideWith((ref) async => organization),
          ],
          child: MaterialApp(
            theme: buildAppTheme(),
            builder: (context, child) => MediaQuery(
              data: const MediaQueryData(size: Size(390, 844)),
              child: child!,
            ),
            home: const Scaffold(
              body: PlayerProfilePage(
                playerId: 'player-1',
                staffView: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final editButton = find.text('Bearbeiten');
      expect(tester.takeException(), isNull, reason: 'before edit dialog');
      expect(editButton, findsOneWidget);
      await tester.ensureVisible(editButton);
      await tester.tap(editButton);
      await tester.pumpAndSettle();

      expect(
          find.byKey(const ValueKey('player-edit-birth-date')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('player-edit-joined-at')), findsOneWidget);
      expect(find.byKey(const ValueKey('player-edit-gender')), findsOneWidget);
      expect(find.text('d · divers'), findsWidgets);
      expect(find.byKey(const ValueKey('player-edit-pass-number')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('player-edit-injury-type')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('player-edit-injury-details')),
          findsOneWidget);
      expect(find.text('Reizung nach Fremdeinwirkung'), findsWidgets);
      expect(find.text('BFV-001234'), findsWidgets);
      final exception = tester.takeException();
      expect(
        exception,
        isNull,
        reason: exception is FlutterError
            ? exception.toStringDeep()
            : exception?.toString(),
      );
    },
  );
}
