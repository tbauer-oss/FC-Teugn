import 'package:fc_teugn_app/core/app_theme.dart';
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
        status: PlayerStatus.active,
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
      expect(tester.takeException(), isNull);
    },
  );
}
