import 'package:fc_teugn_app/core/models/event.dart';
import 'package:fc_teugn_app/features/carpool/carpool_section.dart';
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
  Future<KitLaundryDutyModel> kitLaundryDuty(String eventId) async =>
      KitLaundryDutyModel(
        eventId: eventId,
        title: 'Testspiel',
        startAt: DateTime(2026, 8, 15, 10),
        status: KitLaundryDutyStatus.open,
        eligibleFamilyCount: 0,
        nominationPublished: false,
        viewerEligible: false,
        viewerAssigned: false,
        canRespond: false,
        canComplete: false,
        canManage: false,
      );

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

class _ObservedTickerRepository extends _FastMatchRepository {
  final pending = <Completer<LiveTickerModel>>[];

  @override
  Future<LiveTickerModel> ticker(String eventId,
      {int after = 0, bool waitForChanges = false}) {
    final result = Completer<LiveTickerModel>();
    pending.add(result);
    return result.future;
  }

  void completeLatest() => pending.last.complete(LiveTickerModel.fromJson({}));
}

void main() {
  testWidgets(
      'ticker pauses behind another page or background app and reconnects immediately',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final repository = _ObservedTickerRepository();
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repository),
        playersProvider.overrideWith((ref) async => const []),
        carpoolEventProvider
            .overrideWith((ref, id) async => EventModel.fromJson({
                  'id': id,
                  'title': 'Testspiel',
                  'teamId': 'team-1',
                  'type': 'MATCH',
                  'startAt': '2030-09-17T10:00:00Z',
                  'location': 'Testplatz',
                })),
      ],
      child: MaterialApp(
          navigatorKey: navigator,
          theme: buildAppTheme(),
          home: const Scaffold(
              body: MatchdayPage(matchId: 'live', staffView: true))),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(repository.pending.length, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    repository.completeLatest();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(minutes: 20));
    expect(repository.pending.length, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 1));
    expect(repository.pending.length, 2);

    unawaited(navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Andere Seite')))));
    await tester.pump(const Duration(milliseconds: 400));
    repository.completeLatest();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 20));
    expect(repository.pending.length, 2);
    navigator.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(repository.pending.length, 3);
    await tester.pumpWidget(const SizedBox());
    repository.completeLatest();
    await tester.pump(const Duration(milliseconds: 1));
    expect(tester.takeException(), isNull);
  });

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
            carpoolEventProvider
                .overrideWith((ref, id) async => EventModel.fromJson({
                      'id': id,
                      'title': 'Testspiel',
                      'teamId': 'team-1',
                      'type': 'MATCH',
                      'startAt': '2030-09-17T10:00:00Z',
                      'location': 'Testplatz'
                    })),
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
          carpoolEventProvider
              .overrideWith((ref, id) async => EventModel.fromJson({
                    'id': id,
                    'title': 'Testspiel',
                    'teamId': 'team-1',
                    'type': 'MATCH',
                    'startAt': '2030-09-17T10:00:00Z',
                    'location': 'Testplatz'
                  })),
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
