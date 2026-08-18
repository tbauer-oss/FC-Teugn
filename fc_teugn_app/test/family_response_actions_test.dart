import 'package:fc_teugn_app/core/app_theme.dart';
import 'package:fc_teugn_app/core/api_client.dart';
import 'package:fc_teugn_app/core/data_repository.dart';
import 'package:fc_teugn_app/core/models/event.dart';
import 'package:fc_teugn_app/core/models/personal_response.dart';
import 'package:fc_teugn_app/core/providers.dart';
import 'package:fc_teugn_app/features/shared/family_responses.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _RefreshingRepository extends DataRepository {
  _RefreshingRepository() : super(ApiClient(baseUrl: 'http://localhost'));

  var calls = 0;

  @override
  Future<List<PersonalResponseModel>> personalResponses() async {
    calls++;
    return [
      _response(
        eventId: 'event-$calls',
        title: calls == 1 ? 'Training' : 'Freundschaftsspiel',
      ),
    ];
  }
}

PersonalResponseModel _response({
  String eventId = 'event-1',
  String title = 'Training',
  AttendanceStatus status = AttendanceStatus.unknown,
  bool canRespond = true,
  String? reason,
  String type = 'TRAINING',
  String category = 'TRAINING',
  DateTime? startAt,
}) {
  return PersonalResponseModel(
    eventId: eventId,
    playerId: 'player-1',
    playerName: 'Max Muster',
    teamName: 'E1-Jugend',
    ageGroupCode: 'E1',
    title: title,
    type: type,
    category: category,
    startAt: startAt ?? DateTime.now().add(const Duration(days: 3)),
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

  testWidgets('match response only offers accept or decline', (tester) async {
    await _pumpPage(
      tester,
      _response(
        title: 'Punktspiel',
        type: 'MATCH',
        category: 'LEAGUE_MATCH',
      ),
    );

    expect(find.widgetWithText(FilledButton, 'Zusagen'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Vielleicht'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Absagen'), findsOneWidget);
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

  testWidgets('manual refresh signal reloads visible family responses',
      (tester) async {
    final repository = _RefreshingRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const FamilyResponsesPage(isTrainer: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Training'), findsOneWidget);
    expect(repository.calls, 1);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(FamilyResponsesPage)),
    );
    container.read(manualDataRefreshProvider.notifier).state++;
    await tester.pumpAndSettle();

    expect(find.text('Freundschaftsspiel'), findsOneWidget);
    expect(repository.calls, 2);
  });

  testWidgets('one week is selected and parents can extend the response period',
      (tester) async {
    final now = DateTime.now();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personalResponsesProvider.overrideWith(
            (ref) async => [
              _response(
                eventId: 'near',
                title: 'Training diese Woche',
                startAt: now.add(const Duration(days: 2)),
              ),
              _response(
                eventId: 'later',
                title: 'Training in drei Wochen',
                startAt: now.add(const Duration(days: 20)),
              ),
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

    expect(find.text('1 Woche'), findsOneWidget);
    expect(find.text('Training diese Woche'), findsOneWidget);
    expect(find.text('Training in drei Wochen'), findsNothing);

    await tester.tap(find.text('1 Woche'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('4 Wochen').last);
    await tester.pumpAndSettle();

    expect(find.text('Training in drei Wochen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
