import 'package:fc_teugn_app/core/models/matchday.dart';
import 'package:fc_teugn_app/features/matches/kit_laundry_duty_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [
    320.0,
    360.0,
    375.0,
    390.0,
    412.0,
    430.0,
    480.0,
    599.0,
    673.0,
    841.0,
    900.0,
  ]) {
    testWidgets('trikotdienst stays usable at ${width.toInt()} px',
        (tester) async {
      tester.view.physicalSize = Size(width, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(8),
                child: KitLaundryDutyCard(
                  matchId: 'match-1',
                  staffView: false,
                  compact: true,
                  initialDuty: _duty(),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Trikotdienst'), findsOneWidget);
      expect(find.text('Übernehmen'), findsOneWidget);
      expect(find.text('Ablehnen'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(
        tester
            .getRect(find.byKey(const ValueKey('kit-laundry-duty-card')))
            .right,
        lessThanOrEqualTo(width - 8),
      );
    });
  }

  testWidgets('stored player keeps confirmed family visible', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: KitLaundryDutyCard(
              matchId: 'match-1',
              staffView: true,
              compact: true,
              initialDuty: _duty(
                status: KitLaundryDutyStatus.confirmed,
                assignedFamilyLabel: null,
                assignedPlayerName: 'Mia & Max Mustermann',
                canRespond: false,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Familie Mia & Max Mustermann'), findsOneWidget);
    expect(find.text('Bestätigt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

KitLaundryDutyModel _duty({
  KitLaundryDutyStatus status = KitLaundryDutyStatus.proposed,
  String? assignedFamilyLabel = 'Familie Mustermann',
  String? assignedPlayerName,
  bool canRespond = true,
}) =>
    KitLaundryDutyModel(
      eventId: 'match-1',
      title: 'FC Teugn · Beispiel',
      startAt: DateTime(2026, 8, 22, 10),
      status: status,
      assignedPlayerId: 'player-1',
      assignedPlayerName: assignedPlayerName,
      assignedFamilyLabel: assignedFamilyLabel,
      eligibleFamilyCount: 12,
      nominationPublished: true,
      viewerEligible: true,
      viewerAssigned: true,
      canRespond: canRespond,
      canComplete: false,
      canManage: false,
    );
