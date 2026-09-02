import 'dart:async';

import 'package:fc_teugn_app/core/app_theme.dart';
import 'package:fc_teugn_app/core/models/dashboard_summary.dart';
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

EventModel _matchEvent() => EventModel(
      id: 'match-1',
      teamId: 'team-e1',
      type: EventType.match,
      category: EventCategory.friendlyMatch,
      status: EventStatus.scheduled,
      visibility: EventVisibility.team,
      title: 'SV Saal – FC Teugn E1',
      startAt: DateTime.now().add(const Duration(days: 2)),
      location: 'Sportplatz Saal',
      homeAway: HomeAway.home,
      opponent: 'SV Saal',
      ownTeamName: 'FC Teugn E1',
      attendanceFinalized: false,
      targetTeams: const [],
      attachments: const [],
      attendance: const [],
      attendanceSummary: const AttendanceSummary(),
      missingAttendance: const [],
      carpoolOffers: const [],
      capabilities: const EventCapabilities(),
      reminderMinutes: const [],
    );

Future<void> _pump(
  WidgetTester tester,
  double width, {
  bool pushReady = true,
  Brightness brightness = Brightness.light,
  List<EventModel> events = const [],
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        parentDashboardSummaryProvider.overrideWith(
          (ref) async => DashboardSummary(
            players: [_player()],
            events: events,
            notifications: const [],
          ),
        ),
        personalResponsesProvider.overrideWith((ref) async => [_response()]),
        parentMatchdaysProvider.overrideWith((ref) async => const []),
        parentConsentAttentionProvider.overrideWith((ref) async => const []),
        currentDevicePushReadyProvider.overrideWith(
          (ref) async => pushReady,
        ),
        liveNotificationsProvider.overrideWith((ref) => Stream.value(const [])),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        darkTheme: buildAppTheme(brightness: Brightness.dark),
        themeMode:
            brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
        home: const Scaffold(body: ParentDashboardPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [320.0, 360.0, 390.0, 430.0, 599.0, 700.0, 900.0]) {
    testWidgets('family assistant stays responsive at ${width.toInt()} px',
        (tester) async {
      await _pump(tester, width);

      expect(find.text('Heute wichtig'), findsOneWidget);
      expect(find.text('Als Nächstes'), findsOneWidget);
      expect(find.text('Deine Kinder'), findsOneWidget);
      expect(find.text('Schnellzugriff'), findsOneWidget);
      expect(find.text('Max'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('next training and next match stay visible together',
      (tester) async {
    await _pump(tester, 320, events: [_matchEvent()]);

    expect(find.text('Training'), findsWidgets);
    expect(find.text('FC Teugn E1 – SV Saal'), findsOneWidget);
    expect(find.text('Kein Spiel geplant'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('completed push setup uses the current device status',
      (tester) async {
    await _pump(tester, 390, pushReady: true);

    expect(find.text('Ruhig startklar werden'), findsNothing);
    expect(find.text('Push einstellen'), findsNothing);
  });

  testWidgets('missing device subscription keeps push setup actionable',
      (tester) async {
    await _pump(tester, 390, pushReady: false);

    expect(find.text('Ruhig startklar werden'), findsOneWidget);
    expect(find.text('2 von 3 Schritten erledigt'), findsOneWidget);
    expect(find.text('Push einstellen'), findsOneWidget);
  });

  testWidgets('family panels use dark theme surfaces instead of white',
      (tester) async {
    await _pump(
      tester,
      390,
      brightness: Brightness.dark,
    );

    final panels = tester.widgetList<Container>(
      find.byKey(const ValueKey('family-dashboard-adaptive-panel')),
    );
    expect(panels, isNotEmpty);
    for (final panel in panels) {
      final decoration = panel.decoration! as BoxDecoration;
      final colors = (decoration.gradient! as LinearGradient).colors;
      expect(colors, isNot(contains(Colors.white)));
    }
    expect(find.text('Heute wichtig'), findsOneWidget);
    expect(find.text('Als Nächstes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('background refresh keeps the family assistant calm',
      (tester) async {
    final refresh = Completer<List<PersonalResponseModel>>();
    var responseRequests = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          parentDashboardSummaryProvider.overrideWith(
            (ref) async => DashboardSummary(
              players: [_player()],
              events: const [],
              notifications: const [],
            ),
          ),
          personalResponsesProvider.overrideWith((ref) {
            responseRequests++;
            if (responseRequests == 1) {
              return Future.value([_response()]);
            }
            return refresh.future;
          }),
          parentMatchdaysProvider.overrideWith((ref) async => const []),
          parentConsentAttentionProvider.overrideWith((ref) async => const []),
          currentDevicePushReadyProvider.overrideWith((ref) async => true),
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
    expect(find.text('Als Nächstes'), findsOneWidget);

    refresh.complete([_response()]);
    await tester.pumpAndSettle();
  });
}
