import 'dart:async';

import 'package:fc_teugn_app/core/app_theme.dart';
import 'package:fc_teugn_app/core/models/event.dart';
import 'package:fc_teugn_app/core/models/personal_response.dart';
import 'package:fc_teugn_app/core/models/player.dart';
import 'package:fc_teugn_app/core/providers.dart';
import 'package:fc_teugn_app/features/parent/parent_dashboard_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

PlayerModel _player() => const PlayerModel(
      id: 'player-1',
      firstName: 'Max',
      lastName: 'Muster',
      teamId: 'team-e1',
      teamName: 'E1-Jugend',
      teamNumber: 1,
      ageGroupCode: 'E',
      status: PlayerStatus.active,
      dominantFoot: DominantFoot.right,
    );

PersonalResponseModel _response() => PersonalResponseModel(
      eventId: 'training-1',
      playerId: 'player-1',
      playerName: 'Max',
      teamName: 'E1-Jugend',
      ageGroupCode: 'E1',
      title: 'Training',
      type: 'TRAINING',
      category: 'TRAINING',
      startAt: DateTime.now().add(const Duration(days: 1)),
      location: 'Platz 1 unten',
      responseStatus: AttendanceStatus.unknown,
      canRespond: true,
      isOverdue: false,
    );

Future<void> _pump(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        playersProvider.overrideWith((ref) async => [_player()]),
        personalResponsesProvider.overrideWith((ref) async => [_response()]),
        parentDashboardEventsProvider.overrideWith((ref) async => const []),
        parentMatchdaysProvider.overrideWith((ref) async => const []),
        parentConsentAttentionProvider.overrideWith((ref) async => const []),
        liveNotificationsProvider.overrideWith((ref) => Stream.value(const [])),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(body: ParentDashboardPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [320.0, 360.0, 390.0, 480.0, 599.0]) {
    testWidgets('family assistant stays responsive at ${width.toInt()} px',
        (tester) async {
      await _pump(tester, width);

      expect(find.text('Heute wichtig'), findsOneWidget);
      expect(find.text('Diese Woche'), findsOneWidget);
      expect(find.text('Deine Kinder'), findsOneWidget);
      expect(find.text('Max'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('background refresh keeps the family assistant calm',
      (tester) async {
    final refresh = Completer<List<PersonalResponseModel>>();
    var responseRequests = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playersProvider.overrideWith((ref) async => [_player()]),
          personalResponsesProvider.overrideWith((ref) {
            responseRequests++;
            if (responseRequests == 1) {
              return Future.value([_response()]);
            }
            return refresh.future;
          }),
          parentDashboardEventsProvider.overrideWith((ref) async => const []),
          parentMatchdaysProvider.overrideWith((ref) async => const []),
          parentConsentAttentionProvider.overrideWith((ref) async => const []),
          liveNotificationsProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(body: ParentDashboardPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ParentDashboardPage)),
    );
    container.invalidate(personalResponsesProvider);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    expect(responseRequests, 2);
    expect(
      find.byKey(const ValueKey('parent-dashboard-initial-loading')),
      findsNothing,
    );
    expect(find.text('Diese Woche'), findsOneWidget);

    refresh.complete([_response()]);
    await tester.pumpAndSettle();
  });
}
