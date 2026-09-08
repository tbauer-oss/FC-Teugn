import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fc_teugn_app/core/team_game_format.dart';
import 'package:fc_teugn_app/core/lineup_planner.dart';
import 'package:fc_teugn_app/core/models/event.dart';
import 'package:fc_teugn_app/features/shared/match_game_format_field.dart';

void main() {
  test(
      'BFV formats have a complete lineup with the appropriate goalkeeper count',
      () {
    for (final format in TeamGameFormat.values) {
      for (final formation in format.formations) {
        final slots = lineupSlots(format.playerCount,
            formation: formation, hasGoalkeeper: format.hasGoalkeeper);
        expect(slots.length, format.playerCount, reason: format.apiValue);
        expect(slots.where((s) => s.$3 == 'TW').length,
            format.hasGoalkeeper ? 1 : 0);
        expect(
            isValidFormation(formation, format.playerCount,
                hasGoalkeeper: format.hasGoalkeeper),
            isTrue);
      }
    }
  });
  test(
      'new match stores override; older response keeps team fallback available',
      () {
    final data = EventWriteData(
        category: EventCategory.friendlyMatch,
        title: 'Test',
        startAt: DateTime(2026),
        location: 'Teugn',
        teamIds: const ['e1'],
        gameFormat: TeamGameFormat.football5);
    expect(data.toJson()['gameFormat'], 'FOOTBALL_5');
    expect(MatchDetails.fromJson({'gameFormat': 'FOOTBALL_5'}).gameFormat,
        TeamGameFormat.football5);
    expect(MatchDetails.fromJson({}).gameFormat, isNull);
  });
  testWidgets(
      'E-youth format picker fits a narrow phone and permits 5 against 5',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var format = TeamGameFormat.football7;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StatefulBuilder(
                builder: (context, setState) => MatchGameFormatField(
                    ageGroupCode: 'E',
                    value: format,
                    onChanged: (v) => setState(() => format = v))))));
    await tester.tap(find.byType(DropdownButtonFormField<TeamGameFormat>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('5 gegen 5').last);
    await tester.pumpAndSettle();
    expect(format, TeamGameFormat.football5);
    expect(tester.takeException(), isNull);
  });
}
