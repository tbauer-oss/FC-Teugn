import 'package:fc_teugn_app/core/app_theme.dart';
import 'package:fc_teugn_app/core/models/event.dart';
import 'package:fc_teugn_app/core/models/personal_response.dart';
import 'package:fc_teugn_app/core/providers.dart';
import 'package:fc_teugn_app/features/shared/family_responses.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

PersonalResponseModel _response({
  String eventId = 'event-1',
  String title = 'Training',
  AttendanceStatus status = AttendanceStatus.unknown,
  bool canRespond = true,
  String? reason,
}) {
  return PersonalResponseModel(
    eventId: eventId,
    playerId: 'player-1',
    playerName: 'Max Muster',
    teamName: 'E1-Jugend',
    ageGroupCode: 'E1',
    title: title,
    category: 'TRAINING',
    startAt: DateTime(2026, 8, 22, 10),
    location: 'Sportplatz Teugn',
    responseStatus: status,
    reason: reason,
    canRespond: canRespond,
    isOverdue: false,
  );
}

Future<void> _pumpPage(
  WidgetTester tester,
  PersonalResponseModel response,
) async {
  tester.view.physicalSize = const Size(1100, 760);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        personalResponsesProvider.overrideWith((ref) async => [response]),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const FamilyResponsesPage(isTrainer: false),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('family response offers maybe and optional decline reason',
      (tester) async {
    await _pumpPage(tester, _response());

    expect(find.widgetWithText(FilledButton, 'Vielleicht'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Absagen'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Absagen'));
    await tester.pumpAndSettle();

    expect(find.text('Max Muster absagen?'), findsOneWidget);
    expect(find.text('Grund (optional)'), findsOneWidget);
    expect(find.text('z. B. krank oder verhindert'), findsOneWidget);
  });

  testWidgets('saved decline reason is visible in family response',
      (tester) async {
    await _pumpPage(
      tester,
      _response(
        status: AttendanceStatus.no,
        canRespond: false,
        reason: 'Krank',
      ),
    );

    expect(find.text('Grund: Krank'), findsOneWidget);
  });

  testWidgets('several family responses stay compact at 320 logical pixels',
      (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personalResponsesProvider.overrideWith(
            (ref) async => [
              _response(eventId: 'event-1', title: 'Training'),
              _response(eventId: 'event-2', title: 'Freundschaftsspiel'),
              _response(eventId: 'event-3', title: 'Mannschaftsabend'),
            ],
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const FamilyResponsesPage(isTrainer: false),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('family-response-summary-scroll')),
      findsOneWidget,
    );
    expect(find.text('Freundschaftsspiel'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
