import 'package:fc_teugn_app/core/models/matchday.dart';
import 'package:fc_teugn_app/features/matches/matchday_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('mobile match info uses full-width cards and reaches the end',
      (tester) async {
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: MatchOverview(
              match: _match(),
              staffView: false,
              showLaundryDuty: false,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Vereinsheim Teugn'), findsOneWidget);

    await tester.drag(
      find.byKey(const ValueKey('match-overview-list')),
      const Offset(0, -520),
    );
    await tester.pumpAndSettle();

    final competition = find.byKey(const ValueKey('match-overview-Wettbewerb'));
    expect(competition, findsOneWidget);
    expect(tester.getSize(competition).width, greaterThan(370));

    await tester.drag(
      find.byKey(const ValueKey('match-overview-list')),
      const Offset(0, -900),
    );
    await tester.pumpAndSettle();

    final referee = find.byKey(const ValueKey('match-overview-Schiedsrichter'));
    expect(referee, findsOneWidget);
    expect(referee.hitTestable(), findsOneWidget);
  });

  testWidgets('wide match info uses a balanced three-column grid',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: MatchOverview(
              match: _match(),
              staffView: false,
              showLaundryDuty: false,
            ),
          ),
        ),
      ),
    );

    final competition = find.byKey(const ValueKey('match-overview-Wettbewerb'));
    final matchDay = find.byKey(const ValueKey('match-overview-Spieltag'));
    final location = find.byKey(const ValueKey('match-overview-Spielstätte'));

    expect(competition, findsOneWidget);
    expect(matchDay, findsOneWidget);
    expect(location, findsOneWidget);
    expect(
      tester.getTopLeft(competition).dy,
      tester.getTopLeft(matchDay).dy,
    );
    expect(tester.getTopLeft(matchDay).dy, tester.getTopLeft(location).dy);
    expect(
      tester.getTopLeft(competition).dx,
      lessThan(tester.getTopLeft(matchDay).dx),
    );
    expect(
      tester.getTopLeft(matchDay).dx,
      lessThan(tester.getTopLeft(location).dx),
    );
  });
}

MatchdayModel _match() => MatchdayModel(
      id: 'match-1',
      title: 'FC Teugn · ATSV Kelheim E2',
      startAt: DateTime(2026, 8, 14, 17),
      meetingAt: DateTime(2026, 8, 14, 16, 15),
      meetingLocation: 'Vereinsheim Teugn',
      location: 'Teugn Sportplatz',
      teamId: 'team-1',
      details: const MatchDetailsModel(
        opponent: 'ATSV Kelheim E2',
        isHome: true,
        status: MatchStatus.planned,
        durationMinutes: 60,
        periodMinutes: 15,
        periodCount: 4,
        competition: 'Freundschaftsspiel',
        matchDay: 'Vorbereitung',
        pitch: 'Hauptplatz',
        referee: 'Max Mustermann',
        notes: 'Bitte spätestens 15 Minuten vor dem Treffpunkt da sein.',
      ),
    );
