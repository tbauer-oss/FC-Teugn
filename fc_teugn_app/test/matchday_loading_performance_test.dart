import 'dart:async';

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

class _FastMatchRepository extends DataRepository {
  _FastMatchRepository() : super(ApiClient(baseUrl: 'http://test'));

  @override
  Future<MatchdayModel> match(String eventId) async => MatchdayModel(
        id: eventId,
        title: 'FC Teugn gegen SV Schnell',
        startAt: DateTime(2026, 8, 15, 10),
        location: 'Sportplatz Teugn',
        teamId: 'team-e1',
        playerPoolAgeGroupCode: 'E',
        details: const MatchDetailsModel(
          opponent: 'SV Schnell E1',
          isHome: true,
          status: MatchStatus.planned,
          durationMinutes: 60,
          periodMinutes: 15,
          periodCount: 4,
        ),
      );
}

void main() {
  testWidgets(
    'matchday becomes visible before the shared player request finishes',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final players = Completer<List<PlayerModel>>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repositoryProvider.overrideWithValue(_FastMatchRepository()),
            playersProvider.overrideWith((ref) => players.future),
          ],
          child: MaterialApp(
            theme: buildAppTheme(),
            home: const Scaffold(
              body: MatchdayPage(
                matchId: 'match-fast',
                staffView: true,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump();

      expect(players.isCompleted, isFalse);
      expect(find.text('Spieltag wird geladen …'), findsNothing);
      expect(find.text('SV Schnell E1'), findsWidgets);
      expect(find.byType(TabBar), findsOneWidget);

      expect(tester.takeException(), isNull);

      players.complete(const []);
      await tester.pump();
    },
  );

  testWidgets('tournament squad reports the background player load',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final players = Completer<List<PlayerModel>>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(_FastMatchRepository()),
          playersProvider.overrideWith((ref) => players.future),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(
            body: MatchdayPage(
              matchId: 'tournament-fast',
              staffView: true,
              tournamentPlanning: true,
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    expect(players.isCompleted, isFalse);
    expect(
      find.byKey(const ValueKey('squad-player-loading')),
      findsOneWidget,
    );
    expect(find.text('Kader wird geladen …'), findsOneWidget);

    players.complete(const []);
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(const ValueKey('squad-player-loading')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}
